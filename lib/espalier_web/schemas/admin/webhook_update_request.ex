defmodule EspalierWeb.Schemas.Admin.WebhookUpdateRequest do
  @moduledoc """
  The body of `PUT` and `PATCH /api/admin/webhooks/{id}` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        webhook:
          Fields.object(
            %{
              url: %Schema{
                type: :string,
                minLength: 1,
                maxLength: 255,
                description: "An https URL of a host in WEBHOOK_ALLOWED_HOSTS."
              },
              events: %Schema{
                type: :array,
                minItems: 1,
                maxItems: 4,
                items:
                  Fields.enum(
                    ~w(credential.issued credential.refresh_due credential.expired credential.revoked)
                  )
              },
              secret_env: %Schema{
                type: :string,
                maxLength: 255,
                pattern: "^WEBHOOK_SECRET_[A-Z0-9_]+$(?!\\n)",
                description: "The environment variable that holds the signing secret."
              },
              active: Fields.boolean()
            },
            optional: [:url, :events, :secret_env, :active]
          )
      }),
      %{title: "AdminWebhookUpdateRequest", description: "Changed fields of a webhook."}
    ),
    struct?: false,
    derive?: false
  )
end
