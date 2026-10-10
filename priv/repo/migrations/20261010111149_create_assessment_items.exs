defmodule Espalier.Repo.Migrations.CreateAssessmentItems do
  use Ecto.Migration

  def change do
    create table(:assessment_items, primary_key: false) do
      add :assessment_id, references(:assessments, on_delete: :delete_all, type: :binary_id),
        null: false

      add :item_id, references(:items, on_delete: :delete_all, type: :binary_id), null: false
      add :position, :integer, null: false
    end

    create unique_index(:assessment_items, [:assessment_id, :item_id])
    create index(:assessment_items, [:item_id])
  end
end
