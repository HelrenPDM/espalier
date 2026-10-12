defmodule EspalierWeb.Schemas.Admin.ApiClientList do
  @moduledoc """
  The answer of `GET /api/admin/api-clients` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        clients:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              name: Fields.string(),
              scopes: Fields.array(Fields.enum(["credentials:read"])),
              inserted_at: Fields.datetime(),
              last_used_at: %Schema{type: :string, format: :"date-time", nullable: true}
            })
          )
      }),
      %{title: "AdminApiClientList", description: "The machine clients, ordered by name."}
    ),
    struct?: false,
    derive?: false
  )
end
