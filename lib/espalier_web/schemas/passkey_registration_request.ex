defmodule EspalierWeb.Schemas.PasskeyRegistrationRequest do
  @moduledoc "The body of `POST /api/me/passkeys` (task 0005)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, PasskeyAttestation}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          credential: PasskeyAttestation,
          nickname: Fields.request_string(60, "The name of the passkey in the list.")
        },
        optional: [:nickname]
      ),
      %{title: "PasskeyRegistrationRequest", description: "Registers a passkey."}
    ),
    struct?: false,
    derive?: false
  )
end
