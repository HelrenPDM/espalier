defmodule EspalierWeb.Schemas.AttendanceResult do
  @moduledoc "The answer of `POST /api/formats/{id}/attendance`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        results:
          Fields.array(
            Fields.object(%{
              user_id: Fields.uuid(),
              result:
                Fields.enum(
                  ~w(issued exists not_found),
                  "`issued` for a new certificate, `exists` when the user holds one for the " <>
                    "format and the date, `not_found` without an active user."
                )
            }),
            "One result per distinct user id, in request order."
          )
      }),
      %{title: "AttendanceResult", description: "The result per user."}
    ),
    struct?: false,
    derive?: false
  )
end
