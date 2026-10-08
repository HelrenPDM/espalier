defmodule Espalier.Repo.Migrations.CreateExternalIdentities do
  use Ecto.Migration

  def change do
    create table(:external_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider_key, :string, null: false
      add :issuer, :string, null: false
      add :tenant_id, :string
      add :subject, :binary, null: false
      add :subject_hash, :binary, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:external_identities, [:user_id])
    create unique_index(:external_identities, [:provider_key, :subject_hash])
  end
end
