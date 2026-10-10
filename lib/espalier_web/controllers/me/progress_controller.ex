defmodule EspalierWeb.Me.ProgressController do
  @moduledoc """
  The progress of the signed-in user in a program, with the status of every
  learning objective derived per request from the user's own records
  (README section 7, domain rule 15).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Learning
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.LearningJSON
  alias EspalierWeb.Schemas.{Fields, Progress}

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Learning"]
  security Responses.session()

  operation :show,
    summary: "Read the own progress in a program",
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
        %{200 => {"The progress", "application/json", Progress}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def show(conn, %{program: slug}) do
    with {:ok, progress} <- Learning.progress(conn.assigns.current_scope, slug) do
      json(conn, LearningJSON.progress(%{progress: progress}))
    end
  end
end
