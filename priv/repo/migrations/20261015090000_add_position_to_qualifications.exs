defmodule Espalier.Repo.Migrations.AddPositionToQualifications do
  use Ecto.Migration

  # Issue #39: a pack sets the display order of its qualifications. The
  # existing rows get their place in the former order per program (add-ons
  # last, each group by code), so that a live program lists its
  # qualifications as before until its next publish. Archived rows follow
  # the live ones, so the live rows hold 1 to n, the places that a publish
  # writes, and an unchanged pack in that order shows no change in the diff.
  def up do
    alter table(:qualifications) do
      add :position, :integer
    end

    execute """
    UPDATE qualifications AS q
    SET position = ordered.position
    FROM (
      SELECT id,
             row_number() OVER (
               PARTITION BY program_id
               ORDER BY archived_at IS NOT NULL, add_on, code
             ) AS position
      FROM qualifications
    ) AS ordered
    WHERE q.id = ordered.id
    """

    execute "ALTER TABLE qualifications ALTER COLUMN position SET NOT NULL"
  end

  def down do
    alter table(:qualifications) do
      remove :position
    end
  end
end
