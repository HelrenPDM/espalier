defmodule EspalierWeb.Schemas.Admin.PackDraftFile do
  @moduledoc "A file of a draft with its content (task 0016a, step 9)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        path: Fields.string(),
        content: Fields.string(),
        bytes: Fields.integer(),
        updated_at: Fields.datetime(),
        lock_version: %Schema{
          type: :integer,
          minimum: 1,
          description: "The `lock_version` of the draft."
        }
      }),
      %{title: "AdminPackDraftFile", description: "A file of a draft."}
    ),
    struct?: false,
    derive?: false
  )
end
