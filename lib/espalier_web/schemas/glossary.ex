defmodule EspalierWeb.Schemas.Glossary do
  @moduledoc "The answer of `GET /api/programs/{slug}/glossary`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        terms:
          Fields.array(
            Fields.object(%{
              slug: Fields.string(),
              label: Fields.string(),
              short_text: Fields.string()
            }),
            "The terms ordered by slug."
          )
      }),
      %{title: "Glossary", description: "The glossary of a program."}
    ),
    struct?: false,
    derive?: false
  )
end
