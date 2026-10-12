defmodule EspalierWeb.Schemas.Admin.ApprovedTool do
  @moduledoc """
  The answer of the approved tool routes of task 0015.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        data:
          Fields.object(%{
            id: Fields.uuid(),
            name: Fields.string(),
            vendor: Fields.string(),
            status: Fields.enum(~w(approved restricted not_approved)),
            conditions: Fields.nullable_string(),
            reviewed_on: %Schema{type: :string, format: :date, nullable: true},
            position: Fields.integer()
          })
      }),
      %{title: "AdminApprovedTool", description: "An entry of the approved tool list."}
    ),
    struct?: false,
    derive?: false
  )
end
