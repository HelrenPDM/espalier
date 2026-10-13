defmodule EspalierWeb.Schemas.Admin.PackAlignment do
  @moduledoc """
  The member `alignment` of the pack view (task 0015) and of the check of a
  draft of the pack workbench (task 0016a, step 9): `mode` and `matrix` of
  the payload (`null` without one) and the report entries of the alignment
  checks with file and line.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        mode: %Schema{type: :string, enum: ["strict", "warn"], nullable: true},
        matrix: %Schema{
          type: :array,
          nullable: true,
          items: EspalierWeb.Schemas.Admin.AlignmentMatrixRow
        },
        errors: Fields.array(EspalierWeb.Schemas.Admin.AlignmentFinding),
        warnings: Fields.array(EspalierWeb.Schemas.Admin.AlignmentFinding)
      }),
      %{title: "AdminPackAlignment", description: "The alignment matrix and findings of a pack."}
    ),
    struct?: false,
    derive?: false
  )
end
