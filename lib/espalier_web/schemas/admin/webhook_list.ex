defmodule EspalierWeb.Schemas.Admin.WebhookList do
  @moduledoc """
  The answer of `GET /api/admin/webhooks` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        data:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              url: Fields.string(),
              events: Fields.strings(),
              secret_env: Fields.string(),
              active: Fields.boolean()
            })
          )
      }),
      %{title: "AdminWebhookList", description: "The webhooks, ordered by URL."}
    ),
    struct?: false,
    derive?: false
  )
end
