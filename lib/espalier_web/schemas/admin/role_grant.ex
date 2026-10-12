defmodule EspalierWeb.Schemas.Admin.RoleGrant do
  @moduledoc """
  The answer of `POST /api/admin/role-grants` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        user_id: Fields.uuid(),
        role: Fields.enum(~w(learner facilitator author registrar analyst admin)),
        source: Fields.enum(~w(idp_claim manual)),
        provider_key: Fields.nullable_string()
      }),
      %{title: "AdminRoleGrant", description: "A role grant."}
    ),
    struct?: false,
    derive?: false
  )
end
