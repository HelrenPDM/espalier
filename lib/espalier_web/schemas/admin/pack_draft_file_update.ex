defmodule EspalierWeb.Schemas.Admin.PackDraftFileUpdate do
  @moduledoc "The body of `PUT /api/admin/pack-drafts/:id/files/:file_id` (task 0016a, step 9)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Admin.PackDraftFields, Fields}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        content: PackDraftFields.content(),
        lock_version: PackDraftFields.lock_version()
      }),
      %{title: "AdminPackDraftFileUpdate", description: "The new content of a file."}
    ),
    struct?: false,
    derive?: false
  )
end
