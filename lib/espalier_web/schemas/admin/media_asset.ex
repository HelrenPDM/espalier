defmodule EspalierWeb.Schemas.Admin.MediaAsset do
  @moduledoc """
  An asset of the media library (task 0018, step 15). `url` and
  `poster_url` are set while the asset is `ready`; `failure` and
  `failure_detail` name the code and the reason tag of a `failed` asset.
  `GET /api/admin/media/{id}` adds `uses`.
  """
  require OpenApiSpex

  alias Espalier.Media.Asset
  alias EspalierWeb.Schemas.Admin.MediaUses
  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          id: Fields.uuid(),
          kind: Fields.enum(~w(image svg video captions)),
          status: Fields.enum(~w(queued processing ready failed)),
          failure: %Schema{
            type: :string,
            enum: Enum.map(Asset.failures(), &Atom.to_string/1),
            nullable: true,
            description: "The failure code of a `failed` asset."
          },
          failure_detail: %Schema{
            type: :string,
            enum: Enum.map(Asset.failure_details(), &Atom.to_string/1),
            nullable: true,
            description:
              "The reason tag of `unsupported_animation`, `invalid_svg`, " <>
                "`invalid_captions` and `scan_failed`."
          },
          progress: %Schema{
            type: :integer,
            minimum: 0,
            maximum: 100,
            description: "The progress of a video conversion in percent."
          },
          title: Fields.string(),
          source_name:
            Fields.nullable_string("The name of the uploaded or imported file, for the author."),
          origin: Fields.enum(~w(upload pack)),
          ext: %Schema{
            type: :string,
            enum: ~w(webp svg webm vtt),
            nullable: true,
            description: "The extension of the delivery file."
          },
          bytes: %Schema{type: :integer, nullable: true, description: "The delivery file."},
          width: %Schema{type: :integer, nullable: true},
          height: %Schema{type: :integer, nullable: true},
          duration_ms: %Schema{
            type: :integer,
            nullable: true,
            description: "The length of a video, or the end of the last cue of captions."
          },
          has_audio: Fields.boolean(),
          animated: Fields.boolean(),
          has_alpha: Fields.boolean(),
          url: Fields.nullable_string("`/media/<sha256>.<ext>` of a `ready` asset."),
          poster_url:
            Fields.nullable_string("The poster of a video or the first frame of an animation."),
          inserted_at: Fields.datetime(),
          updated_at: Fields.datetime(),
          uses: MediaUses
        },
        optional: [:uses]
      ),
      %{title: "AdminMediaAsset", description: "A file of the media library."}
    ),
    struct?: false,
    derive?: false
  )
end
