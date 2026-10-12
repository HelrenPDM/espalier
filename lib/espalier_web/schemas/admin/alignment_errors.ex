defmodule EspalierWeb.Schemas.Admin.AlignmentErrors do
  @moduledoc """
  The 409 answers of `POST /api/admin/packs/{id}/publish`: `not_publishable`
  for an import that is not `validated`, and `alignment_errors` with the
  findings of `Espalier.Catalog.Alignment.check/1` at publish time.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          error: Fields.enum(~w(not_publishable alignment_errors)),
          findings: Fields.array(EspalierWeb.Schemas.Admin.AlignmentCheckFinding)
        },
        optional: [:findings]
      ),
      %{title: "AdminAlignmentErrors", description: "The publish was refused."}
    ),
    struct?: false,
    derive?: false
  )
end
