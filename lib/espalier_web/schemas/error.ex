defmodule EspalierWeb.Schemas.Error do
  @moduledoc """
  The error body of every error answer (README section 6.10):
  `{"error": code}`, and for `validation_failed` the codes per member in
  `fields`. It matches `EspalierWeb.ErrorJSON` and
  `EspalierWeb.FallbackController`.
  """
  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    %{
      title: "Error",
      description: "An error code without internals.",
      type: :object,
      properties: %{
        error: %Schema{type: :string, description: "The error code."},
        fields: %Schema{
          type: :object,
          description: "For `validation_failed`: the error codes per member.",
          additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
        }
      },
      required: [:error]
    },
    struct?: false,
    derive?: false
  )
end
