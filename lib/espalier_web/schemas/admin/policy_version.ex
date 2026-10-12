defmodule EspalierWeb.Schemas.Admin.PolicyVersion do
  @moduledoc """
  A version of the policy-version routes of task 0015, with
  `refresh_due_count`: the credentials that a publication with
  `requires_refresher` would move to `refresh_due` now.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        policy_id: Fields.uuid(),
        policy_key: Fields.string(),
        policy_title: Fields.string(),
        number: Fields.integer(),
        body: Fields.string("Markdown."),
        effective_from: Fields.date(),
        published_at: %Schema{type: :string, format: :"date-time", nullable: true},
        requires_refresher: Fields.boolean(),
        refresh_due_count: Fields.integer()
      }),
      %{title: "AdminPolicyVersion", description: "A policy version."}
    ),
    struct?: false,
    derive?: false
  )
end
