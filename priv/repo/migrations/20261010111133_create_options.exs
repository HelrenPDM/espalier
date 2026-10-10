defmodule Espalier.Repo.Migrations.CreateOptions do
  use Ecto.Migration

  def change do
    create table(:options, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :label, :text
      add :correct, :boolean, default: false, null: false
      add :feedback, :text
      add :position, :integer
      add :item_id, references(:items, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:options, [:item_id])
  end
end
