defmodule EspalierWeb.Schemas.PasskeyAttestation do
  @moduledoc """
  The result of `startRegistration` of `@simplewebauthn/browser`
  (`RegistrationResponseJSON`): the member `credential` of
  `POST /api/me/passkeys`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          id: Fields.string("The credential id, base64url."),
          rawId: Fields.string("The credential id, base64url."),
          type: Fields.enum(["public-key"]),
          response:
            Fields.object(
              %{
                clientDataJSON: Fields.string(),
                attestationObject: Fields.string(),
                authenticatorData: Fields.string(),
                transports: Fields.strings("Only the known transports are stored."),
                publicKeyAlgorithm: %Schema{type: :integer},
                publicKey: Fields.string()
              },
              optional: [:authenticatorData, :transports, :publicKeyAlgorithm, :publicKey]
            ),
          authenticatorAttachment: Fields.enum(~w(platform cross-platform)),
          clientExtensionResults: Fields.extension_results()
        },
        optional: [:authenticatorAttachment]
      ),
      %{title: "PasskeyAttestation", description: "A passkey registration, base64url-encoded."}
    ),
    struct?: false,
    derive?: false
  )
end
