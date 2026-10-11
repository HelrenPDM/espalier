defmodule Espalier.Repo.Migrations.CreatePolicyVersions do
  use Ecto.Migration

  def change do
    create table(:policy_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :integer, null: false
      add :body, :text, null: false
      add :effective_from, :date, null: false
      add :published_at, :utc_datetime
      add :requires_refresher, :boolean, default: false, null: false

      add :policy_id, references(:policies, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:policy_versions, [:policy_id])
    create unique_index(:policy_versions, [:policy_id, :number])
  end
end
