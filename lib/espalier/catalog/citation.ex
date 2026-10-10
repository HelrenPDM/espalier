defmodule Espalier.Catalog.Citation do
  @moduledoc """
  A citation of a source by a block, a rule or an item. The check constraint
  `citations_one_parent` requires exactly one of the three parents.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{Block, Item, Rule, Source}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "citations" do
    field :locator, :string

    belongs_to :source, Source
    belongs_to :block, Block
    belongs_to :rule, Rule
    belongs_to :item, Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(citation, attrs) do
    citation
    |> cast(attrs, [:locator])
    |> check_constraint(:block_id, name: :citations_one_parent)
  end
end
