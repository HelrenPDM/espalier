defmodule Espalier.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  alias Espalier.Accounts.PasswordPolicy
  alias Espalier.Crypto.Keys
  alias Espalier.Identity.Oidc
  alias Espalier.Telemetry.QueryLog

  @impl true
  def start(_type, _args) do
    Keys.check!()

    if Application.get_env(:espalier, QueryLog, [])[:enabled] do
      QueryLog.attach()
    end

    PasswordPolicy.load_lists()
    Espalier.RateLimit.init_key(secret_key_base())
    warn_settings()

    children =
      [
        EspalierWeb.Telemetry,
        Espalier.Vault,
        Espalier.Repo,
        {Oban, Application.fetch_env!(:espalier, Oban)}
      ] ++
        bootstrap() ++
        Application.get_env(:espalier, :dev_children, []) ++
        oidc() ++
        [
          {Espalier.RateLimit, clean_period: :timer.minutes(1)},
          {DNSCluster, query: Application.get_env(:espalier, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Espalier.PubSub},
          # Start to serve requests, typically the last entry
          EspalierWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Espalier.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # The boot task grants admin to BOOTSTRAP_ADMIN_EMAILS; release functions
  # and the test suite switch it off.
  defp bootstrap do
    if Application.get_env(:espalier, :bootstrap_on_boot, false),
      do: [Espalier.Accounts.Bootstrap],
      else: []
  end

  # One configuration worker per OIDC provider (task 0006). The test suite
  # starts the supervisor per test.
  defp oidc do
    if Oidc.oidc_env(:start_supervisor, true),
      do: [Oidc.Supervisor],
      else: []
  end

  defp secret_key_base do
    Application.fetch_env!(:espalier, EspalierWeb.Endpoint)[:secret_key_base] || ""
  end

  defp warn_settings do
    if Application.get_env(:espalier, :auth_demo, false) do
      Logger.warning("AUTH_DEMO=true: demo sign-in is enabled; use it for test sessions only")
    end

    if Application.get_env(:espalier, :session_max_hours, 24) > 24 do
      Logger.warning(
        "SESSION_MAX_HOURS is above 24, which deviates from decision D9 (NIST AAL2, ASVS 7.1.1)"
      )
    end

    if not Application.get_env(:espalier, :admin_require_passkey, true) do
      Logger.warning("ADMIN_REQUIRE_PASSKEY=false: admins may sign in and work without a passkey")
    end

    if Application.get_env(:espalier, Espalier.Mailer)[:adapter] ==
         Espalier.Mailer.DisabledAdapter do
      Logger.warning("SMTP_HOST is not set: this instance delivers no mail")
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EspalierWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
