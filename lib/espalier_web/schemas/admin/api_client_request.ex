defmodule EspalierWeb.Schemas.Admin.ApiClientRequest do
  @moduledoc """
  The body of `POST /api/admin/api-clients` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        name: %Schema{type: :string, minLength: 1, maxLength: 100},
        scopes: %Schema{
          type: :array,
          minItems: 1,
          maxItems: 1,
          items: Fields.enum(["credentials:read"])
        }
      }),
      %{title: "AdminApiClientRequest", description: "A new machine client."}
    ),
    struct?: false,
    derive?: false
  )
end
