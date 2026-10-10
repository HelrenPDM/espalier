defmodule Espalier.Repo.Migrations.CreateItemStats do
  use Ecto.Migration

  # An anonymous counter per item, month and org unit: no user key, a random
  # primary key and no time beyond period, the first day of the month
  # (README section 10, task 0009, step 6). All rows without an org unit
  # share one counter per item and month (NULLS NOT DISTINCT, PostgreSQL 15).
  def change do
    create table(:item_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :period, :date, null: false
      add :org_unit, :string
      add :attempts, :integer, null: false, default: 0
      add :correct, :integer, null: false, default: 0
      add :item_id, references(:items, on_delete: :nothing, type: :binary_id), null: false
    end

    create unique_index(:item_stats, [:item_id, :period, :org_unit], nulls_distinct: false)
  end
end
