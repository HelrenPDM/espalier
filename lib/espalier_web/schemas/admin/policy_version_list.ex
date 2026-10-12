defmodule EspalierWeb.Schemas.Admin.PolicyVersionList do
  @moduledoc """
  The answer of `GET /api/admin/policy-versions?policy_id=` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        versions:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              policy_id: Fields.uuid(),
              policy_key: Fields.string(),
              policy_title: Fields.string(),
              number: Fields.integer(),
              body: Fields.string("Markdown."),
              effective_from: Fields.date(),
              published_at: %Schema{type: :string, format: :"date-time", nullable: true},
              requires_refresher: Fields.boolean()
            })
          )
      }),
      %{
        title: "AdminPolicyVersionList",
        description: "The versions of a policy, the highest number first."
      }
    ),
    struct?: false,
    derive?: false
  )
end
