defmodule EspalierWeb.Schemas.Admin.MediaUpdate do
  @moduledoc "The body of `PATCH /api/admin/media/{id}` (task 0018, step 15)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        title: %Schema{
          type: :string,
          minLength: 1,
          maxLength: 255,
          description: "1 to 255 characters without U+0000."
        }
      }),
      %{title: "AdminMediaUpdate", description: "The new title of an asset."}
    ),
    struct?: false,
    derive?: false
  )
end
