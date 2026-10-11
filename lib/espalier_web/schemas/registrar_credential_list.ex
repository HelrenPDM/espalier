defmodule EspalierWeb.Schemas.RegistrarCredentialList do
  @moduledoc "The answer of `GET /api/registrar/credentials`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        credentials:
          Fields.array(
            Fields.object(%{
              display_name: Fields.nullable_string(),
              org_unit: Fields.nullable_string(),
              status: Fields.enum(~w(active refresh_due expired revoked)),
              issued_at: Fields.datetime(),
              valid_until: %{Fields.date() | nullable: true}
            }),
            "One entry per credential of a qualification with this code, ordered by display " <>
              "name. Codes are unique per program, so a person who holds the code in two " <>
              "programs appears once per program."
          )
      }),
      %{
        title: "RegistrarCredentialList",
        description: "The credentials of one qualification (README section 10)."
      }
    ),
    struct?: false,
    derive?: false
  )
end
