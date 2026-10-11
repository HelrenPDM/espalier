defmodule EspalierWeb.PolicyController do
  @moduledoc """
  The policies for learners (README section 7, domain rule 8): the current
  version of every policy with the acknowledgement state of the signed-in
  user, and the approved tool list.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Policies
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.PolicyJSON
  alias EspalierWeb.Schemas.{ApprovedToolList, PolicyList}

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Policies"]
  security Responses.session()

  operation :index,
    summary: "List the current policy versions",
    responses:
      Map.merge(
        %{200 => {"The current versions", "application/json", PolicyList}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]}
        ])
      )

  def index(conn, _params) do
    entries = Policies.list_current_for(conn.assigns.current_scope)
    json(conn, PolicyJSON.index(%{entries: entries}))
  end

  operation :approved_tools,
    summary: "List the approved tools",
    responses:
      Map.merge(
        %{200 => {"The approved tool list", "application/json", ApprovedToolList}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]}
        ])
      )

  def approved_tools(conn, _params) do
    json(conn, PolicyJSON.tools(%{tools: Policies.list_approved_tools()}))
  end
end
