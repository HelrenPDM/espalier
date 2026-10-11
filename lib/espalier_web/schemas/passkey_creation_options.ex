defmodule EspalierWeb.Schemas.PasskeyCreationOptions do
  @moduledoc """
  The creation options of a passkey registration as `@simplewebauthn/browser`
  passes them to `navigator.credentials.create`
  (`Espalier.Accounts.Passkeys.Options.creation/4`, task 0005).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        rp: Fields.object(%{id: Fields.string(), name: Fields.string()}),
        user:
          Fields.object(%{
            id: Fields.string("The WebAuthn user handle, base64url without padding."),
            name: Fields.string(),
            displayName: Fields.string()
          }),
        challenge: Fields.string("Base64url without padding."),
        pubKeyCredParams:
          Fields.array(
            Fields.object(%{
              type: Fields.enum(["public-key"]),
              alg: %Schema{type: :integer, enum: [-8, -7, -257]}
            })
          ),
        timeout: %Schema{type: :integer, description: "Milliseconds (300,000)."},
        excludeCredentials:
          Fields.array(Fields.passkey_descriptor(), "The passkeys the user already holds."),
        authenticatorSelection:
          Fields.object(%{
            residentKey: Fields.enum(["required"]),
            userVerification: Fields.enum(["required"])
          }),
        attestation: Fields.enum(["none"])
      }),
      %{title: "PasskeyCreationOptions", description: "The options JSON of a registration."}
    ),
    struct?: false,
    derive?: false
  )
end
