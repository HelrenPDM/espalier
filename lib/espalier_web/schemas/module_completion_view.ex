defmodule EspalierWeb.Schemas.ModuleCompletionView do
  @moduledoc "The answer of `POST /api/modules/{id}/completion`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{module_id: Fields.uuid(), completed_at: Fields.datetime()}),
      %{title: "ModuleCompletionView", description: "The completion of a module."}
    ),
    struct?: false,
    derive?: false
  )
end
