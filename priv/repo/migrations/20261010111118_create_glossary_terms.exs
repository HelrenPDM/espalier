defmodule Espalier.Repo.Migrations.CreateGlossaryTerms do
  use Ecto.Migration

  def change do
    create table(:glossary_terms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :label, :string
      add :short_text, :text
      add :archived_at, :utc_datetime
      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:glossary_terms, [:program_id, :slug])
  end
end
