defmodule Espalier.Repo.Migrations.CreateApprovedTools do
  use Ecto.Migration

  def change do
    create table(:approved_tools, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :vendor, :string, null: false
      add :status, :string, null: false
      add :conditions, :text
      add :reviewed_on, :date
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:approved_tools, [:name])
  end
end
