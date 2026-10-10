defmodule Espalier.Repo.Migrations.CreateItemObjectives do
  use Ecto.Migration

  def change do
    create table(:item_objectives, primary_key: false) do
      add :item_id, references(:items, on_delete: :delete_all, type: :binary_id), null: false

      add :learning_objective_id,
          references(:learning_objectives, on_delete: :delete_all, type: :binary_id), null: false
    end

    create unique_index(:item_objectives, [:item_id, :learning_objective_id])
    create index(:item_objectives, [:learning_objective_id])
  end
end
