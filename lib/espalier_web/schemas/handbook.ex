defmodule EspalierWeb.Schemas.Handbook do
  @moduledoc """
  The answer of `GET /api/programs/{slug}/handbook` (README section 7,
  domain rule 10).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        modules:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              number: Fields.integer(),
              title: Fields.string(),
              rules:
                Fields.array(
                  Fields.object(%{
                    number: Fields.integer(),
                    statement: Fields.string(),
                    action: Fields.string()
                  })
                )
            }),
            "The modules in number order with their rules."
          ),
        placeholders: Fields.strings("The keys of the policies that placeholder blocks name.")
      }),
      %{title: "Handbook", description: "Every rule with its statement and action."}
    ),
    struct?: false,
    derive?: false
  )
end
