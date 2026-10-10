defmodule Espalier.Repo.Migrations.CreateItemResponses do
  use Ecto.Migration

  # answered_on is the only time of an item response (task 0009, step 6).
  def change do
    create table(:item_responses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :correct, :boolean, default: false, null: false
      add :attempt_no, :integer, null: false
      add :answered_on, :date, null: false

      add :enrollment_id, references(:enrollments, on_delete: :delete_all, type: :binary_id),
        null: false

      add :item_id, references(:items, on_delete: :nothing, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
    end

    create index(:item_responses, [:user_id])

    create unique_index(:item_responses, [:enrollment_id, :item_id, :attempt_no])
    create index(:item_responses, [:item_id])
  end
end
