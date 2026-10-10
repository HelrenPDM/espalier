defmodule EspalierWeb.Schemas.EmailChangeRequest do
  @moduledoc "The body of `PUT /api/me/email`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{email: Fields.request_string(160, "The new e-mail address.")}),
      %{
        title: "EmailChangeRequest",
        description: "Requests an e-mail change; the link goes to the new address."
      }
    ),
    struct?: false,
    derive?: false
  )
end
