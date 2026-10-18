defmodule Espalier.Catalog.Pack.Schema.SlotBuilderConfig do
  @moduledoc """
  The `config` of an item with `kind: slot_builder`: the slots of a prompt that
  the learner builds.

  The mapping sits below the key `config` of the item in `items.yaml`
  (`Espalier.Catalog.Pack.Schema.Item`). The learner chooses one option in
  each slot. The item is correct when every slot holds a chosen option with
  `correct: true`. The item takes no `options`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `slots` | list of mappings | yes | Entries of `Espalier.Catalog.Pack.Schema.Slot`. At least one, with unique `key` values. |

  Each slot has `key`, `label` and at least two `options`, of which at least
  one has `correct: true`. The order of the slots in the file is the order of
  presentation.

  ## Example

  The mapping that stands below `config`, with two slots:

  ```yaml
  slots:
    - key: task
      label: Task
      options:
        - key: task-clear
          label: Write a notice that the team meeting moves from Tuesday to Thursday.
          correct: true
          feedback: This names what the assistant should write.
        - key: task-vague
          label: Write something about the meeting.
          correct: false
          feedback: This leaves the task open.
    - key: format
      label: Format
      options:
        - key: format-short
          label: Three sentences in plain language.
          correct: true
          feedback: This sets the length and the style.
        - key: format-open
          label: Any length and any style.
          correct: false
          feedback: An open format gives a text that you shorten afterwards.
  ```

  The item around the mapping carries `key`, `kind: slot_builder`, `stem` and
  the other fields of `Espalier.Catalog.Pack.Schema.Item`, and no `options`.

  ## Checks

    * `` unknown field `x` `` and `` missing field `slots` ``;
    * `` `slots` must be a list `` and `` entries of `slots` must be maps ``;
    * `` `slots` needs at least one slot ``;
    * `` duplicate key `x` in `slots` ``;
    * the errors of the slots (`Espalier.Catalog.Pack.Schema.Slot`) with the
      path below `slots`.

  The item reports `` a `slot_builder` item needs `config` `` when `config` is
  absent.

  ## See also

  [Content packs](content-packs.md), section "Item kinds". The modules
  `Espalier.Catalog.Pack.Schema.Item`, `Espalier.Catalog.Pack.Schema.Slot` and
  `Espalier.Catalog.Pack.Schema.Option`.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.{Cast, Slot}

  @primary_key false
  embedded_schema do
    embeds_many :slots, Slot
  end

  @typedoc "The config of a `slot_builder` item."
  @type t :: %__MODULE__{}

  @doc """
  Casts the `config` of a `slot_builder` item.

  Returns an `Ecto.Changeset`. `Espalier.Catalog.Pack.Schema.Item` calls it
  for the kind `slot_builder`.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> Cast.cast(attrs, required: [:slots])
    |> Cast.validate_length(:slots, 1, "`slots` needs at least one slot")
    |> Cast.validate_unique_by(:slots, :key)
  end
end
