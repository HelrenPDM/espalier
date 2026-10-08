defmodule Espalier.Repo.Migrations.CreateApiClients do
  use Ecto.Migration

  def change do
    create table(:api_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :token_hash, :binary
      add :scopes, {:array, :string}
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_clients, [:token_hash])
  end
end
