defmodule Espalier.Catalog.Pack.Schema.ChecklistDrillConfig do
  @moduledoc """
  The `config` of a `checklist_drill` item: at least one check in `checks`
  (`Espalier.Catalog.Pack.Schema.ChecklistCheck`), with unique keys, of which
  at least one is required. The answer of the drill always includes
  initials (task 0009, step 10).
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.Schema.{Cast, ChecklistCheck}

  @primary_key false
  embedded_schema do
    embeds_many :checks, ChecklistCheck
  end

  @type t :: %__MODULE__{}

  @doc "Casts the `config` of a `checklist_drill` item."
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
