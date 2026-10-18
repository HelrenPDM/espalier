defmodule Espalier.Catalog.Pack.Schema.ClassificationConfig do
  @moduledoc """
  The `config` of an item with `kind: classification`: the categories, the
  cases that the learner sorts into them, and the expected sorting.

  The mapping sits below the key `config` of the item in `items.yaml`
  (`Espalier.Catalog.Pack.Schema.Item`). The learner assigns each case to one
  category. The item is correct when every case sits in the category that
  `expected` names for it. The item takes no `options`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `categories` | list of mappings | yes | Entries of `Espalier.Catalog.Pack.Schema.ClassificationCategory` (`key`, `label`). At least two, with unique `key` values. |
  | `cases` | list of mappings | yes | Entries of `Espalier.Catalog.Pack.Schema.ClassificationCase` (`key`, `text`, `feedback`). At least one, with unique `key` values. |
  | `expected` | mapping | yes | Maps every case key to a category key. Each key is the `key` of a case, each value is the `key` of a category, and every case has an entry. |

  The order of categories and cases in the file is the order of presentation.
  The keys of categories and the keys of cases are separate lists, so a
  category and a case may use the same key. The check of `expected` runs when
  the rest of the `config` has no error.

  ## Example

  The mapping that stands below `config`:

  ```yaml
  categories:
    - key: assistant-may-draft
      label: The assistant may draft it
    - key: keep-it
      label: I keep it
  cases:
    - key: case-notice
      text: A notice that a meeting moves to another room.
      feedback: The notice holds no judgement about a person, and you check its facts.
    - key: case-assessment
      text: The assessment of a trainee.
      feedback: An assessment is a judgement about a person and stays with you.
  expected:
    case-notice: assistant-may-draft
    case-assessment: keep-it
  ```

  The item around the mapping carries `key`, `kind: classification`, `stem`
  and the other fields of `Espalier.Catalog.Pack.Schema.Item`, and no
  `options`.

  ## Checks

    * `` unknown field `x` `` and `` missing field `expected` `` (also for
      `categories` and `cases`);
    * `` `expected` must be a map `` and `` `categories` must be a list ``;
    * `` `categories` needs at least two categories ``;
    * `` `cases` needs at least one case ``;
    * `` duplicate key `x` in `categories` `` and
      `` duplicate key `x` in `cases` ``;
    * `` `expected` maps no category for the case `x` `` for a case without an
      entry;
    * `` `expected` names the unknown case `x` `` for an entry whose key is no
      case;
    * `` `expected` maps the case `x` to an unknown category `` for a value that
      is no category key.

  The item reports `` a `classification` item needs `config` `` when `config` is
  absent.

  ## See also

  [Content packs](content-packs.md), section "Item kinds". The modules
  `Espalier.Catalog.Pack.Schema.Item`,
  `Espalier.Catalog.Pack.Schema.ClassificationCategory` and
  `Espalier.Catalog.Pack.Schema.ClassificationCase`.
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_change: 2, get_field: 2]

  alias Espalier.Catalog.Pack.Schema.{Cast, ClassificationCase, ClassificationCategory}

  @primary_key false
  embedded_schema do
    embeds_many :categories, ClassificationCategory
    embeds_many :cases, ClassificationCase
    field :expected, :map
  end

  @typedoc "The config of a `classification` item."
  @type t :: %__MODULE__{}

  @doc """
  Casts the `config` of a `classification` item and checks `expected` against
  its categories and cases.

  Returns an `Ecto.Changeset`. `Espalier.Catalog.Pack.Schema.Item` calls it
  for the kind `classification`.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> Cast.cast(attrs, required: [:categories, :cases, :expected])
    |> Cast.validate_length(:categories, 2, "`categories` needs at least two categories")
    |> Cast.validate_length(:cases, 1, "`cases` needs at least one case")
    |> Cast.validate_unique_by(:categories, :key)
    |> Cast.validate_unique_by(:cases, :key)
    |> validate_expected()
  end

  defp validate_expected(changeset) do
    expected = get_change(changeset, :expected)

    if is_map(expected) and changeset.valid?,
      do: check_expected(changeset, expected),
      else: changeset
  end

  defp check_expected(changeset, expected) do
    categories = changeset |> get_field(:categories) |> MapSet.new(& &1.key)
    cases = changeset |> get_field(:cases) |> Enum.map(& &1.key)

    unmapped =
      cases
      |> Enum.reject(&Map.has_key?(expected, &1))
      |> Enum.map(&{[], "`expected` maps no category for the case `#{&1}`"})

    named =
      expected
      |> Enum.sort()
      |> Enum.flat_map(&expected_errors(&1, cases, categories))

    Enum.reduce(unmapped ++ named, changeset, fn {suffix, message}, changeset ->
      Cast.add(changeset, :expected, suffix, message)
    end)
  end

  defp expected_errors({case_key, category}, cases, categories) do
    cond do
      case_key not in cases -> [{[case_key], "`expected` names the unknown case `#{case_key}`"}]
      is_binary(category) and MapSet.member?(categories, category) -> []
      true -> [{[case_key], "`expected` maps the case `#{case_key}` to an unknown category"}]
    end
  end
end
