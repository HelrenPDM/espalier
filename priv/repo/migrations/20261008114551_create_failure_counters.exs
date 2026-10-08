defmodule Espalier.Repo.Migrations.CreateFailureCounters do
  use Ecto.Migration

  def change do
    create table(:failure_counters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :authenticator, :string, null: false
      add :consecutive_failures, :integer, null: false, default: 0
      add :locked_until, :utc_datetime
      add :disabled_at, :utc_datetime
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # NULL values are distinct in a unique index, so both columns are NOT NULL
    # and the upsert of Espalier.Accounts.FailureCounters finds one row per pair.
    create unique_index(:failure_counters, [:user_id, :authenticator])
  end
end
