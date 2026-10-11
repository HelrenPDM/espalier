defmodule EspalierWeb.Schemas.CredentialList do
  @moduledoc "The answer of `GET /api/me/credentials`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{CredentialView, Fields}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        credentials: Fields.array(CredentialView, "The credentials, the newest first.")
      }),
      %{title: "CredentialList", description: "The credentials of the signed-in user."}
    ),
    struct?: false,
    derive?: false
  )
end
