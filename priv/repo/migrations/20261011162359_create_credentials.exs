defmodule Espalier.Repo.Migrations.CreateCredentials do
  use Ecto.Migration

  def change do
    create table(:credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false
      add :issued_at, :utc_datetime, null: false
      add :valid_until, :date
      add :refresh_due_at, :utc_datetime
      add :unlocks_snapshot, {:array, :string}, default: [], null: false

      add :qualification_id, references(:qualifications, on_delete: :nothing, type: :binary_id),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:credentials, [:user_id])

    create index(:credentials, [:qualification_id])
    create unique_index(:credentials, [:user_id, :qualification_id])
  end
end
