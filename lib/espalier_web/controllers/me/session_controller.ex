defmodule EspalierWeb.Me.SessionController do
  @moduledoc """
  Lists the sessions of the signed-in user and ends one of them after
  re-authentication (ASVS 7.5.2).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Fields, SessionList}

  # OpenAPI operations of task 0009 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0004.
  tags ["Account"]

  alias Espalier.Accounts

  action_fallback EspalierWeb.FallbackController

  operation :index,
    summary: "List the own sessions",
    security: Responses.session(),
    responses:
      Map.merge(
        %{200 => {"The sessions", "application/json", SessionList}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]}
        ])
      )

  def index(conn, _params) do
    scope = conn.assigns.current_scope

    sessions =
      for session <- Accounts.list_sessions(scope.user) do
        %{
          id: session.id,
          current: session.id == scope.session.id,
          device: session.device_summary,
          strength: session.strength,
          auth_methods: session.auth_methods,
          authenticated_at: session.authenticated_at,
          last_seen_at: session.last_seen_at,
          expires_at: session.expires_at
        }
      end

    json(conn, %{sessions: sessions})
  end

  operation :delete,
    summary: "End one of the own sessions",
    description: "Needs a second factor within the last 10 minutes.",
    security: Responses.session_and_csrf(),
    parameters: [
      id: [in: :path, required: true, description: "The session id.", schema: Fields.uuid()]
    ],
    responses:
      Map.merge(
        %{204 => "Session ended"},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "reauth_required", "csrf", "cross_site_request"]},
          {404, ["not_found"]}
        ])
      )

  def delete(conn, %{"id" => id}) do
    with :ok <- Accounts.delete_session(conn.assigns.current_scope.user, id) do
      send_resp(conn, :no_content, "")
    end
  end
end
