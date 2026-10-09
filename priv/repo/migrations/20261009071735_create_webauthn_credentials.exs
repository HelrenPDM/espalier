defmodule Espalier.Repo.Migrations.CreateWebauthnCredentials do
  use Ecto.Migration

  def change do
    create table(:webauthn_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :credential_id, :binary, null: false
      add :cose_key, :binary, null: false
      add :sign_count, :integer, default: 0, null: false
      add :aaguid, :binary
      add :backup_eligible, :boolean, default: false, null: false
      add :backed_up, :boolean, default: false, null: false
      add :transports, {:array, :string}, default: []
      add :nickname, :string
      add :last_used_at, :utc_datetime

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:webauthn_credentials, [:user_id])

    create unique_index(:webauthn_credentials, [:credential_id])
  end
end
