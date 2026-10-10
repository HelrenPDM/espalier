defmodule Espalier.Catalog.Pack.Schema.ClassificationCategory do
  @moduledoc "A category of a `classification` item: `key` and `label`."
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
  end

  @type t :: %__MODULE__{}

  @doc "Casts a category of a `classification` item."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(category, attrs) do
    category
    |> Cast.cast(attrs, required: [:key, :label])
    |> Cast.validate_key(:key)
  end
end
