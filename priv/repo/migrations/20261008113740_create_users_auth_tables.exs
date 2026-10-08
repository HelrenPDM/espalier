# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule Espalier.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :binary
      add :email_hash, :binary
      add :display_name, :binary
      add :org_unit, :binary
      add :locale, :string, null: false, default: "en"
      add :status, :string, null: false, default: "active"
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :last_login_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email_hash])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :context, :string, null: false
      add :sent_to_hash, :binary
      add :new_email, :binary
      add :authenticated_at, :utc_datetime
      add :auth_methods, {:array, :string}, null: false, default: []
      add :strength, :string
      add :mfa_at, :utc_datetime
      add :provider_key, :string
      add :idp_sid_hash, :binary
      add :device_summary, :string, size: 64
      add :last_seen_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token_hash])
    create index(:users_tokens, [:expires_at])
    create index(:users_tokens, [:idp_sid_hash], where: "idp_sid_hash IS NOT NULL")
  end
end
