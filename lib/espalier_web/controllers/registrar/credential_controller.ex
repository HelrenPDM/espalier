defmodule EspalierWeb.Registrar.CredentialController do
  @moduledoc """
  The per-person credential list of one qualification for the role
  `registrar` (README section 10). The route answers 404 while
  `REGISTRAR_ENABLED=false`, also for a registrar.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Credentials
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.CredentialJSON
  alias EspalierWeb.Schemas.{Fields, RegistrarCredentialList}

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Registrar"]
  security Responses.session()

  operation :index,
    summary: "List the credentials of a qualification",
    parameters: [
      qualification: [
        in: :query,
        required: true,
        description: "The code of a qualification.",
        schema: Fields.key_param("The code of a qualification.")
      ]
    ],
    responses:
      Map.merge(
        %{200 => {"The credentials", "application/json", RegistrarCredentialList}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["forbidden", "enrollment_required", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def index(conn, %{qualification: code}) do
    with {:ok, rows} <- Credentials.registrar_list(conn.assigns.current_scope, code) do
      json(conn, CredentialJSON.registrar(%{rows: rows}))
    end
  end
end
