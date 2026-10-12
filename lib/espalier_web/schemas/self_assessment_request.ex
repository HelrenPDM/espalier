defmodule EspalierWeb.Schemas.SelfAssessmentRequest do
  @moduledoc "The body of `POST /api/self-assessments`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        program_slug: Fields.key_param("The slug of a published program."),
        segment_key: Fields.key_param("The key of a live segment of the program.")
      }),
      %{
        title: "SelfAssessmentRequest",
        description: "The segment that the learner chose in the self-assessment station."
      }
    ),
    struct?: false,
    derive?: false
  )
end
