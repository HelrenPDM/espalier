defmodule EspalierWeb.Schemas.Admin.UserInviteRequest do
  @moduledoc """
  The body of `POST /api/admin/users` (task 0015).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          email: %Schema{type: :string, minLength: 1, maxLength: 160},
          display_name: %Schema{type: :string, maxLength: 160}
        },
        optional: [:display_name]
      ),
      %{title: "AdminUserInviteRequest", description: "An invitation of a new local user."}
    ),
    struct?: false,
    derive?: false
  )
end
