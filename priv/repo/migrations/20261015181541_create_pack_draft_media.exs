defmodule Espalier.Repo.Migrations.CreatePackDraftMedia do
  use Ecto.Migration

  # The media entries of a workbench draft (task 0018, step 3): a path of the
  # draft and the library asset at that path. A row keeps its asset from
  # deletion.
  def change do
    create table(:pack_draft_media, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :path, :string, size: 527, null: false

      add :pack_draft_id, references(:pack_drafts, on_delete: :delete_all, type: :binary_id),
        null: false

      add :media_asset_id, references(:media_assets, on_delete: :restrict, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pack_draft_media, [:pack_draft_id, :path])
    create index(:pack_draft_media, [:media_asset_id])
  end
end
