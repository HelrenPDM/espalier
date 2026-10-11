defmodule EspalierWeb.Schemas.UserLookupResult do
  @moduledoc "The answer of `POST /api/facilitator/user-lookups`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        display_name: Fields.nullable_string(),
        org_unit: Fields.nullable_string()
      }),
      %{title: "UserLookupResult", description: "An active user."}
    ),
    struct?: false,
    derive?: false
  )
end
