defmodule Espalier.Repo.Migrations.CreateLessons do
  use Ecto.Migration

  def change do
    create table(:lessons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :position, :integer
      add :title, :string
      add :archived_at, :utc_datetime
      add :module_id, references(:modules, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lessons, [:module_id, :key])
  end
end
