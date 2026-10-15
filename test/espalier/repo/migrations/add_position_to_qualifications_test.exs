defmodule Espalier.Repo.Migrations.AddPositionToQualificationsTest do
  @moduledoc """
  The migration of issue #39 gives each existing qualification its place in
  the former display order of its program: base qualifications before
  add-ons, each group by code, and archived rows after the live ones, so
  that the live rows hold 1 to n. The test runs the
  migration down inside the SQL sandbox, inserts rows without `position`
  and runs it up again; the sandbox rolls the DDL back at the end of the
  test. The test runs synchronously, because the DDL locks the table for
  every other test of the partition.
  """
  use Espalier.DataCase, async: false

  alias Ecto.{Migrator, UUID}
  alias Espalier.Catalog.{Program, Qualification}

  @migration Espalier.Repo.Migrations.AddPositionToQualifications
  @migrations_dir Path.expand("../../../../priv/repo/migrations", __DIR__)
  @migration_file Path.join(@migrations_dir, "20261015090000_add_position_to_qualifications.exs")

  # The version leads the file name, where Ecto.Migrator reads it.
  @version @migration_file |> Path.basename() |> Integer.parse() |> elem(0)

  # Without the migration lock: the migrator takes it in a transaction of
  # this process and runs the migration in a task, which would then wait for
  # the sandbox connection that this process holds.
  @migrator_opts [log: false, migration_lock: false]

  test "fills position per program by archive flag, add_on and code and sets the column NOT NULL" do
    migration = migration_module()

    assert Migrator.down(Repo, @version, migration, @migrator_opts) == :ok
    assert position_column() == nil

    first = insert_program!("first-program")
    second = insert_program!("second-program")

    # Inserted neither by code nor in the expected order, with an add-on
    # whose code sorts before base codes and an archived base qualification,
    # which the order by add_on and code alone would place before the add-ons.
    insert_qualifications!(first, [
      {"workshop", true, nil},
      {"intro", false, nil},
      {"coaching", true, nil},
      {"review", false, ~N[2026-09-01 08:00:00]},
      {"basics", false, nil}
    ])

    insert_qualifications!(second, [
      {"advanced", true, nil},
      {"overview", false, nil}
    ])

    assert Migrator.up(Repo, @version, migration, @migrator_opts) == :ok

    assert positions(first) == [
             {"basics", 1},
             {"intro", 2},
             {"coaching", 3},
             {"workshop", 4},
             {"review", 5}
           ]

    assert positions(second) == [{"overview", 1}, {"advanced", 2}]
    assert position_column() == %{type: "integer", nullable: false}
  end

  # The migration module, compiled from its file unless `mix ecto.migrate`
  # loaded it into this VM.
  defp migration_module do
    unless Code.ensure_loaded?(@migration), do: Code.compile_file(@migration_file)
    @migration
  end

  defp insert_program!(slug) do
    Repo.insert!(%Program{
      slug: slug,
      title: "Program #{slug}",
      locale: "en",
      status: :published,
      pack_version: "1.0.0"
    })
  end

  # Schemaless, because the schema names `position`, which the table lacks
  # while the migration is down.
  defp insert_qualifications!(program, rows) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    {count, nil} =
      Repo.insert_all(
        "qualifications",
        for {code, add_on, archived_at} <- rows do
          %{
            id: UUID.bingenerate(),
            program_id: UUID.dump!(program.id),
            code: code,
            title: "Qualification #{code}",
            add_on: add_on,
            archived_at: archived_at,
            inserted_at: now,
            updated_at: now
          }
        end
      )

    assert count == length(rows)
  end

  defp positions(program) do
    Repo.all(
      from q in Qualification,
        where: q.program_id == ^program.id,
        order_by: q.position,
        select: {q.code, q.position}
    )
  end

  # `%{type, nullable}` of qualifications.position from
  # information_schema.columns, or nil without the column.
  defp position_column do
    %{rows: rows} =
      Repo.query!("""
      SELECT data_type, is_nullable
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND table_name = 'qualifications'
        AND column_name = 'position'
      """)

    case rows do
      [[type, nullable]] -> %{type: type, nullable: nullable == "YES"}
      [] -> nil
    end
  end
end
