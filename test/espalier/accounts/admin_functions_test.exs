defmodule Espalier.Accounts.AdminFunctionsTest do
  @moduledoc """
  The reset functions of task 0015 (step 4) at the context level:
  `Accounts.reset_factors/2` (README section 15, decision D11) and
  `Accounts.reset_failure_counters/2` require the role `admin` and write no
  audit event without it (ASVS 8.2.1), each runs in one `Repo.transact/1`
  (ASVS 2.3.3), and the `factors_reset` mail is plain text without a link,
  states the identity check and asks the person to contact an
  administrator. A user without an address receives no mail.
  """
  # Two tests create a trigger inside their sandbox transaction, which locks
  # its table until the test ends, so the module runs alone.
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures

  alias Espalier.Accounts

  alias Espalier.Accounts.{
    ExternalIdentity,
    FailureCounter,
    FailureCounters,
    MailWorker,
    RecoveryCode,
    Scope,
    TotpFactor,
    User,
    UserToken,
    WebauthnCredential
  }

  alias Espalier.Audit.AuditEvent
  alias Espalier.LdapConnHelpers

  setup do
    %{admin: admin_scope(user_fixture()), user: enrolled_user()}
  end

  defp admin_scope(user) do
    {:ok, _grant} = Accounts.grant_role(Scope.system(), user, :admin)
    {_token, session} = session_fixture(user)
    Scope.for_session(user, session, Accounts.list_role_grants(user))
  end

  # A local user with a passkey, a TOTP factor, recovery codes, a session,
  # an e-mail token and a password counter disabled after 50 failures.
  defp enrolled_user do
    user = user_fixture()
    passkey_fixture(user)
    totp_fixture(user)
    recovery_codes_fixture(user)
    {_token, _session} = session_fixture(user)
    email_token_fixture(user, :recovery_email)
    for _ <- 1..FailureCounters.disable_at(), do: FailureCounters.record_failure(user, :password)
    user
  end

  defp count(query), do: Repo.aggregate(query, :count)

  defp state(user) do
    %{
      passkeys: count(from c in WebauthnCredential, where: c.user_id == ^user.id),
      totp: count(from f in TotpFactor, where: f.user_id == ^user.id),
      recovery_codes: count(from r in RecoveryCode, where: r.user_id == ^user.id),
      tokens: count(from t in UserToken, where: t.user_id == ^user.id),
      password_counter: FailureCounters.check(user, :password),
      hashed_password: Repo.get!(User, user.id).hashed_password,
      jobs: mail_kinds(user)
    }
  end

  defp mail_kinds(user) do
    for %Oban.Job{args: %{"kind" => kind, "user_id" => id}} <- all_enqueued(worker: MailWorker),
        id == user.id,
        do: kind
  end

  defp audit_count, do: count(AuditEvent)

  defp audit_events(action, subject) do
    Repo.all(from e in AuditEvent, where: e.action == ^action and e.subject_id == ^subject.id)
  end

  # Makes every row operation `event` on `table` that matches `condition`
  # fail. The trigger lives in the sandbox transaction of the test, so the
  # rollback at its end removes it.
  defp fail_on!(table, event, condition) do
    Repo.query!("""
    CREATE FUNCTION espalier_test_fail() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'forced failure on %', TG_TABLE_NAME;
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER espalier_test_fail BEFORE #{event} ON #{table}
    FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION espalier_test_fail()
    """)
  end

  describe "without the role admin" do
    test "both functions answer {:error, :forbidden} and write no audit event",
         %{user: user} do
      author = user_fixture()
      {:ok, _grant} = Accounts.grant_role(Scope.system(), author, :author)
      {_token, session} = session_fixture(author)
      author_scope = Scope.for_session(author, session, Accounts.list_role_grants(author))

      before = state(user)
      events = audit_count()

      for scope <- [Scope.for_user(user_fixture()), author_scope] do
        assert Accounts.reset_factors(scope, user) == {:error, :forbidden}
        assert Accounts.reset_failure_counters(scope, user) == {:error, :forbidden}
      end

      assert audit_count() == events
      assert state(user) == before
    end
  end

  describe "reset_factors/2" do
    test "removes every factor, counter and token row of a local user and invites it again",
         %{admin: admin, user: user} do
      ref = attach_security_events()

      assert Accounts.reset_factors(admin, user) == {:ok, %{invitation_sent: true}}

      assert %{
               passkeys: 0,
               totp: 0,
               recovery_codes: 0,
               tokens: 0,
               password_counter: :ok,
               hashed_password: nil
             } = state(user)

      assert %FailureCounter{consecutive_failures: 0, locked_until: nil, disabled_at: nil} =
               Repo.get_by!(FailureCounter, user_id: user.id, authenticator: :password)

      assert Enum.sort(mail_kinds(user)) == ["factors_reset", "invitation"]

      assert [%AuditEvent{actor_id: actor_id, subject_type: "User", details: details}] =
               audit_events("user.factors_reset", user)

      assert actor_id == admin.user.id
      assert details == %{"identity_verified" => true}
      assert [%AuditEvent{}] = audit_events("user.invitation_resent", user)

      user_id = user.id
      assert_received {^ref, %{name: :user_updated, change: "factors_reset", user_id: ^user_id}}
    end

    test "sends no invitation to a disabled local user", %{admin: admin, user: user} do
      user = user |> Ecto.Changeset.change(status: :disabled) |> Repo.update!()

      assert Accounts.reset_factors(admin, user) == {:ok, %{invitation_sent: false}}
      assert %{passkeys: 0, totp: 0, recovery_codes: 0, tokens: 0} = state(user)
      assert mail_kinds(user) == ["factors_reset"]
      assert audit_events("user.invitation_resent", user) == []
    end

    test "sends no invitation to a user with an external identity", %{admin: admin, user: user} do
      external_identity_fixture(user)

      assert Accounts.reset_factors(admin, user) == {:ok, %{invitation_sent: false}}
      assert %{passkeys: 0, totp: 0, recovery_codes: 0, tokens: 0} = state(user)
      assert mail_kinds(user) == ["factors_reset"]
    end

    test "removes the last passkey of an admin", %{admin: admin} do
      other_admin = user_fixture(%{password: nil})
      _scope = admin_scope(other_admin)
      passkey_fixture(other_admin)

      assert {:ok, _result} = Accounts.reset_factors(admin, other_admin)
      assert state(other_admin).passkeys == 0
    end

    test "rolls every change back when a step fails", %{admin: admin, user: user} do
      before = state(user)
      events = audit_count()
      fail_on!("audit_events", "INSERT", "NEW.action = 'user.factors_reset'")

      assert_raise Postgrex.Error, ~r/forced failure/, fn ->
        Accounts.reset_factors(admin, user)
      end

      assert state(user) == before
      assert before.passkeys == 1 and before.password_counter == :disabled
      assert audit_count() == events
    end
  end

  describe "reset_failure_counters/2" do
    test "clears the counters with the user's user_id", %{admin: admin, user: user} do
      for _ <- 1..7, do: FailureCounters.record_failure(user, :totp)
      other = user_fixture()

      for _ <- 1..FailureCounters.disable_at(),
          do: FailureCounters.record_failure(other, :password)

      before = state(user)
      ref = attach_security_events()

      assert {:ok, %User{id: id}} = Accounts.reset_failure_counters(admin, user)
      assert id == user.id

      for counter <- Repo.all(from c in FailureCounter, where: c.user_id == ^user.id) do
        assert %FailureCounter{consecutive_failures: 0, locked_until: nil, disabled_at: nil} =
                 counter
      end

      assert FailureCounters.check(other, :password) == :disabled
      assert Map.drop(state(user), [:password_counter]) == Map.drop(before, [:password_counter])
      assert state(user).password_counter == :ok

      assert [%AuditEvent{actor_id: actor_id}] =
               audit_events("user.failure_counters_reset", user)

      assert actor_id == admin.user.id

      assert_received {^ref,
                       %{name: :user_updated, change: "failure_counters_reset", user_id: ^id}}
    end

    test "deletes the directory counter of the user's LDAP identity",
         %{admin: admin, user: user} do
      config = LdapConnHelpers.put_ldap_provider()
      subject = Ecto.UUID.generate()

      identity =
        external_identity_fixture(user, %{
          provider_key: config.key,
          issuer: "ldap:" <> config.key,
          subject: subject
        })

      counter =
        Repo.insert!(%FailureCounter{
          authenticator: :ldap,
          provider_key: config.key,
          subject_hash:
            ExternalIdentity.hash_input(identity.issuer, identity.tenant_id, identity.subject),
          consecutive_failures: FailureCounters.disable_at(),
          disabled_at: DateTime.utc_now(:second)
        })

      assert {:ok, _user} = Accounts.reset_failure_counters(admin, user)
      assert Repo.get(FailureCounter, counter.id) == nil
      assert [%AuditEvent{details: details}] = audit_events("failure_counter.reset", user)
      assert details == %{"provider_key" => config.key}
    end

    test "rolls the cleared counters back when the directory reset fails",
         %{admin: admin, user: user} do
      identity =
        external_identity_fixture(user, %{
          provider_key: "dir",
          issuer: "ldap:dir",
          subject: Ecto.UUID.generate()
        })

      Repo.insert!(%FailureCounter{
        authenticator: :ldap,
        provider_key: "dir",
        subject_hash:
          ExternalIdentity.hash_input(identity.issuer, identity.tenant_id, identity.subject),
        consecutive_failures: 3
      })

      events = audit_count()
      fail_on!("failure_counters", "DELETE", "OLD.authenticator = 'ldap'")

      assert_raise Postgrex.Error, ~r/forced failure/, fn ->
        Accounts.reset_failure_counters(admin, user)
      end

      assert FailureCounters.check(user, :password) == :disabled
      assert audit_count() == events
    end
  end

  describe "the factors_reset mail" do
    test "is plain text without a link, states the identity check and names the next step",
         %{admin: admin, user: user} do
      {:ok, _result} = Accounts.reset_factors(admin, user)

      assert [%Oban.Job{args: args}] =
               Enum.filter(
                 all_enqueued(worker: MailWorker),
                 &(&1.args["kind"] == "factors_reset")
               )

      assert args == %{"kind" => "factors_reset", "user_id" => user.id}
      assert :ok = perform_job(MailWorker, args)

      assert_received {:email, %Swoosh.Email{} = email}
      assert email.to == [{"", user.email}]
      assert email.subject == "Your sign-in methods were reset"
      assert email.html_body == nil

      body = email.text_body
      assert body =~ "An administrator removed every second factor"
      assert body =~ "after your organization verified your identity"
      assert body =~ "If you did not ask for this reset, contact an administrator"
      refute body =~ "http"
      refute body =~ "://"
      refute body =~ "#token="
      refute body =~ Application.fetch_env!(:espalier, :public_url)
    end

    test "a user without an address receives none", %{user: user} do
      Repo.update_all(from(u in User, where: u.id == ^user.id),
        set: [email: nil, email_hash: nil]
      )

      assert :ok =
               perform_job(MailWorker, %{"kind" => "factors_reset", "user_id" => user.id})

      refute_received {:email, _email}
    end
  end
end
