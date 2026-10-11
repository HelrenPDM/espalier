defmodule EspalierWeb.Facilitator.UserLookupController do
  @moduledoc """
  Finds one active user by the exact e-mail address for the attendance page
  of a facilitator. The address travels in the JSON body, so no URL carries
  it (ASVS 14.2.1); the route changes no state. Display name and org unit
  are encrypted and cannot be searched in SQL, so the lookup works on the
  exact address only (README section 6.9).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Credentials
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.CredentialJSON
  alias EspalierWeb.Schemas.{EmailLookupRequest, UserLookupResult}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Attendance"]
  security Responses.session_and_csrf()

  operation :create,
    summary: "Find a user by e-mail address",
    request_body: {"The address", "application/json", EmailLookupRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The user", "application/json", UserLookupResult}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["forbidden", "enrollment_required", "csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def create(conn, _params) do
    %{email: email} = conn.body_params

    with {:ok, user} <- Credentials.lookup_user(conn.assigns.current_scope, email) do
      json(conn, CredentialJSON.user(%{user: user}))
    end
  end
end
