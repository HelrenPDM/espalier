defmodule EspalierWeb.Schemas.Admin.User do
  @moduledoc """
  A user of the admin area (task 0015): no address and no subject (ASVS
  15.3.1).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        display_name: Fields.nullable_string(),
        status: Fields.enum(~w(active disabled)),
        roles: Fields.array(Fields.enum(~w(learner facilitator author registrar analyst admin))),
        last_login_at: %Schema{type: :string, format: :"date-time", nullable: true},
        enrolled:
          Fields.boolean("True when the user holds a passkey or a confirmed TOTP factor."),
        provider_keys:
          Fields.strings("The provider keys of the external identities; no subject."),
        grants:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              user_id: Fields.uuid(),
              role: Fields.enum(~w(learner facilitator author registrar analyst admin)),
              source: Fields.enum(~w(idp_claim manual)),
              provider_key: Fields.nullable_string()
            })
          )
      }),
      %{title: "AdminUser", description: "A user with roles, grants and linked providers."}
    ),
    struct?: false,
    derive?: false
  )
end
