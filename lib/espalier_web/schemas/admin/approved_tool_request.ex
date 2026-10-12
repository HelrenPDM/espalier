defmodule EspalierWeb.Schemas.Admin.ApprovedToolRequest do
  @moduledoc """
  The body of `POST /api/admin/approved-tools` (task 0015), in the nested
  shape of `mix phx.gen.json`.
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
            optional: [:conditions, :reviewed_on]
          )
      }),
      %{title: "AdminApprovedToolRequest", description: "A new entry of the approved tool list."}
    ),
    struct?: false,
    derive?: false
  )
end
