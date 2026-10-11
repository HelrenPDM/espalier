defmodule EspalierWeb.Schemas.LogoutRedirect do
  @moduledoc """
  The 200 answer of `DELETE /api/session` for an OIDC session whose
  provider has an end-session endpoint (task 0006, step 13).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        logout_url:
          Fields.string(
            "The RP-initiated logout URL of the provider, with `post_logout_redirect_uri` " <>
              "`PUBLIC_URL/signed-out`."
          )
      }),
      %{title: "LogoutRedirect", description: "Signed out; the provider session ends next."}
    ),
    struct?: false,
    derive?: false
  )
end
