defmodule EspalierWeb.Schemas.Admin.PackDraftFileRequest do
  @moduledoc "The body of `POST /api/admin/pack-drafts/:id/files` (task 0016a, step 9)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Admin.PackDraftFields, Fields}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        path: PackDraftFields.path(),
        content: PackDraftFields.content(),
        lock_version: PackDraftFields.lock_version()
      }),
      %{title: "AdminPackDraftFileRequest", description: "A new file of a draft."}
    ),
    struct?: false,
    derive?: false
  )
end
