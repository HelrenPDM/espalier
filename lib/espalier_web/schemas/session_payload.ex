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
           signup: Fields.enum(~w(closed invite domain)),
           test_notes:
             Fields.boolean(
               "Mirrors `TEST_NOTES`: the SPA records the test session notes in the browser."
             ),
           feedback_free_text:
             Fields.boolean(
               "Mirrors `FEEDBACK_FREE_TEXT`: the feedback station shows free-text questions."
             )
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

  @doc """
  The schema of an answer that carries the session payload and the members
  `extra`, required unless named in `optional`, with `title` and
  `description` (task 0011).
  """
  def with_members(title, description, extra, optional \\ []) do
    base = schema()
    required = Enum.sort(base.required ++ (Map.keys(extra) -- optional))

    %{
      base
      | title: title,
        description: description,
        properties: Map.merge(base.properties, extra),
        required: required
    }
  end
end
