defmodule EspalierWeb.Schemas.Admin.PackImport do
  @moduledoc """
  The answer of the pack routes of task 0015. `payload` is the normalized
  pack with its answer keys for a `validated` import (authors only), and
  `alignment` holds the matrix of the stored payload and the alignment
  entries of the report. `media` holds the media of the payload with the
  state of their assets, and `media_policy` the media settings that the
  preview applies (task 0018, step 10).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Admin.PackMedia
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
        alignment: EspalierWeb.Schemas.Admin.PackAlignment,
        media: PackMedia.media(),
        media_policy: PackMedia.policy()
      }),
      %{title: "AdminPackImport", description: "A content pack import."}
    ),
    struct?: false,
    derive?: false
  )
end
