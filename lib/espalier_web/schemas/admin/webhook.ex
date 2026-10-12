defmodule EspalierWeb.Schemas.Admin.Webhook do
  @moduledoc """
  The answer of the webhook routes of task 0015.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        data:
          Fields.object(%{
            id: Fields.uuid(),
            url: Fields.string(),
            events: Fields.strings(),
            secret_env: Fields.string(),
            active: Fields.boolean()
          })
      }),
      %{title: "AdminWebhook", description: "A webhook."}
    ),
    struct?: false,
    derive?: false
  )
end
