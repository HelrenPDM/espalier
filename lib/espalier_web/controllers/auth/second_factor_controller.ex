defmodule EspalierWeb.Auth.SecondFactorController do
  @moduledoc """
  Completes the pending state of a first factor with a TOTP code, a passkey
  or a recovery code (README section 6.2). The session becomes `mfa` through
  `log_in_user/3`, which issues a new token and a new CSRF token and keeps
  the provider and the `sid` hash of the pending state.

  Every failure answers 401 `authentication_failed`. The fifth failure in a
  pending state clears it, so the person starts again with the first
  factor; the bucket `second_factor_user` and the durable counters are the
  limits that hold, because a client can resubmit an earlier cookie.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts.{Factors, MailWorker}

  alias EspalierWeb.{
    FactorInput,
    FallbackController,
    SessionController,
    UserAuth,
    WebauthnCeremony
  }

  alias EspalierWeb.Plugs.RateLimit

  action_fallback EspalierWeb.FallbackController

  @failures_key :pending_second_factor_failures
  @max_failures 5

  plug RateLimit, [bucket: :second_factor_ip] when action in [:create]

  def create(conn, params) do
    with {:ok, factor, input} <- FactorInput.parse(params, [:totp, :passkey, :recovery_code]) do
      case UserAuth.fetch_pending_second_factor(conn) do
        {:ok, pending} -> throttle_and_verify(conn, pending, factor, input)
        :error -> no_pending_state(conn, factor)
      end
    end
  end

  defp throttle_and_verify(conn, pending, factor, input) do
    conn = RateLimit.check_account(conn, :second_factor_user, pending.user.id)
    if conn.halted, do: conn, else: verify(conn, pending, factor, input)
  end

  # The ceremony ends with every request, also without a pending state.
  defp no_pending_state(conn, factor) do
    {conn, _challenge} =
      if factor == :passkey,
        do: WebauthnCeremony.finish(conn, :second_factor, nil),
        else: {conn, nil}

    Factors.log_failure(%{ip: conn.remote_ip, factor: factor}, :no_pending_state)
    FallbackController.render_error(conn, :authentication_failed)
  end

  defp verify(conn, pending, factor, input) do
    user = pending.user
    {conn, fun} = FactorInput.verifier(conn, user, factor, input, :second_factor)

    case Factors.verify(user, factor, fun, %{ip: conn.remote_ip}) do
      {:ok, result} ->
        conn =
          conn
          |> delete_session(@failures_key)
          |> UserAuth.log_in_user(user,
            auth_methods: pending.auth_methods ++ [factor],
            strength: :mfa,
            mfa_at: DateTime.utc_now(:second),
            provider_key: pending.provider_key,
            idp_sid_hash: pending.idp_sid_hash
          )

        respond(conn, user, factor, result)

      {:error, _reason} ->
        conn
        |> count_failure()
        |> FallbackController.render_error(:authentication_failed)
    end
  end

  defp respond(conn, user, :recovery_code, remaining) do
    Oban.insert!(MailWorker.job("recovery_used", %{user_id: user.id, count: remaining}))
    SessionController.render_session(conn, :ok, %{recovery_codes_remaining: remaining})
  end

  defp respond(conn, _user, _factor, _result), do: SessionController.render_session(conn)

  defp count_failure(conn) do
    failures = (get_session(conn, @failures_key) || 0) + 1

    if failures >= @max_failures do
      conn
      |> delete_session(:pending_second_factor)
      |> delete_session(@failures_key)
    else
      put_session(conn, @failures_key, failures)
    end
  end
end
