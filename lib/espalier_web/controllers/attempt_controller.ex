defmodule EspalierWeb.AttemptController do
  @moduledoc """
  Exam attempts under the pass rule (README section 7, domain rule 5). The
  answer is 201 with the outcome and the evaluation per item; the stored
  attempt holds no answers.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Learning
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.LearningJSON
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.Schemas.{AttemptRequest, AttemptResult, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Learning"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Submit an exam attempt",
    parameters: [
      id: [in: :path, required: true, description: "The exam id.", schema: Fields.uuid()]
    ],
    request_body: {"The answers", "application/json", AttemptRequest, required: true},
    responses:
      Map.merge(
        %{201 => {"The attempt", "application/json", AttemptResult}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {409, ["not_enrolled"]},
          {422, ["validation_failed"]},
          {429, ["rate_limited"]}
        ])
      )

  def create(conn, %{id: id}) do
    scope = conn.assigns.current_scope
    conn = RateLimit.check_account(conn, :assessment_attempt, scope.user.id)

    if conn.halted do
      conn
    else
      with {:ok, attempt, results} <-
             Learning.submit_attempt(scope, id, conn.body_params.answers) do
        conn
        |> put_status(:created)
        |> json(LearningJSON.attempt(%{attempt: attempt, results: results}))
      end
    end
  end
end
