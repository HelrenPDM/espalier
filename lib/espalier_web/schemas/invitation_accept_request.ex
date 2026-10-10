defmodule EspalierWeb.Schemas.InvitationAcceptRequest do
  @moduledoc "The body of `POST /api/auth/invitations/accept`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{token: Fields.request_string(255, "The token of the invitation link.")}),
      %{
        title: "InvitationAcceptRequest",
        description: "Accepts an invitation and opens an enrollment session."
      }
    ),
    struct?: false,
    derive?: false
  )
end
