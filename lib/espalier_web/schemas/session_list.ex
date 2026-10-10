defmodule EspalierWeb.Schemas.SessionList do
  @moduledoc "The answer of `GET /api/me/sessions`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        sessions:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              current: Fields.boolean("True on the calling session."),
              device: Fields.nullable_string("The device summary of the user agent."),
              strength: Fields.enum(~w(mfa recovery enrollment demo)),
              auth_methods:
                Fields.array(
                  Fields.enum(
                    ~w(passkey password totp recovery_code email_code oidc ldap idp_mfa demo)
                  )
                ),
              authenticated_at: Fields.datetime(),
              last_seen_at: Fields.datetime(),
              expires_at: Fields.datetime()
            })
          )
      }),
      %{title: "SessionList", description: "The sessions of the signed-in user."}
    ),
    struct?: false,
    derive?: false
  )
end
