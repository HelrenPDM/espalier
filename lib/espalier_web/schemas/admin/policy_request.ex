defmodule EspalierWeb.Schemas.Admin.PolicyRequest do
  @moduledoc """
  The body of `POST /api/admin/policies` (task 0015), in the nested shape
  of `mix phx.gen.json`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        policy:
          Fields.object(%{
            key: Fields.key_param("The key that qualification requirements name."),
            title: %Schema{type: :string, minLength: 1, maxLength: 255}
          })
      }),
      %{title: "AdminPolicyRequest", description: "A new policy."}
    ),
    struct?: false,
    derive?: false
  )
end
