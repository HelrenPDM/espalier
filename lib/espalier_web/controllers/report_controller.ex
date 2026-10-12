defmodule EspalierWeb.ReportController do
  @moduledoc """
  The reports for the role `analyst` (README sections 8 and 10). They
  aggregate the anonymous rows and count credentials per qualification and
  status; every cell whose count lies below `INSIGHTS_MIN_GROUP_SIZE` is
  suppressed, and no report returns a user id, a display name or a row per
  person. The router admits only analysts, and every function of
  `Espalier.Insights` behind these routes checks the role again.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Insights
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.InsightsJSON

  alias EspalierWeb.Schemas.{
    CompetenceReport,
    CredentialReport,
    FeedbackReport,
    Fields,
    FormatReport,
    ItemReport,
    SelfAssessmentReport
  }

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Reports"]
  security Responses.session()

  @program [
    program: [
      in: :query,
      required: true,
      description: "The slug of a program in any status.",
      schema: Fields.key_param("The slug of a program in any status.")
    ]
  ]

  @errors Responses.errors([
            {401, ["unauthenticated"]},
            {403, ["forbidden", "enrollment_required", "cross_site_request"]},
            {404, ["not_found"]},
            {422, ["validation_failed"]}
          ])

  operation :self_assessment,
    summary: "Report the self-assessment segments",
    description: "The number of answers per segment and month, and per org unit when enabled.",
    parameters: @program,
    responses:
      Map.merge(%{200 => {"The report", "application/json", SelfAssessmentReport}}, @errors)

  def self_assessment(conn, %{program: slug}) do
    with {:ok, report} <- Insights.self_assessment_report(conn.assigns.current_scope, slug) do
      json(conn, InsightsJSON.self_assessment_report(report))
    end
  end

  operation :items,
    summary: "Report the practice items",
    description: "The attempts and the share correct per practice item and month.",
    parameters: @program,
    responses: Map.merge(%{200 => {"The report", "application/json", ItemReport}}, @errors)

  def items(conn, %{program: slug}) do
    with {:ok, report} <- Insights.item_report(conn.assigns.current_scope, slug) do
      json(conn, InsightsJSON.item_report(report))
    end
  end

  operation :competence,
    summary: "Report the competence areas",
    description:
      "The share correct of the practice items per competence area and depth of the " <>
        "learning objectives they name, per month, and per org unit when enabled.",
    parameters: @program,
    responses: Map.merge(%{200 => {"The report", "application/json", CompetenceReport}}, @errors)

  def competence(conn, %{program: slug}) do
    with {:ok, report} <- Insights.competence_report(conn.assigns.current_scope, slug) do
      json(conn, InsightsJSON.competence_report(report))
    end
  end

  operation :formats,
    summary: "Report the companion format votes",
    description: "The number of \"would use\" votes per companion format.",
    parameters: @program,
    responses: Map.merge(%{200 => {"The report", "application/json", FormatReport}}, @errors)

  def formats(conn, %{program: slug}) do
    with {:ok, report} <- Insights.format_report(conn.assigns.current_scope, slug) do
      json(conn, InsightsJSON.format_report(report))
    end
  end

  operation :feedback,
    summary: "Report the feedback",
    description:
      "The choice and scale distributions per question, and the free-text answers in " <>
        "random order once their number reaches the threshold.",
    parameters: @program,
    responses: Map.merge(%{200 => {"The report", "application/json", FeedbackReport}}, @errors)

  def feedback(conn, %{program: slug}) do
    with {:ok, report} <- Insights.feedback_report(conn.assigns.current_scope, slug) do
      json(conn, InsightsJSON.feedback_report(report))
    end
  end

  operation :credentials,
    summary: "Report the credentials",
    description: "The number of credentials per qualification and status.",
    parameters: @program,
    responses: Map.merge(%{200 => {"The report", "application/json", CredentialReport}}, @errors)

  def credentials(conn, %{program: slug}) do
    with {:ok, report} <- Insights.credential_report(conn.assigns.current_scope, slug) do
      json(conn, InsightsJSON.credential_report(report))
    end
  end
end
