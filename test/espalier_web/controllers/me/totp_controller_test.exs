defmodule EspalierWeb.Me.TotpControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts.{FailureCounter, MailWorker, Totp, UserToken}
  alias Espalier.Repo

  defp start_totp(conn) do
    conn = api_request(conn, :post, "/api/me/totp")
    body = json_response(conn, 200)
    {conn, Base.decode32!(body["secret_base32"], padding: false)}
  end

  test "an invitee sets a password and confirms TOTP" do
    user = unconfirmed_user_fixture()
    {token, _row} = email_token_fixture(user, :invite)
    conn = api_request(api_conn(), :post, "/api/auth/invitations/accept", %{token: token})
    assert json_response(conn, 200)["session"]["strength"] == "enrollment"

    conn = api_request(conn, :post, "/api/me/totp")
    assert json_response(conn, 409) == %{"error" => "password_required"}

    conn =
      api_request(conn, :put, "/api/me/password", %{password: "plum orbit lantern 4719 again"})

    assert json_response(conn, 200)["session"]["strength"] == "enrollment"

    {conn, secret} = start_totp(conn)
    conn = api_request(conn, :post, "/api/me/totp/confirm", %{code: totp_code(secret)})
    body = json_response(conn, 200)

    assert body["session"]["session"]["strength"] == "mfa"
    assert body["session"]["session"]["auth_methods"] == ["email_code", "totp"]
    assert length(body["recovery_codes"]) == 10
    assert body["totp"]["enabled"]
    assert Totp.enabled?(user)

    assert_enqueued(
      worker: MailWorker,
      args: %{"kind" => "factor_added", "user_id" => user.id, "factor" => "totp"}
    )
  end

  test "a federated user without a local factor enrolls TOTP and keeps provider and sid hash" do
    user = user_fixture(password: nil)
    external_identity_fixture(user, provider_key: "test")
    sid_hash = :crypto.strong_rand_bytes(32)

    conn =
      log_in_user(api_conn(), user,
        auth_methods: [:oidc],
        strength: :enrollment,
        mfa_at: nil,
        provider_key: "test",
        idp_sid_hash: sid_hash
      )

    {conn, secret} = start_totp(conn)
    conn = api_request(conn, :post, "/api/me/totp/confirm", %{code: totp_code(secret)})
    body = json_response(conn, 200)
    assert body["session"]["session"]["auth_methods"] == ["oidc", "totp"]
    assert body["session"]["session"]["provider_key"] == "test"

    token = get_session(conn, :user_token)
    assert %UserToken{strength: :mfa, provider_key: "test"} = session_row(token)
    assert raw_idp_sid_hash(token) == sid_hash
  end

  describe "in an mfa session" do
    setup %{conn: conn} do
      user = user_fixture()
      {_authenticator, _credential} = passkey_fixture(user)
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "a wrong confirmation code answers 422 and counts", %{conn: conn, user: user} do
      {conn, _secret} = start_totp(conn)
      conn = api_request(conn, :post, "/api/me/totp/confirm", %{code: "000000"})
      assert json_response(conn, 422) == %{"error" => "invalid_code"}

      assert Repo.get_by(FailureCounter, user_id: user.id, authenticator: :totp).consecutive_failures ==
               1

      refute Totp.enabled?(user)
    end

    test "an enabled factor answers 409 on a new enrollment", %{conn: conn, user: user} do
      totp_fixture(user)
      conn = api_request(conn, :post, "/api/me/totp")
      assert json_response(conn, 409) == %{"error" => "totp_already_enabled"}
    end

    test "removal needs a recent second factor and leaves a factor", %{user: user} do
      {_factor, secret} = totp_fixture(user)
      eleven_minutes_ago = DateTime.add(DateTime.utc_now(:second), -660)
      conn = log_in_user(api_conn(), user, mfa_at: eleven_minutes_ago)

      conn = api_request(conn, :delete, "/api/me/totp")
      assert json_response(conn, 403) == %{"error" => "reauth_required"}

      csrf_before = conn |> get_req_header("x-csrf-token") |> hd()
      conn = api_request(conn, :post, "/api/me/reauth", %{totp: totp_code(secret)})
      body = json_response(conn, 200)
      refute body["csrf_token"] == csrf_before
      assert body["recent_auth_until"]

      # The session of the setup is the other one.
      conn = api_request(conn, :delete, "/api/me/totp")
      assert json_response(conn, 200) == %{"other_sessions" => 1}
      refute Totp.enabled?(user)

      assert_enqueued(
        worker: MailWorker,
        args: %{"kind" => "factor_removed", "user_id" => user.id, "factor" => "totp"}
      )
    end
  end

  test "the last factor cannot be removed", %{conn: conn} do
    user = user_fixture()
    totp_fixture(user)
    conn = log_in_user(conn, user)
    conn = api_request(conn, :delete, "/api/me/totp")
    assert json_response(conn, 409) == %{"error" => "last_factor"}
    assert Totp.enabled?(user)
  end
end
