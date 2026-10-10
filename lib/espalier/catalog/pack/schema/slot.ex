defmodule Espalier.Catalog.Pack.Schema.Slot do
  @moduledoc """
  A slot of a `slot_builder` item: `key`, `label` and at least two `options`
  (`Espalier.Catalog.Pack.Schema.Option`), at least one of them correct.
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.Schema.{Cast, Option}

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
    embeds_many :options, Option
  end

  @type t :: %__MODULE__{}

  @doc "Casts a slot of a `slot_builder` item."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(slot, attrs) do
    slot
    |> Cast.cast(attrs, required: [:key, :label, :options])
    |> Cast.validate_key(:key)
    |> Cast.validate_unique_by(:options, :key)
    |> validate_options()
  end

  defp validate_options(changeset) do
    options = changeset |> get_field(:options) |> List.wrap()
    present? = Map.has_key?(changeset.params || %{}, "options")

    cond do
      not present? or Cast.errored?(changeset, :options) ->
        changeset

      length(options) < 2 ->
        Cast.add(changeset, :options, "a slot needs at least two options")

      not Enum.any?(options, &(&1.correct == true)) ->
        Cast.add(changeset, :options, "a slot needs at least one correct option")

      true ->
        changeset
    end
  end
end
