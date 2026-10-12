defmodule EspalierWeb.Schemas.Admin.PolicyVersionPublishRequest do
  @moduledoc """
  The body of `POST /api/admin/policy-versions/{id}/publish` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        requires_refresher:
          Fields.boolean(
            "True moves the credentials whose qualification requires the policy to refresh_due."
          )
      }),
      %{title: "AdminPolicyVersionPublishRequest", description: "The publication of a draft."}
    ),
    struct?: false,
    derive?: false
  )
end
