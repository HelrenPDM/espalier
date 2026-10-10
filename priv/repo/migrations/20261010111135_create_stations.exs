defmodule Espalier.Repo.Migrations.CreateStations do
  use Ecto.Migration

  def change do
    create table(:stations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer
      add :kind, :string
      add :title, :string
      add :config, :map

      add :program_id, references(:programs, on_delete: :delete_all, type: :binary_id),
        null: false

      add :module_id, references(:modules, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:stations, [:program_id])
    create index(:stations, [:module_id])
  end
end
