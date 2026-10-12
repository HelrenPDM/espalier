defmodule EspalierWeb.Schemas.Admin.RoleGrantRequest do
  @moduledoc """
  The body of `POST /api/admin/role-grants` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        user_id: Fields.uuid(),
        role: Fields.enum(~w(facilitator author registrar analyst admin))
      }),
      %{title: "AdminRoleGrantRequest", description: "A manual role grant."}
    ),
    struct?: false,
    derive?: false
  )
end
