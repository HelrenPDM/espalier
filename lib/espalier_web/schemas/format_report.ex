defmodule EspalierWeb.Schemas.FormatReport do
  @moduledoc "The answer of `GET /api/insights/formats`."
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
        formats:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              key: Fields.string(),
              title: Fields.string(),
              cell: ReportCell
            }),
            "One entry per live companion format, in format order."
          )
      }),
      %{
        title: "FormatReport",
        description: "The number of \"would use\" votes per companion format."
      }
    ),
    struct?: false,
    derive?: false
  )
end
