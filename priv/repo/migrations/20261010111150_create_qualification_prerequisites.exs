defmodule Espalier.Repo.Migrations.CreateQualificationPrerequisites do
  use Ecto.Migration

  def change do
    create table(:qualification_prerequisites, primary_key: false) do
      add :qualification_id,
          references(:qualifications, on_delete: :delete_all, type: :binary_id), null: false

      add :prerequisite_id, references(:qualifications, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create unique_index(:qualification_prerequisites, [:qualification_id, :prerequisite_id])
    create index(:qualification_prerequisites, [:prerequisite_id])
  end
end
