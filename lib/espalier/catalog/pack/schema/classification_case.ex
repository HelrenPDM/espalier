defmodule Espalier.Catalog.Pack.Schema.ClassificationCase do
  @moduledoc """
  An element of `cases`: a case that the learner sorts into a category of a
  `classification` item.

  Cases sit in the list `cases` of the `config` of a `classification` item
  (`Espalier.Catalog.Pack.Schema.ClassificationConfig`). The `expected`
  mapping of the config names the category of each case by the `key` of the
  case. The `feedback` of a case belongs to the case, whichever category the
  learner chose.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | Matches `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique among the cases of the item. |
  | `text` | string | yes | The case that the learner sorts. A non-empty string. |
  | `feedback` | string | yes | The explanation of the case, returned with the result of an answer. A non-empty string. |

  ## Example

  ```yaml
  - key: case-notice
    text: A notice that a meeting moves to another room.
    feedback: The notice holds no judgement about a person, and you check its facts.
  - key: case-assessment
    text: The assessment of a trainee.
    feedback: An assessment is a judgement about a person and stays with you.
  ```

  ## Checks

    * `` unknown field `x` `` and `` missing field `feedback` `` (also for `key`
      and `text`);
    * `` `text` must not be empty `` for a blank string;
    * `` `key` value `X` does not match the key format `^[a-z0-9][a-z0-9-]*$` ``;
    * `` duplicate key `x` in `cases` `` and `` `cases` needs at least one case ``
      from the config;
    * `` `expected` maps no category for the case `x` `` when `expected` has no
      entry for the case.

  ## See also

  [Content packs](content-packs.md), section "Item kinds". The module
  `Espalier.Catalog.Pack.Schema.ClassificationConfig` holds the cases.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :text, :string
    field :feedback, :string
  end

  @typedoc "A case, as cast from an element of `cases`."
  @type t :: %__MODULE__{}

  @doc """
  Casts an element of `cases`.

  Returns an `Ecto.Changeset`.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(case_entry, attrs) do
    case_entry
    |> Cast.cast(attrs, required: [:key, :text, :feedback])
    |> Cast.validate_key(:key)
  end
end
