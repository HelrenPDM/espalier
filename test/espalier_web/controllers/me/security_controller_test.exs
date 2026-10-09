defmodule EspalierWeb.Me.SecurityControllerTest do
  use EspalierWeb.ConnCase, async: true

  test "lists the factors of the user", %{conn: conn} do
    user = user_fixture()
    {_authenticator, credential} = passkey_fixture(user)
    totp_fixture(user)
    recovery_codes_fixture(user)
    conn = log_in_user(conn, user)

    body = conn |> api_request(:get, "/api/me/security") |> json_response(200)

    assert [%{"id" => id, "backup_eligible" => false, "transports" => ["internal"]}] =
             body["passkeys"]

    assert id == credential.id
    assert body["totp"]["enabled"]
    assert body["recovery_codes"]["remaining"] == 10
    assert body["password_set"]
    assert body["recent_auth_until"]
  end

  test "an enrollment session reaches it without recent_auth_until" do
    user = user_fixture(password: nil)

    conn =
      log_in_user(api_conn(), user,
        strength: :enrollment,
        auth_methods: [:email_code],
        mfa_at: nil
      )

    body = conn |> api_request(:get, "/api/me/security") |> json_response(200)
    assert body["passkeys"] == []
    refute body["totp"]["enabled"]
    refute body["password_set"]
    assert body["recent_auth_until"] == nil
  end
end
