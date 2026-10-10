defmodule EspalierWeb.Schemas.AttemptRequest do
  @moduledoc "The body of `POST /api/assessments/{id}/attempts`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Answer, Fields}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        answers: %Schema{
          type: :object,
          description:
            "Every item id of the exam mapped to its answer. A missing or unknown item id " <>
              "answers 422 with `fields.answers` `incomplete`.",
          additionalProperties: Answer,
          maxProperties: 200
        }
      }),
      %{title: "AttemptRequest", description: "The answers of an exam attempt."}
    ),
    struct?: false,
    derive?: false
  )
end
