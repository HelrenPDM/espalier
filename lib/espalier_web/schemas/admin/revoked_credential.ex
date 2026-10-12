defmodule EspalierWeb.Schemas.Admin.RevokedCredential do
  @moduledoc """
  The answer of `POST /api/admin/credentials/{id}/revoke` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        qualification_code: Fields.string(),
        status: Fields.enum(["revoked"])
      }),
      %{title: "AdminRevokedCredential", description: "A revoked credential."}
    ),
    struct?: false,
    derive?: false
  )
end
