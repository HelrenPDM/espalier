defmodule EspalierWeb.ProviderController do
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.ProviderList

  # OpenAPI operations of task 0009 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0004.
  tags ["Session"]
  security Responses.public()

  # The public entries of the external providers in configured order
  # (Espalier.Identity.Config.public_entry/1).
  operation :index,
    summary: "List the external identity providers",
    description: "The public entries of the configured providers in configured order.",
    responses:
      Map.merge(
        %{200 => {"The providers", "application/json", ProviderList}},
        Responses.errors([{403, ["cross_site_request"]}])
      )

  def index(conn, _params) do
    json(conn, %{providers: Application.get_env(:espalier, :auth_providers, [])})
  end
end
