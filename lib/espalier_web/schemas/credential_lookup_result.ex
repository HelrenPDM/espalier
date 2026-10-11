defmodule EspalierWeb.Schemas.CredentialLookupResult do
  @moduledoc """
  The answer of `POST /api/integration/credential-lookups`: the credentials
  in force, with qualification code, status, unlocked tasks and validity
  only (ASVS 15.3.1).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        credentials:
          Fields.array(
            Fields.object(%{
              qualification_code: Fields.string(),
              status: Fields.enum(~w(active refresh_due)),
              unlocks_snapshot: Fields.strings("The tasks the credential unlocks."),
              valid_until: %{Fields.date() | nullable: true}
            }),
            "The credentials in force; an unknown address gives an empty list."
          )
      }),
      %{title: "CredentialLookupResult", description: "The credentials in force of a person."}
    ),
    struct?: false,
    derive?: false
  )
end
