defmodule EspalierWeb.Schemas.ProgramView do
  @moduledoc "The answer of `GET /api/programs/{slug}`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{CompanionFormatView, Fields}

  @option Fields.object(%{key: Fields.string(), label: Fields.string()})

  @question Fields.object(%{
              key: Fields.string(),
              kind: Fields.enum(~w(single_choice scale free_text)),
              label: Fields.string(),
              options: Fields.array(@option, "The options of a `single_choice` question.")
            })

  @station Fields.object(%{
             position: Fields.integer(),
             kind:
               Fields.enum(
                 ~w(self_assessment overview module credential companion_formats feedback)
               ),
             title: Fields.string(),
             module_id: %{Fields.uuid("The module of a module station.") | nullable: true},
             question: Fields.nullable_string("The question of the self-assessment station."),
             intro: Fields.nullable_string("The introduction of the station."),
             questions: Fields.array(@question, "The questions of the feedback station.")
           })

  @segment Fields.object(%{
             key: Fields.string(),
             label: Fields.string(),
             description: Fields.string(),
             default_path: Fields.enum(~w(short full))
           })

  @module_summary Fields.object(%{
                    id: Fields.uuid(),
                    number: Fields.integer(),
                    title: Fields.string(),
                    summary: Fields.string(),
                    phases: Fields.phases(),
                    single_path: Fields.boolean("True when the module ignores the path.")
                  })

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        slug: Fields.string(),
        title: Fields.string(),
        locale: Fields.string(),
        pack_version: Fields.string(),
        stations: Fields.array(@station, "The stations of the learner journey in order."),
        segments: Fields.array(@segment, "The segments of the self-assessment station."),
        modules: Fields.array(@module_summary, "The modules in number order."),
        companion_formats: Fields.array(CompanionFormatView)
      }),
      %{title: "ProgramView", description: "A published program."}
    ),
    struct?: false,
    derive?: false
  )
end
