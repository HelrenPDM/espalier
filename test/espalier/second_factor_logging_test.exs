defmodule Espalier.SecondFactorLoggingTest do
  # Logger.put_module_level/2 changes the level of Espalier.SecurityLog for the node.
  use EspalierWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Espalier.Accounts.{Challenges, Factors, Passkeys}
  alias Espalier.Accounts.Passkeys.Options
  alias Espalier.Logger.JSONFormatter
  alias Espalier.SoftAuthenticator
  alias Espalier.Test.LogForwarder

  setup do
    Logger.put_module_level(Espalier.SecurityLog, :info)
    on_exit(fn -> Logger.delete_module_level(Espalier.SecurityLog) end)
    :ok
  end

  test "the second factors write their events and no code, challenge or token" do
    user = user_fixture()
    {_factor, secret} = totp_fixture(user)
    {authenticator, _credential} = passkey_fixture(user)
    [code | _] = codes = recovery_codes_fixture(user)
    totp = totp_code(secret)
    ref = attach_security_events()

    {{tokens, challenges}, log} =
      with_log([level: :info], fn ->
        conn =
          api_request(api_conn(), :post, "/api/auth/password", %{
            email: user.email,
            password: valid_user_password()
          })

        conn = api_request(conn, :post, "/api/auth/second-factor", %{totp: "000000"})
        assert json_response(conn, 401)
        conn = api_request(conn, :post, "/api/auth/second-factor", %{totp: totp})
        first = get_session(conn, :user_token)

        conn =
          api_request(api_conn(), :post, "/api/auth/password", %{
            email: user.email,
            password: valid_user_password()
          })

        conn = api_request(conn, :post, "/api/auth/second-factor", %{recovery_code: code})
        second = get_session(conn, :user_token)

        conn = api_request(api_conn(), :post, "/api/auth/passkey/options")
        options = json_response(conn, 200)

        conn =
          api_request(
            conn,
            :post,
            "/api/auth/passkey",
            SoftAuthenticator.assert(authenticator, options)
          )

        third = get_session(conn, :user_token)

        {[first, second, third], [options["challenge"]]}
      end)

    assert_received {^ref, %{name: :authn_login_fail, factor: "totp", reason: "invalid_code"}}
    assert_received {^ref, %{name: :authn_login_success, factor: "totp"}}
    assert_received {^ref, %{name: :authn_login_success, factor: "password+totp"}}
    assert_received {^ref, %{name: :authn_login_success, factor: "recovery_code"}}
    assert_received {^ref, %{name: :authn_login_success, factor: "passkey"}}
    assert_received {^ref, %{name: :session_created}}

    assert log =~ "authn_login_success"

    values =
      [totp | codes] ++
        Enum.map(codes, &String.replace(&1, "-", "")) ++
        challenges ++
        Enum.flat_map(tokens, &[Base.url_encode64(&1, padding: false), Base.encode64(&1)])

    for value <- values, do: refute(log =~ value)
  end

  test "factor changes are logged as user_updated with the change" do
    user = user_fixture()
    ref = attach_security_events()
    Factors.notify_change(user, :factor_added, :totp)
    Factors.notify_change(user, :recovery_codes_regenerated, :recovery_code)

    assert_received {^ref, %{name: :user_updated, change: "factor_added", factor: "totp"}}

    assert_received {^ref,
                     %{
                       name: :user_updated,
                       change: "recovery_codes_regenerated",
                       factor: "recovery_code"
                     }}
  end

  test "the production formatter writes risk_signal of a sign count that does not increase" do
    {JSONFormatter, config} =
      "config/prod.exs"
      |> Config.Reader.read!(env: :prod, target: :host)
      |> get_in([:logger, :default_handler, :formatter])

    LogForwarder.attach()

    user = user_fixture()
    {authenticator, _credential} = passkey_fixture(user, sign_count: 7)
    challenge = Passkeys.new_authentication_challenge()
    row = Challenges.issue(:sign_in, nil, challenge)

    assertion =
      SoftAuthenticator.assert(authenticator, Options.request(challenge, []), sign_count: 7)

    {:ok, result} = Passkeys.authenticate(row, assertion, nil)
    Factors.record_success(user, :passkey, result, %{user_id: user.id, factor: :passkey})

    assert_received {:log_event, %{meta: %{event: :authn_login_success}} = event}
    line = event |> JSONFormatter.format(config) |> IO.iodata_to_binary()

    assert line =~ ~s("risk_signal":"sign_count")
    assert line =~ ~s("level":"warning")
    assert line =~ ~s("credential_ref":")
    assert line =~ ~s("factor":"passkey")
  end
end
