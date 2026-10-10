defmodule Espalier.Catalog.Pack.Schema.ClassificationConfig do
  @moduledoc """
  The `config` of a `classification` item: at least two `categories`
  (`key`, `label`), at least one case in `cases` (`key`, `text`, `feedback`),
  and `expected`, which maps every case key to a category key and names no
  other case.
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

  @type t :: %__MODULE__{}

  @doc "Casts the `config` of a `classification` item."
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
