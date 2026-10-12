defmodule EspalierWeb.Schemas.Admin.AlignmentMatrixRow do
  @moduledoc """
  A row of `Espalier.Catalog.Alignment.matrix/1` (task 0008 step 13): one
  per module, competence area and depth.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        module: Fields.integer("The module number."),
        area: Fields.enum(~w(subject method self social)),
        depth: Fields.enum(~w(know apply judge)),
        objectives: Fields.strings(),
        lessons: Fields.strings(),
        evidence: Fields.strings("Entries item:<key> and format:<key>."),
        elsewhere: Fields.nullable_string("The place of areas_elsewhere.")
      }),
      %{title: "AdminAlignmentMatrixRow", description: "A row of the alignment matrix."}
    ),
    struct?: false,
    derive?: false
  )
end
