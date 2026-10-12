defmodule EspalierWeb.Schemas.SelfAssessmentResult do
  @moduledoc "The answer of `POST /api/self-assessments`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        path: %{
          Fields.enum(
            ~w(short full),
            "The path of the enrollment afterwards. A new answer applies the segment's " <>
              "default path unless the learner chose the path by hand; `null` only for an " <>
              "answer recorded earlier when the user has no enrollment."
          )
          | nullable: true
        },
        already_recorded:
          Fields.boolean(
            "True when the user had answered before; the answer and the enrollment stay " <>
              "unchanged."
          )
      }),
      %{
        title: "SelfAssessmentResult",
        description: "The path after a self-assessment, stored without the person."
      }
    ),
    struct?: false,
    derive?: false
  )
end
