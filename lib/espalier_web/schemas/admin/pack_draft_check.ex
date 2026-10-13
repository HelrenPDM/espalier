defmodule EspalierWeb.Schemas.Admin.PackDraftCheck do
  @moduledoc """
  The answer of the check of a draft (task 0016a, step 9): the
  `lock_version` that was checked, the report of the loader and the
  validator of task 0008 in the form of an import report, and the alignment
  matrix with its findings.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        lock_version: %Schema{type: :integer, minimum: 1, description: "The version checked."},
        report:
          Fields.object(%{
            errors: Fields.array(EspalierWeb.Schemas.Admin.ReportEntry),
            warnings: Fields.array(EspalierWeb.Schemas.Admin.ReportEntry)
          }),
        alignment: EspalierWeb.Schemas.Admin.PackAlignment
      }),
      %{title: "AdminPackDraftCheck", description: "The check of a draft."}
    ),
    struct?: false,
    derive?: false
  )
end
