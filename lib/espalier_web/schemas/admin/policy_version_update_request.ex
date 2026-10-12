defmodule EspalierWeb.Schemas.Admin.PolicyVersionUpdateRequest do
  @moduledoc """
  The body of `PUT` and `PATCH /api/admin/policy-versions/{id}` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          body: %Schema{type: :string, minLength: 1, maxLength: 200_000, description: "Markdown."},
          effective_from: Fields.date(),
          requires_refresher: Fields.boolean()
        },
        optional: [:body, :effective_from, :requires_refresher]
      ),
      %{title: "AdminPolicyVersionUpdateRequest", description: "Changed fields of a draft."}
    ),
    struct?: false,
    derive?: false
  )
end
