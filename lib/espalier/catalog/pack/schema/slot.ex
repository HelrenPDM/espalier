defmodule Espalier.Catalog.Pack.Schema.Slot do
  @moduledoc """
  An element of `slots`: one part of the answer in a `slot_builder` item, with
  the options for that part.

  Slots sit in the list `slots` of the `config` of a `slot_builder` item
  (`Espalier.Catalog.Pack.Schema.SlotBuilderConfig`). The learner chooses one
  option for each slot, and the answer to the item is correct when every
  slot holds a chosen option with `correct: true`. A slot may hold several correct options.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | Matches `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique among the slots of the item. |
  | `label` | string | yes | The name of the slot, such as "Task" or "Format". A non-empty string. |
  | `options` | list of mappings | yes | Entries of `Espalier.Catalog.Pack.Schema.Option`. At least two, at least one with `correct: true`, and unique `key` values within the slot. |

  The keys of the options are unique within the slot.

  ## Example

  One slot with a correct and a wrong option:

  ```yaml
  key: task
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
  ```

  ## Checks

    * `` unknown field `x` `` and `` missing field `options` `` (also for `key`
      and `label`);
    * `` `options` must be a list `` and `` entries of `options` must be maps ``;
    * `` a slot needs at least two options ``;
    * `` a slot needs at least one correct option ``;
    * `` duplicate key `x` in `options` ``;
    * `` duplicate key `x` in `slots` `` from the config, for two slots with the
      same key;
    * the errors of the options, with the path below `options`
      (`Espalier.Catalog.Pack.Schema.Option`).

  ## See also

  [Content packs](content-packs.md), section "Item kinds". The modules
  `Espalier.Catalog.Pack.Schema.SlotBuilderConfig` and
  `Espalier.Catalog.Pack.Schema.Item` hold the slot.
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.Schema.{Cast, Option}

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
    embeds_many :options, Option
  end

  @typedoc "A slot, as cast from an element of `slots`."
  @type t :: %__MODULE__{}

  @doc """
  Casts an element of `slots` and checks the count of its options and of its
  correct options.

  Returns an `Ecto.Changeset`.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(slot, attrs) do
    slot
    |> Cast.cast(attrs, required: [:key, :label, :options])
    |> Cast.validate_key(:key)
    |> Cast.validate_unique_by(:options, :key)
    |> validate_options()
  end

  defp validate_options(changeset) do
    options = changeset |> get_field(:options) |> List.wrap()
    present? = Map.has_key?(changeset.params || %{}, "options")

    cond do
      not present? or Cast.errored?(changeset, :options) ->
        changeset

      length(options) < 2 ->
        Cast.add(changeset, :options, "a slot needs at least two options")

      not Enum.any?(options, &(&1.correct == true)) ->
        Cast.add(changeset, :options, "a slot needs at least one correct option")

      true ->
        changeset
    end
  end
end
