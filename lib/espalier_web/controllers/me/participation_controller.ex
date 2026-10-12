defmodule EspalierWeb.Me.ParticipationController do
  @moduledoc """
  What the signed-in user has answered in a program: the self-assessment,
  the feedback and the format votes. The answer comes from the
  participation markers and holds no segment and no feedback answer; the
  format ids are the user's own votes (README section 10).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Insights
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.InsightsJSON
  alias EspalierWeb.Schemas.{Fields, Participation}

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Insights"]
  security Responses.session()

  operation :show,
    summary: "Read the own participation in a program",
    parameters: [
      program: [
        in: :query,
        required: true,
        description: "The slug of a published program.",
        schema: Fields.key_param("The slug of a published program.")
      ]
    ],
    responses:
      Map.merge(
        %{200 => {"The participation", "application/json", Participation}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def show(conn, %{program: slug}) do
    with {:ok, participation} <- Insights.participation(conn.assigns.current_scope, slug) do
      json(conn, InsightsJSON.participation(participation))
    end
  end
end
