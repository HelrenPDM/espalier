defmodule EspalierWeb.Schemas.Admin.ExportRequest do
  @moduledoc """
  The body of `POST /api/admin/exports` (task 0016, step 10).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        module_id: Fields.uuid("A live module of a published program."),
        scorm_version: Fields.enum(~w(scorm12 scorm2004), "SCORM 1.2 or SCORM 2004 4th edition.")
      }),
      %{title: "AdminExportRequest", description: "The export of one module as a SCORM package."}
    ),
    struct?: false,
    derive?: false
  )
end
