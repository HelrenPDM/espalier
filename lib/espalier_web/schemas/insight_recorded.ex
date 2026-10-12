defmodule EspalierWeb.Schemas.InsightRecorded do
  @moduledoc "The answer of `POST /api/formats/{id}/votes` and `POST /api/feedback`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        already_recorded:
          Fields.boolean("True when the user had answered before; nothing new was stored.")
      }),
      %{
        title: "InsightRecorded",
        description: "Whether an anonymous answer was stored now or before."
      }
    ),
    struct?: false,
    derive?: false
  )
end
