defmodule Espalier.Repo.Migrations.CreateAuthChallenges do
  use Ecto.Migration

  def change do
    create table(:auth_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :purpose, :string
      add :challenge, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:auth_challenges, [:user_id])
    create index(:auth_challenges, [:expires_at])
  end
end
