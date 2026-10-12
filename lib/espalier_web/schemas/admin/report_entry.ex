defmodule EspalierWeb.Schemas.Admin.ReportEntry do
  @moduledoc """
  An entry of the import report (task 0008 step 9).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          file: Fields.string(),
          line: %Schema{type: :integer, nullable: true},
          message: Fields.string(),
          check: %Schema{type: :integer, minimum: 1, maximum: 4},
          module: Fields.integer(),
          key: Fields.string(),
          omitted: Fields.integer("The number of entries a closing entry stands for.")
        },
        optional: [:check, :module, :key, :omitted]
      ),
      %{title: "AdminReportEntry", description: "A report entry."}
    ),
    struct?: false,
    derive?: false
  )
end
