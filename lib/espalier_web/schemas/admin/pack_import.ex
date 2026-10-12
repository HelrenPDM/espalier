defmodule EspalierWeb.Schemas.Admin.PackImport do
  @moduledoc """
  The answer of the pack routes of task 0015. `payload` is the normalized
  pack with its answer keys for a `validated` import (authors only), and
  `alignment` holds the matrix of the stored payload and the alignment
  entries of the report.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        status: Fields.enum(~w(validated failed published)),
        pack_key: Fields.nullable_string(),
        pack_version: Fields.nullable_string(),
        inserted_at: Fields.datetime(),
        published_at: %Schema{type: :string, format: :"date-time", nullable: true},
        report:
          Fields.object(%{
            errors: Fields.array(EspalierWeb.Schemas.Admin.ReportEntry),
            warnings: Fields.array(EspalierWeb.Schemas.Admin.ReportEntry)
          }),
        payload: %Schema{
          type: :object,
          nullable: true,
          additionalProperties: true,
          description: "The normalized pack of a validated import."
        },
        alignment:
          Fields.object(%{
            mode: %Schema{type: :string, enum: ["strict", "warn"], nullable: true},
            matrix: %Schema{
              type: :array,
              nullable: true,
              items: EspalierWeb.Schemas.Admin.AlignmentMatrixRow
            },
            errors: Fields.array(EspalierWeb.Schemas.Admin.AlignmentFinding),
            warnings: Fields.array(EspalierWeb.Schemas.Admin.AlignmentFinding)
          })
      }),
      %{title: "AdminPackImport", description: "A content pack import."}
    ),
    struct?: false,
    derive?: false
  )
end
