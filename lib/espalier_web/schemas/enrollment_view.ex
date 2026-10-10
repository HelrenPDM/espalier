defmodule EspalierWeb.Schemas.EnrollmentView do
  @moduledoc "The answer of `POST /api/enrollments` and `PATCH /api/enrollments/{id}`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        program_id: Fields.uuid(),
        path: Fields.enum(~w(short full)),
        path_chosen_manually: Fields.boolean("True after the learner chose the path by hand."),
        started_at: Fields.datetime()
      }),
      %{title: "EnrollmentView", description: "The enrollment of the signed-in user."}
    ),
    struct?: false,
    derive?: false
  )
end
