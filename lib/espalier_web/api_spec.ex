defmodule EspalierWeb.ApiSpec do
  @moduledoc """
  The OpenAPI document of the API (README section 8), served at
  `GET /api/openapi` and written to `frontend/openapi.json` by
  `make api-types`, from which the SPA generates its types.

  The paths come from the router: `OpenApiSpex.Paths.from_router/1` reads
  every route whose controller defines operations with
  `OpenApiSpex.ControllerSpecs`. Task 0009 describes the learner routes and
  the routes of task 0004; the tasks named in README section 6.12 add the
  operations of their own routes.

  Two security schemes describe the backend-for-frontend session: the
  session cookie `__Host-espalier` and the CSRF token in the `x-csrf-token`
  header of every mutating request (README section 6.5).
  """
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme}

  @version Mix.Project.config()[:version]

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{title: "Espalier API", version: @version},
      paths: Paths.from_router(EspalierWeb.Router),
      components: %Components{
        securitySchemes: %{
          "session_cookie" => %SecurityScheme{
            type: "apiKey",
            in: "cookie",
            name: "__Host-espalier",
            description: "The session cookie of the backend-for-frontend session."
          },
          "csrf_header" => %SecurityScheme{
            type: "apiKey",
            in: "header",
            name: "x-csrf-token",
            description:
              "The CSRF token of the session payload, sent with every mutating request."
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
