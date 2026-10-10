defmodule Espalier.Catalog.Option do
  @moduledoc "An answer option of a choice item or a poll, with its feedback."
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Item

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "options" do
    field :key, :string
    field :label, :string
    field :correct, :boolean, default: false
    field :feedback, :string
    field :position, :integer

    belongs_to :item, Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:key, :label, :correct, :feedback, :position])
    |> validate_required([:key, :label, :correct, :position])
  end
end
