defmodule EspalierWeb.Schemas.PasskeyView do
  @moduledoc "A passkey of the signed-in user, without key material (task 0005)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        nickname: Fields.nullable_string(),
        inserted_at: Fields.datetime(),
        last_used_at: %{Fields.datetime() | nullable: true},
        backup_eligible: Fields.boolean("The authenticator can sync the passkey."),
        backed_up: Fields.boolean("The passkey is synced."),
        transports: Fields.strings()
      }),
      %{title: "PasskeyView", description: "A registered passkey."}
    ),
    struct?: false,
    derive?: false
  )
end
