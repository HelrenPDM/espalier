defmodule EspalierWeb.Schemas.OidcIntent do
  @moduledoc "The 201 answer of `POST /api/auth/oidc/{provider}/intents` (task 0006)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        url:
          Fields.string(
            "The authorize path with the intent (`/auth/oidc/<key>?intent=<token>`), " <>
              "opened as a top-level navigation."
          )
      }),
      %{
        title: "OidcIntent",
        description: "The intent works once, for 5 minutes, with the creating session."
      }
    ),
    struct?: false,
    derive?: false
  )
end
