defmodule EspalierWeb.Schemas.TotpConfirmResult do
  @moduledoc """
  The answer of `POST /api/me/totp/confirm` (task 0005,
  `EspalierWeb.Me.FactorResponse`). `recovery_codes` and `session` appear
  when the confirmation completes an enrollment or a recovery.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, SessionPayload}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          totp: Fields.object(%{enabled: Fields.boolean(), enabled_at: Fields.datetime()}),
          other_sessions: Fields.integer("The other live sessions of the user."),
          recovery_codes: Fields.strings("Shown once: ten new recovery codes."),
          session: SessionPayload
        },
        optional: [:recovery_codes, :session]
      ),
      %{title: "TotpConfirmResult", description: "The authenticator app is enabled."}
    ),
    struct?: false,
    derive?: false
  )
end
