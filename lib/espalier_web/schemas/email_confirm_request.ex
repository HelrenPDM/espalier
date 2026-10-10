defmodule EspalierWeb.Schemas.EmailConfirmRequest do
  @moduledoc "The body of `POST /api/me/email/confirm`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{token: Fields.request_string(255, "The token of the confirmation link.")}),
      %{title: "EmailConfirmRequest", description: "Confirms an e-mail change."}
    ),
    struct?: false,
    derive?: false
  )
end
