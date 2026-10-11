defmodule EspalierWeb.AttendanceController do
  @moduledoc """
  Attendance certificates for a session of a companion format held outside
  the platform (README section 7, domain rule 11). The route requires the
  role `facilitator`; the certificate belongs to the learner. The answer
  holds one result per user and no route lists the certificates that a
  facilitator has issued (README section 10).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Credentials
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.CredentialJSON
  alias EspalierWeb.Schemas.{AttendanceRequest, AttendanceResult, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Attendance"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Issue attendance certificates",
    description:
      "Issues one certificate per active user for a format of a published program, held " <>
        "today or earlier. A format without `attendance_counts` records the certificate and " <>
        "satisfies no requirement.",
    parameters: [
      id: [in: :path, required: true, description: "The format id.", schema: Fields.uuid()]
    ],
    request_body: {"The attendance", "application/json", AttendanceRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"One result per user", "application/json", AttendanceResult}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["forbidden", "enrollment_required", "csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def create(conn, %{id: id}) do
    %{user_ids: user_ids, held_on: held_on} = conn.body_params

    with {:ok, results} <-
           Credentials.issue_attendance(conn.assigns.current_scope, id, user_ids, held_on) do
      json(conn, CredentialJSON.attendance(%{results: results}))
    end
  end
end
