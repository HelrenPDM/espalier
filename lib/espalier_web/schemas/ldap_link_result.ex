defmodule EspalierWeb.Schemas.LdapLinkResult do
  @moduledoc "The answer of `POST /api/me/identities/ldap/{provider}` (task 0007)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{status: Fields.enum(~w(linked already_linked))}),
      %{title: "LdapLinkResult", description: "The directory account is connected."}
    ),
    struct?: false,
    derive?: false
  )
end
