defmodule EspalierWeb.Schemas.DemoSignInRequest do
  @moduledoc "The body of `POST /api/auth/demo`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{slot: %Schema{type: :integer, minimum: 1, maximum: 20}}),
      %{title: "DemoSignInRequest", description: "A demo sign-in with `AUTH_DEMO=true`."}
    ),
    struct?: false,
    derive?: false
  )
end
