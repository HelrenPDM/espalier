defmodule EspalierWeb.Schemas.ModuleView do
  @moduledoc "The answer of `GET /api/modules/{id}`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, ItemView, ObjectiveView}

  @source Fields.object(%{
            key: Fields.string(),
            title: Fields.string(),
            publisher: Fields.string(),
            url: Fields.nullable_string(),
            edition_date: Fields.date(),
            retrieved_on: Fields.date(),
            kind: Fields.enum(~w(law guidance vendor study press other))
          })

  @citation Fields.object(%{locator: Fields.nullable_string(), source: @source})

  @block Fields.object(%{
           kind:
             Fields.enum(~w(text explanation example case_comparison quote callout placeholder)),
           body: Fields.string("Markdown."),
           provenance: Fields.provenance(),
           collapsed_on:
             Fields.array(
               Fields.enum(~w(short full)),
               "The paths on which the block starts collapsed."
             ),
           placeholder_key:
             Fields.nullable_string("The policy that a placeholder block renders."),
           citations: Fields.array(@citation)
         })

  @lesson Fields.object(%{
            id: Fields.uuid(),
            key: Fields.string(),
            position: Fields.integer(),
            title: Fields.string(),
            blocks: Fields.array(@block)
          })

  @rule Fields.object(%{
          id: Fields.uuid(),
          number: Fields.integer(),
          statement: Fields.string(),
          action: Fields.string(),
          citations: Fields.array(@citation)
        })

  @exam Fields.object(%{
          id: Fields.uuid(),
          key: Fields.string(),
          title: Fields.string(),
          max_wrong: Fields.integer(),
          counts_for_credential: Fields.boolean(),
          items: Fields.array(ItemView, "The exam items in order.")
        })

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        program_slug: Fields.string(),
        number: Fields.integer(),
        title: Fields.string(),
        summary: Fields.string(),
        phases: Fields.phases(),
        single_path: Fields.boolean("True when the module ignores the path."),
        lessons: Fields.array(@lesson, "The lessons in position order."),
        rules: Fields.array(@rule, "The rules in number order."),
        practice_items: Fields.array(ItemView, "The items that no exam lists."),
        exams: Fields.array(@exam),
        objectives: Fields.array(ObjectiveView, "The objectives of the topic in position order.")
      }),
      %{title: "ModuleView", description: "The content of a module without answer keys."}
    ),
    struct?: false,
    derive?: false
  )
end
