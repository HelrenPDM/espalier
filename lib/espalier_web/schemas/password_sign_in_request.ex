defmodule EspalierWeb.Schemas.PasswordSignInRequest do
  @moduledoc "The body of `POST /api/auth/password`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        email: Fields.request_string(160, "The e-mail address."),
        password: Fields.request_string(128, "The password.")
      }),
      %{
        title: "PasswordSignInRequest",
        description: "A password sign-in; it yields the pending second-factor state."
      }
    ),
    struct?: false,
    derive?: false
  )
end
