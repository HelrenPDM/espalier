defmodule EspalierWeb.Schemas.CredentialView do
  @moduledoc """
  The answer of `GET /api/me/credentials/{id}`, and the shape of each entry
  of `GET /api/me/credentials`. A credential names the tasks it unlocks and
  carries no score, percentage or rank (README principle 2).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        qualification_code: Fields.string(),
        qualification_title: Fields.string(),
        locale:
          Fields.string(
            "The language of the program, in which the qualification title and the " <>
              "unlocked tasks are written."
          ),
        holder_display_name: Fields.nullable_string("The display name of the holder."),
        status: Fields.enum(~w(active refresh_due expired revoked)),
        issued_at: Fields.datetime(),
        valid_until: %{Fields.date("The last day of validity, or `null`.") | nullable: true},
        unlocks_snapshot: Fields.strings("The tasks the credential unlocks, as issued.")
      }),
      %{title: "CredentialView", description: "A credential of the signed-in user."}
    ),
    struct?: false,
    derive?: false
  )
end
