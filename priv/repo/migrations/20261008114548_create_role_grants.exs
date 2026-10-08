defmodule Espalier.Repo.Migrations.CreateRoleGrants do
  use Ecto.Migration

  def change do
    create table(:role_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false
      add :source, :string, null: false
      add :provider_key, :string
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # The first column serves lookups by user.
    create unique_index(:role_grants, [:user_id, :role, :source])
  end
end
