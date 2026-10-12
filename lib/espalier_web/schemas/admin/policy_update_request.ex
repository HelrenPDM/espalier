defmodule EspalierWeb.Schemas.Admin.PolicyUpdateRequest do
  @moduledoc """
  The body of `PUT` and `PATCH /api/admin/policies/{id}` (task 0015). A
  policy with a published version keeps its key.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        policy:
          Fields.object(
            %{
              key: Fields.key_param("The key that qualification requirements name."),
              title: %Schema{type: :string, minLength: 1, maxLength: 255}
            },
            optional: [:key, :title]
          )
      }),
      %{title: "AdminPolicyUpdateRequest", description: "Changed fields of a policy."}
    ),
    struct?: false,
    derive?: false
  )
end
