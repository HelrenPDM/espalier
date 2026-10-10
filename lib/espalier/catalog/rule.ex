defmodule Espalier.Catalog.Rule do
  @moduledoc "A numbered rule of a module with its statement and action."
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{Citation, Item}
  alias Espalier.Catalog.Module, as: CatalogModule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "rules" do
    field :number, :integer
    field :statement, :string
    field :action, :string
    field :archived_at, :utc_datetime

    belongs_to :module, CatalogModule
    has_many :citations, Citation
    many_to_many :items, Item, join_through: "item_rules"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:number, :statement, :action])
    |> validate_required([:number, :statement, :action])
  end
end
