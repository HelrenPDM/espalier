defmodule Espalier.SecurityLog do
  @moduledoc """
  Security events with the names of the OWASP Logging Vocabulary
  (README section 6.10, `docs/security/logging.md`).

  Each event emits the telemetry event `[:espalier, :security, :event]` and
  writes one log line whose message is the event name and whose metadata
  carries the attributes. Only the names and attribute keys below are
  accepted; any other raises `ArgumentError`, so no token, password, code or
  address reaches the log through this module. Sessions appear by the id of
  their row.
  """

  require Logger

  @events [
    :authn_login_success,
    :authn_login_successafterfail,
    :authn_login_fail,
    :authn_login_fail_max,
    :authn_login_lock,
    :authn_password_change,
    :authn_password_change_fail,
    :authn_token_created,
    :authn_token_revoked,
    :authz_fail,
    :authz_change,
    :privilege_permissions_changed,
    :excess_rate_limit_exceeded,
    :excess_sessions_exceeded,
    :malicious_csrf,
    :session_created,
    :session_renewed,
    :session_expired,
    :session_logout,
    :session_use_after_expire,
    :user_created,
    :user_updated,
    # Rescued wax_ exceptions and rejected clientDataJSON (task 0005).
    :input_validation_fail,
    # Operational event of Espalier.Accounts.BreachedPasswords.
    :breach_check_unavailable,
    # Operational event of the TLS probe after a failed LDAPS connect (task 0007).
    :directory_tls_failed
  ]

  # Failures and rejections log at warning, everything else at info.
  @warnings [
    :authn_login_fail,
    :authn_login_fail_max,
    :authn_login_lock,
    :authn_password_change_fail,
    :authz_fail,
    :excess_rate_limit_exceeded,
    :excess_sessions_exceeded,
    :malicious_csrf,
    :session_use_after_expire,
    :input_validation_fail,
    :breach_check_unavailable,
    :directory_tls_failed
  ]

  @attributes [
    :user_id,
    :session_id,
    :ip,
    :factor,
    :provider,
    :reason,
    :count,
    :account_hash,
    # Task 0005: a sign count that does not increase, the first 8 hex
    # characters of the SHA-256 hash of a credential id, the kind of a factor
    # change, and the module of a rescued exception (never its message).
    :risk_signal,
    :credential_ref,
    :change,
    :exception,
    # Task 0006: the purpose of an OIDC flow (sign_in, link, step_up) and the
    # trigger of a session end (front_channel).
    :purpose,
    :trigger
  ]

  @doc "The accepted event names."
  @spec events() :: [atom()]
  def events, do: @events

  @doc "The accepted attribute keys."
  @spec attributes() :: [atom()]
  def attributes, do: @attributes

  @doc """
  Records the security event `name` with `attrs`.

  ## Options

    * `:level` - overrides the log level (`:info` for successes and
      `:warning` for failures and rejections).
  """
  @spec event(atom(), map() | keyword(), keyword()) :: :ok
  def event(name, attrs \\ %{}, opts \\ []) do
    if name not in @events do
      raise ArgumentError, "unknown security event #{inspect(name)}"
    end

    attrs = Map.new(attrs)

    case Map.keys(attrs) -- @attributes do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown security event attributes #{inspect(unknown)}"
    end

    attrs =
      attrs
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn {key, value} -> {key, format(value)} end)

    :telemetry.execute([:espalier, :security, :event], %{count: 1}, Map.put(attrs, :name, name))

    level = Keyword.get(opts, :level, if(name in @warnings, do: :warning, else: :info))
    Logger.log(level, Atom.to_string(name), [event: name] ++ Map.to_list(attrs))
  end

  defp format(ip) when is_tuple(ip) and tuple_size(ip) in [4, 8],
    do: ip |> :inet.ntoa() |> to_string()

  defp format(value) when is_atom(value) and not is_boolean(value), do: Atom.to_string(value)
  defp format(value), do: value
end
