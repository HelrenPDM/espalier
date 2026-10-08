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
      mail_from: mail_from!(env, config_env)
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
