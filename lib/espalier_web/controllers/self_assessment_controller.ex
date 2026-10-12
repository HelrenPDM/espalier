defmodule EspalierWeb.SelfAssessmentController do
  @moduledoc """
  The anonymous self-assessment (README section 7, domain rule 1, and
  section 10). The answer is stored without the person, a participation
  marker lets each person count once, and a new answer preselects the
  segment's default path unless the learner chose a path by hand.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Insights
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.InsightsJSON
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.Schemas.{SelfAssessmentRequest, SelfAssessmentResult}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Insights"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Answer the self-assessment",
    description:
      "Stores the segment without the person and applies its default path to the " <>
        "enrollment, which this call creates when none exists. A second answer of the same " <>
        "person stores nothing and changes nothing.",
    request_body:
      {"The program and the segment", "application/json", SelfAssessmentRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The path", "application/json", SelfAssessmentResult}},
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
      %{program_slug: slug, segment_key: key} = conn.body_params

      with {:ok, result} <- Insights.record_self_assessment(scope, slug, key) do
        json(conn, InsightsJSON.self_assessment(result))
      end
    end
  end
end
