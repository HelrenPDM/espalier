defmodule EspalierWeb.Schemas.Admin.PackDraftRequest do
  @moduledoc """
  The body of `POST /api/admin/pack-drafts` (task 0016a, step 9): a start
  from an empty skeleton (`name`), a published program (`program_slug`) or
  an import with a payload (`pack_import_id`). The member of the source is
  required, and a member of another source answers 422 `validation_failed`
  with `not_allowed`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          source: Fields.enum(~w(empty program import)),
          name: %Schema{
            type: :string,
            minLength: 1,
            maxLength: 255,
            description: "For `empty`: the title of the pack."
          },
          program_slug: Fields.key_param("For `program`: the slug of a published program."),
          pack_import_id: Fields.uuid("For `import`: a `validated` or `published` import.")
        },
        optional: [:name, :program_slug, :pack_import_id]
      ),
      %{title: "AdminPackDraftRequest", description: "The starting point of a new draft."}
    ),
    struct?: false,
    derive?: false
  )
end
