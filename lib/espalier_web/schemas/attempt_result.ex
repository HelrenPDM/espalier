defmodule EspalierWeb.Schemas.AttemptResult do
  @moduledoc "The answer of `POST /api/assessments/{id}/attempts`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, ItemResult}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        assessment_id: Fields.uuid(),
        number: Fields.integer("The number of the attempt, from 1."),
        outcome: Fields.enum(~w(passed failed_core failed_errors)),
        wrong_count: Fields.integer(),
        core_failed: Fields.boolean(),
        submitted_at: Fields.datetime(),
        results: Fields.array(ItemResult, "The evaluation per item in exam order.")
      }),
      %{title: "AttemptResult", description: "An exam attempt under the pass rule."}
    ),
    struct?: false,
    derive?: false
  )
end
