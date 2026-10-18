defmodule Espalier.Catalog.Pack.Schema.ChecklistCheck do
  @moduledoc """
  An element of `checks`: one check of a `checklist_drill` item.

  Checks sit in the list `checks` of the `config` of a `checklist_drill` item
  (`Espalier.Catalog.Pack.Schema.ChecklistDrillConfig`). The learner sets the
  checks that apply. A check with `required: true` must be set for the drill
  to count as correct.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | Matches `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique among the checks of the item. |
  | `label` | string | yes | The text of the check. A non-empty string. |
  | `required` | boolean | yes | `true` or `false`. At least one check of the item has `required: true`. |

  ## Example

  ```yaml
  - key: facts-checked
    label: Every name, number and date in the draft is checked against a source.
    required: true
  - key: second-reader
    label: A colleague has read the draft.
    required: false
  ```

  ## Checks

    * `` unknown field `x` `` and `` missing field `required` `` (also for `key`
      and `label`);
    * `` `required` must be `true` or `false` ``;
    * `` `label` must not be empty `` for a blank string;
    * `` `key` value `X` does not match the key format `^[a-z0-9][a-z0-9-]*$` ``;
    * `` duplicate key `x` in `checks` `` and
      `` a `checklist_drill` item needs at least one required check `` from the
      config.

  ## See also

  [Content packs](content-packs.md), section "Item kinds". The module
  `Espalier.Catalog.Pack.Schema.ChecklistDrillConfig` holds the checks.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
    field :required, :boolean
  end

  @typedoc "A check, as cast from an element of `checks`."
  @type t :: %__MODULE__{}

  @doc """
  Casts an element of `checks`.

  Returns an `Ecto.Changeset`.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(check, attrs) do
    check
    |> Cast.cast(attrs, required: [:key, :label, :required])
    |> Cast.validate_key(:key)
  end
end
