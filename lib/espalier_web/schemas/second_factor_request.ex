defmodule EspalierWeb.Schemas.SecondFactorRequest do
  @moduledoc """
  The body of `POST /api/auth/second-factor` (task 0005): exactly one of
  `totp`, `passkey` and `recovery_code`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, PasskeyAssertion}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          totp: Fields.request_string(6, "A six-digit code of the authenticator app."),
          passkey: PasskeyAssertion,
          recovery_code:
            Fields.request_string(64, "A recovery code; case, spaces and hyphens do not count.")
        },
        optional: [:totp, :passkey, :recovery_code]
      ),
      %{
        title: "SecondFactorRequest",
        description: "Exactly one second factor.",
        minProperties: 1,
        maxProperties: 1
      }
    ),
    struct?: false,
    derive?: false
  )
end
