defmodule EspalierWeb.Schemas.PolicyList do
  @moduledoc "The answer of `GET /api/policies`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        policies:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid("The id of the current version."),
              key: Fields.string(),
              title: Fields.string(),
              number: Fields.integer(),
              effective_from: Fields.date(),
              body: Fields.string("Markdown."),
              acknowledged_at: %{
                Fields.datetime("When the signed-in user acknowledged this version.")
                | nullable: true
              }
            }),
            "The current version of every policy, ordered by key."
          )
      }),
      %{
        title: "PolicyList",
        description: "The current policy versions with the acknowledgement of the signed-in user."
      }
    ),
    struct?: false,
    derive?: false
  )
end
