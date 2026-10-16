defmodule EspalierWeb.Schemas.BlockMedia do
  @moduledoc """
  The media of a `figure` or a `video` block (task 0018, step 12), resolved
  from the media of the published program into URLs below `/media/`. The
  standalone preview and the SCORM player build the same shape from the
  media object of `GET /api/admin/packs/{id}` and of `content.json`.

  A figure fills `image`, `alt`, `decorative` and `size`, and `poster` for
  an animated image. A video fills `video` for a file of the pack or an
  external file, or `embed` for the player of a streaming service, and
  `title`, `captions` and `poster`. `available` is false when an external
  or embed host has left `MEDIA_EXTERNAL_HOSTS` or `MEDIA_EMBED_HOSTS` since
  the publish, or when a media file is missing.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  @image %{
    Fields.object(%{
      url: Fields.string("`/media/<sha256>.<ext>`."),
      mime: Fields.enum(~w(image/webp image/svg+xml)),
      width: %Schema{
        type: :integer,
        nullable: true,
        description: "`null` for an SVG without a fixed size."
      },
      height: %Schema{
        type: :integer,
        nullable: true,
        description: "`null` for an SVG without a fixed size."
      },
      has_alpha: Fields.boolean("True when the image has transparent pixels."),
      animated: Fields.boolean("True for an animated WebP; `poster` holds its first frame.")
    })
    | nullable: true,
      description: "The image of a figure."
  }

  @video %{
    Fields.object(%{
      url: Fields.string("`/media/<sha256>.webm`, or the `https:` URL of an external file."),
      mime: Fields.enum(~w(video/webm video/mp4)),
      width: %Schema{type: :integer, nullable: true},
      height: %Schema{type: :integer, nullable: true},
      duration_ms: %Schema{type: :integer, nullable: true},
      has_audio: %Schema{type: :boolean, nullable: true},
      external: Fields.boolean("True for a file on an allowlisted CDN host.")
    })
    | nullable: true,
      description: "The video file of a video block; `null` for an embed."
  }

  @poster %{
    Fields.object(%{
      url: Fields.string(),
      width: Fields.integer(),
      height: Fields.integer()
    })
    | nullable: true,
      description:
        "The poster of a video, the first frame of an animated image, or the image of " <>
          "the `poster` attribute, which gives the first frame of an animated image."
  }

  @embed %{
    Fields.object(%{
      url: Fields.string("The `https:` URL of the player."),
      host: Fields.string("The host of the player, which the consent notice names.")
    })
    | nullable: true,
      description: "The player of a streaming service, loaded in an iframe."
  }

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        image: @image,
        video: @video,
        poster: @poster,
        embed: @embed,
        captions:
          Fields.array(
            Fields.object(%{url: Fields.string(), lang: Fields.string("A BCP 47 tag.")}),
            "The captions of a video file; the first is the default track."
          ),
        alt: Fields.nullable_string("The alternative text of a figure; `null` when decorative."),
        decorative: Fields.boolean("True for a figure without alternative text."),
        size: %Schema{type: :string, enum: ~w(small medium full), nullable: true},
        title: Fields.nullable_string("The title of a video."),
        available:
          Fields.boolean(
            "False when a host has left its allowlist since the publish or a file is missing."
          )
      }),
      %{title: "BlockMedia", description: "The media of a figure or a video block."}
    ),
    struct?: false,
    derive?: false
  )

  @doc "The member `media` of a block: the media of a figure or a video, `null` otherwise."
  def member do
    %Schema{
      allOf: [__MODULE__],
      nullable: true,
      description: "The media of a figure or a video block; `null` for the other kinds."
    }
  end
end
