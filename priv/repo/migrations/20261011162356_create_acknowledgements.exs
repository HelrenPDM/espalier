defmodule Espalier.Repo.Migrations.CreateAcknowledgements do
  use Ecto.Migration

  def change do
    create table(:acknowledgements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :acknowledged_at, :utc_datetime, null: false

      add :policy_version_id,
          references(:policy_versions, on_delete: :nothing, type: :binary_id),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:acknowledgements, [:user_id])

    create index(:acknowledgements, [:policy_version_id])
    create unique_index(:acknowledgements, [:user_id, :policy_version_id])
  end
end
