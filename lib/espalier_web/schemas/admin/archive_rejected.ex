defmodule EspalierWeb.Schemas.Admin.ArchiveRejected do
  @moduledoc """
  The 422 answers of `POST /api/admin/packs`: `archive_rejected` with the
  report of `Espalier.Catalog.Pack.Archive.extract/2`, and
  `validation_failed` for a body without the field `file`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          error: Fields.enum(~w(archive_rejected validation_failed)),
          report:
            Fields.object(%{
              errors: Fields.array(EspalierWeb.Schemas.Admin.ReportEntry),
              warnings: Fields.array(EspalierWeb.Schemas.Admin.ReportEntry)
            }),
          fields: %Schema{
            type: :object,
            additionalProperties: Fields.strings(),
            description: "For `validation_failed`: the error codes per member."
          }
        },
        optional: [:report, :fields]
      ),
      %{title: "AdminArchiveRejected", description: "The upload was rejected."}
    ),
    struct?: false,
    derive?: false
  )
end
