defmodule EspalierWeb.Me.ReauthControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts.{AuthChallenge, Scope}
  alias Espalier.Repo
  alias Espalier.SoftAuthenticator

  setup %{conn: conn} do
    user = user_fixture()
    {authenticator, _credential} = passkey_fixture(user)
    {_factor, secret} = totp_fixture(user)
    stale = DateTime.add(DateTime.utc_now(:second), -660)

    %{
      user: user,
      authenticator: authenticator,
      secret: secret,
      conn: log_in_user(conn, user, auth_methods: [:password, :totp], mfa_at: stale)
    }
  end

  test "TOTP reissues the session with a recent second factor", %{conn: conn, secret: secret} do
    old = get_session(conn, :user_token)
    conn = api_request(conn, :post, "/api/me/reauth", %{totp: totp_code(secret)})
    body = json_response(conn, 200)

    new = get_session(conn, :user_token)
    refute new == old
    assert session_row(old) == nil
    row = session_row(new)
    assert row.auth_methods == [:password, :totp]
    assert Scope.recent_auth?(%Scope{session: row})
    {:ok, until, 0} = DateTime.from_iso8601(body["recent_auth_until"])
    assert DateTime.compare(until, DateTime.add(DateTime.utc_now(), 590)) == :gt
    assert body["session"]["recent_auth_until"]
  end

  test "a passkey of the purpose reauth adds the method", %{
    conn: conn,
    authenticator: authenticator
  } do
    conn = api_request(conn, :post, "/api/auth/passkey/options", %{purpose: "reauth"})
    options = json_response(conn, 200)
    id = get_session(conn, "webauthn_ceremony")

    conn =
      api_request(conn, :post, "/api/me/reauth", %{
        passkey: SoftAuthenticator.assert(authenticator, options)
      })

    assert json_response(conn, 200)["session"]["auth_methods"] == ["password", "totp", "passkey"]
    assert Repo.get(AuthChallenge, id) == nil
  end

  test "every failure answers 401 authentication_failed", %{conn: conn, secret: secret} do
    conn = api_request(conn, :post, "/api/me/reauth", %{totp: "000000"})
    assert json_response(conn, 401) == %{"error" => "authentication_failed"}

    conn = api_request(conn, :post, "/api/me/reauth", %{passkey: %{"rawId" => "AA"}})
    assert json_response(conn, 401) == %{"error" => "authentication_failed"}

    conn = api_request(conn, :post, "/api/me/reauth", %{recovery_code: "AAAA"})
    assert json_response(conn, 400) == %{"error" => "bad_request"}

    conn = api_request(conn, :post, "/api/me/reauth", %{totp: totp_code(secret)})
    assert json_response(conn, 200)
  end

  test "an enrollment session cannot re-authenticate", %{user: user} do
    conn =
      log_in_user(api_conn(), user,
        strength: :enrollment,
        auth_methods: [:email_code],
        mfa_at: nil
      )

    conn = api_request(conn, :post, "/api/me/reauth", %{totp: "000000"})
    assert json_response(conn, 403) == %{"error" => "enrollment_required"}
  end
end
