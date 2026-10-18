defmodule Espalier.Catalog.Pack.Schema.Option do
  @moduledoc """
  An element of `options`: an answer option of a choice item or a poll, or an
  option of a slot.

  Options sit in the list `options` of an item with the kind `single_choice`,
  `multiple_choice` or `poll` (`Espalier.Catalog.Pack.Schema.Item`), and in the
  list `options` of a slot of a `slot_builder` item
  (`Espalier.Catalog.Pack.Schema.Slot`). No file holds options on its own. The
  order of the list is the order in the file. The learner picks options by
  `key`, and the catalog views carry neither `correct` nor `feedback`;
  `Espalier.Learning.Evaluator` reads them when it evaluates an answer.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | Matches `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique among the options of the same item or the same slot. |
  | `label` | string | yes | The text of the option. A non-empty string. |
  | `correct` | boolean | yes | `true` or `false`. The item or the slot counts the correct options: one in a `single_choice` item, at least one in a `multiple_choice` item and in a slot, none in a `poll`. |
  | `feedback` | string | yes | The text that the evaluation returns for the option: for a choice item for every option, chosen or not; for a slot for the chosen option. A non-empty string. A poll option needs it because the schema requires it, but the evaluation of a poll returns no option feedback. |

  The count of options and of correct options belongs to the item or the slot.
  The same holds for the uniqueness of the keys, which the item and the slot
  check.

  ## Example

  Two options of a `single_choice` item, as a list below `options`:

  ```yaml
  - key: likely-words
    label: It continues the text with words that are likely to follow.
    correct: true
    feedback: Right. The assistant continues text from learned probabilities.
  - key: checked-facts
    label: It looks up the answer in a list of checked facts.
    correct: false
    feedback: The assistant holds no list of checked facts.
  ```

  ## Checks

    * `` unknown field `x` `` for a key that is no field of an option;
    * `` missing field `feedback` `` (also for `key`, `label` and `correct`);
    * `` `correct` must be `true` or `false` ``;
    * `` `label` must not be empty `` for a blank string;
    * `` `key` value `X` does not match the key format `^[a-z0-9][a-z0-9-]*$` ``;
    * `` `key` must have at most 255 characters ``;
    * `` duplicate key `x` in `options` `` from the item or the slot that holds
      the option;
    * the counts of options and of correct options, which the item
      (`Espalier.Catalog.Pack.Schema.Item`) and the slot
      (`Espalier.Catalog.Pack.Schema.Slot`) report.

  ## See also

  [Content packs](content-packs.md), section "Item kinds". The modules
  `Espalier.Catalog.Pack.Schema.Item` and `Espalier.Catalog.Pack.Schema.Slot`
  hold the options.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
    field :correct, :boolean
    field :feedback, :string
  end

  @typedoc "An answer option, as cast from an element of `options`."
  @type t :: %__MODULE__{}

  @doc """
  Casts an element of `options`.

  Returns an `Ecto.Changeset`.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(option, attrs) do
    option
    |> Cast.cast(attrs, required: [:key, :label, :correct, :feedback])
    |> Cast.validate_key(:key)
  end
end
