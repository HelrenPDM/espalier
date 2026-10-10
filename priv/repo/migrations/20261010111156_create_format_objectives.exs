defmodule Espalier.Repo.Migrations.CreateFormatObjectives do
  use Ecto.Migration

  def change do
    create table(:format_objectives, primary_key: false) do
      add :companion_format_id,
          references(:companion_formats, on_delete: :delete_all, type: :binary_id), null: false

      add :learning_objective_id,
          references(:learning_objectives, on_delete: :delete_all, type: :binary_id), null: false
    end

    create unique_index(:format_objectives, [:companion_format_id, :learning_objective_id])
    create index(:format_objectives, [:learning_objective_id])
  end
end
