defmodule EspalierWeb.Schemas.FeedbackReport do
  @moduledoc "The answer of `GET /api/insights/feedback`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, ReportCell}
  alias OpenApiSpex.Schema

  @free_text %Schema{
    nullable: true,
    description:
      "For a `free_text` question, the answers in random order once their number reaches " <>
        "`INSIGHTS_MIN_GROUP_SIZE`, and a suppressed entry before; `null` for the other kinds.",
    oneOf: [
      Fields.object(%{
        count: %Schema{type: :integer, minimum: 1},
        answers: Fields.strings()
      }),
      Fields.object(%{suppressed: %Schema{type: :boolean, enum: [true]}})
    ]
  }

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        min_group_size:
          Fields.integer(
            "`INSIGHTS_MIN_GROUP_SIZE`: a cell whose count lies below it is suppressed."
          ),
        locale:
          Fields.string(
            "The content language of the program, which the pack text of the report carries."
          ),
        questions:
          Fields.array(
            Fields.object(%{
              key: Fields.string(),
              kind: Fields.enum(~w(single_choice scale free_text)),
              label: Fields.string(),
              choices:
                Fields.array(
                  Fields.object(%{
                    key:
                      Fields.string(
                        "The option key of a `single_choice` question, or the value `1` to " <>
                          "`5` of a `scale` question."
                      ),
                    label: Fields.nullable_string("The option label; `null` for a scale value."),
                    cell: ReportCell
                  }),
                  "The number of answers per option or scale value; empty for `free_text`."
                ),
              free_text: @free_text
            }),
            "The questions of the feedback station, in their order."
          )
      }),
      %{
        title: "FeedbackReport",
        description: "The distributions of the feedback answers per question."
      }
    ),
    struct?: false,
    derive?: false
  )
end
