defmodule Espalier.Repo.Migrations.CreateProgramMedia do
  use Ecto.Migration

  # The media of a published program (task 0018, step 3): one row per media
  # path of the payload of its import. A row keeps its asset from deletion.
  def change do
    create table(:program_media, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :path, :string, size: 527, null: false

      add :program_id, references(:programs, on_delete: :delete_all, type: :binary_id),
        null: false

      add :media_asset_id, references(:media_assets, on_delete: :restrict, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:program_media, [:program_id, :path])
    create index(:program_media, [:media_asset_id])
  end
end
