defmodule Espalier.Repo.Migrations.CreateFeedbackResponses do
  use Ecto.Migration

  # The anonymous answers of the feedback station: no user key, a random
  # primary key and only a date with day precision (README section 10, task
  # 0014).
  def change do
    create table(:feedback_responses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :answers, :map, null: false
      add :recorded_on, :date, null: false

      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false
    end

    create index(:feedback_responses, [:program_id])
  end
end
