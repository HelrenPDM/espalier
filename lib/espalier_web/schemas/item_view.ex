defmodule EspalierWeb.Schemas.ItemView do
  @moduledoc """
  An item without its answer key (README section 7, domain rule 4): no
  `correct`, no `feedback`, no `expected` and no raw `config`. The lists of
  the other kinds are empty.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  @choice Fields.object(%{key: Fields.string(), label: Fields.string()})

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        key: Fields.string(),
        kind:
          Fields.enum(
            ~w(single_choice multiple_choice slot_builder classification checklist_drill poll)
          ),
        stem: Fields.string(),
        provenance: Fields.provenance(),
        lesson_id: %{Fields.uuid("The lesson of a practice item.") | nullable: true},
        objective_keys: Fields.strings("The sorted keys of the objectives the item serves."),
        options: Fields.array(@choice, "The options of a choice item or a poll."),
        slots:
          Fields.array(
            Fields.object(%{
              key: Fields.string(),
              label: Fields.string(),
              options: Fields.array(@choice)
            }),
            "The slots of a slot builder with their options."
          ),
        cases:
          Fields.array(
            Fields.object(%{key: Fields.string(), text: Fields.string()}),
            "The cases of a classification."
          ),
        categories: Fields.array(@choice, "The categories of a classification."),
        checks:
          Fields.array(
            Fields.object(%{
              key: Fields.string(),
              label: Fields.string(),
              required: Fields.boolean()
            }),
            "The checks of a checklist drill."
          )
      }),
      %{title: "ItemView", description: "A practice or exam item without its answer key."}
    ),
    struct?: false,
    derive?: false
  )
end
