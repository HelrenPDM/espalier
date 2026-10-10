defmodule EspalierWeb.Schemas.ItemResponseRequest do
  @moduledoc "The body of `POST /api/items/{id}/responses`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Answer, Fields}

  OpenApiSpex.schema(
    Map.merge(Fields.object(%{answer: Answer}), %{
      title: "ItemResponseRequest",
      description: "A practice answer. The answer is evaluated and stored nowhere."
    }),
    struct?: false,
    derive?: false
  )
end
