defmodule Espalier.Repo.Migrations.CreatePackDrafts do
  use Ecto.Migration

  def change do
    create table(:pack_drafts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :pack_key, :string
      add :lock_version, :integer, null: false, default: 1
      add :created_by_id, references(:users, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:pack_drafts, [:created_by_id])
  end
end
