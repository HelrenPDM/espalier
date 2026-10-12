defmodule Espalier.RuntimeConfig do
  @moduledoc """
  Parses and validates the account and session settings from the
  environment (README section 6.11). `config/runtime.exs` calls `parse!/2`
  in every environment, so an invalid value stops the boot with a message
  that names the variable and never contains a secret.

  | Variable | Key | Default |
  |---|---|---|
  | `SESSION_IDLE_MINUTES` | `:session_idle_minutes` | 60 |
  | `SESSION_MAX_HOURS` | `:session_max_hours` | 24 |
  | `SESSION_MAX_CONCURRENT` | `:session_max_concurrent` | 5 |
  | `LOCAL_ACCOUNTS` | `:local_accounts` | `true` |
  | `SIGNUP` | `:signup` | `closed` (`invite`, `domain`) |
  | `SIGNUP_DOMAINS` | `:signup_domains` | none |
  | `PASSWORD_BREACH_CHECK` | `:password_breach_check` | `off` (`hibp`) |
  | `PASSWORD_CONTEXT_WORDS` | `:password_context_words` | none |
  | `AUTH_DEMO` | `:auth_demo` | `false` |
  | `BOOTSTRAP_ADMIN_EMAILS` | `:bootstrap_admin_emails` | none |
  | `TRUSTED_PROXIES` | `:trusted_proxies` | none |
  | `PUBLIC_URL` | `:public_url` | `http://localhost:5173`, required in production |
  | `MAIL_FROM` | `:mail_from` | `Espalier <noreply@localhost>`, required in production with `SMTP_HOST` |
  | `ADMIN_REQUIRE_PASSKEY` | `:admin_require_passkey` | `true` |
  | `TRACKING_DETAIL` | `:learning`, `:tracking_detail` | `minimal` (`standard`) |
  | `INSIGHTS_ORG_UNIT` | `:learning`, `:insights_org_unit` | `false` |
  | `CREDENTIAL_NOTICE_DAYS` | `:credential_notice_days` | 30 |
  | `CREDENTIAL_GRACE_DAYS` | `:credential_grace_days` | 30 |
  | `REGISTRAR_ENABLED` | `:registrar_enabled` | `false` |
  | `WEBHOOK_ALLOWED_HOSTS` | `:webhook_allowed_hosts` | none |
  | `INSIGHTS_MIN_GROUP_SIZE` | `:insights`, `:min_group_size` | 5 |
  | `FEEDBACK_FREE_TEXT` | `:insights`, `:feedback_free_text` | `false` |
  | `TEST_NOTES` | `:insights`, `:test_notes` | `false` |
  | `RETENTION_ITEM_RESPONSES_DAYS` | `:insights`, `:retention_item_responses_days` | unset |
  | `RETENTION_ANONYMOUS_DAYS` | `:insights`, `:retention_anonymous_days` | unset |
  | `RETENTION_AUDIT_DAYS` | `:insights`, `:retention_audit_days` | unset |
  | `RETENTION_ATTEMPTS_DAYS` | `:insights`, `:retention_attempts_days` | unset |
  | `PACK_UPLOAD_MAX_MB` | `:pack_upload_max_mb` | 20 |
  | `EXPORT_DIR` | `:export_dir` | `tmp/exports` (`tmp/test-exports` in tests), required in production |

  `TRACKING_DETAIL` and `INSIGHTS_ORG_UNIT` (README section 10) come back
  under the key `:learning`, so that `config :espalier, :learning` holds
  both.

  The insights settings of task 0014 come back under the key `:insights`:
  the group threshold of the reports, the switches for free-text feedback
  and the test session notes, and the four retention periods in days. An
  unset retention variable is `nil`, and `Espalier.Insights.RetentionWorker`
  then deletes nothing from its tables (README section 10).

  `WEBHOOK_ALLOWED_HOSTS` (task 0013) lists the receivers of webhooks as
  comma-separated entries `host` or `host:port`, an IPv6 address in square
  brackets. Each entry becomes `{host, port}` with the host lower-case and
  `port` `nil` for an entry without a port, which stands for the default
  port of the webhook URL's scheme. An entry with a scheme or a path stops
  the boot.

  `PACK_UPLOAD_MAX_MB` (task 0015) bounds the body of a content pack upload
  in MB (ASVS 5.2.1); the archive check of
  `Espalier.Catalog.Pack.Archive.extract/2` admits declared sizes of at most
  five times that limit.

  `EXPORT_DIR` (task 0016) is the directory of the SCORM packages that
  `Espalier.Interop.ExportWorker` writes and the download route reads. The
  defaults of development and tests lie below `tmp/`, which `.gitignore`
  covers; in production an unset value stops the boot.
  """

  @doc "Returns the settings as a keyword list for `config :espalier`."
  @spec parse!(%{optional(String.t()) => String.t()}, atom()) :: keyword()
  def parse!(env, config_env) when is_map(env) do
    signup =
      enum!(
        env,
        "SIGNUP",
        %{"closed" => :closed, "invite" => :invite, "domain" => :domain},
        "closed"
      )

    signup_domains = env |> list("SIGNUP_DOMAINS") |> Enum.map(&String.downcase/1)

    if signup == :domain and signup_domains == [] do
      raise ArgumentError, "SIGNUP=domain requires SIGNUP_DOMAINS"
    end

    [
      session_idle_minutes: positive!(env, "SESSION_IDLE_MINUTES", 60),
      session_max_hours: positive!(env, "SESSION_MAX_HOURS", 24),
      session_max_concurrent: positive!(env, "SESSION_MAX_CONCURRENT", 5),
      local_accounts: boolean!(env, "LOCAL_ACCOUNTS", true),
      signup: signup,
      signup_domains: signup_domains,
      password_breach_check:
        enum!(env, "PASSWORD_BREACH_CHECK", %{"off" => :off, "hibp" => :hibp}, "off"),
      password_context_words: list(env, "PASSWORD_CONTEXT_WORDS"),
      auth_demo: boolean!(env, "AUTH_DEMO", false),
      bootstrap_admin_emails: emails!(env, "BOOTSTRAP_ADMIN_EMAILS"),
      trusted_proxies: env |> list("TRUSTED_PROXIES") |> Enum.map(&proxy!/1),
      public_url: public_url!(env, config_env),
      mail_from: mail_from!(env, config_env),
      admin_require_passkey: boolean!(env, "ADMIN_REQUIRE_PASSKEY", true),
      credential_notice_days: positive!(env, "CREDENTIAL_NOTICE_DAYS", 30),
      credential_grace_days: positive!(env, "CREDENTIAL_GRACE_DAYS", 30),
      registrar_enabled: boolean!(env, "REGISTRAR_ENABLED", false),
      webhook_allowed_hosts: env |> list("WEBHOOK_ALLOWED_HOSTS") |> Enum.map(&webhook_host!/1),
      pack_upload_max_mb: positive!(env, "PACK_UPLOAD_MAX_MB", 20),
      export_dir: export_dir!(env, config_env),
      learning: [
        tracking_detail:
          enum!(
            env,
            "TRACKING_DETAIL",
            %{"minimal" => :minimal, "standard" => :standard},
            "minimal"
          ),
        insights_org_unit: boolean!(env, "INSIGHTS_ORG_UNIT", false)
      ],
      insights: [
        min_group_size: positive!(env, "INSIGHTS_MIN_GROUP_SIZE", 5),
        feedback_free_text: boolean!(env, "FEEDBACK_FREE_TEXT", false),
        test_notes: boolean!(env, "TEST_NOTES", false),
        retention_item_responses_days: positive!(env, "RETENTION_ITEM_RESPONSES_DAYS", nil),
        retention_anonymous_days: positive!(env, "RETENTION_ANONYMOUS_DAYS", nil),
        retention_audit_days: positive!(env, "RETENTION_AUDIT_DAYS", nil),
        retention_attempts_days: positive!(env, "RETENTION_ATTEMPTS_DAYS", nil)
      ]
    ]
  end

  # `docker run --env-file` keeps the double quotes of a .env value, so one
  # pair of surrounding quotes is removed.
  defp value(env, name) do
    value = env |> Map.get(name, "") |> String.trim()

    value =
      if String.length(value) >= 2 and String.starts_with?(value, "\"") and
           String.ends_with?(value, "\""),
         do: value |> String.slice(1..-2//1) |> String.trim(),
         else: value

    if value == "", do: nil, else: value
  end

  defp positive!(env, name, default) do
    case value(env, name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {n, ""} when n > 0 -> n
          _ -> raise ArgumentError, "#{name} must be a positive integer"
        end
    end
  end

  defp boolean!(env, name, default) do
    case value(env, name) do
      nil -> default
      "true" -> true
      "false" -> false
      _ -> raise ArgumentError, "#{name} must be true or false"
    end
  end

  defp enum!(env, name, allowed, default) do
    case Map.fetch(allowed, value(env, name) || default) do
      {:ok, atom} ->
        atom

      :error ->
        raise ArgumentError, "#{name} must be one of #{allowed |> Map.keys() |> Enum.join(", ")}"
    end
  end

  defp list(env, name) do
    case value(env, name) do
      nil -> []
      value -> value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  defp emails!(env, name) do
    for email <- list(env, name) do
      email = email |> String.trim() |> String.downcase()

      if not String.match?(email, ~r/^[^@,;\s]+@[^@,;\s]+$/) do
        raise ArgumentError, "#{name} holds an entry that is no e-mail address"
      end

      email
    end
  end

  @doc """
  Parses one entry of `TRUSTED_PROXIES`, an address or a CIDR range, into
  `{address, prefix_length}`.
  """
  @spec proxy!(String.t()) :: {:inet.ip_address(), non_neg_integer()}
  def proxy!(entry) do
    {address, prefix} =
      case String.split(entry, "/", parts: 2) do
        [address] -> {address, nil}
        [address, prefix] -> {address, prefix}
      end

    with {:ok, ip} <- :inet.parse_strict_address(String.to_charlist(address)),
         bits = if(tuple_size(ip) == 4, do: 32, else: 128),
         {:ok, length} <- prefix_length(prefix, bits) do
      {ip, length}
    else
      _ -> raise ArgumentError, "TRUSTED_PROXIES holds an invalid entry"
    end
  end

  @doc """
  Parses one entry of `WEBHOOK_ALLOWED_HOSTS`, `host` or `host:port`, into
  `{host, port}` with the host lower-case and `port` `nil` for an entry
  without a port.
  """
  @spec webhook_host!(String.t()) :: {String.t(), pos_integer() | nil}
  def webhook_host!(entry) do
    if String.contains?(entry, ["://", "/", "?", "#", "@"]) do
      raise ArgumentError, "WEBHOOK_ALLOWED_HOSTS holds an entry with a scheme or a path"
    end

    with [_entry | groups] <-
           Regex.run(~r/\A(?:\[([0-9a-fA-F:.]+)\]|([A-Za-z0-9.-]+))(?::([0-9]{1,5}))?\z/, entry),
         {host, port} <- host_and_port(groups),
         true <- valid_host?(groups, host),
         true <- port == nil or port in 1..65_535 do
      {String.downcase(host), port}
    else
      _ -> raise ArgumentError, "WEBHOOK_ALLOWED_HOSTS holds an invalid entry"
    end
  end

  # An address in square brackets must be an IPv6 address.
  defp valid_host?([address | _rest], address) when address != "",
    do: match?({:ok, _ip}, :inet.parse_ipv6strict_address(String.to_charlist(address)))

  defp valid_host?(_groups, _name), do: true

  # Regex.run/2 returns "" for an unmatched group before a matched one and
  # leaves out unmatched groups at the end.
  defp host_and_port([address]), do: {address, nil}
  defp host_and_port(["", name]), do: {name, nil}
  defp host_and_port(["", name, port]), do: {name, String.to_integer(port)}
  defp host_and_port([address, "", port]), do: {address, String.to_integer(port)}

  defp prefix_length(nil, bits), do: {:ok, bits}

  defp prefix_length(prefix, bits) do
    case Integer.parse(prefix) do
      {n, ""} when n >= 0 and n <= bits -> {:ok, n}
      _ -> :error
    end
  end

  defp public_url!(env, config_env) do
    case value(env, "PUBLIC_URL") do
      nil when config_env == :prod ->
        raise ArgumentError, "PUBLIC_URL is required"

      nil ->
        "http://localhost:5173"

      url ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and host not in [nil, ""] ->
            String.trim_trailing(url, "/")

          _ ->
            raise ArgumentError, "PUBLIC_URL must be an http or https URL"
        end
    end
  end

  defp export_dir!(env, config_env) do
    case value(env, "EXPORT_DIR") do
      nil when config_env == :prod -> raise ArgumentError, "EXPORT_DIR is required"
      nil when config_env == :test -> "tmp/test-exports"
      nil -> "tmp/exports"
      dir -> dir
    end
  end

  # An instance without SMTP_HOST sends no mail, so MAIL_FROM is required in
  # production only together with SMTP_HOST.
  defp mail_from!(env, config_env) do
    requires_sender? = config_env == :prod and value(env, "SMTP_HOST") != nil

    case value(env, "MAIL_FROM") do
      nil when requires_sender? -> raise ArgumentError, "MAIL_FROM is required with SMTP_HOST"
      nil -> {"Espalier", "noreply@localhost"}
      value -> parse_mail_from!(value)
    end
  end

  defp parse_mail_from!(value) do
    case Regex.run(~r/\A(?:(.*?)\s*<([^<>\s]+@[^<>\s]+)>|([^<>\s]+@[^<>\s]+))\z/, value) do
      [_, name, address] -> {String.trim(name, "\""), address}
      [_, "", "", address] -> {"", address}
      _ -> raise ArgumentError, "MAIL_FROM must be an address or Name <address>"
    end
  end
end
