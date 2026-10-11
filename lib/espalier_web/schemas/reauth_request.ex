defmodule EspalierWeb.Schemas.ReauthRequest do
  @moduledoc """
  The body of `POST /api/me/reauth` (task 0005): exactly one of `totp` and
  `passkey`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, PasskeyAssertion}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          totp: Fields.request_string(6, "A six-digit code of the authenticator app."),
          passkey: PasskeyAssertion
        },
        optional: [:totp, :passkey]
      ),
      %{
        title: "ReauthRequest",
        description: "Exactly one local second factor.",
        minProperties: 1,
        maxProperties: 1
      }
    ),
    struct?: false,
    derive?: false
  )
end
