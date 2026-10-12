defmodule EspalierWeb.Schemas.Admin.PolicyList do
  @moduledoc """
  The answer of `GET /api/admin/policies` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        data:
          Fields.array(
            Fields.object(%{id: Fields.uuid(), key: Fields.string(), title: Fields.string()})
          )
      }),
      %{title: "AdminPolicyList", description: "The policies, ordered by key."}
    ),
    struct?: false,
    derive?: false
  )
end
