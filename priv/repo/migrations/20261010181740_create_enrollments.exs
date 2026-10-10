defmodule Espalier.Repo.Migrations.CreateEnrollments do
  use Ecto.Migration

  def change do
    create table(:enrollments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :path, :string, null: false
      add :path_chosen_manually, :boolean, default: false, null: false
      add :started_at, :utc_datetime, null: false

      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:enrollments, [:user_id, :program_id])

    create index(:enrollments, [:program_id])
  end
end
