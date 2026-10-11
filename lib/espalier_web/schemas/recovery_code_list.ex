defmodule EspalierWeb.Schemas.RecoveryCodeList do
  @moduledoc "The answer of `POST /api/me/recovery-codes` (task 0005)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        recovery_codes:
          Fields.strings("Shown once: ten new codes; every earlier code stops working.")
      }),
      %{title: "RecoveryCodeList", description: "New recovery codes."}
    ),
    struct?: false,
    derive?: false
  )
end
