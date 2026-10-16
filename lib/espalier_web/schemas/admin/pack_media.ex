defmodule EspalierWeb.Schemas.Admin.PackMedia do
  @moduledoc """
  The media of an import in the answer of `GET /api/admin/packs/{id}` (task
  0018, step 10): one entry per `media/` path of the payload with the state
  and the facts of its asset, and the media policy of the installation for
  the preview. `status` is `missing` when the asset was deleted.
  """
  require OpenApiSpex

  alias Espalier.Media.Asset
  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        kind: Fields.enum(~w(image svg video captions)),
        status: Fields.enum(~w(missing queued processing ready failed)),
        failure: %Schema{
          type: :string,
          enum: Enum.map(Asset.failures(), &Atom.to_string/1),
          nullable: true
        },
        failure_detail: %Schema{
          type: :string,
          enum: Enum.map(Asset.failure_details(), &Atom.to_string/1),
          nullable: true
        },
        url: Fields.nullable_string("`/media/<sha256>.<ext>` while `ready`."),
        mime: Fields.nullable_string(),
        width: %Schema{type: :integer, nullable: true},
        height: %Schema{type: :integer, nullable: true},
        duration_ms: %Schema{type: :integer, nullable: true},
        progress: %Schema{
          type: :integer,
          minimum: 0,
          maximum: 100,
          description: "The progress of a video conversion in percent."
        },
        has_audio: Fields.boolean(),
        has_alpha: Fields.boolean(),
        animated: Fields.boolean(),
        poster_url: Fields.nullable_string()
      }),
      %{title: "AdminPackMedia", description: "A media file of an import."}
    ),
    struct?: false,
    derive?: false
  )

  @doc "The member `media` of the pack view: the entries keyed by path."
  def media do
    %Schema{
      type: :object,
      additionalProperties: __MODULE__,
      description:
        "The media of the payload keyed by their `media/` path; `{}` without a payload."
    }
  end

  @doc "The member `media_policy` of the pack view."
  def policy do
    Fields.object(
      %{
        external_hosts: Fields.strings("`MEDIA_EXTERNAL_HOSTS` as `host` or `host:port`."),
        embed_hosts: Fields.strings("`MEDIA_EMBED_HOSTS` as `host` or `host:port`."),
        embed_consent: Fields.enum(~w(click auto), "`MEDIA_EMBED_CONSENT`.")
      },
      description: "The media settings of the installation, which the preview applies."
    )
  end
end
