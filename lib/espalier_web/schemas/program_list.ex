defmodule EspalierWeb.Schemas.ProgramList do
  @moduledoc "The answer of `GET /api/programs`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        programs:
          Fields.array(
            Fields.object(%{
              slug: Fields.string("The key of the content pack."),
              title: Fields.string(),
              locale: Fields.string("The language tag of the content.")
            })
          )
      }),
      %{title: "ProgramList", description: "The published programs, ordered by slug."}
    ),
    struct?: false,
    derive?: false
  )
end
