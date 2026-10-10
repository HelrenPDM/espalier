defmodule Espalier.Repo.Migrations.CreateAssessmentAttempts do
  use Ecto.Migration

  def change do
    create table(:assessment_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :integer, null: false
      add :wrong_count, :integer, null: false
      add :core_failed, :boolean, default: false, null: false
      add :outcome, :string, null: false
      add :submitted_at, :utc_datetime, null: false

      add :enrollment_id, references(:enrollments, on_delete: :delete_all, type: :binary_id),
        null: false

      add :assessment_id, references(:assessments, on_delete: :nothing, type: :binary_id),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:assessment_attempts, [:user_id])

    create unique_index(:assessment_attempts, [:enrollment_id, :assessment_id, :number])
    create index(:assessment_attempts, [:assessment_id])
  end
end
