defmodule Espalier.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  alias Espalier.Accounts.PasswordPolicy
  alias Espalier.Crypto.Keys
  alias Espalier.Identity.{Ldap, Oidc}
  alias Espalier.Media
  alias Espalier.Telemetry.QueryLog
  alias EspalierWeb.Plugs.SecurityHeaders

  @impl true
  def start(_type, _args) do
    Keys.check!()

    if Application.get_env(:espalier, QueryLog, [])[:enabled] do
      QueryLog.attach()
    end

    PasswordPolicy.load_lists()
    Espalier.RateLimit.init_key(secret_key_base())
    warn_settings()
    log_settings()
    Ldap.log_providers()

    # The CSP of the application with the media hosts of task 0018, read by
    # EspalierWeb.Plugs.SecurityHeaders on every response.
    SecurityHeaders.put_csp(Media.external_hosts(), Media.embed_hosts())

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
          # Each LDAP sign-in runs in a task with a hard deadline (task 0007).
          {Task.Supervisor, name: Espalier.Identity.LdapTaskSupervisor},
          # The checks and imports of pack drafts run in tasks, at most
          # max_parallel_checks at once with the zip builds of the draft
          # downloads (task 0016a), and at most max_parallel_downloads
          # downloads run at once, one per user (task 0018).
          {Task.Supervisor, name: Espalier.Workbench.TaskSupervisor},
          Espalier.Workbench.CheckLimiter,
          Espalier.Workbench.DownloadLimiter,
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

  @doc """
  Returns the one line that the boot logs with the effective session and
  data protection settings (README sections 6.11 and 10) and each provider
  with its key, type and MFA mode: values only, without any secret or
  address.
  """
  @spec settings_line() :: String.t()
  def settings_line, do: settings_line(&Application.get_env(:espalier, &1))

  # The line for the settings that `get` returns for each key of
  # `config :espalier`, so that a test can pass fixed values.
  @doc false
  @spec settings_line((atom() -> term())) :: String.t()
  def settings_line(get) do
    learning = get.(:learning) || []
    insights = get.(:insights) || []

    providers =
      case get.(:identity_providers) || [] do
        [] -> "none"
        providers -> Enum.map_join(providers, ", ", &"#{&1.key} (#{&1.type}, MFA #{&1.mfa})")
      end

    settings = [
      {"SESSION_IDLE_MINUTES", get.(:session_idle_minutes)},
      {"SESSION_MAX_HOURS", get.(:session_max_hours)},
      {"SESSION_MAX_CONCURRENT", get.(:session_max_concurrent)},
      {"SIGNUP", get.(:signup)},
      {"LOCAL_ACCOUNTS", get.(:local_accounts)},
      {"AUTH_DEMO", get.(:auth_demo)},
      {"PASSWORD_BREACH_CHECK", get.(:password_breach_check)},
      {"TRACKING_DETAIL", learning[:tracking_detail]},
      {"INSIGHTS_ORG_UNIT", learning[:insights_org_unit]},
      {"REGISTRAR_ENABLED", get.(:registrar_enabled)},
      {"INSIGHTS_MIN_GROUP_SIZE", insights[:min_group_size]},
      {"FEEDBACK_FREE_TEXT", insights[:feedback_free_text]},
      {"TEST_NOTES", insights[:test_notes]},
      {"RETENTION_ATTEMPTS_DAYS", insights[:retention_attempts_days]},
      {"RETENTION_ITEM_RESPONSES_DAYS", insights[:retention_item_responses_days]},
      {"RETENTION_ANONYMOUS_DAYS", insights[:retention_anonymous_days]},
      {"RETENTION_AUDIT_DAYS", insights[:retention_audit_days]}
    ]

    "Effective settings: " <>
      Enum.map_join(settings, " ", &setting/1) <>
      "; providers: " <> providers
  end

  defp setting({name, nil}), do: "#{name}=unset"
  defp setting({name, value}), do: "#{name}=#{value}"

  defp log_settings, do: Logger.info(settings_line())

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EspalierWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
