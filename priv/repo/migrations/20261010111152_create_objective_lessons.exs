defmodule Espalier.Repo.Migrations.CreateObjectiveLessons do
  use Ecto.Migration

  def change do
    create table(:objective_lessons, primary_key: false) do
      add :learning_objective_id,
          references(:learning_objectives, on_delete: :delete_all, type: :binary_id), null: false

      add :lesson_id, references(:lessons, on_delete: :delete_all, type: :binary_id), null: false
    end

    create unique_index(:objective_lessons, [:learning_objective_id, :lesson_id])
    create index(:objective_lessons, [:lesson_id])
  end
end
