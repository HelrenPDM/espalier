defmodule Espalier.Repo.Migrations.CreateInterestVotes do
  use Ecto.Migration

  # An anonymous "would use" vote for a companion format: no user key, a
  # random primary key and only a date with day precision (README section
  # 10, task 0014).
  def change do
    create table(:interest_votes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :choice, :string, null: false
      add :recorded_on, :date, null: false

      add :companion_format_id,
          references(:companion_formats, on_delete: :nothing, type: :binary_id),
          null: false
    end

    create index(:interest_votes, [:companion_format_id])
  end
end
