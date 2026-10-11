defmodule EspalierWeb.Schemas.OidcIntentRequest do
  @moduledoc "The body of `POST /api/auth/oidc/{provider}/intents` (task 0006)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        purpose:
          Fields.enum(
            ~w(link step_up),
            "`link` connects the provider; `step_up` re-authenticates at the provider."
          )
      }),
      %{title: "OidcIntentRequest", description: "Creates a single-use intent."}
    ),
    struct?: false,
    derive?: false
  )
end
