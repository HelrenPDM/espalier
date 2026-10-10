defmodule Espalier.Repo.Migrations.CreateAssessments do
  use Ecto.Migration

  def change do
    create table(:assessments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :title, :string
      add :kind, :string
      add :counts_for_credential, :boolean, default: false, null: false
      add :max_wrong, :integer
      add :core_required, :boolean, default: false, null: false
      add :archived_at, :utc_datetime
      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false
      add :module_id, references(:modules, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assessments, [:program_id, :key])
    create index(:assessments, [:module_id])
  end
end
