defmodule EspalierWeb.Schemas.LdapCredentialsRequest do
  @moduledoc """
  The body of `POST /api/auth/ldap/{provider}` and
  `POST /api/me/identities/ldap/{provider}` (task 0007).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        username: Fields.request_string(255, "The directory login."),
        password: Fields.request_string(128, "The directory password.")
      }),
      %{title: "LdapCredentialsRequest", description: "A directory bind."}
    ),
    struct?: false,
    derive?: false
  )
end
