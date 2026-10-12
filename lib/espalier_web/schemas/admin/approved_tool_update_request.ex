defmodule EspalierWeb.Schemas.Admin.ApprovedToolUpdateRequest do
  @moduledoc """
  The body of `PUT` and `PATCH /api/admin/approved-tools/{id}` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        approved_tool:
          Fields.object(
            %{
              name: %Schema{type: :string, minLength: 1, maxLength: 255},
              vendor: %Schema{type: :string, minLength: 1, maxLength: 255},
              status: Fields.enum(~w(approved restricted not_approved)),
              conditions: %Schema{type: :string, maxLength: 10_000, nullable: true},
              reviewed_on: %Schema{type: :string, format: :date, nullable: true},
              position: %Schema{type: :integer, minimum: 0, maximum: 2_147_483_647}
            },
            optional: [:name, :vendor, :status, :conditions, :reviewed_on, :position]
          )
      }),
      %{
        title: "AdminApprovedToolUpdateRequest",
        description: "Changed fields of an approved tool."
      }
    ),
    struct?: false,
    derive?: false
  )
end
