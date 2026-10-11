defmodule EspalierWeb.Me.RequirementController do
  @moduledoc """
  The met and open requirements of the signed-in user per qualification of
  a program, with the station that satisfies each requirement (README
  section 7, domain rule 6).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Credentials
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.CredentialJSON
  alias EspalierWeb.Schemas.{Fields, RequirementList}

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Credentials"]
  security Responses.session()

  operation :show,
    summary: "Read the own requirements in a program",
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
        %{200 => {"The requirements", "application/json", RequirementList}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def show(conn, %{program: slug}) do
    with {:ok, entries} <- Credentials.requirements(conn.assigns.current_scope, slug) do
      json(conn, CredentialJSON.requirements(%{entries: entries}))
    end
  end
end
