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

  `PUBLIC_URL` comes back with a lower-case host, without the default port
  of its scheme and without a trailing `/`, which is the form of the origin
  that browsers send (task 0017).

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
  covers; in production an unset value stops the boot. The directory
  belongs to one installation and its database: the retention of
  `Espalier.Interop.prune_exports/1` deletes the packages there that the
  database does not know, so two installations must not share it.

  `errors/2` runs the same checks as `parse!/2` and returns the message of
  every invalid value instead of raising at the first, so that the boot
  check of task 0017 (`Espalier.BootCheck`) names every gap in one boot.
  """

  @typep env :: %{optional(String.t()) => String.t()}

  @doc """
  Returns the settings as a keyword list for `config :espalier`, or raises
  `ArgumentError` with the message of the first invalid value.
  """
  @spec parse!(env(), atom()) :: keyword()
  def parse!(env, config_env) when is_map(env) do
    case parse(env, config_env) do
      {settings, []} -> settings
      {_settings, [message | _rest]} -> raise ArgumentError, message
    end
  end

  @doc """
  Runs the checks of `parse!/2` and returns the message of every invalid or
  missing value in the order of the variables, or `[]`. A message names the
  variable and never contains its value.
  """
  @spec errors(env(), atom()) :: [String.t()]
  def errors(env, config_env) when is_map(env) do
    {_settings, errors} = parse(env, config_env)
    errors
  end

  @doc """
  Returns the trimmed value of `name` in `env` without one pair of
  surrounding double quotes, or `nil` for a missing, empty or
  whitespace-only value. `docker run --env-file` keeps the double quotes of
  a .env value.
  """
  @spec value(env(), String.t()) :: String.t() | nil
  def value(env, name) do
    value = env |> Map.get(name, "") |> String.trim()

    value =
      if String.length(value) >= 2 and String.starts_with?(value, "\"") and
           String.ends_with?(value, "\""),
         do: value |> String.slice(1..-2//1) |> String.trim(),
         else: value

    if value == "", do: nil, else: value
  end

  defp parse(env, config_env) do
    signup =
      enum(
        env,
        "SIGNUP",
        %{"closed" => :closed, "invite" => :invite, "domain" => :domain},
        "closed"
      )

    fields = [
      session_idle_minutes: positive(env, "SESSION_IDLE_MINUTES", 60),
      session_max_hours: positive(env, "SESSION_MAX_HOURS", 24),
      session_max_concurrent: positive(env, "SESSION_MAX_CONCURRENT", 5),
      local_accounts: boolean(env, "LOCAL_ACCOUNTS", true),
      signup: signup,
      signup_domains: signup_domains(env, signup),
      password_breach_check:
        enum(env, "PASSWORD_BREACH_CHECK", %{"off" => :off, "hibp" => :hibp}, "off"),
      password_context_words: {:ok, list(env, "PASSWORD_CONTEXT_WORDS")},
      auth_demo: boolean(env, "AUTH_DEMO", false),
      bootstrap_admin_emails: entries(env, "BOOTSTRAP_ADMIN_EMAILS", &email/1),
      trusted_proxies: entries(env, "TRUSTED_PROXIES", &proxy/1),
      public_url: public_url(env, config_env),
      mail_from: mail_from(env, config_env),
      admin_require_passkey: boolean(env, "ADMIN_REQUIRE_PASSKEY", true),
      credential_notice_days: positive(env, "CREDENTIAL_NOTICE_DAYS", 30),
      credential_grace_days: positive(env, "CREDENTIAL_GRACE_DAYS", 30),
      registrar_enabled: boolean(env, "REGISTRAR_ENABLED", false),
      webhook_allowed_hosts: entries(env, "WEBHOOK_ALLOWED_HOSTS", &webhook_host/1),
      pack_upload_max_mb: positive(env, "PACK_UPLOAD_MAX_MB", 20),
      export_dir: export_dir(env, config_env),
      learning: [
        tracking_detail:
          enum(
            env,
            "TRACKING_DETAIL",
            %{"minimal" => :minimal, "standard" => :standard},
            "minimal"
          ),
        insights_org_unit: boolean(env, "INSIGHTS_ORG_UNIT", false)
      ],
      insights: [
        min_group_size: positive(env, "INSIGHTS_MIN_GROUP_SIZE", 5),
        feedback_free_text: boolean(env, "FEEDBACK_FREE_TEXT", false),
        test_notes: boolean(env, "TEST_NOTES", false),
        retention_item_responses_days: positive(env, "RETENTION_ITEM_RESPONSES_DAYS", nil),
        retention_anonymous_days: positive(env, "RETENTION_ANONYMOUS_DAYS", nil),
        retention_audit_days: positive(env, "RETENTION_AUDIT_DAYS", nil),
        retention_attempts_days: positive(env, "RETENTION_ATTEMPTS_DAYS", nil)
      ]
    ]

    {settings, errors} = Enum.map_reduce(fields, [], &resolve/2)
    {settings, Enum.reverse(errors)}
  end

  # A field holds a result or a keyword list of results; an invalid value
  # becomes nil in the settings and adds its message.
  defp resolve({key, {:ok, value}}, errors), do: {{key, value}, errors}
  defp resolve({key, {:error, message}}, errors), do: {{key, nil}, [message | errors]}

  defp resolve({key, fields}, errors) when is_list(fields) do
    {values, errors} = Enum.map_reduce(fields, errors, &resolve/2)
    {{key, values}, errors}
  end

  defp signup_domains(env, signup) do
    domains = env |> list("SIGNUP_DOMAINS") |> Enum.map(&String.downcase/1)

    if signup == {:ok, :domain} and domains == [],
      do: {:error, "SIGNUP=domain requires SIGNUP_DOMAINS"},
      else: {:ok, domains}
  end

  defp positive(env, name, default) do
    case value(env, name) do
      nil ->
        {:ok, default}

      value ->
        case Integer.parse(value) do
          {n, ""} when n > 0 -> {:ok, n}
          _ -> {:error, "#{name} must be a positive integer"}
        end
    end
  end

  defp boolean(env, name, default) do
    case value(env, name) do
      nil -> {:ok, default}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, "#{name} must be true or false"}
    end
  end

  defp enum(env, name, allowed, default) do
    case Map.fetch(allowed, value(env, name) || default) do
      {:ok, atom} ->
        {:ok, atom}

      :error ->
        {:error, "#{name} must be one of #{allowed |> Map.keys() |> Enum.join(", ")}"}
    end
  end

  defp list(env, name) do
    case value(env, name) do
      nil -> []
      value -> value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  # The entries of a comma-separated list, or the message of the first
  # invalid entry, which names the variable.
  defp entries(env, name, parse) do
    env
    |> list(name)
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, values} ->
      case parse.(entry) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        {:error, _message} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp email(entry) do
    email = entry |> String.trim() |> String.downcase()

    if String.match?(email, ~r/^[^@,;\s]+@[^@,;\s]+$/),
      do: {:ok, email},
      else: {:error, "BOOTSTRAP_ADMIN_EMAILS holds an entry that is no e-mail address"}
  end

  @doc """
  Returns `url` with a lower-case host, without the default port of its
  scheme and without a trailing slash, the form of the origin that browsers
  send. The passkey origins and the Fetch Metadata check compare it exactly,
  and every address that Espalier derives from `PUBLIC_URL` (the OIDC
  redirect URI, the post-logout redirect URI, the links of the mails) uses
  it. A value without a host comes back without the trailing slash only.
  """
  @spec normalize_url(String.t()) :: String.t()
  def normalize_url(url) do
    case URI.parse(url) do
      %URI{host: host} = uri when is_binary(host) and host != "" ->
        %URI{uri | host: String.downcase(host)} |> URI.to_string() |> String.trim_trailing("/")

      _uri ->
        String.trim_trailing(url, "/")
    end
  end

  @doc """
  Parses one entry of `TRUSTED_PROXIES`, an address or a CIDR range, into
  `{address, prefix_length}`. An IPv4-mapped entry (`::ffff:a.b.c.d`) with a
  prefix of at least 96 becomes its IPv4 form with the prefix minus 96,
  because `EspalierWeb.Plugs.TrustedProxy` compares the IPv4 form of a
  mapped peer. Other IPv6 ranges, `::/0` among them, stay IPv6 and match
  IPv6 peers only.
  """
  @spec proxy!(String.t()) :: {:inet.ip_address(), non_neg_integer()}
  def proxy!(entry), do: ok!(proxy(entry))

  defp proxy(entry) do
    {address, prefix} =
      case String.split(entry, "/", parts: 2) do
        [address] -> {address, nil}
        [address, prefix] -> {address, prefix}
      end

    with {:ok, ip} <- :inet.parse_strict_address(String.to_charlist(address)),
         bits = if(tuple_size(ip) == 4, do: 32, else: 128),
         {:ok, length} <- prefix_length(prefix, bits) do
      {:ok, unmap_proxy(ip, length)}
    else
      _ -> {:error, "TRUSTED_PROXIES holds an invalid entry"}
    end
  end

  defp unmap_proxy({0, 0, 0, 0, 0, 0xFFFF, high, low}, length) when length >= 96,
    do: {{div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)}, length - 96}

  defp unmap_proxy(ip, length), do: {ip, length}

  @doc """
  Parses one entry of `WEBHOOK_ALLOWED_HOSTS`, `host` or `host:port`, into
  `{host, port}` with the host lower-case and `port` `nil` for an entry
  without a port.
  """
  @spec webhook_host!(String.t()) :: {String.t(), pos_integer() | nil}
  def webhook_host!(entry), do: ok!(webhook_host(entry))

  defp webhook_host(entry) do
    if String.contains?(entry, ["://", "/", "?", "#", "@"]) do
      {:error, "WEBHOOK_ALLOWED_HOSTS holds an entry with a scheme or a path"}
    else
      with [_entry | groups] <-
             Regex.run(
               ~r/\A(?:\[([0-9a-fA-F:.]+)\]|([A-Za-z0-9.-]+))(?::([0-9]{1,5}))?\z/,
               entry
             ),
           {host, port} <- host_and_port(groups),
           true <- valid_host?(groups, host),
           true <- port == nil or port in 1..65_535 do
        {:ok, {String.downcase(host), port}}
      else
        _ -> {:error, "WEBHOOK_ALLOWED_HOSTS holds an invalid entry"}
      end
    end
  end

  defp ok!({:ok, value}), do: value
  defp ok!({:error, message}), do: raise(ArgumentError, message)

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

  defp public_url(env, config_env) do
    case value(env, "PUBLIC_URL") do
      nil when config_env == :prod ->
        {:error, "PUBLIC_URL is required"}

      nil ->
        {:ok, "http://localhost:5173"}

      url ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and host not in [nil, ""] ->
            {:ok, normalize_url(url)}

          _ ->
            {:error, "PUBLIC_URL must be an http or https URL"}
        end
    end
  end

  defp export_dir(env, config_env) do
    case value(env, "EXPORT_DIR") do
      nil when config_env == :prod -> {:error, "EXPORT_DIR is required"}
      nil when config_env == :test -> {:ok, "tmp/test-exports"}
      nil -> {:ok, "tmp/exports"}
      dir -> {:ok, dir}
    end
  end

  # An instance without SMTP_HOST sends no mail, so MAIL_FROM is required in
  # production only together with SMTP_HOST.
  defp mail_from(env, config_env) do
    requires_sender? = config_env == :prod and value(env, "SMTP_HOST") != nil

    case value(env, "MAIL_FROM") do
      nil when requires_sender? -> {:error, "MAIL_FROM is required with SMTP_HOST"}
      nil -> {:ok, {"Espalier", "noreply@localhost"}}
      value -> parse_mail_from(value)
    end
  end

  defp parse_mail_from(value) do
    case Regex.run(~r/\A(?:(.*?)\s*<([^<>\s]+@[^<>\s]+)>|([^<>\s]+@[^<>\s]+))\z/, value) do
      [_, name, address] -> {:ok, {String.trim(name, "\""), address}}
      [_, "", "", address] -> {:ok, {"", address}}
      _ -> {:error, "MAIL_FROM must be an address or Name <address>"}
    end
  end
end
