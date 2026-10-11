defmodule EspalierWeb.AcknowledgementController do
  @moduledoc """
  Records that the signed-in user acknowledged a published policy version.
  A draft and an unknown id answer 404, and a repeated acknowledgement
  answers 200 with the stored row.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Policies
  alias Espalier.Policies.PolicyVersion
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.PolicyJSON
  alias EspalierWeb.Schemas.{AcknowledgementView, EmptyRequest, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Policies"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Acknowledge a policy version",
    parameters: [
      id: [
        in: :path,
        required: true,
        description: "The id of a published policy version.",
        schema: Fields.uuid()
      ]
    ],
    request_body: {"No members", "application/json", EmptyRequest, required: false},
    responses:
      Map.merge(
        %{200 => {"The acknowledgement", "application/json", AcknowledgementView}},
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
      with %PolicyVersion{} = version <-
             Policies.get_published_version(id) || {:error, :not_found},
           {:ok, acknowledgement} <- Policies.acknowledge(scope, version) do
        json(conn, PolicyJSON.acknowledgement(%{acknowledgement: acknowledgement}))
      end
    end
  end
end
