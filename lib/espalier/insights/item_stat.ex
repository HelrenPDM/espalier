defmodule Espalier.Insights.ItemStat do
  @moduledoc """
  An anonymous counter of practice answers per item, month and org unit
  (README section 10). The row carries no user key, a random primary key and
  no time beyond `period`, the first day of the month. `org_unit` is filled
  only with `INSIGHTS_ORG_UNIT=true`, and all rows without an org unit share
  one counter per item and month.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Item

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "item_stats" do
    field :period, :date
    field :org_unit, :string
    field :attempts, :integer, default: 0
    field :correct, :integer, default: 0
    belongs_to :item, Item
  end

  @doc false
  def changeset(item_stat, attrs) do
    item_stat
    |> cast(attrs, [:item_id, :period, :org_unit, :attempts, :correct])
    |> validate_required([:item_id, :period, :attempts, :correct])
    |> unique_constraint([:item_id, :period, :org_unit])
  end
end
