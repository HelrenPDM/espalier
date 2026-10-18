defmodule Espalier.Repo.Migrations.AddMediaAssetIdsToPackImports do
  use Ecto.Migration

  # The asset ids of payload["media"] (task 0018, step 3), so that the uses
  # of an asset need no scan of the payloads.
  def change do
    alter table(:pack_imports) do
      add :media_asset_ids, {:array, :binary_id}, default: [], null: false
    end

    create index(:pack_imports, [:media_asset_ids], using: :gin)
  end
end
