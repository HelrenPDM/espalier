defmodule EspalierWeb.Schemas.Admin.AlignmentCheckFinding do
  @moduledoc """
  A finding of `Espalier.Catalog.Alignment.check/1` as the 409 answer
  `alignment_errors` carries it.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        check: %Schema{type: :integer, minimum: 1, maximum: 4},
        module: Fields.integer("The module number."),
        file: Fields.string("objectives.yaml, items.yaml or module.yaml."),
        key: Fields.string(),
        message: Fields.string()
      }),
      %{
        title: "AdminAlignmentCheckFinding",
        description: "An alignment finding of a check at publish time."
      }
    ),
    struct?: false,
    derive?: false
  )
end
