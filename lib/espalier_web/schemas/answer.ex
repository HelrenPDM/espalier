defmodule EspalierWeb.Schemas.Answer do
  @moduledoc """
  An answer to an item. Each kind uses its members (README section 7, domain
  rule 4): `options` for `single_choice`, `multiple_choice` and `poll`,
  `slots` for `slot_builder`, `cases` for `classification`, and `checks`
  with `initials` for `checklist_drill`. The server checks that the answer
  uses the members of the item's kind and names keys of the item.

  An item holds at most 100 options, slots, cases or checks that a learner
  can answer; the pack format sets no lower bound.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  @entries 100

  OpenApiSpex.schema(
    %{
      title: "Answer",
      description: "An answer to an item, with the members of the item's kind.",
      type: :object,
      additionalProperties: false,
      properties: %{
        options: %Schema{
          type: :array,
          items: Fields.key_param("An option key."),
          maxItems: @entries,
          uniqueItems: true,
          description: "The chosen option keys."
        },
        slots: %Schema{
          type: :object,
          additionalProperties: Fields.key_param("The option key chosen for the slot."),
          maxProperties: @entries,
          description: "Slot key to the chosen option key."
        },
        cases: %Schema{
          type: :object,
          additionalProperties: Fields.key_param("The category key chosen for the case."),
          maxProperties: @entries,
          description: "Case key to the chosen category key."
        },
        checks: %Schema{
          type: :array,
          items: Fields.key_param("A check key."),
          maxItems: @entries,
          uniqueItems: true,
          description: "The keys of the checks that are set."
        },
        initials: %Schema{
          type: :string,
          maxLength: 16,
          description: "The initials that confirm a checklist drill; 2 to 5 characters count."
        }
      }
    },
    struct?: false,
    derive?: false
  )
end
