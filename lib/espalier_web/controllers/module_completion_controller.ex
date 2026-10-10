defmodule EspalierWeb.ModuleCompletionController do
  @moduledoc """
  Completes a module once every exam of the module that counts for a
  credential has a passed attempt (ASVS 2.3.1). A repeated call answers 200
  with the stored row.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Learning
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.LearningJSON
  alias EspalierWeb.Plugs.RateLimit

  alias EspalierWeb.Schemas.{
    AssessmentsOpenError,
    EmptyRequest,
    Error,
    Fields,
    ModuleCompletionView
  }

  alias OpenApiSpex.Schema

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Learning"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Complete a module",
    parameters: [
      id: [in: :path, required: true, description: "The module id.", schema: Fields.uuid()]
    ],
    request_body: {"No members", "application/json", EmptyRequest, required: false},
    responses:
      Map.merge(
        %{
          200 => {"The completion", "application/json", ModuleCompletionView},
          409 =>
            {"`assessments_open` with the open exams, or `not_enrolled`", "application/json",
             %Schema{oneOf: [AssessmentsOpenError, Error]}}
        },
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
    conn = RateLimit.check_account(conn, :learner_write, scope.user.id)

    if conn.halted do
      conn
    else
      with {:ok, completion} <- Learning.complete_module(scope, id) do
        json(conn, LearningJSON.completion(%{completion: completion}))
      end
    end
  end
end
