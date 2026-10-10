defmodule Espalier.Repo.Migrations.CreateModuleCompletions do
  use Ecto.Migration

  def change do
    create table(:module_completions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :completed_at, :utc_datetime, null: false

      add :enrollment_id, references(:enrollments, on_delete: :delete_all, type: :binary_id),
        null: false

      add :module_id, references(:modules, on_delete: :nothing, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:module_completions, [:user_id])

    create unique_index(:module_completions, [:enrollment_id, :module_id])
    create index(:module_completions, [:module_id])
  end
end
