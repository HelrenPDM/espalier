defmodule Espalier.Catalog.Pack.Schema.ClassificationCase do
  @moduledoc "A case of a `classification` item: `key`, `text` and `feedback`."
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :text, :string
    field :feedback, :string
  end

  @type t :: %__MODULE__{}

  @doc "Casts a case of a `classification` item."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(case_entry, attrs) do
    case_entry
    |> Cast.cast(attrs, required: [:key, :text, :feedback])
    |> Cast.validate_key(:key)
  end
end
