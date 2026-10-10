defmodule Espalier.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :kind, :string
      add :stem, :text
      add :core, :boolean, default: false, null: false
      add :phase, :string
      add :provenance, :string
      add :config, :map
      add :position, :integer
      add :archived_at, :utc_datetime
      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false
      add :module_id, references(:modules, on_delete: :nothing, type: :binary_id), null: false
      add :lesson_id, references(:lessons, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:items, [:program_id, :key])
    create index(:items, [:module_id])
    create index(:items, [:lesson_id])
  end
end
