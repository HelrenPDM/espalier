defmodule Espalier.Repo.Migrations.CreateItemReveals do
  use Ecto.Migration

  def change do
    create table(:item_reveals, primary_key: false) do
      add :item_id, references(:items, on_delete: :delete_all, type: :binary_id), null: false
      add :lesson_id, references(:lessons, on_delete: :delete_all, type: :binary_id), null: false
    end

    create unique_index(:item_reveals, [:item_id, :lesson_id])
    create index(:item_reveals, [:lesson_id])
  end
end
