defmodule EspalierWeb.Schemas.Admin.Export do
  @moduledoc """
  The answer of `POST /api/admin/exports` and `GET /api/admin/exports/:id`
  (task 0016, step 10). `download_path` is set while the status is `done`
  and `null` otherwise; `error` holds a short text for a `failed` export.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        module:
          Fields.object(%{
            id: Fields.uuid(),
            number: Fields.integer(),
            title: Fields.string(),
            program: Fields.object(%{slug: Fields.string(), title: Fields.string()})
          }),
        scorm_version: Fields.enum(~w(scorm12 scorm2004)),
        status: Fields.enum(~w(queued running done failed)),
        error: Fields.nullable_string("A short text for a failed export."),
        inserted_at: Fields.datetime(),
        download_path:
          Fields.nullable_string("The path of the download while the status is `done`.")
      }),
      %{title: "AdminExport", description: "A SCORM export of one module."}
    ),
    struct?: false,
    derive?: false
  )
end
