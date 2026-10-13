defmodule Espalier.Repo.Migrations.CreateExports do
  use Ecto.Migration

  def change do
    create table(:exports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scorm_version, :string, null: false
      add :status, :string, null: false
      add :file_name, :string
      add :error, :text

      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false

      add :module_id, references(:modules, on_delete: :nothing, type: :binary_id), null: false
      add :requested_by_id, references(:users, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:exports, [:program_id])
    create index(:exports, [:module_id])
    create index(:exports, [:requested_by_id])
    create index(:exports, [:inserted_at])
  end
end
