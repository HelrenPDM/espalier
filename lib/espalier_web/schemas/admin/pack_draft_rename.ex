defmodule EspalierWeb.Schemas.Admin.PackDraftRename do
  @moduledoc "The body of `PATCH /api/admin/pack-drafts/:id/files/:file_id` (task 0016a, step 9)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Admin.PackDraftFields, Fields}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        path: PackDraftFields.path(),
        lock_version: PackDraftFields.lock_version()
      }),
      %{title: "AdminPackDraftRename", description: "The new path of a file."}
    ),
    struct?: false,
    derive?: false
  )
end
