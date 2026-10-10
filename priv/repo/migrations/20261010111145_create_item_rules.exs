defmodule Espalier.Repo.Migrations.CreateItemRules do
  use Ecto.Migration

  def change do
    create table(:item_rules, primary_key: false) do
      add :item_id, references(:items, on_delete: :delete_all, type: :binary_id), null: false
      add :rule_id, references(:rules, on_delete: :delete_all, type: :binary_id), null: false
    end

    create unique_index(:item_rules, [:item_id, :rule_id])
    create index(:item_rules, [:rule_id])
  end
end
