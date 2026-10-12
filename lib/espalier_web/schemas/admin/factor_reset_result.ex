defmodule EspalierWeb.Schemas.Admin.FactorResetResult do
  @moduledoc """
  The answer of `POST /api/admin/users/{id}/reset-factors` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        invitation_sent: Fields.boolean("True when a local account received a new invitation.")
      }),
      %{title: "AdminFactorResetResult", description: "The result of a factor reset."}
    ),
    struct?: false,
    derive?: false
  )
end
