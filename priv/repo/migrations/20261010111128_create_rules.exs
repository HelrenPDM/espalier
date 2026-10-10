defmodule Espalier.Repo.Migrations.CreateRules do
  use Ecto.Migration

  def change do
    create table(:rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :integer, null: false
      add :statement, :text
      add :action, :text
      add :archived_at, :utc_datetime
      add :module_id, references(:modules, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rules, [:module_id, :number])
  end
end
