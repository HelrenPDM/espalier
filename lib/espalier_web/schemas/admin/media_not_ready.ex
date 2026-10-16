defmodule EspalierWeb.Schemas.Admin.MediaNotReady do
  @moduledoc """
  The 409 answer `media_not_ready` (task 0018, steps 10 and 16): the publish
  of an import whose media are not all `ready`, the start of a draft from a
  program or an import whose captions are not `ready`, or the download of a
  draft whose media file is not `ready` or missing. Each entry names a path
  of the pack and the state of its asset; `failure` names the code of a
  `failed` asset and is `null` for any other state.
  """
  require OpenApiSpex

  alias Espalier.Media.Asset
  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        error: Fields.enum(~w(media_not_ready)),
        media:
          Fields.array(
            Fields.object(%{
              path: Fields.string(),
              status: Fields.enum(~w(missing queued processing failed)),
              failure: %Schema{
                type: :string,
                enum: Enum.map(Asset.failures(), &Atom.to_string/1),
                nullable: true
              }
            })
          )
      }),
      %{
        title: "AdminMediaNotReady",
        description:
          "A media file is not ready: at the publish of an import, at the start of a " <>
            "draft from a program or an import, or at the download of a draft. " <>
            "`failure` names the code of a `failed` asset."
      }
    ),
    struct?: false,
    derive?: false
  )
end
