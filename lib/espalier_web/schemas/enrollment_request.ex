defmodule EspalierWeb.Schemas.EnrollmentRequest do
  @moduledoc "The body of `POST /api/enrollments`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        program_slug: Fields.key_param("The slug of a published program."),
        path: Fields.enum(~w(short full), "The path preselected from the segment default.")
      }),
      %{title: "EnrollmentRequest", description: "Enrolls the signed-in user in a program."}
    ),
    struct?: false,
    derive?: false
  )
end
