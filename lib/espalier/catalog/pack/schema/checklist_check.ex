defmodule Espalier.Catalog.Pack.Schema.ChecklistCheck do
  @moduledoc "A check of a `checklist_drill` item: `key`, `label` and `required`."
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
    field :required, :boolean
  end

  @type t :: %__MODULE__{}

  @doc "Casts a check of a `checklist_drill` item."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(check, attrs) do
    check
    |> Cast.cast(attrs, required: [:key, :label, :required])
    |> Cast.validate_key(:key)
  end
end
