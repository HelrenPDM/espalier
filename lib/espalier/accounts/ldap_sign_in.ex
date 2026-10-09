defmodule Espalier.Accounts.LdapSignIn do
  @moduledoc """
  Sign-in and linking with a directory account (task 0007, step 16;
  `docs/architecture/auth-ldap.puml`).

  Both pathways verify the directory password the same way:

  1. The bucket `ldap_account` counts the provider key and the normalized
     username before any directory call; a denial returns
     `{:error, :rate_limited, retry_after_ms}`.
  2. `Espalier.Identity.Ldap.authenticate/4` runs the search and the user
     bind. Between them, `before_bind/3` counts the directory subject in the
     bucket `ldap_subject`, because one Active Directory account answers to
     `sAMAccountName` and to `userPrincipalName`, and reserves the durable
     counter with `FailureCounters.reserve_directory/5`.
  3. The result settles the reservation: a success deletes the row, a wrong
     password keeps the count, and every other failure gives it back.
  4. A failed LDAPS connect starts at most one TLS probe per provider and
     minute, which logs `directory_tls_failed`.

  Every failure returns no earlier than `failure_floor_ms` after the call
  started, so an unknown user, a wrong password, a lock and a directory
  error take the same minimum time and give the same answer. Security
  events carry `provider`, `factor` `ldap`, `purpose` and the client IP,
  and the user id when the identity is known, otherwise the `account_hash`
  of the `ldap_account` identifier; never the username, the DN or the
  password.
  """

  import Ecto.Query

  alias Espalier.{Accounts, RateLimit, Repo, SecurityLog}
  alias Espalier.Accounts.{ExternalIdentity, FailureCounters}
  alias Espalier.Identity.{Assertion, Ldap}
  alias Espalier.Identity.Ldap.Config, as: LdapConfig

  @probe_period_ms 60_000

  @doc """
  Signs in with a directory account. `meta` holds `:ip` and an optional
  `:now`.

  Returns `{:ok, user}`, `{:error, :invalid_credentials}` for every
  authentication failure and for a disabled account,
  `{:error, :rate_limited, retry_after_ms}`, or `{:error, :link_required}`
  when the directory's e-mail address belongs to another account.
  """
  def sign_in(%LdapConfig{} = provider, username, password, meta) do
    meta = Map.new(meta)
    started = System.monotonic_time(:millisecond)
    log = log_attrs(provider, meta, "sign_in")

    case verify_directory_password(provider, username, password, meta, log) do
      {:ok, entry, log} ->
        case Accounts.sign_in_external(provider, assertion(provider, entry)) do
          {:ok, user} ->
            SecurityLog.event(
              :authn_login_success,
              log |> Map.delete(:account_hash) |> Map.put(:user_id, user.id)
            )

            {:ok, user}

          {:error, :account_disabled} ->
            fail(log, :account_disabled, started)

          {:error, :no_account} ->
            SecurityLog.event(:authn_login_fail, Map.put(log, :reason, :link_required))
            wait_for_floor(started)
            {:error, :link_required}
        end

      {:error, :rate_limited, _retry_after_ms} = denied ->
        denied

      {:error, :invalid_credentials} ->
        wait_for_floor(started)
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Links a directory account to `user` after the same checks as
  `sign_in/4`, through `Accounts.link_external_identity/3`. It never
  creates a user.

  Returns `{:ok, :linked}`, `{:ok, :already_linked}`,
  `{:error, :identity_in_use}`, `{:error, :provider_already_linked}`,
  `{:error, :invalid_credentials}` or `{:error, :rate_limited, ms}`.
  """
  def link(user, %LdapConfig{} = provider, username, password, meta) do
    meta = Map.new(meta)
    started = System.monotonic_time(:millisecond)
    log = provider |> log_attrs(meta, "link") |> Map.put(:user_id, user.id)

    case verify_directory_password(provider, username, password, meta, log) do
      {:ok, entry, _log} ->
        SecurityLog.event(:authn_login_success, log)

        case Accounts.link_external_identity(user.id, provider, assertion(provider, entry)) do
          {:ok, _linked} = result ->
            result

          {:error, reason} = error ->
            SecurityLog.event(:authn_login_fail, Map.put(log, :reason, reason))
            error
        end

      {:error, :rate_limited, _retry_after_ms} = denied ->
        denied

      {:error, :invalid_credentials} ->
        wait_for_floor(started)
        {:error, :invalid_credentials}
    end
  end

  @doc "The assertion of a directory entry for `Accounts.sign_in_external/2` (step 17)."
  def assertion(%LdapConfig{key: key}, entry) do
    %Assertion{
      provider_key: key,
      issuer: "ldap:" <> key,
      tenant_id: nil,
      subject: entry.subject,
      display_name: entry.display_name,
      email: entry.email,
      roles: entry.groups,
      org_unit: entry.org_unit,
      directory: %{dn: entry.dn, upn: entry.upn, login: entry.login}
    }
  end

  ## Directory password

  # Returns {:ok, entry, log}, {:error, :rate_limited, ms} or
  # {:error, :invalid_credentials}, and logs every failure.
  defp verify_directory_password(provider, username, password, meta, log)
       when is_binary(username) do
    identifier = provider.key <> ":" <> String.downcase(String.trim(username))

    log =
      if Map.has_key?(log, :user_id),
        do: log,
        else: Map.put(log, :account_hash, RateLimit.account_hash(identifier))

    case RateLimit.check_account(:ldap_account, identifier) do
      {:allow, _count} ->
        authenticate(provider, username, password, meta, log)

      {:deny, retry_after_ms} ->
        SecurityLog.event(:excess_rate_limit_exceeded, Map.put(log, :reason, :ldap_account))
        {:error, :rate_limited, retry_after_ms}
    end
  end

  defp verify_directory_password(_provider, _username, _password, _meta, log) do
    SecurityLog.event(:authn_login_fail, Map.put(log, :reason, :invalid_input))
    {:error, :invalid_credentials}
  end

  defp authenticate(provider, username, password, meta, log) do
    now = Map.get(meta, :now, DateTime.utc_now())

    result =
      Ldap.authenticate(provider, username, password,
        before_bind: &before_bind(provider, now, &1)
      )

    log = identify(log, provider, result)

    case result do
      {:ok, entry, reservation} ->
        if reservation, do: FailureCounters.directory_succeeded(reservation)
        {:ok, entry, log}

      {:error, reason, _entry, reservation} ->
        settle_failure(provider, reason, reservation, now, log)
        maybe_probe(provider, reason)
        {:error, :invalid_credentials}
    end
  end

  # Runs inside the sign-in task, between the search and the user bind.
  defp before_bind(provider, now, entry) do
    case RateLimit.check_account(:ldap_subject, provider.key <> ":" <> entry.subject) do
      {:allow, _count} ->
        FailureCounters.reserve_directory(
          provider.key,
          entry.subject,
          provider.failure_limit,
          provider.lock_minutes,
          now
        )

      {:deny, _retry_after_ms} ->
        {:error, :subject_throttled}
    end
  end

  defp settle_failure(_provider, :bind_failed, reservation, now, log) when reservation != nil do
    SecurityLog.event(:authn_login_fail, Map.put(log, :reason, :bind_failed))

    case FailureCounters.directory_failed(reservation, now) do
      :limit_reached ->
        SecurityLog.event(:authn_login_fail_max, Map.put(log, :count, reservation.count))

      :disabled ->
        SecurityLog.event(:authn_login_lock, Map.put(log, :count, reservation.count))

      :counted ->
        :ok
    end
  end

  # A task that is killed after its reservation returns no reservation, and
  # the reserved count stays, which errs towards the directory's threshold.
  defp settle_failure(_provider, reason, reservation, _now, log) do
    if reservation, do: FailureCounters.release_directory(reservation)

    # The subject check runs inside the task, so its event comes from here.
    if reason == :subject_throttled do
      SecurityLog.event(:excess_rate_limit_exceeded, Map.put(log, :reason, :ldap_subject))
    end

    SecurityLog.event(:authn_login_fail, Map.put(log, :reason, reason))
  end

  defp maybe_probe(%LdapConfig{tls: :ldaps} = provider, :connect_failed) do
    case RateLimit.hit({:ldap_tls_probe, provider.key}, @probe_period_ms, 1) do
      {:allow, _count} ->
        Task.Supervisor.start_child(Espalier.Identity.LdapTaskSupervisor, fn ->
          probe(provider)
        end)

      {:deny, _retry_after_ms} ->
        :ok
    end
  end

  defp maybe_probe(_provider, _reason), do: :ok

  defp probe(provider) do
    case Ldap.tls_probe(provider) do
      :ok ->
        :ok

      {:error, reason} ->
        SecurityLog.event(:directory_tls_failed, %{
          provider: provider.key,
          reason: Ldap.reason_tag(reason)
        })
    end
  end

  ## Logging and timing

  defp log_attrs(provider, meta, purpose) do
    %{provider: provider.key, factor: "ldap", purpose: purpose, ip: meta[:ip]}
  end

  # An event carries the user id once the directory identity is known, and
  # the account hash only for an unknown one.
  defp identify(%{user_id: _user_id} = log, _provider, _result),
    do: Map.delete(log, :account_hash)

  defp identify(log, provider, result) do
    entry =
      case result do
        {:ok, entry, _reservation} -> entry
        {:error, _reason, entry, _reservation} -> entry
      end

    case entry && identity_user_id(provider, entry.subject) do
      nil -> log
      user_id -> log |> Map.delete(:account_hash) |> Map.put(:user_id, user_id)
    end
  end

  defp identity_user_id(provider, subject) do
    Repo.one(
      from i in ExternalIdentity,
        where:
          i.provider_key == ^provider.key and
            i.subject_hash == ^ExternalIdentity.hash_input("ldap:" <> provider.key, nil, subject),
        select: i.user_id
    )
  end

  defp fail(log, reason, started) do
    SecurityLog.event(:authn_login_fail, Map.put(log, :reason, reason))
    wait_for_floor(started)
    {:error, :invalid_credentials}
  end

  # The floor covers the time difference between an unknown user (one
  # connection) and a wrong password (two connections and the group
  # searches).
  defp wait_for_floor(started) do
    floor =
      Application.get_env(:espalier, __MODULE__, []) |> Keyword.get(:failure_floor_ms, 1_000)

    remaining = started + floor - System.monotonic_time(:millisecond)
    if remaining > 0, do: Process.sleep(remaining)
    :ok
  end
end
