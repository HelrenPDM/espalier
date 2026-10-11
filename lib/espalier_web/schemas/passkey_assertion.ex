defmodule EspalierWeb.Schemas.PasskeyAssertion do
  @moduledoc """
  The result of `startAuthentication` of `@simplewebauthn/browser`
  (`AuthenticationResponseJSON`): the body of `POST /api/auth/passkey` and
  the member `passkey` of the second factor and the re-authentication.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

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
                authenticatorData: Fields.string(),
                signature: Fields.string(),
                userHandle: Fields.string("The user handle of a discoverable credential.")
              },
              optional: [:userHandle]
            ),
          authenticatorAttachment: Fields.enum(~w(platform cross-platform)),
          clientExtensionResults: Fields.extension_results()
        },
        optional: [:authenticatorAttachment]
      ),
      %{title: "PasskeyAssertion", description: "A passkey assertion, base64url-encoded."}
    ),
    struct?: false,
    derive?: false
  )
end
