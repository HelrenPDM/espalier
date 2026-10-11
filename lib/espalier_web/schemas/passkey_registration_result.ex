defmodule EspalierWeb.Schemas.PasskeyRegistrationResult do
  @moduledoc """
  The answer of `POST /api/me/passkeys` (task 0005,
  `EspalierWeb.Me.FactorResponse`). `recovery_codes` and `session` appear
  when the registration completes an enrollment or a recovery.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, PasskeyView, SessionPayload}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          passkey: PasskeyView,
          other_sessions: Fields.integer("The other live sessions of the user."),
          recovery_codes: Fields.strings("Shown once: ten new recovery codes."),
          session: SessionPayload
        },
        optional: [:recovery_codes, :session]
      ),
      %{title: "PasskeyRegistrationResult", description: "The registered passkey."}
    ),
    struct?: false,
    derive?: false
  )
end
