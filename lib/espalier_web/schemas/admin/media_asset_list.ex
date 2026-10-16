defmodule EspalierWeb.Schemas.Admin.MediaAssetList do
  @moduledoc """
  A page of the media library (task 0018, step 15), newest first. `next` is
  the opaque cursor of the following page, or `null` on the last page.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Admin.MediaAsset
  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        items: Fields.array(MediaAsset),
        next: Fields.nullable_string("The cursor of the next page, for the query `after`.")
      }),
      %{title: "AdminMediaAssetList", description: "A page of the media library."}
    ),
    struct?: false,
    derive?: false
  )
end
