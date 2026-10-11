defmodule EspalierWeb.Schemas.SecuritySummary do
  @moduledoc """
  The answer of `GET /api/me/security` (task 0005 step 17,
  `Espalier.Accounts.Factors.summary/1`). `linked_providers` (task 0011)
  holds the provider keys of the user's external identities and no
  subject, issuer or directory value.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, PasskeyView}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        passkeys: Fields.array(PasskeyView),
        totp:
          Fields.object(%{
            enabled: Fields.boolean(),
            enabled_at: %{Fields.datetime() | nullable: true}
          }),
        recovery_codes:
          Fields.object(%{
            remaining: Fields.integer("The number of unused codes."),
            generated_at: %{Fields.datetime() | nullable: true}
          }),
        password_set: Fields.boolean(),
        admin_passkey_required:
          Fields.boolean("An admin without a passkey while `ADMIN_REQUIRE_PASSKEY=true`."),
        linked_providers:
          Fields.strings(
            "The sorted provider keys of the external identities; `[]` for a local account."
          ),
        recent_auth_until: %{
          Fields.datetime("The end of the 10-minute window of a recent second factor.")
          | nullable: true
        }
      }),
      %{title: "SecuritySummary", description: "The second factors of the signed-in user."}
    ),
    struct?: false,
    derive?: false
  )
end
