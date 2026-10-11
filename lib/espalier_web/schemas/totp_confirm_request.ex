defmodule EspalierWeb.Schemas.TotpConfirmRequest do
  @moduledoc "The body of `POST /api/me/totp/confirm` (task 0005)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{code: Fields.request_string(6, "A six-digit code of the new secret.")}),
      %{title: "TotpConfirmRequest", description: "Confirms the authenticator app."}
    ),
    struct?: false,
    derive?: false
  )
end
