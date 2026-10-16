defmodule EspalierWeb.Schemas.Admin.MediaInUse do
  @moduledoc """
  The 409 answer `asset_in_use` of `DELETE /api/admin/media/{id}` (task
  0018, step 15): a published program or a draft uses the asset.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Admin.MediaUses
  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{error: Fields.enum(~w(asset_in_use)), uses: MediaUses}),
      %{title: "AdminMediaInUse", description: "The asset is in use."}
    ),
    struct?: false,
    derive?: false
  )
end
