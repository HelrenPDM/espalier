defmodule Espalier.Repo.Migrations.CreateParticipationMarkers do
  use Ecto.Migration

  # Records that a person has answered a self-assessment, a format vote or
  # the feedback, without a timestamp (README section 10, task 0014). A
  # self-assessment or feedback marker holds no answer; a vote has a single
  # choice, so its marker states the vote. The unique index lets each person
  # count once.
  def change do
    create table(:participation_markers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :subject_type, :string, null: false
      add :subject_id, :uuid, null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
    end

    create index(:participation_markers, [:user_id])
    create unique_index(:participation_markers, [:user_id, :subject_type, :subject_id])
  end
end
