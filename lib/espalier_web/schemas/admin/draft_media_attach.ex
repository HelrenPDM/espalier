defmodule EspalierWeb.Schemas.Admin.DraftMediaAttach do
  @moduledoc """
  The body of `POST /api/admin/pack-drafts/{id}/media` (task 0018, step 16).
  An image, SVG or video asset becomes a media entry at `path`, whose
  extension must be the delivery extension of the asset; a captions asset
  becomes a text file at a `.vtt` path.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Admin.PackDraftFields
  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        media_asset_id:
          Fields.uuid(
            "An asset of the media library. An image, SVG or video asset may still be " <>
              "converting; a captions asset must be `ready`."
          ),
        path: PackDraftFields.media_path(),
        lock_version: PackDraftFields.lock_version()
      }),
      %{title: "AdminDraftMediaAttach", description: "A library asset for a draft."}
    ),
    struct?: false,
    derive?: false
  )
end
