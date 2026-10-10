defmodule EspalierWeb.Schemas.SessionPayload do
  @moduledoc """
  The session payload of `GET /api/session` and of the sign-in answers
  (`EspalierWeb.SessionJSON`, task 0004 step 35, README section 6.12).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  @user %{
    Fields.object(%{
      id: Fields.uuid(),
      display_name: Fields.nullable_string(),
      email: Fields.nullable_string("`null` for demo accounts and accounts without an address."),
      locale: Fields.string()
    })
    | nullable: true
  }

  @session %{
    Fields.object(%{
      strength: Fields.enum(~w(mfa recovery enrollment demo)),
      auth_methods:
        Fields.array(
          Fields.enum(~w(passkey password totp recovery_code email_code oidc ldap idp_mfa demo))
        ),
      provider_key:
        Fields.nullable_string("The provider of the session row; `null` for local and demo."),
      recent_auth_until: %{
        Fields.datetime("The end of the 10-minute window of a recent second factor.")
        | nullable: true
      },
      expires_at: Fields.datetime(),
      idle_timeout_minutes: Fields.integer()
    })
    | nullable: true
  }

  @pending %{
    Fields.object(%{next: Fields.enum(["second_factor"]), expires_at: Fields.datetime()})
    | nullable: true,
      description: "The pending second-factor state after a first factor."
  }

  @flags Fields.object(%{
           admin_passkey_required: Fields.boolean(),
           demo: Fields.boolean("Mirrors `AUTH_DEMO`."),
           local_accounts: Fields.boolean(),
           signup: Fields.enum(~w(closed invite domain))
         })

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        user: @user,
        roles: Fields.array(Fields.enum(~w(learner facilitator author registrar analyst admin))),
        session: @session,
        pending: @pending,
        csrf_token: Fields.string("The token for the `x-csrf-token` header."),
        providers: Fields.array(Fields.provider()),
        flags: @flags
      }),
      %{title: "SessionPayload", description: "The session of the browser."}
    ),
    struct?: false,
    derive?: false
  )
end
