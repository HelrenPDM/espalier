defmodule EspalierWeb.Schemas.Admin.UserList do
  @moduledoc """
  The answer of `GET /api/admin/users` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        users: Fields.array(EspalierWeb.Schemas.Admin.User),
        page: Fields.integer(),
        per_page: Fields.integer(),
        total: Fields.integer()
      }),
      %{title: "AdminUserList", description: "One page of users, ordered by creation."}
    ),
    struct?: false,
    derive?: false
  )
end
