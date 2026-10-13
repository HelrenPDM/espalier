defmodule Espalier.Repo.Migrations.CreatePackDraftFiles do
  use Ecto.Migration

  def change do
    create table(:pack_draft_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Espalier.Workbench.Paths admits paths of at most 527 bytes, ASCII in
      # the pack layout.
      add :path, :string, size: 527, null: false
      add :content, :text, null: false

      add :pack_draft_id, references(:pack_drafts, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pack_draft_files, [:pack_draft_id, :path])
  end
end
