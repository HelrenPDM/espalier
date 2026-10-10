defmodule Espalier.Repo.Migrations.CreateCitations do
  use Ecto.Migration

  def change do
    create table(:citations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :locator, :string
      add :source_id, references(:sources, on_delete: :nothing, type: :binary_id), null: false
      add :block_id, references(:blocks, on_delete: :delete_all, type: :binary_id)
      add :rule_id, references(:rules, on_delete: :delete_all, type: :binary_id)
      add :item_id, references(:items, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:citations, [:source_id])
    create index(:citations, [:block_id])
    create index(:citations, [:rule_id])
    create index(:citations, [:item_id])

    # A citation belongs to exactly one block, rule or item.
    create constraint(:citations, :citations_one_parent,
             check: "num_nonnulls(block_id, rule_id, item_id) = 1"
           )
  end
end
