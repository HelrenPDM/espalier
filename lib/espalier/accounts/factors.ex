defmodule Espalier.Accounts.Factors do
  @moduledoc """
  Factor rules and the shared verification path of the second factors
  (README sections 6.2, 6.6 and 6.10).

  A local account is enrolled when it holds a passkey, or a confirmed TOTP
  factor together with a password or an external identity. The last
  remaining second factor cannot be removed, and with
  `ADMIN_REQUIRE_PASSKEY=true` an admin keeps at least one passkey.

  `verify/5` checks the durable failure counter of a factor before it runs
  the verification, records a failure against the user that the request
  identified before any verification, resets the counter on success, and
  writes the security events and mails of these outcomes.
  """

  import Ecto.Query

  alias Espalier.Accounts

  alias Espalier.Accounts.{
    FailureCounters,
    MailWorker,
    Passkeys,
    RecoveryCodes,
    Scope,
    Totp,
    User,
    UserToken,
    WebauthnCredential
  }

  alias Espalier.{Repo, SecurityLog}
  alias EspalierWeb.UserAuth

  @mail_after_failures 5

  ## Rules

  @doc """
  True when the user holds a passkey, or a confirmed TOTP factor together
  with a password or an external identity.
  """
  def satisfied?(%User{} = user) do
    holds_passkey?(user) or (Totp.enabled?(user) and first_factor?(user))
  end

  defp first_factor?(user) do
    is_binary(user.hashed_password) or Accounts.external_identity?(user)
  end

  @doc "True when the user holds a passkey. The passkey gate of task 0015 calls it."
  def holds_passkey?(%User{id: user_id}) do
    Repo.exists?(from c in WebauthnCredential, where: c.user_id == ^user_id)
  end

  @doc """
  Checks whether `factor` (`{:passkey, credential}` or `:totp`) may be
  removed. Returns `:ok`, `{:error, :admin_passkey_required}` for the last
  passkey of an admin while `ADMIN_REQUIRE_PASSKEY` is `true`, or
  `{:error, :last_factor}` when the account would hold no second factor.
  """
  def removable?(%User{} = user, factor) do
    passkeys = Repo.aggregate(from(c in WebauthnCredential, where: c.user_id == ^user.id), :count)
    passkey? = match?({:passkey, _}, factor)
    passkeys_after = if passkey?, do: passkeys - 1, else: passkeys

    cond do
      passkey? and passkeys_after == 0 and admin_requires_passkey?(user) ->
        {:error, :admin_passkey_required}

      passkeys_after > 0 or totp_after?(user, factor) ->
        :ok

      true ->
        {:error, :last_factor}
    end
  end

  defp totp_after?(user, factor),
    do: factor != :totp and Totp.enabled?(user) and first_factor?(user)

  @doc """
  Removes `factor` (`{:passkey, credential}` or `:totp`) of the scope's user
  after `removable?/2`. The check and the deletion run in one transaction
  that locks the user row first, so concurrent removals run one after the
  other and the second sees the state after the first. Returns `:ok`,
  `{:error, :last_factor}`, `{:error, :admin_passkey_required}` or
  `{:error, :not_found}`.
  """
  def remove(%Scope{user: %User{} = user} = scope, factor) do
    result =
      Repo.transact(fn ->
        Accounts.lock_user!(user)

        with :ok <- removable?(user, factor),
             :ok <- delete_factor(scope, factor) do
          {:ok, factor}
        end
      end)

    with {:ok, _factor} <- result, do: :ok
  end

  defp delete_factor(%Scope{user: user}, {:passkey, %WebauthnCredential{id: id}}) do
    case Repo.delete_all(
           from c in WebauthnCredential, where: c.id == ^id and c.user_id == ^user.id
         ) do
      {1, _} -> :ok
      _ -> {:error, :not_found}
    end
  end

  defp delete_factor(scope, :totp), do: Totp.disable(scope)

  defp admin_requires_passkey?(user) do
    Application.get_env(:espalier, :admin_require_passkey, true) and
      :admin in Accounts.roles_for(user)
  end

  @doc """
  True when `ADMIN_REQUIRE_PASSKEY` is set, `roles` hold `admin` and the
  user holds no passkey (`flags.admin_passkey_required` of the session).
  """
  def admin_passkey_required?(%User{} = user, roles) do
    Application.get_env(:espalier, :admin_require_passkey, true) and :admin in roles and
      not holds_passkey?(user)
  end

  @doc "The body of `GET /api/me/security` without `recent_auth_until`."
  def summary(%User{} = user) do
    totp = Totp.get_enabled(user)

    %{
      passkeys:
        for credential <- Passkeys.list_credentials(user) do
          %{
            id: credential.id,
            nickname: credential.nickname,
            inserted_at: credential.inserted_at,
            last_used_at: credential.last_used_at,
            backup_eligible: credential.backup_eligible,
            backed_up: credential.backed_up,
            transports: credential.transports
          }
        end,
      totp: %{enabled: not is_nil(totp), enabled_at: totp && totp.enabled_at},
      recovery_codes: %{
        remaining: RecoveryCodes.remaining(user),
        generated_at: RecoveryCodes.generated_at(user)
      },
      password_set: is_binary(user.hashed_password),
      admin_passkey_required: admin_passkey_required?(user, Accounts.roles_for(user))
    }
  end

  ## Enrollment and recovery

  @doc """
  Completes an enrollment or a recovery after a new factor `method`.

  It runs only in a session of strength `enrollment` or `recovery` and when
  `satisfied?/1` holds. It issues ten recovery codes when the user holds
  none, and always in a recovery. A recovery also clears every failure
  counter, which re-enables disabled authenticators. It deletes the
  invitation tokens of the user and signs in with strength `mfa` through
  `log_in_user/3`, which replaces the session row and rotates the CSRF
  token; the new row keeps `provider_key` and the bytes of `idp_sid_hash`.

  Returns `{conn, codes}`, where `codes` is `nil` when no new codes were
  issued or the session was not upgraded.
  """
  def complete_enrollment(conn, %Scope{user: user, session: %UserToken{} = session}, method)
      when session.strength in [:enrollment, :recovery] do
    if satisfied?(user) do
      codes =
        if session.strength == :recovery or not RecoveryCodes.any?(user),
          do: RecoveryCodes.generate(Scope.for_user(user))

      if session.strength == :recovery, do: FailureCounters.clear_all(user)

      Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id and t.context == :invite)

      conn =
        UserAuth.log_in_user(conn, user,
          auth_methods: session.auth_methods ++ [method],
          strength: :mfa,
          mfa_at: DateTime.utc_now(:second),
          provider_key: session.provider_key,
          idp_sid_hash: session.idp_sid_hash,
          completes: session.strength
        )

      {conn, codes}
    else
      {conn, nil}
    end
  end

  def complete_enrollment(conn, %Scope{}, _method), do: {conn, nil}

  ## Verification

  @doc """
  Verifies the factor `kind` (`:totp`, `:passkey` or `:recovery_code`) of
  `user` through `fun`, which returns `:ok`, `{:ok, result}` or
  `{:error, reason}`.

  A locked or disabled counter fails without running `fun` and without
  counting. Any other failure counts against `user`; the fiftieth disables
  the factor and mails the user. A success resets the counter and mails the
  user when it stood at five or more. `meta` carries `:ip`.

  ## Options

    * `:events` - `false` skips the success event and the mail after
      failures (TOTP confirmation, which is no sign-in). Defaults to `true`.
    * `:allow_disabled` - lets a disabled counter pass (the confirmation of
      a new TOTP factor in a recovery session).
  """
  def verify(%User{} = user, kind, fun, meta \\ %{}, opts \\ [])
      when kind in [:totp, :passkey, :recovery_code] do
    now = DateTime.utc_now()
    log = %{user_id: user.id, ip: meta[:ip], factor: kind}

    case {FailureCounters.check(user, kind, now), Keyword.get(opts, :allow_disabled, false)} do
      {status, allow_disabled?} when status == :ok or (status == :disabled and allow_disabled?) ->
        run_verification(user, kind, fun, log, now, opts)

      {:disabled, false} ->
        log_failure(log, :counter_disabled)

      {{:locked, _until}, _allow_disabled?} ->
        log_failure(log, :counter_locked)
    end
  end

  defp run_verification(user, kind, fun, log, now, opts) do
    case fun.() do
      :ok -> record_success(user, kind, nil, log, opts)
      {:ok, result} -> record_success(user, kind, result, log, opts)
      {:error, reason} -> record_failure(user, kind, reason, log, now)
    end
  end

  @doc """
  Records a verified factor without a counter check: resets the counter,
  mails the user after five or more failures and logs the success. The
  discoverable passkey sign-in calls it after `Passkeys.authenticate/4`.
  """
  def record_success(%User{} = user, kind, result, log, opts \\ []) do
    previous = FailureCounters.reset(user, kind)

    if Keyword.get(opts, :events, true) do
      if previous >= @mail_after_failures do
        Oban.insert!(
          MailWorker.job("failed_attempts", %{
            user_id: user.id,
            count: previous,
            factor: Atom.to_string(kind)
          })
        )

        SecurityLog.event(:authn_login_successafterfail, Map.put(log, :count, previous))
      end

      success_event(log, result)
    end

    {:ok, result}
  end

  defp success_event(log, %{risk_signal: "sign_count", credential: credential}) do
    SecurityLog.event(
      :authn_login_success,
      Map.merge(log, %{
        risk_signal: "sign_count",
        credential_ref: WebauthnCredential.credential_ref(credential.credential_id)
      }),
      level: :warning
    )
  end

  defp success_event(log, _result), do: SecurityLog.event(:authn_login_success, log)

  defp record_failure(user, kind, reason, log, now) do
    {:ok, counter} = FailureCounters.record_failure(user, kind, now)

    if counter.consecutive_failures == FailureCounters.disable_at() do
      Oban.insert!(
        MailWorker.job("authenticator_disabled", %{user_id: user.id, factor: Atom.to_string(kind)})
      )
    end

    log_failure(log, reason)
  end

  @doc "Logs `authn_login_fail` with `reason` and returns `{:error, reason}`."
  def log_failure(log, reason) do
    SecurityLog.event(:authn_login_fail, Map.put(log, :reason, reason))
    {:error, reason}
  end

  ## Notifications of factor changes

  @doc """
  Mails the user and logs `user_updated` for a factor change: `change` is
  `:factor_added`, `:factor_removed` or `:recovery_codes_regenerated`.
  """
  def notify_change(%User{} = user, change, factor) do
    {kind, args} =
      case change do
        :factor_added -> {"factor_added", %{factor: Atom.to_string(factor)}}
        :factor_removed -> {"factor_removed", %{factor: Atom.to_string(factor)}}
        :recovery_codes_regenerated -> {"recovery_codes_regenerated", %{}}
      end

    Oban.insert!(MailWorker.job(kind, Map.put(args, :user_id, user.id)))
    SecurityLog.event(:user_updated, %{user_id: user.id, change: change, factor: factor})
  end
end
