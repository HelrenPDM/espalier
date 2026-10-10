defmodule Espalier.Learning.SchemaTest do
  # The tables of task 0009 hold the fields of domain-records.puml and no
  # answer, no objective status and, for the anonymous counter, no user key
  # and no time beyond its period (README section 7, rule 15, and section 10).
  use Espalier.DataCase, async: true

  @diagram Path.expand("../../../docs/architecture/domain-records.puml", __DIR__)
  @tables ~w(enrollments item_responses assessment_attempts module_completions item_stats)

  @varchar "character varying"
  @timestamp "timestamp without time zone"

  # The fields of each class in domain-records.puml with their SQL types.
  @fields %{
    "enrollments" => %{
      "path" => @varchar,
      "path_chosen_manually" => "boolean",
      "started_at" => @timestamp
    },
    "item_responses" => %{
      "correct" => "boolean",
      "attempt_no" => "integer",
      "answered_on" => "date"
    },
    "assessment_attempts" => %{
      "number" => "integer",
      "wrong_count" => "integer",
      "core_failed" => "boolean",
      "outcome" => @varchar,
      "submitted_at" => @timestamp
    },
    "module_completions" => %{"completed_at" => @timestamp},
    "item_stats" => %{
      "period" => "date",
      "org_unit" => @varchar,
      "attempts" => "integer",
      "correct" => "integer"
    }
  }

  # The keys and timestamps that the diagram leaves out.
  @keys %{
    "enrollments" => %{
      "id" => "uuid",
      "program_id" => "uuid",
      "user_id" => "uuid",
      "inserted_at" => @timestamp,
      "updated_at" => @timestamp
    },
    "item_responses" => %{
      "id" => "uuid",
      "enrollment_id" => "uuid",
      "item_id" => "uuid",
      "user_id" => "uuid"
    },
    "assessment_attempts" => %{
      "id" => "uuid",
      "enrollment_id" => "uuid",
      "assessment_id" => "uuid",
      "user_id" => "uuid",
      "inserted_at" => @timestamp,
      "updated_at" => @timestamp
    },
    "module_completions" => %{
      "id" => "uuid",
      "enrollment_id" => "uuid",
      "module_id" => "uuid",
      "user_id" => "uuid",
      "inserted_at" => @timestamp,
      "updated_at" => @timestamp
    },
    "item_stats" => %{"id" => "uuid", "item_id" => "uuid"}
  }

  @classes %{
    "Enrollment" => "enrollments",
    "ItemResponse" => "item_responses",
    "AssessmentAttempt" => "assessment_attempts",
    "ModuleCompletion" => "module_completions",
    "ItemStat" => "item_stats"
  }

  # Diagram types to the SQL types of their columns: enums are strings.
  @sql_types %{
    "AttemptOutcome" => @varchar,
    "Path" => @varchar,
    "boolean" => "boolean",
    "date" => "date",
    "datetime" => @timestamp,
    "int" => "integer",
    "string" => @varchar
  }

  setup do
    %{columns: columns()}
  end

  test "all five tables exist", %{columns: columns} do
    assert columns |> Map.keys() |> Enum.sort() == Enum.sort(@tables)
  end

  test "item_stats has no user key and no timestamps", %{columns: columns} do
    for column <- ~w(user_id inserted_at updated_at) do
      refute Map.has_key?(columns["item_stats"], column)
    end
  end

  test "item_responses has no timestamps", %{columns: columns} do
    refute Map.has_key?(columns["item_responses"], "inserted_at")
    refute Map.has_key?(columns["item_responses"], "updated_at")
  end

  test "no table stores an answer or an objective", %{columns: columns} do
    for {table, table_columns} <- columns, column <- Map.keys(table_columns) do
      refute column in ["answer", "answers"], "#{table}.#{column}"
      refute column =~ "objective", "#{table}.#{column}"
    end
  end

  test "domain-records.puml gives each class the fields and types of the tables" do
    diagram = diagram_fields()

    assert diagram |> Map.keys() |> Enum.sort() == @classes |> Map.keys() |> Enum.sort()

    for {class, table} <- @classes do
      assert Map.new(diagram[class], fn {field, type} -> {field, Map.fetch!(@sql_types, type)} end) ==
               @fields[table],
             class
    end
  end

  test "each table holds the fields of the diagram with their SQL types, and its keys",
       %{columns: columns} do
    for table <- @tables do
      assert columns[table] == Map.merge(@fields[table], @keys[table]), table
    end
  end

  test "the unique index on item_stats treats rows without an org unit as one" do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT ix.indexdef, i.indisunique, i.indnullsnotdistinct
        FROM pg_indexes ix
        JOIN pg_class c
          ON c.relname = ix.indexname AND c.relnamespace = ix.schemaname::regnamespace
        JOIN pg_index i ON i.indexrelid = c.oid
        WHERE ix.schemaname = current_schema() AND ix.tablename = 'item_stats'
        """,
        []
      )

    assert [[indexdef, true, true]] =
             Enum.filter(rows, fn [indexdef | _rest] ->
               indexdef =~ "(item_id, period, org_unit)"
             end)

    assert indexdef =~ "CREATE UNIQUE INDEX"
    assert indexdef =~ "NULLS NOT DISTINCT"
  end

  # Table name to column name to `data_type` of information_schema.columns.
  defp columns do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT table_name, column_name, data_type
        FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = ANY($1)
        """,
        [@tables]
      )

    rows
    |> Enum.group_by(&Enum.at(&1, 0), fn [_table, column, type] -> {column, type} end)
    |> Map.new(fn {table, pairs} -> {table, Map.new(pairs)} end)
  end

  # Class name to `[{field, type}]` for the classes of `@classes`.
  defp diagram_fields do
    for [_match, class, body] <-
          Regex.scan(~r/^\s*class (\w+) \{\n(.*?)\n\s*\}/ms, File.read!(@diagram)),
        Map.has_key?(@classes, class),
        into: %{} do
      {class,
       for([_line, field, type] <- Regex.scan(~r/^\s*(\w+) : (\w+)/m, body), do: {field, type})}
    end
  end
end
