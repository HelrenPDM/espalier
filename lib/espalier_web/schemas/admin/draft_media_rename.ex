defmodule EspalierWeb.Schemas.Admin.DraftMediaRename do
  @moduledoc "The body of `PATCH /api/admin/pack-drafts/{id}/media/{media_id}` (task 0018, step 16)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Admin.PackDraftFields
  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        path: PackDraftFields.media_path(),
        lock_version: PackDraftFields.lock_version()
      }),
      %{title: "AdminDraftMediaRename", description: "The new path of a media entry."}
    ),
    struct?: false,
    derive?: false
  )
end
