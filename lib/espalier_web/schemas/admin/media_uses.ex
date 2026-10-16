defmodule EspalierWeb.Schemas.Admin.MediaUses do
  @moduledoc """
  The uses of a media asset (task 0018, steps 8 and 15): the published
  programs of `program_media`, the drafts of `pack_draft_media` and the
  imports in status `validated` whose payload names the asset. Programs and
  drafts keep the asset from deletion; validated imports do not.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        programs:
          Fields.array(
            Fields.object(%{slug: Fields.string(), title: Fields.string()}),
            "The published programs that show the asset."
          ),
        drafts:
          Fields.array(
            Fields.object(%{id: Fields.uuid(), title: Fields.string(), path: Fields.string()}),
            "The drafts of the pack workbench that hold the asset, with its path there."
          ),
        imports:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              pack_key: Fields.nullable_string(),
              inserted_at: Fields.datetime()
            }),
            "The validated imports whose payload names the asset."
          )
      }),
      %{title: "AdminMediaUses", description: "Where a media asset is used."}
    ),
    struct?: false,
    derive?: false
  )
end
