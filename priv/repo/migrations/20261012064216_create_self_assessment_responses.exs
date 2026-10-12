defmodule Espalier.Repo.Migrations.CreateSelfAssessmentResponses do
  use Ecto.Migration

  # An anonymous self-assessment: no user key, a random primary key and only
  # a date with day precision (README section 10, task 0014). org_unit is
  # filled only with INSIGHTS_ORG_UNIT=true.
  def change do
    create table(:self_assessment_responses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :segment_key, :string, null: false
      add :org_unit, :string
      add :recorded_on, :date, null: false

      add :program_id, references(:programs, on_delete: :nothing, type: :binary_id), null: false
    end

    create index(:self_assessment_responses, [:program_id])
  end
end
