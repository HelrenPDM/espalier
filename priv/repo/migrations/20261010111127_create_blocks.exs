defmodule Espalier.Repo.Migrations.CreateBlocks do
  use Ecto.Migration

  def change do
    create table(:blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer
      add :kind, :string
      add :body, :text
      add :provenance, :string
      add :collapsed_on, {:array, :string}
      add :placeholder_key, :string
      add :lesson_id, references(:lessons, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:blocks, [:lesson_id])
  end
end
