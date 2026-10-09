defmodule Espalier.Repo.Migrations.CreateRecoveryCodes do
  use Ecto.Migration

  def change do
    create table(:recovery_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code_hmac, :binary, null: false
      add :used_at, :utc_datetime

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:recovery_codes, [:user_id])
    create unique_index(:recovery_codes, [:user_id, :code_hmac])
  end
end
