defmodule Espalier.Repo.Migrations.CreateSegments do
  use Ecto.Migration

  def change do
    create table(:segments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :label, :string
      add :description, :text
      add :default_path, :string
      add :position, :integer
      add :archived_at, :utc_datetime
      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:segments, [:program_id, :key])
  end
end
