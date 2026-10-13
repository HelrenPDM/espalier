defmodule EspalierWeb.Schemas.Admin.PackDraftCheckRequest do
  @moduledoc """
  The body of `POST /api/admin/pack-drafts/:id/check` (task 0016a, step 9):
  no member, or the unsaved content of one file of the draft (`file_id` and
  `content` together), which replaces its stored content for this check
  only.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Admin.PackDraftFields, Fields}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          file_id: Fields.uuid("A file of the draft."),
          content: PackDraftFields.content()
        },
        optional: [:file_id, :content]
      ),
      %{title: "AdminPackDraftCheckRequest", description: "The overlay of a check."}
    ),
    struct?: false,
    derive?: false
  )
end
