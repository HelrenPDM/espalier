defmodule EspalierWeb.Schemas.Admin.ApprovedToolList do
  @moduledoc """
  The answer of `GET /api/admin/approved-tools` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        data:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              name: Fields.string(),
              vendor: Fields.string(),
              status: Fields.enum(~w(approved restricted not_approved)),
              conditions: Fields.nullable_string(),
              reviewed_on: %Schema{type: :string, format: :date, nullable: true},
              position: Fields.integer()
            })
          )
      }),
      %{
        title: "AdminApprovedToolList",
        description: "The approved tool list, ordered by position and name."
      }
    ),
    struct?: false,
    derive?: false
  )
end
