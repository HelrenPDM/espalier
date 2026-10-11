defmodule EspalierWeb.Schemas.PasskeyRequestOptions do
  @moduledoc """
  The request options of a passkey assertion as `@simplewebauthn/browser`
  passes them to `navigator.credentials.get`
  (`Espalier.Accounts.Passkeys.Options.request/3`, task 0005).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          challenge: Fields.string("Base64url without padding."),
          timeout: %Schema{type: :integer, description: "Milliseconds (300,000)."},
          rpId: Fields.string(),
          userVerification: Fields.enum(["required"]),
          allowCredentials:
            Fields.array(
              Fields.passkey_descriptor(),
              "The credentials of the user; absent for the discoverable sign-in."
            )
        },
        optional: [:allowCredentials]
      ),
      %{title: "PasskeyRequestOptions", description: "The options JSON of an assertion."}
    ),
    struct?: false,
    derive?: false
  )
end
