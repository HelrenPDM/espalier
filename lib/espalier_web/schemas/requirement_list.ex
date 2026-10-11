defmodule EspalierWeb.Schemas.RequirementList do
  @moduledoc "The answer of `GET /api/me/requirements`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  @requirement Fields.object(%{
                 kind:
                   Fields.enum(
                     ~w(module_completed assessment_passed policy_acknowledged attendance qualification_held)
                   ),
                 target_key:
                   Fields.string(
                     "The module number, the exam key, the policy key, the format key or " <>
                       "the qualification code."
                   ),
                 station_position: %{
                   Fields.integer(
                     "The position of the station that satisfies the requirement, or `null` " <>
                       "when no station of the program does."
                   )
                   | nullable: true
                 }
               })

  @credential %{
    Fields.object(%{
      id: Fields.uuid(),
      status: Fields.enum(~w(active refresh_due expired revoked)),
      issued_at: Fields.datetime(),
      valid_until: %{Fields.date() | nullable: true}
    })
    | nullable: true,
      description: "The credential of the signed-in user, or `null` without one."
  }

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        qualifications:
          Fields.array(
            Fields.object(%{
              code: Fields.string(),
              title: Fields.string(),
              add_on: Fields.boolean(),
              unlocks: Fields.strings("The tasks that a credential unlocks."),
              credential: @credential,
              met: Fields.array(@requirement, "The requirements that hold."),
              open: Fields.array(@requirement, "The requirements that do not hold yet.")
            }),
            "The live qualifications of the program."
          )
      }),
      %{
        title: "RequirementList",
        description: "The met and open requirements of the signed-in user per qualification."
      }
    ),
    struct?: false,
    derive?: false
  )
end
