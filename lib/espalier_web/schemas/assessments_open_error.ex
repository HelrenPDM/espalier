defmodule EspalierWeb.Schemas.AssessmentsOpenError do
  @moduledoc """
  The 409 answer of `POST /api/modules/{id}/completion` while an exam that
  counts for a credential has no passed attempt.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        error: Fields.enum(["assessments_open"]),
        assessments:
          Fields.array(
            Fields.object(%{id: Fields.uuid(), key: Fields.string(), title: Fields.string()}),
            "The exams without a passed attempt."
          )
      }),
      %{title: "AssessmentsOpenError", description: "The open exams of the module."}
    ),
    struct?: false,
    derive?: false
  )
end
