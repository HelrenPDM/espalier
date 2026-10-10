defmodule Espalier.Catalog.Pack.Schema.SlotBuilderConfig do
  @moduledoc """
  The `config` of a `slot_builder` item: at least one slot in `slots`
  (`Espalier.Catalog.Pack.Schema.Slot`), with unique keys.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.{Cast, Slot}

  @primary_key false
  embedded_schema do
    embeds_many :slots, Slot
  end

  @type t :: %__MODULE__{}

  @doc "Casts the `config` of a `slot_builder` item."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> Cast.cast(attrs, required: [:slots])
    |> Cast.validate_length(:slots, 1, "`slots` needs at least one slot")
    |> Cast.validate_unique_by(:slots, :key)
  end
end
