defmodule EspalierWeb.Schemas.AttendanceRequest do
  @moduledoc "The body of `POST /api/formats/{id}/attendance`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        user_ids: %Schema{
          type: :array,
          items: Fields.uuid(),
          minItems: 1,
          maxItems: 200,
          description: "The users who attended."
        },
        held_on:
          Fields.date(
            "The day of the session, from 2000-01-01 to today; an earlier day answers 422 " <>
              "`past`, a later one 422 `future`."
          )
      }),
      %{title: "AttendanceRequest", description: "The attendance of a session of a format."}
    ),
    struct?: false,
    derive?: false
  )
end
