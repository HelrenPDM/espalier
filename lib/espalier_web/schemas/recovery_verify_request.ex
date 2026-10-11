defmodule EspalierWeb.Schemas.RecoveryVerifyRequest do
  @moduledoc "The body of `POST /api/auth/recovery/verify` (task 0005)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        token: Fields.request_string(255, "The token of the recovery link."),
        recovery_code:
          Fields.request_string(
            64,
            "A saved recovery code; case, spaces and hyphens do not count."
          )
      }),
      %{
        title: "RecoveryVerifyRequest",
        description: "The link and a saved recovery code open a recovery session."
      }
    ),
    struct?: false,
    derive?: false
  )
end
