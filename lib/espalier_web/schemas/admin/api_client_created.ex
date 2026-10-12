defmodule EspalierWeb.Schemas.Admin.ApiClientCreated do
  @moduledoc """
  The 201 answer of `POST /api/admin/api-clients` (task 0015): the token is
  shown exactly once.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        client:
          Fields.object(%{
            id: Fields.uuid(),
            name: Fields.string(),
            scopes: Fields.array(Fields.enum(["credentials:read"])),
            inserted_at: Fields.datetime(),
            last_used_at: %Schema{type: :string, format: :"date-time", nullable: true}
          }),
        token: Fields.string("The bearer token, shown once.")
      }),
      %{title: "AdminApiClientCreated", description: "A new machine client with its token."}
    ),
    struct?: false,
    derive?: false
  )
end
