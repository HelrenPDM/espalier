defmodule EspalierWeb.ItemResponseController do
  @moduledoc """
  Evaluates a practice answer on the server (README section 7, domain rules
  3 and 4). Exam items answer 404, because exam items are evaluated only
  inside an attempt (ASVS 2.3.1). The answer is stored nowhere.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Learning
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.LearningJSON
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.Schemas.{Fields, ItemResponseRequest, ItemResult}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Learning"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Answer a practice item",
    parameters: [
      id: [in: :path, required: true, description: "The item id.", schema: Fields.uuid()]
    ],
    request_body: {"The answer", "application/json", ItemResponseRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The evaluation", "application/json", ItemResult}},
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
    conn = RateLimit.check_account(conn, :learner_write, scope.user.id)

    if conn.halted do
      conn
    else
      with {:ok, result} <- Learning.respond(scope, id, conn.body_params.answer) do
        json(conn, LearningJSON.item_result(%{item_id: id, result: result}))
      end
    end
  end
end
