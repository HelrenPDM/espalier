defmodule EspalierWeb.Schemas.PasskeyOptionsRequest do
  @moduledoc "The body of `POST /api/auth/passkey/options` (task 0005)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          purpose:
            Fields.enum(
              ~w(sign_in second_factor reauth),
              "The ceremony: discoverable sign-in (the default), the second factor of a " <>
                "pending sign-in, or the re-authentication of an `mfa` session."
            )
        },
        optional: [:purpose]
      ),
      %{title: "PasskeyOptionsRequest", description: "Starts a passkey assertion ceremony."}
    ),
    struct?: false,
    derive?: false
  )
end
