defmodule Espalier.Repo.Migrations.CreateLearningObjectives do
  use Ecto.Migration

  def change do
    create table(:learning_objectives, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :statement, :text, null: false
      add :area, :string, null: false
      add :depth, :string, null: false
      add :phase, :string, null: false
      add :domain, :string
      add :position, :integer
      add :archived_at, :utc_datetime
      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false
      add :module_id, references(:modules, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:learning_objectives, [:program_id, :key])
    create index(:learning_objectives, [:module_id])
  end
end
