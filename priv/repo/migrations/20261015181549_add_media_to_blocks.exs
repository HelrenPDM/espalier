defmodule Espalier.Repo.Migrations.AddMediaToBlocks do
  use Ecto.Migration

  # The attributes of the figure and video blocks of task 0018 (step 3); NULL
  # for the other kinds.
  def change do
    alter table(:blocks) do
      add :media, :map
    end
  end
end
