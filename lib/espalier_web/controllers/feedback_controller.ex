defmodule EspalierWeb.FeedbackController do
  @moduledoc """
  The answers to the feedback station (README section 7, domain rule 12).
  They are stored without the person, and each person answers once. Free
  text is accepted only with `FEEDBACK_FREE_TEXT=true`.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Insights
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.InsightsJSON
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.Schemas.{FeedbackRequest, InsightRecorded}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Insights"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Answer the feedback station",
    request_body: {"The answers", "application/json", FeedbackRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"Whether the feedback is new", "application/json", InsightRecorded}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]},
          {429, ["rate_limited"]}
        ])
      )

  def create(conn, _params) do
    scope = conn.assigns.current_scope
    conn = RateLimit.check_account(conn, :insights_write, scope.user.id)

    if conn.halted do
      conn
    else
      %{program_slug: slug, answers: answers} = conn.body_params

      with {:ok, result} <- Insights.record_feedback(scope, slug, answers) do
        json(conn, InsightsJSON.recorded(result))
      end
    end
  end
end
