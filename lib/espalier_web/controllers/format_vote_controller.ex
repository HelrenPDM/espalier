defmodule EspalierWeb.FormatVoteController do
  @moduledoc """
  The anonymous "would use" vote for a companion format (README section 7,
  domain rule 11). The vote is stored without the person and cannot be
  changed afterwards.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Insights
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.InsightsJSON
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.Schemas.{Fields, FormatVoteRequest, InsightRecorded}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Insights"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Vote for a companion format",
    parameters: [
      id: [
        in: :path,
        required: true,
        description: "The id of a live companion format of a published program.",
        schema: Fields.uuid()
      ]
    ],
    request_body: {"The choice", "application/json", FormatVoteRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"Whether the vote is new", "application/json", InsightRecorded}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]},
          {429, ["rate_limited"]}
        ])
      )

  def create(conn, %{id: id}) do
    scope = conn.assigns.current_scope
    conn = RateLimit.check_account(conn, :insights_write, scope.user.id)

    if conn.halted do
      conn
    else
      with {:ok, result} <- Insights.vote_format(scope, id, conn.body_params.choice) do
        json(conn, InsightsJSON.recorded(result))
      end
    end
  end
end
