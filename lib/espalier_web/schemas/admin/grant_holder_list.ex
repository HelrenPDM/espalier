defmodule EspalierWeb.Schemas.Admin.GrantHolderList do
  @moduledoc """
  The answer of `GET /api/admin/role-grants` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{users: Fields.array(EspalierWeb.Schemas.Admin.User)}),
      %{title: "AdminGrantHolderList", description: "The users with a grant beyond learner."}
    ),
    struct?: false,
    derive?: false
  )
end
