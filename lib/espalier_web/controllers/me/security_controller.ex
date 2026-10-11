defmodule EspalierWeb.Me.SecurityController do
  @moduledoc """
  The second factors of the signed-in user (`GET /api/me/security`): passkeys,
  TOTP, the recovery codes left, whether a password is set, whether an admin
  still needs a passkey, and the end of the recent-auth window. Enrollment
  and recovery sessions reach it.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.SecuritySummary

  # OpenAPI operations of task 0011 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0005.
  tags ["Account"]
  security Responses.session()

  alias Espalier.Accounts.{Factors, Scope}

  operation :show,
    summary: "List the own second factors",
    description:
      "Passkeys, the authenticator app, the recovery codes left, whether a password is " <>
        "set, the linked providers and the end of the recent-auth window. Enrollment and " <>
        "recovery sessions reach it.",
    responses:
      Map.merge(
        %{200 => {"The factors", "application/json", SecuritySummary}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["forbidden", "cross_site_request"]}
        ])
      )

  def show(conn, _params) do
    scope = conn.assigns.current_scope

    recent_auth_until =
      if Scope.recent_auth?(scope), do: Scope.recent_auth_until(scope.session.mfa_at)

    json(conn, Map.put(Factors.summary(scope.user), :recent_auth_until, recent_auth_until))
  end
end
