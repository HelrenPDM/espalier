defmodule EspalierWeb.Schemas.Participation do
  @moduledoc "The answer of `GET /api/me/participation`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        self_assessment: Fields.boolean("True after the self-assessment of the program."),
        feedback: Fields.boolean("True after the feedback of the program."),
        format_votes:
          Fields.uuids(
            "The ids of the live companion formats of the program that the user voted for."
          )
      }),
      %{
        title: "Participation",
        description:
          "What the signed-in user has answered in a program, from the participation " <>
            "markers; it holds no segment and no feedback answer, and the format ids are " <>
            "the user's own votes."
      }
    ),
    struct?: false,
    derive?: false
  )
end
