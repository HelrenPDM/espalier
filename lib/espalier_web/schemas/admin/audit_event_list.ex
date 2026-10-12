defmodule EspalierWeb.Schemas.Admin.AuditEventList do
  @moduledoc """
  The answer of `GET /api/admin/audit` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        events:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              at: Fields.datetime(),
              action: Fields.string(),
              actor_id: %Schema{type: :string, format: :uuid, nullable: true},
              actor_display_name: Fields.nullable_string(),
              subject_type: Fields.nullable_string(),
              subject_id: %Schema{type: :string, format: :uuid, nullable: true},
              details: %Schema{type: :object, description: "Role names, keys and counts."}
            })
          ),
        page: Fields.integer(),
        per_page: Fields.integer()
      }),
      %{title: "AdminAuditEventList", description: "One page of audit events, newest first."}
    ),
    struct?: false,
    derive?: false
  )
end
