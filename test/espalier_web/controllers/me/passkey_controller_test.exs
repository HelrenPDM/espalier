defmodule EspalierWeb.Me.PasskeyControllerTest do
  # put_setting/2 changes :signup and :admin_require_passkey for the node.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query

  alias Espalier.Accounts
  alias Espalier.Accounts.{AuthChallenge, MailWorker, RoleGrant, Scope, UserToken}
  alias Espalier.Repo
  alias Espalier.SoftAuthenticator

  defp enrollment_conn(user) do
    {token, _row} = email_token_fixture(user, :invite)
    conn = api_request(api_conn(), :post, "/api/auth/invitations/accept", %{token: token})
    assert json_response(conn, 200)["session"]["strength"] == "enrollment"
    conn
  end

  defp register_passkey(conn, opts \\ []) do
    conn = api_request(conn, :post, "/api/me/passkeys/options")
    options = json_response(conn, 200)
    authenticator = SoftAuthenticator.new() |> SoftAuthenticator.put_user_handle(options)
    credential = SoftAuthenticator.attest(authenticator, options, opts)
    {api_request(conn, :post, "/api/me/passkeys", %{credential: credential}), authenticator}
  end

  defp admin(user) do
    %RoleGrant{}
    |> RoleGrant.changeset(%{role: :admin, source: :manual}, Scope.for_user(user))
    |> Repo.insert!()

    user
  end

  describe "enrollment after an invitation" do
    test "a passkey upgrades the enrollment session once", %{} do
      user = unconfirmed_user_fixture()
      conn = enrollment_conn(user)

      conn = api_request(conn, :get, "/api/me/sessions")
      assert json_response(conn, 403) == %{"error" => "enrollment_required"}

      {conn, _authenticator} = register_passkey(conn)
      body = json_response(conn, 200)
      assert length(body["recovery_codes"]) == 10
      assert body["session"]["session"]["strength"] == "mfa"
      assert body["session"]["session"]["auth_methods"] == ["email_code", "passkey"]
      assert body["session"]["csrf_token"]
      assert body["other_sessions"] == 0

      assert %UserToken{strength: :mfa, mfa_at: %DateTime{}} =
               session_row(get_session(conn, :user_token))

      {conn, _authenticator} = register_passkey(conn)
      body = json_response(conn, 200)
      refute Map.has_key?(body, "recovery_codes")
      refute Map.has_key?(body, "session")
      assert body["passkey"]["id"]
      assert length(Accounts.Passkeys.list_credentials(user)) == 2
    end

    test "an enrolled user receives no invitation and old links fail" do
      put_setting(:signup, :invite)
      user = unconfirmed_user_fixture()
      conn = enrollment_conn(user)
      {invite, _row} = email_token_fixture(user, :invite)

      {conn, _authenticator} = register_passkey(conn)
      assert json_response(conn, 200)["recovery_codes"]

      assert Accounts.enrolled?(user)
      assert Accounts.resend_invitation(Scope.system(), user) == {:error, :not_invitable}

      conn = api_request(api_conn(), :post, "/api/auth/invitations", %{email: user.email})
      assert json_response(conn, 202)
      assert_enqueued(worker: MailWorker, args: %{"kind" => "none"})
      refute_enqueued(worker: MailWorker, args: %{"kind" => "invitation", "user_id" => user.id})

      conn = api_request(api_conn(), :post, "/api/auth/invitations/accept", %{token: invite})
      assert json_response(conn, 400) == %{"error" => "invalid_token"}

      assert :ok = perform_job(MailWorker, %{kind: "invitation", user_id: user.id})

      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id and t.context == :invite) ==
               []

      assert_no_email_sent()
    end

    test "a demo session and a request without a session are refused" do
      demo = user_fixture()
      conn = log_in_user(api_conn(), demo, strength: :demo, auth_methods: [:demo], mfa_at: nil)
      conn = api_request(conn, :post, "/api/me/passkeys/options")
      assert json_response(conn, 403) == %{"error" => "forbidden"}

      conn = api_request(api_conn(), :post, "/api/me/passkeys/options")
      assert json_response(conn, 401) == %{"error" => "unauthenticated"}
    end
  end

  describe "registration in an mfa session" do
    setup %{conn: conn} do
      user = user_fixture()
      {_authenticator, credential} = passkey_fixture(user)
      %{user: user, credential: credential, conn: log_in_user(conn, user)}
    end

    test "adds a passkey, mails the user and offers to end the other sessions",
         %{conn: conn, user: user} do
      session_fixture(user)
      ref = attach_security_events()
      {conn, _authenticator} = register_passkey(conn)
      body = json_response(conn, 200)
      assert body["other_sessions"] == 1
      refute Map.has_key?(body, "recovery_codes")

      assert_enqueued(
        worker: MailWorker,
        args: %{"kind" => "factor_added", "user_id" => user.id, "factor" => "passkey"}
      )

      assert_received {^ref, %{name: :user_updated, change: "factor_added", factor: "passkey"}}
    end

    test "a failed registration answers 422 and consumes the challenge", %{conn: conn} do
      conn = api_request(conn, :post, "/api/me/passkeys/options")
      id = get_session(conn, "webauthn_ceremony")
      options = json_response(conn, 200)
      authenticator = SoftAuthenticator.new() |> SoftAuthenticator.put_user_handle(options)

      credential = SoftAuthenticator.attest(authenticator, options, cross_origin: true)
      conn = api_request(conn, :post, "/api/me/passkeys", %{credential: credential})
      assert json_response(conn, 422) == %{"error" => "registration_failed"}
      assert Repo.get(AuthChallenge, id) == nil

      credential = SoftAuthenticator.attest(authenticator, options)
      conn = api_request(conn, :post, "/api/me/passkeys", %{credential: credential})
      assert json_response(conn, 422) == %{"error" => "registration_failed"}
    end

    test "needs a second factor from the last 10 minutes", %{user: user} do
      eleven_minutes_ago = DateTime.add(DateTime.utc_now(:second), -660)
      conn = log_in_user(api_conn(), user, mfa_at: eleven_minutes_ago)

      for {method, path} <- [{:post, "/api/me/passkeys/options"}, {:post, "/api/me/passkeys"}] do
        conn = api_request(conn, method, path)
        assert json_response(conn, 403) == %{"error" => "reauth_required"}, path
      end
    end
  end

  describe "removal" do
    test "removes a passkey after the factor rules", %{conn: conn} do
      put_setting(:admin_require_passkey, true)
      user = user_fixture()
      {_authenticator, first} = passkey_fixture(user)
      conn = log_in_user(conn, user)

      conn = api_request(conn, :delete, "/api/me/passkeys/#{first.id}")
      assert json_response(conn, 409) == %{"error" => "last_factor"}

      {_authenticator, second} = passkey_fixture(user)
      conn = api_request(conn, :delete, "/api/me/passkeys/#{first.id}")
      assert json_response(conn, 200) == %{"other_sessions" => 0}

      assert_enqueued(
        worker: MailWorker,
        args: %{"kind" => "factor_removed", "user_id" => user.id, "factor" => "passkey"}
      )

      conn = api_request(conn, :delete, "/api/me/passkeys/#{first.id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}

      other = user_fixture()
      {_authenticator, foreign} = passkey_fixture(other)
      conn = api_request(conn, :delete, "/api/me/passkeys/#{foreign.id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert Repo.reload(second)
    end

    test "an admin keeps the last passkey while ADMIN_REQUIRE_PASSKEY is true", %{conn: conn} do
      put_setting(:admin_require_passkey, true)
      user = admin(user_fixture())
      totp_fixture(user)
      {_authenticator, credential} = passkey_fixture(user)
      conn = log_in_user(conn, user)

      conn = api_request(conn, :delete, "/api/me/passkeys/#{credential.id}")
      assert json_response(conn, 409) == %{"error" => "admin_passkey_required"}

      without_passkey = admin(user_fixture())
      totp_fixture(without_passkey)
      conn = log_in_user(api_conn(), without_passkey)
      conn = api_request(conn, :get, "/api/session")
      assert json_response(conn, 200)["flags"]["admin_passkey_required"] == true

      conn = api_request(conn, :get, "/api/me/security")
      assert json_response(conn, 200)["admin_passkey_required"] == true
    end
  end
end
