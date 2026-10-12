defmodule EspalierWeb.Schemas.Admin.PackDiff do
  @moduledoc """
  The answer of `GET /api/admin/packs/{id}/diff` (task 0015): the added,
  changed and archived keys per keyed kind. Lessons appear as
  `<module number>/<lesson key>` and rules as `<module number>/<rule
  number>`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        modules:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          }),
        lessons:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          }),
        learning_objectives:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings(),
            changed_fields: %Schema{
              type: :object,
              additionalProperties: Fields.strings(),
              description: "The names of the differing fields per changed objective key."
            }
          }),
        items:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          }),
        rules:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          }),
        assessments:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          }),
        qualifications:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          }),
        formats:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          }),
        sources:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          }),
        segments:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          }),
        glossary_terms:
          Fields.object(%{
            added: Fields.strings(),
            changed: Fields.strings(),
            archived: Fields.strings()
          })
      }),
      %{
        title: "AdminPackDiff",
        description: "The difference between a pack and the live program."
      }
    ),
    struct?: false,
    derive?: false
  )
end
