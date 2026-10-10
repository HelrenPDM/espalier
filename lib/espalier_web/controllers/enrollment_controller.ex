defmodule EspalierWeb.EnrollmentController do
  @moduledoc """
  Enrollment and path (README section 7, domain rule 1). `POST` enrolls the
  signed-in user and keeps a path that the learner chose by hand; `PATCH`
  records the learner's choice. Only `path` and `program_slug` come from the
  request (ASVS 8.2.3).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Learning
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.LearningJSON
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.Schemas.{EnrollmentPathRequest, EnrollmentRequest, EnrollmentView, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Learning"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Enroll in a program",
    description:
      "Creates the enrollment (201). An existing enrollment answers 200 and takes the given " <>
        "path only while the learner has not chosen a path by hand.",
    request_body:
      {"The program and the path", "application/json", EnrollmentRequest, required: true},
    responses:
      Map.merge(
        %{
          200 => {"The existing enrollment", "application/json", EnrollmentView},
          201 => {"The new enrollment", "application/json", EnrollmentView}
        },
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
    conn = RateLimit.check_account(conn, :learner_write, scope.user.id)

    if conn.halted, do: conn, else: enroll(conn, scope, conn.body_params)
  end

  defp enroll(conn, scope, %{program_slug: slug, path: path}) do
    with {:ok, status, enrollment} <- Learning.enroll(scope, slug, path) do
      conn
      |> put_status(if status == :created, do: :created, else: :ok)
      |> json(LearningJSON.enrollment(%{enrollment: enrollment}))
    end
  end

  operation :update,
    summary: "Choose the path",
    description: "Sets the path and marks it as chosen by the learner.",
    parameters: [
      id: [in: :path, required: true, description: "The enrollment id.", schema: Fields.uuid()]
    ],
    request_body: {"The path", "application/json", EnrollmentPathRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The enrollment", "application/json", EnrollmentView}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]},
          {429, ["rate_limited"]}
        ])
      )

  def update(conn, %{id: id}) do
    scope = conn.assigns.current_scope
    conn = RateLimit.check_account(conn, :learner_write, scope.user.id)

    if conn.halted do
      conn
    else
      with {:ok, enrollment} <- Learning.update_path(scope, id, conn.body_params.path) do
        json(conn, LearningJSON.enrollment(%{enrollment: enrollment}))
      end
    end
  end
end
