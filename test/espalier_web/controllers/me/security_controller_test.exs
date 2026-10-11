defmodule EspalierWeb.Me.SecurityControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts
  alias Espalier.Identity.OidcProvider

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

  describe "linked_providers (task 0011)" do
    test "is [] for a local account", %{conn: conn} do
      user = user_fixture()
      passkey_fixture(user)

      body =
        conn |> log_in_user(user) |> api_request(:get, "/api/me/security") |> json_response(200)

      assert body["linked_providers"] == []
    end

    test "lists the provider keys after a link, sorted, without identity values", %{conn: conn} do
      user = user_fixture()
      passkey_fixture(user)
      tenant = "3f0c2a9e-7b1d-4e5a-8c6f-2d9b0e4a1c7d"
      issuer = "https://login.microsoftonline.com/#{tenant}/v2.0"
      provider = %OidcProvider{key: "entra", type: "entra", issuer: issuer, tenant_id: tenant}
      identity = %{"issuer" => issuer, "tenant_id" => tenant, "subject" => "object-id-1"}

      assert Accounts.link_external_identity(user.id, provider, identity) == {:ok, :linked}
      external_identity_fixture(user, provider_key: "corp", subject: "subject-2")

      body =
        conn |> log_in_user(user) |> api_request(:get, "/api/me/security") |> json_response(200)

      assert body["linked_providers"] == ["corp", "entra"]
      encoded = JSON.encode!(body)
      refute encoded =~ "object-id-1"
      refute encoded =~ issuer
    end
  end
end
