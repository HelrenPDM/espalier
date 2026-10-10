defmodule EspalierWeb.Schemas.EnrollmentPathRequest do
  @moduledoc "The body of `PATCH /api/enrollments/{id}`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{path: Fields.enum(~w(short full), "The path the learner chose.")}),
      %{title: "EnrollmentPathRequest", description: "Sets the path by the learner's choice."}
    ),
    struct?: false,
    derive?: false
  )
end
