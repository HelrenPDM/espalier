defmodule Espalier.Repo.Migrations.CreateTotpFactors do
  use Ecto.Migration

  def change do
    create table(:totp_factors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :secret, :binary, null: false
      add :last_used_step, :integer
      add :enabled_at, :utc_datetime

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # A user holds at most one TOTP factor (domain-records.puml).
    create unique_index(:totp_factors, [:user_id])
  end
end
