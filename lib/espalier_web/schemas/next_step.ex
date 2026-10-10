defmodule EspalierWeb.Schemas.NextStep do
  @moduledoc "The answer of `POST /api/auth/password`: the next sign-in step."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{next: Fields.enum(["second_factor"])}),
      %{title: "NextStep", description: "The sign-in continues with a second factor."}
    ),
    struct?: false,
    derive?: false
  )
end
