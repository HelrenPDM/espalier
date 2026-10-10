defmodule EspalierWeb.Schemas.ItemResult do
  @moduledoc """
  The evaluation of an answer (README section 7, domain rules 3 and 4). It
  reaches the learner only in the answer to the learner's own submission.

  `option_feedback` holds, for a choice item, every option with `selected`,
  `correct` (the option is a correct option) and `feedback`; for a slot
  builder every slot with the chosen option in `choice`, `correct` and the
  option's `feedback`; for a classification every case with `choice`,
  `expected`, `correct` and `feedback`; for a checklist drill every check
  with `selected`, `required` and `correct`; for a poll nothing.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  @entry Fields.object(
           %{
             key: Fields.string("The key of the option, slot, case or check."),
             correct: Fields.boolean(),
             selected: Fields.boolean(),
             choice: Fields.nullable_string(),
             expected: Fields.nullable_string(),
             required: Fields.boolean(),
             feedback: Fields.nullable_string()
           },
           optional: [:selected, :choice, :expected, :required, :feedback]
         )

  @rule Fields.object(%{
          id: Fields.uuid(),
          number: Fields.integer(),
          statement: Fields.string(),
          action: Fields.string()
        })

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        item_id: Fields.uuid(),
        correct: %{Fields.boolean("`null` for a poll.") | nullable: true},
        option_feedback: Fields.array(@entry),
        rules: Fields.array(@rule, "The rules that the item refers to."),
        reveals:
          Fields.uuids(
            "Lessons whose explanations expand after a wrong answer on the short path; empty " <>
              "unless the answer is wrong."
          )
      }),
      %{title: "ItemResult", description: "The evaluation of an answer."}
    ),
    struct?: false,
    derive?: false
  )
end
