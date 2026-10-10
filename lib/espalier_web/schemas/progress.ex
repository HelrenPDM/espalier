defmodule EspalierWeb.Schemas.Progress do
  @moduledoc "The answer of `GET /api/me/progress`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, ObjectiveProgress}

  @enrollment %{
    Fields.object(%{
      id: Fields.uuid(),
      path: Fields.enum(~w(short full)),
      path_chosen_manually: Fields.boolean()
    })
    | nullable: true,
      description: "The enrollment, or `null` without one."
  }

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          enrollment: @enrollment,
          completed_module_ids: Fields.uuids(),
          exams:
            Fields.array(
              Fields.object(%{
                assessment_id: Fields.uuid(),
                outcome: Fields.enum(~w(passed failed_core failed_errors))
              }),
              "Per exam with an attempt: `passed` when any attempt passed, otherwise the " <>
                "outcome of the latest attempt."
            ),
          answered_item_ids:
            Fields.uuids("The answered items; present only with `TRACKING_DETAIL=standard`."),
          objectives:
            Fields.array(
              ObjectiveProgress,
              "Every objective of the program, ordered by module number and position."
            )
        },
        optional: [:answered_item_ids]
      ),
      %{title: "Progress", description: "The progress of the signed-in user in a program."}
    ),
    struct?: false,
    derive?: false
  )
end
