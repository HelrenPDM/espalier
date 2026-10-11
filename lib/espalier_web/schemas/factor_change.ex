defmodule EspalierWeb.Schemas.FactorChange do
  @moduledoc """
  The answer of `DELETE /api/me/passkeys/{id}` and `DELETE /api/me/totp`
  (task 0005): the number of other live sessions, which the SPA offers to
  end (ASVS 7.4.3).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{other_sessions: Fields.integer("The other live sessions of the user.")}),
      %{title: "FactorChange", description: "The factor was removed."}
    ),
    struct?: false,
    derive?: false
  )
end
