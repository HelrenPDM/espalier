defmodule EspalierWeb.Schemas.EmailLookupRequest do
  @moduledoc """
  The body of `POST /api/facilitator/user-lookups` and
  `POST /api/integration/credential-lookups`. The address travels in the
  body, so no URL carries it (ASVS 14.2.1).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        email: %Schema{
          type: :string,
          minLength: 1,
          maxLength: 254,
          description: "The exact address; letter case and surrounding spaces do not matter."
        }
      }),
      %{title: "EmailLookupRequest", description: "A lookup by e-mail address."}
    ),
    struct?: false,
    derive?: false
  )
end
