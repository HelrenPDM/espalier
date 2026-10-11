defmodule EspalierWeb.Schemas.PolicyText do
  @moduledoc """
  The current version of a policy as a placeholder block and the handbook
  render it (README section 7, domain rule 8). `policy/0` returns the
  member schema that is `null` while the policy has no published version.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  @properties %{
    key: Fields.string("The policy key, the `placeholder_key` of the block."),
    number: Fields.integer("The number of the current version."),
    effective_from: Fields.date(),
    body: Fields.string("Markdown.")
  }

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(@properties),
      %{title: "PolicyText", description: "The current version of a policy."}
    ),
    struct?: false,
    derive?: false
  )

  @doc """
  The member `policy` of a placeholder block and of a handbook placeholder:
  the current version, or `null` without a published version.
  """
  def policy do
    %{
      Fields.object(@properties)
      | nullable: true,
        description: "The current version of the policy, or `null` without a published version."
    }
  end
end
