defmodule EspalierWeb.Integration.CredentialLookupController do
  @moduledoc """
  The integration API for machine clients (README section 11): the
  credentials in force of a person, looked up by the address in the JSON
  body (ASVS 14.2.1). The pipeline `:integration` authenticates the client
  by its bearer token with the scope `credentials:read`; the route runs
  without the session cookie, the CSRF layer and the Fetch Metadata plug
  (ASVS 3.5.1). An unknown address gives an empty list, and the route
  changes no state.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Credentials
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.CredentialJSON
  alias EspalierWeb.Schemas.{CredentialLookupResult, EmailLookupRequest}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer

  tags ["Integration"]
  security [%{"bearer_token" => []}]

  operation :create,
    summary: "Look up the credentials in force of a person",
    request_body: {"The address", "application/json", EmailLookupRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The credentials in force", "application/json", CredentialLookupResult}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["forbidden"]},
          {422, ["validation_failed"]}
        ])
      )

  def create(conn, _params) do
    %{email: email} = conn.body_params
    json(conn, CredentialJSON.lookup(%{credentials: Credentials.in_force_for_email(email)}))
  end
end
