defmodule Espalier.Credentials.SchemaTest do
  @moduledoc """
  The tables of task 0013 (spec step 24, bullet "Schema", with steps 1, 4,
  5 and 7): only the person-linked tables carry `user_id`, the unique
  indexes of steps 4 and 5 exist, `attendance_certificates.issued_by_id`
  stays nullable and is set to NULL when its user is deleted, the task adds
  no Oban migration, and it adds no rotation-only schema, because its
  tables hold no protected column.
  """
  use Espalier.DataCase, async: true

  alias Espalier.Crypto.Rotation

  @person_tables ~w(acknowledgements credentials attendance_certificates)
  @tables ~w(policies policy_versions approved_tools webhooks) ++ @person_tables

  # Table to the columns of each unique index of steps 4 and 5.
  @unique_indexes %{
    "policies" => ["key"],
    "policy_versions" => ["policy_id", "number"],
    "acknowledgements" => ["user_id", "policy_version_id"],
    "credentials" => ["user_id", "qualification_id"],
    "attendance_certificates" => ["user_id", "companion_format_id", "held_on"]
  }

  # Person-linked table to the reference of its parent row (step 5).
  @parents %{
    "acknowledgements" => "policy_version_id",
    "credentials" => "qualification_id",
    "attendance_certificates" => "companion_format_id"
  }

  @rotation_dir Path.expand("../../../lib/espalier/crypto/rotation", __DIR__)
  @migrations_dir Path.expand("../../../priv/repo/migrations", __DIR__)

  setup do
    %{columns: columns()}
  end

  test "all seven tables exist", %{columns: columns} do
    assert columns |> Map.keys() |> Enum.sort() == Enum.sort(@tables)
  end

  test "exactly the person-linked tables hold one user_id column", %{columns: columns} do
    for table <- @person_tables do
      assert Enum.count(columns[table], &(&1.name == "user_id")) == 1, table
    end

    for table <- @tables -- @person_tables do
      refute Enum.any?(columns[table], &(&1.name == "user_id")), table
    end
  end

  test "user_id and the reference to the parent row are NOT NULL in the person-linked tables",
       %{columns: columns} do
    for table <- @person_tables, column <- ["user_id", @parents[table]] do
      assert %{nullable: false} = Enum.find(columns[table], &(&1.name == column)),
             "#{table}.#{column}"
    end
  end

  test "the unique indexes of steps 4 and 5 exist" do
    unique = unique_indexes()

    for {table, index_columns} <- @unique_indexes do
      assert index_columns in Map.get(unique, table, []), "#{table} #{inspect(index_columns)}"
    end
  end

  test "attendance_certificates.issued_by_id is nullable and set to NULL on delete",
       %{columns: columns} do
    certificate_columns = columns["attendance_certificates"]

    assert %{nullable: true} = Enum.find(certificate_columns, &(&1.name == "issued_by_id"))
    assert %{nullable: false} = Enum.find(certificate_columns, &(&1.name == "user_id"))

    rules = delete_rules("attendance_certificates")
    assert rules["issued_by_id"] == "SET NULL"
  end

  test "the task adds no Oban migration: exactly one migration names Oban.Migration" do
    oban_migrations =
      for file <- File.ls!(@migrations_dir),
          path = Path.join(@migrations_dir, file),
          File.regular?(path),
          String.contains?(File.read!(path), "Oban.Migration"),
          do: file

    assert [_only] = oban_migrations
  end

  test "the task adds no rotation-only schema" do
    assert @rotation_dir |> File.ls!() |> Enum.sort() ==
             ~w(external_identities.ex totp_factors.ex users.ex users_tokens.ex)

    sources = Enum.map(Rotation.schemas(), & &1.__schema__(:source))
    assert sources -- @tables == sources
  end

  # Table name to a list of `%{name, nullable}` from information_schema.columns.
  defp columns do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT table_name, column_name, is_nullable
        FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = ANY($1)
        """,
        [@tables]
      )

    Enum.group_by(rows, &Enum.at(&1, 0), fn [_table, column, nullable] ->
      %{name: column, nullable: nullable == "YES"}
    end)
  end

  # Table name to the column lists of its unique indexes, in index order.
  defp unique_indexes do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT t.relname, array_agg(a.attname ORDER BY k.ord)
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
        WHERE i.indisunique AND NOT i.indisprimary
          AND n.nspname = current_schema() AND t.relname = ANY($1)
        GROUP BY t.relname, i.indexrelid
        """,
        [@tables]
      )

    Enum.group_by(rows, &Enum.at(&1, 0), &Enum.at(&1, 1))
  end

  # Column name to the delete rule of its foreign key in `table`.
  defp delete_rules(table) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT kcu.column_name, rc.delete_rule
        FROM information_schema.referential_constraints rc
        JOIN information_schema.key_column_usage kcu
          ON kcu.constraint_schema = rc.constraint_schema
         AND kcu.constraint_name = rc.constraint_name
        WHERE kcu.table_schema = current_schema() AND kcu.table_name = $1
        """,
        [table]
      )

    Map.new(rows, fn [column, rule] -> {column, rule} end)
  end
end
