defmodule EspalierWeb.Schemas.ItemReport do
  @moduledoc "The answer of `GET /api/insights/items`."
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
        months:
          Fields.array(
            Fields.date("The first day of a month."),
            "Every month with statistics, in ascending order."
          ),
        rows:
          Fields.array(
            Fields.object(%{
              item_id: Fields.uuid(),
              key: Fields.string(),
              kind:
                Fields.enum(
                  ~w(single_choice multiple_choice slot_builder classification checklist_drill)
                ),
              module_number: Fields.integer(),
              stem: Fields.string("The question of the item, Markdown from the pack."),
              cells:
                Fields.array(
                  ReportCell,
                  "One cell per entry of `months`: the attempts as count and the share " <>
                    "correct as value."
                )
            }),
            "One row per live item with statistics, by module number and item position; " <>
              "polls stay out."
          )
      }),
      %{
        title: "ItemReport",
        description: "The attempts and the share correct per practice item and month."
      }
    ),
    struct?: false,
    derive?: false
  )
end
