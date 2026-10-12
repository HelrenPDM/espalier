defmodule EspalierWeb.Schemas.FeedbackRequest do
  @moduledoc "The body of `POST /api/feedback`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        program_slug: Fields.key_param("The slug of a published program."),
        answers: %Schema{
          type: :object,
          minProperties: 1,
          maxProperties: 100,
          # anyOf keeps the first branch that casts: OpenApiSpex also casts
          # a string of digits to an integer, so a free text such as "3"
          # would match both branches of a oneOf.
          additionalProperties: %Schema{
            anyOf: [
              %Schema{
                type: :string,
                minLength: 1,
                maxLength: 2_000,
                description:
                  "The option key of a `single_choice` question, or the text of a " <>
                    "`free_text` question (only with `FEEDBACK_FREE_TEXT=true`)."
              },
              %Schema{
                type: :integer,
                minimum: 1,
                maximum: 5,
                description: "The value of a `scale` question."
              }
            ]
          },
          description:
            "The answers by question key of the feedback station. Every key names a " <>
              "question of the station, and at least one question is answered; an answer " <>
              "that does not fit its question answers 422 with the member `answers`."
        }
      }),
      %{
        title: "FeedbackRequest",
        description: "The answers to the feedback station, stored without the person."
      }
    ),
    struct?: false,
    derive?: false
  )
end
