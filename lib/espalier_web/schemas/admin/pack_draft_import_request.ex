defmodule EspalierWeb.Schemas.Admin.PackDraftImportRequest do
  @moduledoc "The body of `POST /api/admin/pack-drafts/:id/imports` (task 0016a, step 9)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Admin.PackDraftFields, Fields}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{lock_version: PackDraftFields.lock_version()}),
      %{title: "AdminPackDraftImportRequest", description: "The import of a draft."}
    ),
    struct?: false,
    derive?: false
  )
end
