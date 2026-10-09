# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule Espalier.AccountsTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import Swoosh.TestAssertions

  alias Espalier.Accounts
  alias Espalier.Accounts.{MailWorker, Scope, User, UserToken}
  alias Espalier.Hashed.HMAC

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists, whatever its case and whitespace" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
      assert %User{id: ^id} = Accounts.get_user_by_email("  " <> String.upcase(user.email) <> " ")
    end
  end

  describe "create_session/2 for the directory pathway (task 0007, step 18)" do
    test "a directory bind alone opens an enrollment session of 30 minutes" do
      user = user_fixture()
      now = DateTime.utc_now(:second)

      assert {token, session} =
               Accounts.create_session(user, %{auth_methods: [:ldap], strength: :enrollment})

      assert is_binary(token)
      assert session.strength == :enrollment
      assert session.auth_methods == [:ldap]
      assert_in_delta DateTime.diff(session.expires_at, now, :second), 30 * 60, 5
    end

    test "a directory bind alone never opens an mfa session" do
      user = user_fixture()

      assert_raise ArgumentError, fn ->
        Accounts.create_session(user, %{auth_methods: [:ldap], strength: :mfa})
      end
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "users" do
    test "store e-mail, display name and org unit encrypted and the address hash keyed" do
      user = user_fixture(%{display_name: "Ada", email: "Ada@Example.org"})
      user = user |> Ecto.Changeset.change(org_unit: "Unit 7") |> Repo.update!()

      %{rows: [[email, email_hash, display_name, org_unit]]} =
        Repo.query!(
          "SELECT email, email_hash, display_name, org_unit FROM users WHERE id = $1",
          [Ecto.UUID.dump!(user.id)]
        )

      for value <- [email, display_name, org_unit] do
        assert <<1, 10, "AES.GCM.V1", _::binary>> = value
      end

      assert email_hash == HMAC.hash("ada@example.org")
      assert %User{email: "ada@example.org", org_unit: "Unit 7"} = Repo.get!(User, user.id)
      refute inspect(user) =~ "ada@example.org"
    end

    test "hash passwords with Argon2id and keep no hint or secret question" do
      user = user_fixture()
      assert "$argon2id$" <> _ = user.hashed_password
      refute :password_hint in User.__schema__(:fields)
      refute Enum.any?(User.__schema__(:fields), &(Atom.to_string(&1) =~ "question"))
    end
  end

  describe "invite_user/2" do
    test "requires the role admin" do
      assert Accounts.invite_user(user_scope_fixture(), %{email: unique_user_email()}) ==
               {:error, :forbidden}
    end

    test "requires email to be set and valid" do
      assert {:error, changeset} = Accounts.invite_user(Scope.system(), %{})
      assert %{email: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} = Accounts.invite_user(Scope.system(), %{email: "not valid"})
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)

      too_long = String.duplicate("db", 100)
      assert {:error, changeset} = Accounts.invite_user(Scope.system(), %{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "refuses an address with a line break, so no header reaches a mail" do
      for email <- ["a@example.org\r\nBcc: b@example.org", "a@example.org\nSubject: x"] do
        assert {:error, changeset} = Accounts.invite_user(Scope.system(), %{email: email})
        assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
      end

      assert {:error, changeset} =
               Accounts.invite_user(Scope.system(), %{
                 email: unique_user_email(),
                 locale: "en\r\n"
               })

      assert %{locale: [_]} = errors_on(changeset)
    end

    test "refuses an address that has an account, whatever its case" do
      %{email: email} = user_fixture()
      assert Accounts.invite_user(Scope.system(), %{email: email}) == {:error, :user_exists}

      assert Accounts.invite_user(Scope.system(), %{email: String.upcase(email)}) ==
               {:error, :user_exists}
    end

    test "creates the user with the local part as display name and enqueues the invitation" do
      assert {:ok, user} = Accounts.invite_user(Scope.system(), %{email: "Grace.H@example.org"})
      assert user.display_name == "grace.h"
      assert user.email == "grace.h@example.org"
      assert is_nil(user.confirmed_at)
      assert is_nil(user.hashed_password)
      assert_enqueued(worker: MailWorker, args: %{"kind" => "invitation", "user_id" => user.id})
      assert [%{action: "user.invited"}] = Repo.all(Espalier.Audit.AuditEvent)
    end

    test "keeps a given display name and checks its length in code points" do
      assert {:ok, %User{display_name: "Chloë"}} =
               Accounts.invite_user(Scope.system(), %{
                 email: unique_user_email(),
                 display_name: "Chloë"
               })

      assert {:error, changeset} =
               Accounts.invite_user(Scope.system(), %{
                 email: unique_user_email(),
                 display_name: String.duplicate("ë", 201)
               })

      assert %{display_name: [_]} = errors_on(changeset)
    end
  end

  describe "accept_invitation/1" do
    setup do
      user = unconfirmed_user_fixture()
      {token, _row} = email_token_fixture(user, :invite)
      %{user: user, token: token}
    end

    test "confirms the user and works once", %{user: user, token: token} do
      assert {:ok, accepted} = Accounts.accept_invitation(token)
      assert accepted.id == user.id
      assert accepted.confirmed_at
      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
      assert Accounts.accept_invitation(token) == {:error, :invalid_token}
    end

    test "works only within 10 minutes", %{token: token} do
      later = DateTime.add(DateTime.utc_now(), 11, :minute)
      assert Accounts.accept_invitation(token, later) == {:error, :invalid_token}
      assert {:ok, _user} = Accounts.accept_invitation(token)
    end

    test "fails after the address changed", %{user: user, token: token} do
      user |> User.email_changeset(%{email: unique_user_email()}) |> Repo.update!()
      assert Accounts.accept_invitation(token) == {:error, :invalid_token}
    end

    test "fails for a user who received an external identity after the invitation",
         %{user: user, token: token} do
      external_identity_fixture(user)
      assert Accounts.accept_invitation(token) == {:error, :invalid_token}
    end

    test "fails for a user who enrolled a second factor", %{user: user, token: token} do
      passkey_fixture(user)
      assert Accounts.enrolled?(user)
      assert Accounts.accept_invitation(token) == {:error, :invalid_token}
    end

    test "fails for a disabled user and for a malformed token", %{user: user, token: token} do
      assert Accounts.accept_invitation("not a token!") == {:error, :invalid_token}
      assert Accounts.accept_invitation(nil) == {:error, :invalid_token}
      user |> Ecto.Changeset.change(status: :disabled) |> Repo.update!()
      assert Accounts.accept_invitation(token) == {:error, :invalid_token}
    end

    test "raises for an unconfirmed user with a password (pre-stuffing guard)",
         %{user: user, token: token} do
      user
      |> Ecto.Changeset.change(hashed_password: Argon2.hash_pwd_salt(valid_user_password()))
      |> Repo.update!()

      assert_raise RuntimeError, ~r/unconfirmed user with a password/, fn ->
        Accounts.accept_invitation(token)
      end
    end
  end

  describe "invitation mails" do
    test "the worker mails a link with the token in the fragment, valid for 10 minutes" do
      {:ok, user} = Accounts.invite_user(Scope.system(), %{email: "ada@example.org"})
      assert :ok = perform_job(MailWorker, %{kind: "invitation", user_id: user.id})

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.org"}]
        assert email.text_body =~ "/invite#token="
        token = extract_link_token(email)

        row =
          Repo.get_by!(UserToken,
            token_hash: UserToken.hash(Base.url_decode64!(token, padding: false))
          )

        assert row.context == :invite
        assert_in_delta DateTime.diff(row.expires_at, DateTime.utc_now()), 600, 5
        assert {:ok, _user} = Accounts.accept_invitation(token)
      end)
    end

    test "an invitation job for a user with an external identity inserts no row and sends no mail" do
      user = unconfirmed_user_fixture()
      external_identity_fixture(user)

      assert :ok = perform_job(MailWorker, %{kind: "invitation", user_id: user.id})
      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
      assert_no_email_sent()
    end

    test "an invitation job for an enrolled user inserts no row and sends no mail" do
      user = unconfirmed_user_fixture()
      totp_fixture(user)
      assert Accounts.enrolled?(user)

      assert :ok = perform_job(MailWorker, %{kind: "invitation", user_id: user.id})
      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
      assert_no_email_sent()
    end

    test "no job argument contains a plain address or a token" do
      {:ok, _user} = Accounts.invite_user(Scope.system(), %{email: "plain@example.org"})
      {:ok, user} = Accounts.invite_user(Scope.system(), %{email: "other@example.org"})
      :ok = Accounts.request_email_change(user, "new-address@example.org")

      for job <- all_enqueued(worker: MailWorker) do
        encoded = JSON.encode!(job.args)
        refute encoded =~ "@example.org"
      end
    end
  end

  describe "request_invitation/1" do
    setup do
      Application.put_env(:espalier, :signup, :invite)
      on_exit(fn -> Application.put_env(:espalier, :signup, :closed) end)
    end

    test "sends a fresh invitation to an invitable user" do
      user = unconfirmed_user_fixture()
      assert :ok = Accounts.request_invitation(String.upcase(user.email))
      assert_enqueued(worker: MailWorker, args: %{"kind" => "invitation", "user_id" => user.id})
    end

    test "enqueues the no-op job for unknown addresses and users with an external identity" do
      user = unconfirmed_user_fixture()
      external_identity_fixture(user)

      assert :ok = Accounts.request_invitation(user.email)
      assert :ok = Accounts.request_invitation("nobody@example.org")

      assert [%{args: %{"kind" => "none"}}, %{args: %{"kind" => "none"}}] =
               all_enqueued(worker: MailWorker)
    end
  end

  describe "request_email_change/2 and confirm_email_change/2" do
    setup do
      %{user: user_fixture()}
    end

    test "mails the new address, and the confirmation updates the hash and tells the old address",
         %{user: user} do
      old_email = user.email
      assert :ok = Accounts.request_email_change(user, " New@Example.org ")
      [job] = all_enqueued(worker: MailWorker)
      assert job.args["kind"] == "change_email"
      assert MailWorker.decrypt_arg(job.args["email"]) == "new@example.org"

      assert :ok = perform_job(MailWorker, job.args)

      token =
        receive do
          {:email, email} ->
            assert email.to == [{"", "new@example.org"}]
            assert email.text_body =~ "/account/email/confirm#token="
            extract_link_token(email)
        end

      assert {:ok, updated} = Accounts.confirm_email_change(user, token)
      assert updated.email == "new@example.org"
      assert %User{id: id} = Accounts.get_user_by_email("new@example.org")
      assert id == user.id
      refute Accounts.get_user_by_email(old_email)
      assert Accounts.confirm_email_change(updated, token) == {:error, :invalid_token}

      assert_enqueued(
        worker: MailWorker,
        args: %{"kind" => "email_changed", "user_id" => user.id}
      )

      [changed] = all_enqueued(worker: MailWorker, args: %{"kind" => "email_changed"})
      assert :ok = perform_job(MailWorker, changed.args)
      assert_email_sent(to: [{"", old_email}])
    end

    test "the token is bound to the account and lives 10 minutes", %{user: user} do
      {token, _row} =
        email_token_fixture(user, :change_email, "next@example.org",
          new_email: "next@example.org"
        )

      assert Accounts.confirm_email_change(user_fixture(), token) == {:error, :invalid_token}

      later = DateTime.add(DateTime.utc_now(), 11, :minute)
      assert Accounts.confirm_email_change(user, token, later) == {:error, :invalid_token}
      assert {:ok, _user} = Accounts.confirm_email_change(user, token)
    end

    test "an address of another account enqueues the no-op job", %{user: user} do
      other = user_fixture()
      assert :ok = Accounts.request_email_change(user, other.email)
      assert [%{args: %{"kind" => "none"}}] = all_enqueued(worker: MailWorker)
    end
  end

  describe "update_user_password/3" do
    setup do
      user = user_fixture()
      {token, session} = session_fixture(user)
      %{user: user, token: token, session: session}
    end

    test "requires the current password and counts a wrong one", %{user: user} do
      assert {:error, changeset} =
               Accounts.update_user_password(user, %{password: "another long passphrase 1"})

      assert errors_on(changeset) == %{current_password: ["can't be blank"]}

      assert {:error, changeset} =
               Accounts.update_user_password(user, %{
                 "current_password" => "wrong but long password",
                 "password" => "another long passphrase 1"
               })

      assert errors_on(changeset) == %{current_password: ["is invalid"]}

      assert Repo.get_by!(Espalier.Accounts.FailureCounter, user_id: user.id).consecutive_failures ==
               1
    end

    test "updates the password, deletes every token row and keeps a copy of one session",
         %{user: user, session: session} do
      {other_token, _other} = session_fixture(user)

      assert {:ok, {updated, token}} =
               Accounts.update_user_password(
                 user,
                 %{
                   current_password: valid_user_password(),
                   password: "another long passphrase 1"
                 },
                 keep_session: session
               )

      assert User.valid_password?(updated, "another long passphrase 1")
      assert Accounts.get_session_by_token(other_token) == {:error, :not_found}
      assert {:ok, _user, copy} = Accounts.get_session_by_token(token)
      assert copy.expires_at == session.expires_at
      assert copy.id != session.id

      assert_enqueued(
        worker: MailWorker,
        args: %{"kind" => "password_changed", "user_id" => user.id}
      )
    end

    test "without require_current, a user without a password sets one" do
      user = user_fixture(%{password: nil})

      assert {:ok, {user, nil}} =
               Accounts.update_user_password(user, %{password: "another long passphrase 1"},
                 require_current: false
               )

      assert User.valid_password?(user, "another long passphrase 1")
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      {token, _session} = session_fixture(user_fixture())
      assert Accounts.delete_user_session_token(token) == :ok
      assert Accounts.get_session_by_token(token) == {:error, :not_found}
    end
  end
end
