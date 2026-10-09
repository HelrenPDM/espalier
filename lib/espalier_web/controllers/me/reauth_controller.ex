defmodule EspalierWeb.Me.ReauthController do
  @moduledoc """
  Re-authentication with a local second factor (`POST /api/me/reauth`):
  TOTP, or a passkey with options of the purpose `reauth`. A success
  reissues the session token with `mfa_at` now, which opens the window of
  `require_recent_auth` for 10 minutes, and rotates the CSRF token. Every
  failure answers 401 `authentication_failed`. Federated users without a
  local factor step up through their provider (task 0006).
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts.{Factors, Scope}
  alias EspalierWeb.{FactorInput, FallbackController, SessionController, UserAuth}
  alias EspalierWeb.Plugs.RateLimit

  action_fallback EspalierWeb.FallbackController

  def create(conn, params) do
    user = conn.assigns.current_scope.user

    with {:ok, factor, input} <- FactorInput.parse(params, [:totp, :passkey]) do
      conn = RateLimit.check_account(conn, :reauth_user, user.id)
      if conn.halted, do: conn, else: verify(conn, user, factor, input)
    end
  end

  defp verify(conn, user, factor, input) do
    {conn, fun} = FactorInput.verifier(conn, user, factor, input, :reauth)

    with {:ok, _result} <- Factors.verify(user, factor, fun, %{ip: conn.remote_ip}),
         {:ok, conn} <- UserAuth.step_up(conn, factor) do
      scope = conn.assigns.current_scope

      SessionController.render_session(conn, :ok, %{
        recent_auth_until: Scope.recent_auth_until(scope.session.mfa_at)
      })
    else
      {:error, :not_found} -> FallbackController.render_error(conn, :unauthenticated)
      {:error, _reason} -> FallbackController.render_error(conn, :authentication_failed)
    end
  end
end
