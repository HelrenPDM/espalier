defmodule Espalier.Repo.Migrations.CreatePolicies do
  use Ecto.Migration

  def change do
    create table(:policies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :title, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:policies, [:key])
  end
end
