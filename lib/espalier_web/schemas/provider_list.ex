defmodule EspalierWeb.Schemas.ProviderList do
  @moduledoc "The answer of `GET /auth/providers`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        providers: Fields.array(Fields.provider(), "In configured order.")
      }),
      %{title: "ProviderList", description: "The external identity providers."}
    ),
    struct?: false,
    derive?: false
  )
end
