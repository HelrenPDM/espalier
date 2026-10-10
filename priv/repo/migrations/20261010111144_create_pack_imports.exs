defmodule Espalier.Repo.Migrations.CreatePackImports do
  use Ecto.Migration

  def change do
    create table(:pack_imports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pack_key, :string
      add :pack_version, :string
      add :status, :string, null: false
      add :report, :map, null: false
      add :payload, :map
      add :published_at, :utc_datetime
      # The id of the importing user, or NULL for the mix tasks and the release
      # function. A plain UUID without a foreign key: the catalog keeps no
      # reference to the users table.
      add :imported_by_id, :uuid

      timestamps(type: :utc_datetime)
    end

    create index(:pack_imports, [:pack_key])
  end
end
