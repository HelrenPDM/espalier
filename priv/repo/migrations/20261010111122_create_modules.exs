defmodule Espalier.Repo.Migrations.CreateModules do
  use Ecto.Migration

  def change do
    create table(:modules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :integer, null: false
      add :title, :string
      add :summary, :text
      add :phases, {:array, :string}
      add :domains, {:array, :string}
      add :single_path, :boolean, default: false, null: false
      add :refresher_unit, :boolean, default: false, null: false
      add :areas_elsewhere, :map, null: false
      add :archived_at, :utc_datetime
      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:modules, [:program_id, :number])
  end
end
