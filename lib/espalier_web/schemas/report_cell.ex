defmodule EspalierWeb.Schemas.ReportCell do
  @moduledoc """
  A cell of an analyst report: `{count, value}`, or `{suppressed: true}`
  when the count lies below `INSIGHTS_MIN_GROUP_SIZE`
  (`Espalier.Insights.cell/2`).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    %{
      title: "ReportCell",
      description:
        "A cell with its count and value, or a suppressed cell whose count lies below " <>
          "`INSIGHTS_MIN_GROUP_SIZE`; a suppressed cell carries neither.",
      oneOf: [
        Fields.object(%{
          count: %Schema{type: :integer, minimum: 1, description: "The number counted."},
          value: %Schema{
            type: :number,
            description:
              "The share correct from 0 to 1 in the item and competence reports; the count " <>
                "in every other report."
          }
        }),
        Fields.object(%{suppressed: %Schema{type: :boolean, enum: [true]}})
      ]
    },
    struct?: false,
    derive?: false
  )
end
