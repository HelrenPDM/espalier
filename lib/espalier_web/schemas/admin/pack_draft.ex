defmodule EspalierWeb.Schemas.Admin.PackDraft do
  @moduledoc """
  A draft of the pack workbench (task 0016a, step 9). The single view and
  the answers of the changes carry `files` without content and the media
  entries of task 0018 in `media`; the list leaves both out. The answer of
  the upload adds `skipped`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Admin.MediaAsset
  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          id: Fields.uuid(),
          title: Fields.string(),
          pack_key: Fields.nullable_string("The key of `pack.yaml`, when it is usable."),
          lock_version: %Schema{
            type: :integer,
            minimum: 1,
            description: "Grows by one with each file change; every change sends it."
          },
          inserted_at: Fields.datetime(),
          updated_at: Fields.datetime(),
          usage:
            Fields.object(%{
              files: Fields.integer("The number of files."),
              bytes: Fields.integer("The bytes of all contents.")
            }),
          limits:
            Fields.object(%{
              files: Fields.integer("At most 2,000 files per draft."),
              file_bytes: Fields.integer("At most 1,048,576 bytes per file."),
              draft_bytes: Fields.integer("At most five times `PACK_UPLOAD_MAX_MB` per draft.")
            }),
          files:
            Fields.array(
              Fields.object(%{
                id: Fields.uuid(),
                path: Fields.string(),
                bytes: Fields.integer(),
                updated_at: Fields.datetime()
              }),
              "The files ordered by path, without content."
            ),
          media:
            Fields.array(
              Fields.object(%{id: Fields.uuid(), path: Fields.string(), asset: MediaAsset}),
              "The media entries ordered by path, each with its library asset."
            ),
          skipped:
            Fields.object(
              %{
                paths: Fields.strings("The first 100 paths, sorted."),
                omitted: Fields.integer("The number of further skipped paths.")
              },
              description: "The files of an uploaded archive outside the pack layout."
            )
        },
        optional: [:files, :media, :skipped]
      ),
      %{title: "AdminPackDraft", description: "A draft of the pack workbench."}
    ),
    struct?: false,
    derive?: false
  )
end
