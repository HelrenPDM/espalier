defmodule Espalier.Repo.Migrations.CreatePrograms do
  use Ecto.Migration

  def change do
    create table(:programs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :title, :string
      add :locale, :string
      add :status, :string
      add :pack_version, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:programs, [:slug])
  end
end
