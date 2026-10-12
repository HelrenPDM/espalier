defmodule EspalierWeb.Schemas.SelfAssessmentReport do
  @moduledoc "The answer of `GET /api/insights/self-assessment`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, ReportCell}

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
        by_org_unit: Fields.boolean("Mirrors `INSIGHTS_ORG_UNIT`."),
        months:
          Fields.array(
            Fields.date("The first day of a month."),
            "Every month with answers, in ascending order."
          ),
        rows:
          Fields.array(
            Fields.object(%{
              segment_key: Fields.string(),
              label:
                Fields.nullable_string(
                  "The label of the segment; `null` when the program has no segment with " <>
                    "this key."
                ),
              org_unit:
                Fields.nullable_string(
                  "`null` when `by_org_unit` is false, and in the row of the answers without " <>
                    "an org unit."
                ),
              cells: Fields.array(ReportCell, "One cell per entry of `months`, in that order.")
            }),
            "One row per segment (and org unit) with answers, in segment order."
          )
      }),
      %{
        title: "SelfAssessmentReport",
        description: "The number of self-assessment answers per segment and month."
      }
    ),
    struct?: false,
    derive?: false
  )
end
