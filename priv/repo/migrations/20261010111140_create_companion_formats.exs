defmodule Espalier.Repo.Migrations.CreateCompanionFormats do
  use Ecto.Migration

  def change do
    create table(:companion_formats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :title, :string
      add :description, :text
      add :phases, {:array, :string}
      add :attendance_counts, :boolean, default: false, null: false
      add :position, :integer
      add :archived_at, :utc_datetime
      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:companion_formats, [:program_id, :key])
  end
end
