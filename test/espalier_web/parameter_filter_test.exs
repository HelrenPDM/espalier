defmodule EspalierWeb.ParameterFilterTest do
  # Logger.put_module_level/2 changes the level of Phoenix.Logger for the node.
  use EspalierWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Espalier.SoftAuthenticator

  @entries_0004 ~w(password current_password email token code secret recovery_code)
  @entries_0005 ~w(totp passkey credential response rawId)

  test "the list holds the entries of tasks 0004 and 0005 and filters nested values" do
    # Phoenix compiles the list at boot, so the test reads the configuration file.
    filters =
      "config/config.exs"
      |> Config.Reader.read!(env: :test, target: :host)
      |> get_in([:phoenix, :filter_parameters])

    for key <- @entries_0004 ++ @entries_0005, do: assert(key in filters, key)

    params = %{
      "totp" => "123456",
      "passkey" => %{"rawId" => "r", "response" => %{"signature" => "s"}},
      "credential" => %{"response" => %{"attestationObject" => "a"}},
      "rawId" => "r",
      "response" => %{"clientDataJSON" => "c", "userHandle" => "u"},
      "nested" => [%{"totp" => "654321"}]
    }

    filtered = Phoenix.Logger.filter_values(params)

    for key <- ["totp", "passkey", "credential", "rawId", "response"],
        do: assert(filtered[key] == "[FILTERED]", key)

    assert filtered["nested"] == [%{"totp" => "[FILTERED]"}]
  end

  test "the router log holds no TOTP code and no WebAuthn payload" do
    Logger.put_module_level(Phoenix.Logger, :debug)
    on_exit(fn -> Logger.delete_module_level(Phoenix.Logger) end)

    user = user_fixture()
    {_factor, secret} = totp_fixture(user)
    {authenticator, _credential} = passkey_fixture(user)
    code = totp_code(secret)

    {{assertion, registration}, log} =
      with_log([level: :debug], fn ->
        conn =
          api_request(api_conn(), :post, "/api/auth/password", %{
            email: user.email,
            password: valid_user_password()
          })

        conn = api_request(conn, :post, "/api/auth/second-factor", %{totp: code})
        assert json_response(conn, 200)["session"]["strength"] == "mfa"

        options_conn = api_request(api_conn(), :post, "/api/auth/passkey/options")
        assertion = SoftAuthenticator.assert(authenticator, json_response(options_conn, 200))
        conn = api_request(options_conn, :post, "/api/auth/passkey", assertion)
        assert json_response(conn, 200)

        conn = api_request(conn, :post, "/api/me/passkeys/options")
        options = json_response(conn, 200)
        new_authenticator = SoftAuthenticator.new() |> SoftAuthenticator.put_user_handle(options)
        registration = SoftAuthenticator.attest(new_authenticator, options)
        conn = api_request(conn, :post, "/api/me/passkeys", %{credential: registration})
        assert json_response(conn, 200)

        {assertion, registration}
      end)

    assert log =~ "Parameters:"
    assert log =~ "[FILTERED]"
    refute log =~ code
    refute log =~ user.email
    assert log =~ ~s("rawId" => "[FILTERED]")
    assert log =~ ~s("response" => "[FILTERED]")

    for member <- ["clientDataJSON", "authenticatorData", "signature", "userHandle"],
        do: refute(log =~ assertion["response"][member], member)

    for member <- ["clientDataJSON", "attestationObject"],
        do: refute(log =~ registration["response"][member], member)

    # The registration sits under "credential", so not even its id appears.
    refute log =~ registration["rawId"]
  end
end
