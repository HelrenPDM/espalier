defmodule Espalier.LoggingTest do
  # Replaces the mail adapter for the whole node in one test.
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures
  import ExUnit.CaptureLog

  alias Espalier.Accounts
  alias Espalier.Accounts.{MailWorker, Scope}

  test "a failed sign-in emits authn_login_fail without the password or the address" do
    user = user_fixture()
    password = "a very wrong password 4711"
    ref = attach_security_events()

    log =
      capture_log([level: :warning, metadata: :all], fn ->
        assert {:error, :invalid_credentials} =
                 Accounts.authenticate_password(user.email, password, %{ip: {192, 0, 2, 7}})
      end)

    assert_received {^ref,
                     %{name: :authn_login_fail, factor: "password", provider: "local"} = meta}

    assert meta.user_id == user.id
    assert meta.ip == "192.0.2.7"

    for secret <- [password, user.email] do
      refute inspect(meta) =~ secret
      refute log =~ secret
    end

    assert log =~ "authn_login_fail"
  end

  test "the parameter filter covers the categories of README section 6.10" do
    # Phoenix compiles the list at boot, so the test reads the configuration
    # file and checks the compiled filter on nested parameters.
    filters =
      "config/config.exs"
      |> Config.Reader.read!(env: :test, target: :host)
      |> get_in([:phoenix, :filter_parameters])

    keys = ~w(password current_password email token code secret recovery_code)

    for key <- keys, do: assert(key in filters)

    params = Map.new(keys, &{&1, "plain"})
    filtered = Phoenix.Logger.filter_values(%{"nested" => params, "new_email" => "plain"})
    assert filtered["new_email"] == "[FILTERED]"
    assert Enum.all?(filtered["nested"], fn {_key, value} -> value == "[FILTERED]" end)
  end

  test "a failed delivery logs a warning with the job id and the kind, without the address" do
    previous = Application.fetch_env!(:espalier, Espalier.Mailer)
    Application.put_env(:espalier, Espalier.Mailer, adapter: Espalier.Test.FailingMailAdapter)
    on_exit(fn -> Application.put_env(:espalier, Espalier.Mailer, previous) end)

    {:ok, user} = Accounts.invite_user(Scope.system(), %{email: "failing@example.org"})

    log =
      capture_log([level: :warning], fn ->
        assert {:error, _reason} =
                 perform_job(MailWorker, %{kind: "invitation", user_id: user.id})
      end)

    assert log =~ ~r/mail delivery failed: job \d+, kind invitation/
    refute log =~ "failing@example.org"
  end

  test "an unhandled exception is logged by the HTTP server: Bandit logs 500 by default" do
    # Bandit 1.12 logs exceptions whose status lies in log_exceptions_with_status_codes,
    # 500..599 by default; the endpoint configuration does not narrow it.
    http = Application.get_env(:espalier, EspalierWeb.Endpoint)[:http] || []
    assert Keyword.get(http, :log_exceptions_with_status_codes, 500..599) == 500..599
  end
end
