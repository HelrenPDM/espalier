defmodule EspalierWeb.Schemas.ApprovedToolList do
  @moduledoc "The answer of `GET /api/approved-tools`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        tools:
          Fields.array(
            Fields.object(%{
              id: Fields.uuid(),
              name: Fields.string(),
              vendor: Fields.string(),
              status: Fields.enum(~w(approved restricted not_approved)),
              conditions: Fields.nullable_string(),
              reviewed_on: %{Fields.date() | nullable: true},
              position: Fields.integer()
            }),
            "The tools ordered by position."
          )
      }),
      %{title: "ApprovedToolList", description: "The approved tool list."}
    ),
    struct?: false,
    derive?: false
  )
end
