defmodule EspalierWeb.Schemas.FinishRequest do
  @moduledoc "The body of `POST /api/auth/finish` (task 0006)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        ticket: Fields.request_string(255, "The ticket from the fragment of `/auth/finish`.")
      }),
      %{title: "FinishRequest", description: "Ends an OIDC flow same-origin."}
    ),
    struct?: false,
    derive?: false
  )
end
