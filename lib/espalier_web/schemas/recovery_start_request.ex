defmodule EspalierWeb.Schemas.RecoveryStartRequest do
  @moduledoc "The body of `POST /api/auth/recovery/start` (task 0005)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{email: Fields.request_string(160, "The e-mail address of the account.")}),
      %{title: "RecoveryStartRequest", description: "Sends a recovery link."}
    ),
    struct?: false,
    derive?: false
  )
end
