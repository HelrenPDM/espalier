defmodule Espalier.Repo.Migrations.CreateWebhooks do
  use Ecto.Migration

  def change do
    create table(:webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :string, null: false
      add :events, {:array, :string}, default: [], null: false
      add :secret_env, :string, null: false
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
