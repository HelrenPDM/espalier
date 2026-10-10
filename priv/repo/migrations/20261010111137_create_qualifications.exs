defmodule Espalier.Repo.Migrations.CreateQualifications do
  use Ecto.Migration

  def change do
    create table(:qualifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :title, :string
      add :audience, :text
      add :unlocks, {:array, :string}
      add :add_on, :boolean, default: false, null: false
      add :validity_kind, :string
      add :validity_months, :integer
      add :refresher_mode, :string
      add :phases, {:array, :string}
      add :archived_at, :utc_datetime
      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:qualifications, [:program_id, :code])
  end
end
