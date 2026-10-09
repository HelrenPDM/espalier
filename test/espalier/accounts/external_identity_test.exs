defmodule Espalier.Accounts.ExternalIdentityTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import EspalierWeb.ConnCase, only: [raw_idp_sid_hash: 1]

  alias Espalier.Accounts
  alias Espalier.Accounts.{ExternalIdentity, MailWorker, Scope, UserToken}
  alias Espalier.Identity.{Assertion, OidcProvider}

  # The HMAC secret of config/test.exs (task 0003).
  @hmac_secret String.duplicate("s", 32)
  @tenant "3f0c2a9e-7b1d-4e5a-8c6f-2d9b0e4a1c7d"
  @issuer "https://login.microsoftonline.com/#{@tenant}/v2.0"

  defp provider do
    %OidcProvider{
      key: "entra",
      type: "entra",
      label: "Microsoft 365",
      issuer: @issuer,
      tenant_id: @tenant,
      provision: true,
      mfa: :local,
      role_map: [author: "Espalier.Author", admin: "Espalier.Admin"]
    }
  end

  defp assertion do
    %Assertion{
      provider_key: "entra",
      issuer: @issuer,
      tenant_id: @tenant,
      subject: "object-id",
      display_name: "Ada Example",
      roles: []
    }
  end

  defp identity_fixture(user, assertion) do
    external_identity_fixture(user,
      provider_key: assertion.provider_key,
      issuer: assertion.issuer,
      tenant_id: assertion.tenant_id,
      subject: assertion.subject
    )
  end

  test "hash_input/3 joins issuer, tenant id and subject with NUL bytes" do
    assert ExternalIdentity.hash_input("demo", nil, "slot-1") == "demo" <> <<0, 0>> <> "slot-1"

    assert ExternalIdentity.hash_input("iss", "tid", "sub") ==
             "iss" <> <<0>> <> "tid" <> <<0>> <> "sub"
  end

  test "the same subject at two issuers yields two subject_hash values" do
    # One identity per provider and account (task 0006), so two providers.
    user = user_fixture()

    a =
      external_identity_fixture(user,
        provider_key: "a",
        issuer: "https://a.example.org",
        subject: "same"
      )

    b =
      external_identity_fixture(user,
        provider_key: "b",
        issuer: "https://b.example.org",
        subject: "same"
      )

    %{rows: rows} =
      Repo.query!("SELECT subject_hash FROM external_identities WHERE id = ANY($1)", [
        [Ecto.UUID.dump!(a.id), Ecto.UUID.dump!(b.id)]
      ])

    assert [[hash_a], [hash_b]] = rows
    assert hash_a != hash_b
  end

  test "the changeset fills subject_hash and ignores a given one" do
    user = user_fixture()

    changeset =
      ExternalIdentity.changeset(
        %ExternalIdentity{},
        %{
          provider_key: "x",
          issuer: "iss",
          tenant_id: "tid",
          subject: "sub",
          subject_hash: "forged"
        },
        Scope.for_user(user)
      )

    assert Ecto.Changeset.get_change(changeset, :subject_hash) ==
             ExternalIdentity.hash_input("iss", "tid", "sub")

    identity = Repo.insert!(changeset)

    assert Repo.get_by(ExternalIdentity,
             provider_key: "x",
             subject_hash: ExternalIdentity.hash_input("iss", "tid", "sub")
           ).id == identity.id

    refute Repo.get_by(ExternalIdentity, provider_key: "x", subject_hash: "forged")
  end

  test "tenant_id is optional and the subject is stored encrypted" do
    identity = external_identity_fixture(user_fixture(), subject: "secret-subject")
    assert is_nil(identity.tenant_id)

    %{rows: [[subject]]} =
      Repo.query!("SELECT subject FROM external_identities WHERE id = $1", [
        Ecto.UUID.dump!(identity.id)
      ])

    refute subject =~ "secret-subject"
  end

  describe "sign_in_external/2" do
    setup do
      %{provider: provider(), assertion: assertion()}
    end

    test "a known identity signs in its account and refreshes the display name", %{
      provider: provider,
      assertion: assertion
    } do
      user = user_fixture(password: nil)
      identity_fixture(user, assertion)

      assert {:ok, signed_in} =
               Accounts.sign_in_external(provider, %{assertion | display_name: "Ada New"})

      assert signed_in.id == user.id
      assert Accounts.get_user!(user.id).display_name == "Ada New"
    end

    test "provisioning creates the account, the identity and the idp_claim grants", %{
      provider: provider,
      assertion: assertion
    } do
      ref = attach_security_events()
      assertion = %{assertion | email: "Ada@Example.org", roles: ["Espalier.Author"]}

      assert {:ok, user} = Accounts.sign_in_external(provider, assertion)
      assert user.email == "ada@example.org"
      assert user.display_name == "Ada Example"
      assert Accounts.provider_linked?(user.id, "entra")
      assert Accounts.roles_for(user) == [:learner, :author]

      assert_received {^ref, %{name: :user_created, provider: "entra", user_id: user_id}}
      assert user_id == user.id
    end

    test "without provisioning an unknown identity gets no account", %{
      provider: provider,
      assertion: assertion
    } do
      assert Accounts.sign_in_external(%{provider | provision: false}, assertion) ==
               {:error, :no_account}

      assert Repo.aggregate(ExternalIdentity, :count) == 0
    end

    test "a verified address of a local account neither links nor creates", %{
      provider: provider,
      assertion: assertion
    } do
      local = user_fixture()

      assert Accounts.sign_in_external(provider, %{assertion | email: local.email}) ==
               {:error, :no_account}

      refute Accounts.external_identity?(local)
      assert Accounts.get_user!(local.id).hashed_password == local.hashed_password
      assert Repo.aggregate(ExternalIdentity, :count) == 0
    end

    test "a new verified address replaces the stored one and mails the previous one", %{
      provider: provider,
      assertion: assertion
    } do
      user = user_fixture(password: nil, email: "old@example.org")
      identity_fixture(user, assertion)
      ref = attach_security_events()

      assert {:ok, _user} =
               Accounts.sign_in_external(provider, %{assertion | email: "new@example.org"})

      assert Accounts.get_user!(user.id).email == "new@example.org"
      assert Accounts.get_user_by_email("new@example.org").id == user.id
      [job] = all_enqueued(worker: MailWorker, args: %{"kind" => "email_changed"})
      assert MailWorker.decrypt_arg(job.args["email"]) == "old@example.org"

      assert_received {^ref,
                       %{name: :user_updated, change: "email", provider: "entra", user_id: id}}

      assert id == user.id

      # An address of another account is not taken over.
      other = user_fixture()
      assert {:ok, _user} = Accounts.sign_in_external(provider, %{assertion | email: other.email})
      assert Accounts.get_user!(user.id).email == "new@example.org"
    end

    test "a disabled account cannot sign in", %{provider: provider, assertion: assertion} do
      user = user_fixture(password: nil)
      identity_fixture(user, assertion)
      Accounts.disable_user(Scope.system(), user)

      assert Accounts.sign_in_external(provider, assertion) == {:error, :account_disabled}
    end

    test "an account with identities at two providers keeps the grants of both", %{
      provider: provider,
      assertion: assertion
    } do
      user = user_fixture(password: nil)
      identity_fixture(user, assertion)

      corp = %OidcProvider{
        key: "corp",
        type: "oidc",
        issuer: "https://id.example.org",
        provision: true,
        role_map: [author: "authors"]
      }

      corp_assertion = %Assertion{
        provider_key: "corp",
        issuer: corp.issuer,
        subject: "corp-subject",
        roles: ["authors"]
      }

      identity_fixture(user, corp_assertion)

      {:ok, _} = Accounts.sign_in_external(provider, %{assertion | roles: ["Espalier.Admin"]})
      {:ok, _} = Accounts.sign_in_external(corp, corp_assertion)
      assert Accounts.roles_for(user) |> Enum.sort() == [:admin, :author, :learner]

      {:ok, _} = Accounts.sign_in_external(corp, %{corp_assertion | roles: []})
      assert Accounts.roles_for(user) |> Enum.sort() == [:admin, :learner]

      {:ok, _} = Accounts.sign_in_external(provider, %{assertion | roles: ["Espalier.Author"]})
      assert Accounts.roles_for(user) |> Enum.sort() == [:author, :learner]
    end

    test "idp_claim grants follow the claims and manual grants stay", %{
      provider: provider,
      assertion: assertion
    } do
      user = user_fixture(password: nil)
      identity_fixture(user, assertion)
      {:ok, _grant} = Accounts.grant_role(Scope.system(), user, :analyst)

      {:ok, _} = Accounts.sign_in_external(provider, %{assertion | roles: ["Espalier.Admin"]})
      assert Accounts.roles_for(user) |> Enum.sort() == [:admin, :analyst, :learner]

      {:ok, _} = Accounts.sign_in_external(provider, %{assertion | roles: []})
      assert Accounts.roles_for(user) |> Enum.sort() == [:analyst, :learner]
    end
  end

  describe "linking" do
    setup do
      %{provider: provider(), assertion: assertion(), user: user_fixture()}
    end

    test "check_external_link/3 covers every outcome", %{
      provider: provider,
      assertion: assertion,
      user: user
    } do
      assert Accounts.check_external_link(user.id, provider, assertion) == :ok

      identity_fixture(user, assertion)
      assert Accounts.check_external_link(user.id, provider, assertion) == {:ok, :already_linked}

      other = user_fixture()

      assert Accounts.check_external_link(other.id, provider, assertion) ==
               {:error, :identity_in_use}

      second = %{assertion | subject: "another-object-id"}

      assert Accounts.check_external_link(user.id, provider, second) ==
               {:error, :provider_already_linked}
    end

    test "link_external_identity/3 links once and mails identity_linked", %{
      provider: provider,
      assertion: assertion,
      user: user
    } do
      ref = attach_security_events()

      identity = %{
        "issuer" => assertion.issuer,
        "tenant_id" => assertion.tenant_id,
        "subject" => assertion.subject
      }

      assert Accounts.link_external_identity(user.id, provider, identity) == {:ok, :linked}

      assert_enqueued(
        worker: MailWorker,
        args: %{"kind" => "identity_linked", "user_id" => user.id, "provider_key" => "entra"}
      )

      assert_received {^ref, %{name: :user_updated, change: "identity_linked", provider: "entra"}}

      assert Accounts.link_external_identity(user.id, provider, assertion) ==
               {:ok, :already_linked}

      assert length(all_enqueued(worker: MailWorker, args: %{"kind" => "identity_linked"})) == 1

      assert Accounts.link_external_identity(user_fixture().id, provider, assertion) ==
               {:error, :identity_in_use}

      assert Accounts.link_external_identity(user.id, provider, %{assertion | subject: "x"}) ==
               {:error, :provider_already_linked}
    end

    test "the identity_linked mail names the provider", %{user: user} do
      Swoosh.TestAssertions.assert_no_email_sent()
      perform_job(MailWorker, %{kind: "identity_linked", user_id: user.id, provider_key: "corp"})

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.to == [{"", user.email}]
        assert email.text_body =~ "corp was linked to your Espalier account"
      end)

      no_mail =
        user_fixture(password: nil)
        |> Ecto.Changeset.change(email: nil, email_hash: nil)
        |> Repo.update!()

      assert :ok =
               perform_job(MailWorker, %{
                 kind: "identity_linked",
                 user_id: no_mail.id,
                 provider_key: "corp"
               })
    end

    test "of two concurrent links to one provider one is refused", %{
      provider: provider,
      assertion: assertion,
      user: user
    } do
      results =
        [assertion, %{assertion | subject: "another-object-id"}]
        |> Enum.map(fn identity ->
          Task.async(fn -> Accounts.link_external_identity(user.id, provider, identity) end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.sort(results) == [{:error, :provider_already_linked}, {:ok, :linked}]
      assert Repo.aggregate(ExternalIdentity, :count) == 1
    end

    test "check_external_step_up/3 needs the user's identity and idp_trusted", %{
      provider: provider,
      assertion: assertion,
      user: user
    } do
      identity_fixture(user, assertion)
      trusted = %{provider | mfa: :idp_trusted}

      assert Accounts.check_external_step_up(user.id, trusted, assertion) == :ok

      assert Accounts.check_external_step_up(user.id, provider, assertion) ==
               {:error, :step_up_not_available}

      assert Accounts.check_external_step_up(user_fixture().id, trusted, assertion) ==
               {:error, :identity_mismatch}
    end
  end

  describe "sign-in tickets" do
    setup do
      %{user: user_fixture()}
    end

    defp ticket_attrs(user, extra \\ %{}) do
      Map.merge(
        %{user_id: user.id, provider_key: "entra", purpose: "sign_in", auth_methods: [:oidc]},
        extra
      )
    end

    test "a ticket works once, with its binding, for 60 seconds", %{user: user} do
      {ticket, binding} = Accounts.create_login_ticket(ticket_attrs(user, %{idp_amr: ["pwd"]}))
      assert byte_size(Base.url_decode64!(ticket, padding: false)) == 32
      assert byte_size(Base.url_decode64!(binding, padding: false)) == 32

      assert {:ok, consumed} = Accounts.consume_login_ticket(ticket, binding)
      assert consumed.user_id == user.id
      assert consumed.auth_methods == [:oidc]
      assert consumed.idp_amr == ["pwd"]
      assert Accounts.consume_login_ticket(ticket, binding) == {:error, :invalid}

      {ticket, binding} = Accounts.create_login_ticket(ticket_attrs(user))
      assert Accounts.consume_login_ticket(ticket, "another-binding") == {:error, :invalid}
      assert Accounts.consume_login_ticket(ticket, binding) == {:error, :invalid}

      {ticket, binding} = Accounts.create_login_ticket(ticket_attrs(user))
      [row] = Repo.all(from t in UserToken, where: t.context == :login_ticket)
      assert DateTime.diff(row.expires_at, row.inserted_at) == 60

      Repo.update_all(from(t in UserToken, where: t.id == ^row.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1)]
      )

      assert Accounts.consume_login_ticket(ticket, binding) == {:error, :invalid}
    end

    test "of two concurrent consumptions one wins", %{user: user} do
      {ticket, binding} = Accounts.create_login_ticket(ticket_attrs(user))

      results =
        [1, 2]
        |> Enum.map(fn _ ->
          Task.async(fn -> Accounts.consume_login_ticket(ticket, binding) end)
        end)
        |> Enum.map(&Task.await/1)

      assert [{:error, :invalid}, {:ok, _ticket}] = Enum.sort(results)
    end

    test "a link ticket carries the encrypted identity", %{user: user} do
      identity = %{issuer: "https://id.example.org", tenant_id: nil, subject: "s-1"}

      {ticket, binding} =
        Accounts.create_login_ticket(
          ticket_attrs(user, %{purpose: "link", link_identity: identity})
        )

      %{rows: [[stored]]} =
        Repo.query!("SELECT link_identity FROM users_tokens WHERE context = 'login_ticket'")

      refute stored =~ "s-1"

      assert {:ok, %{link_identity: decoded}} = Accounts.consume_login_ticket(ticket, binding)

      assert decoded == %{
               "issuer" => "https://id.example.org",
               "tenant_id" => nil,
               "subject" => "s-1"
             }
    end

    test "binding_hash holds HMAC-SHA256 of the binding under the test secret", %{user: user} do
      {_ticket, binding} = Accounts.create_login_ticket(ticket_attrs(user))

      %{rows: [[stored]]} =
        Repo.query!("SELECT binding_hash FROM users_tokens WHERE context = 'login_ticket'")

      assert stored == :crypto.mac(:hmac, :sha256, @hmac_secret, binding)
    end

    test "idp_sid_hash keeps its bytes from ticket to session to reissued session", %{user: user} do
      sid_hash = UserToken.hash_idp_sid("sid-ada")
      expected = :crypto.mac(:hmac, :sha256, @hmac_secret, "sid-ada")
      assert sid_hash == expected

      {ticket, binding} =
        Accounts.create_login_ticket(ticket_attrs(user, %{idp_sid_hash: sid_hash}))

      %{rows: [[stored]]} =
        Repo.query!("SELECT idp_sid_hash FROM users_tokens WHERE context = 'login_ticket'")

      assert stored == expected

      {:ok, consumed} = Accounts.consume_login_ticket(ticket, binding)

      {token, _session} =
        Accounts.create_session(user, %{
          auth_methods: [:oidc],
          strength: :enrollment,
          provider_key: "entra",
          idp_sid_hash: consumed.idp_sid_hash
        })

      assert raw_idp_sid_hash(token) == expected

      {:ok, reissued} = Accounts.reissue_session(token, %{mfa_at: DateTime.utc_now(:second)})
      assert raw_idp_sid_hash(reissued) == expected

      assert Accounts.delete_sessions_by_idp_sid("entra", "sid-ada") == 1
      assert Accounts.get_session_by_token(reissued) == {:error, :not_found}
    end
  end

  describe "OIDC intents" do
    setup do
      user = user_fixture()
      {token, session} = session_fixture(user)
      %{user: user, scope: %Scope{user: user, session: session}, token: token}
    end

    defp intent_rows do
      Repo.aggregate(from(t in UserToken, where: t.context == :oidc_intent), :count)
    end

    test "an intent works once in the session that created it", %{scope: scope, user: user} do
      intent = Accounts.create_oidc_intent(scope, provider(), "link")
      [row] = Repo.all(from t in UserToken, where: t.context == :oidc_intent)
      assert DateTime.diff(row.expires_at, row.inserted_at) == 300

      assert Accounts.consume_oidc_intent(intent, "entra", scope.session.id) ==
               {:ok, %{user_id: user.id, purpose: "link"}}

      assert Accounts.consume_oidc_intent(intent, "entra", scope.session.id) == {:error, :invalid}
    end

    test "another session, no session and another provider each delete the intent", %{
      scope: scope
    } do
      for {provider_key, session_id, result} <- [
            {"entra", Ecto.UUID.generate(), {:error, :session_mismatch}},
            {"entra", nil, {:error, :session_mismatch}},
            {"google", scope.session.id, {:error, :invalid}}
          ] do
        intent = Accounts.create_oidc_intent(scope, provider(), "step_up")
        assert Accounts.consume_oidc_intent(intent, provider_key, session_id) == result
        assert intent_rows() == 0
      end
    end
  end

  describe "front-channel deletion" do
    test "ends only the sessions of the provider and sid" do
      user = user_fixture()
      sid = UserToken.hash_idp_sid("sid-1")

      {match, _} = session_fixture(user, provider_key: "entra", idp_sid_hash: sid)

      {other_sid, _} =
        session_fixture(user,
          provider_key: "entra",
          idp_sid_hash: UserToken.hash_idp_sid("sid-2")
        )

      {other_provider, _} = session_fixture(user, provider_key: "corp", idp_sid_hash: sid)

      assert Accounts.delete_sessions_by_idp_sid("entra", "sid-1") == 1
      assert Accounts.get_session_by_token(match) == {:error, :not_found}
      assert {:ok, _, _} = Accounts.get_session_by_token(other_sid)
      assert {:ok, _, _} = Accounts.get_session_by_token(other_provider)
    end
  end
end
