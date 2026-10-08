defmodule Espalier.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  # Version 14 is the current migration of Oban 2.24.1 (installation guide).
  def up, do: Oban.Migration.up(version: 14)

  def down, do: Oban.Migration.down(version: 1)
end
