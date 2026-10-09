defmodule EspalierWeb.Me.SecurityController do
  @moduledoc """
  The second factors of the signed-in user (`GET /api/me/security`): passkeys,
  TOTP, the recovery codes left, whether a password is set, whether an admin
  still needs a passkey, and the end of the recent-auth window. Enrollment
  and recovery sessions reach it.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts.{Factors, Scope}

  def show(conn, _params) do
    scope = conn.assigns.current_scope

    recent_auth_until =
      if Scope.recent_auth?(scope), do: Scope.recent_auth_until(scope.session.mfa_at)

    json(conn, Map.put(Factors.summary(scope.user), :recent_auth_until, recent_auth_until))
  end
end
