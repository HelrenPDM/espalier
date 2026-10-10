defmodule Espalier.Repo.Migrations.CreateSources do
  use Ecto.Migration

  def change do
    create table(:sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :title, :string
      add :publisher, :string
      add :url, :string
      add :edition_date, :date
      add :retrieved_on, :date
      add :kind, :string
      add :archived_at, :utc_datetime
      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sources, [:program_id, :key])
  end
end
