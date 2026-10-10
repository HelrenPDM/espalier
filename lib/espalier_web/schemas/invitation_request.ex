defmodule EspalierWeb.Schemas.InvitationRequest do
  @moduledoc "The body of `POST /api/auth/invitations`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{email: Fields.request_string(160, "The e-mail address to invite.")}),
      %{title: "InvitationRequest", description: "A self-service invitation request."}
    ),
    struct?: false,
    derive?: false
  )
end
