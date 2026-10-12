defmodule EspalierWeb.Schemas.Admin.PolicyVersionRequest do
  @moduledoc """
  The body of `POST /api/admin/policy-versions` (task 0015): a new draft.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          policy_id: Fields.uuid("The policy of the draft."),
          body: %Schema{type: :string, minLength: 1, maxLength: 200_000, description: "Markdown."},
          effective_from: Fields.date(),
          requires_refresher: Fields.boolean()
        },
        optional: [:requires_refresher]
      ),
      %{title: "AdminPolicyVersionRequest", description: "A new draft version."}
    ),
    struct?: false,
    derive?: false
  )
end
