defmodule EspalierWeb.Schemas.CompetenceReport do
  @moduledoc "The answer of `GET /api/insights/competence`."
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
            "Every month with statistics, in ascending order."
          ),
        rows:
          Fields.array(
            Fields.object(%{
              area: Fields.enum(~w(subject method self social), "The CORE competence area."),
              depth: Fields.enum(~w(know apply judge)),
              org_unit:
                Fields.nullable_string(
                  "`null` when `by_org_unit` is false, and in the row of the answers without " <>
                    "an org unit."
                ),
              cells:
                Fields.array(
                  ReportCell,
                  "One cell per entry of `months`: the attempts as count and the share " <>
                    "correct as value."
                )
            }),
            "One row per competence area and depth (and org unit) with statistics, by area, " <>
              "depth and org unit."
          )
      }),
      %{
        title: "CompetenceReport",
        description:
          "The share correct of the practice items per competence area and depth of the " <>
            "learning objectives they name, and month."
      }
    ),
    struct?: false,
    derive?: false
  )
end
