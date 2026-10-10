defmodule EspalierWeb.Schemas.Accepted do
  @moduledoc """
  The 202 answer of `POST /api/auth/invitations` and `PUT /api/me/email`,
  the same for known and unknown addresses.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{status: Fields.enum(["accepted"])}),
      %{title: "Accepted", description: "The request was accepted."}
    ),
    struct?: false,
    derive?: false
  )
end
