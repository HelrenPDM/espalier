defmodule Espalier.Catalog.Pack.Schema.Segment do
  @moduledoc """
  An entry of `segments.yaml`: `key`, `label`, `description` and
  `default_path` (`short` or `full`).
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
    field :description, :string
    field :default_path, Ecto.Enum, values: [:short, :full]
  end

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `segments.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(segment, attrs) do
    segment
    |> Cast.cast(attrs, required: [:key, :label, :description, :default_path])
    |> Cast.validate_key(:key)
    |> Cast.validate_max_length(:label)
  end
end
