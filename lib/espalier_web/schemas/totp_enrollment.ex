defmodule EspalierWeb.Schemas.TotpEnrollment do
  @moduledoc """
  The answer of `POST /api/me/totp` (task 0005): the new secret as QR code,
  in base32 and as `otpauth://` URI. The factor works after one valid code.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        qr_svg_data_url: Fields.string("A `data:image/svg+xml;base64,` URL of the QR code."),
        secret_base32: Fields.string("The secret in base32 without padding."),
        otpauth_uri: Fields.string()
      }),
      %{title: "TotpEnrollment", description: "A TOTP secret awaiting its first code."}
    ),
    struct?: false,
    derive?: false
  )
end
