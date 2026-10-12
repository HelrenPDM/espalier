defmodule EspalierWeb.Schemas.Admin.AlignmentFinding do
  @moduledoc """
  An entry of the import report that comes from
  `Espalier.Catalog.Alignment.check/1`, at the file and line of the pack.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        file: Fields.string("The path in the pack."),
        line: Fields.integer(),
        check: %Schema{type: :integer, minimum: 1, maximum: 4},
        module: Fields.integer("The module number."),
        key: Fields.string("The objective key, the item key or the area."),
        message: Fields.string()
      }),
      %{title: "AdminAlignmentFinding", description: "An alignment finding with file and line."}
    ),
    struct?: false,
    derive?: false
  )
end
