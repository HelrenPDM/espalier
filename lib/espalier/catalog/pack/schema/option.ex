defmodule Espalier.Catalog.Pack.Schema.Option do
  @moduledoc """
  An answer option of a choice item, a poll or a slot of a `slot_builder`
  item: `key`, `label`, `correct` and `feedback`, all required.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
    field :correct, :boolean
    field :feedback, :string
  end

  @type t :: %__MODULE__{}

  @doc "Casts an answer option."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(option, attrs) do
    option
    |> Cast.cast(attrs, required: [:key, :label, :correct, :feedback])
    |> Cast.validate_key(:key)
  end
end
