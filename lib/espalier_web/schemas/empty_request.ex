defmodule EspalierWeb.Schemas.EmptyRequest do
  @moduledoc """
  The optional body of a route without request members, such as
  `POST /api/modules/{id}/completion`. A body with any member answers 422.
  """
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "EmptyRequest",
      description: "No members.",
      type: :object,
      properties: %{},
      additionalProperties: false
    },
    struct?: false,
    derive?: false
  )
end
