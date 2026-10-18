defmodule Espalier.Catalog.Pack.Schema.ChecklistDrillConfig do
  @moduledoc """
  The `config` of an item with `kind: checklist_drill`: the checks that the
  learner runs on a draft.

  The mapping sits below the key `config` of the item in `items.yaml`
  (`Espalier.Catalog.Pack.Schema.Item`). The learner sets the checks that
  apply and confirms them with initials. The item is correct when every check
  with `required: true` is set and the initials have 2 to 5 characters after
  trimming (`Espalier.Learning.Evaluator`). The answer to the drill always
  includes the initials. The item takes no `options`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `checks` | list of mappings | yes | Entries of `Espalier.Catalog.Pack.Schema.ChecklistCheck` (`key`, `label`, `required`) with unique `key` values. At least one of them has `required: true`. |

  The order of the checks in the file is the order of presentation. An entry
  with `required: false` is a check that the learner may leave unset.

  ## Example

  The mapping that stands below `config`:

  ```yaml
  checks:
    - key: facts-checked
      label: Every name, number and date in the draft is checked against a source.
      required: true
    - key: second-reader
      label: A colleague has read the draft.
      required: false
  ```

  The item around the mapping carries `key`, `kind: checklist_drill`, `stem`
  and the other fields of `Espalier.Catalog.Pack.Schema.Item`, and no
  `options`.

  ## Checks

    * `` unknown field `x` `` and `` missing field `checks` ``;
    * `` `checks` must be a list `` and `` entries of `checks` must be maps ``;
    * `` duplicate key `x` in `checks` ``;
    * `` a `checklist_drill` item needs at least one required check `` when no
      check has `required: true`, an empty list included;
    * the errors of the checks (`Espalier.Catalog.Pack.Schema.ChecklistCheck`)
      with the path below `checks`.

  The item reports `` a `checklist_drill` item needs `config` `` when `config`
  is absent.

  ## See also

  [Content packs](content-packs.md), section "Item kinds". The modules
  `Espalier.Catalog.Pack.Schema.Item` and
  `Espalier.Catalog.Pack.Schema.ChecklistCheck`.
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.Schema.{Cast, ChecklistCheck}

  @primary_key false
  embedded_schema do
    embeds_many :checks, ChecklistCheck
  end

  @typedoc "The config of a `checklist_drill` item."
  @type t :: %__MODULE__{}

  @doc """
  Casts the `config` of a `checklist_drill` item.

  Returns an `Ecto.Changeset`. `Espalier.Catalog.Pack.Schema.Item` calls it
  for the kind `checklist_drill`.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> Cast.cast(attrs, required: [:checks])
    |> Cast.validate_unique_by(:checks, :key)
    |> validate_required_check()
  end

  defp validate_required_check(changeset) do
    checks = changeset |> get_field(:checks) |> List.wrap()
    present? = Map.has_key?(changeset.params || %{}, "checks")

    if present? and not Cast.errored?(changeset, :checks) and
         not Enum.any?(checks, &(&1.required == true)),
       do:
         Cast.add(
           changeset,
           :checks,
           "a `checklist_drill` item needs at least one required check"
         ),
       else: changeset
  end
end
