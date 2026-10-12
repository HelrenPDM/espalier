defmodule Espalier.Insights.SchemaTest do
  @moduledoc """
  The tables of task 0014 (spec steps 1 and 2, and the second and third
  item of the Acceptance list; README section 10): the anonymous tables
  `self_assessment_responses`, `interest_votes`, `feedback_responses` and
  `item_stats` hold no `user_id` column and no foreign key to `users`; the
  three new anonymous tables and `participation_markers` hold no
  `inserted_at` or `updated_at`; `participation_markers` has the unique
  index on `(user_id, subject_type, subject_id)` and a foreign key to
  `users` with `ON DELETE CASCADE`; and the primary key of a row inserted
  through `Espalier.Insights` is a random UUID of version 4, so that the
  nightly `CLUSTER` on the key hides the insertion order.
  """
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures
  import Espalier.InsightsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Insights
  alias Espalier.Insights.ParticipationMarker

  @anonymous_tables ~w(self_assessment_responses interest_votes feedback_responses item_stats)
  @untimed_tables ~w(self_assessment_responses interest_votes feedback_responses participation_markers)
  @tables Enum.uniq(@anonymous_tables ++ @untimed_tables)

  # Each anonymous table to the tables its foreign keys reference.
  @references %{
    "self_assessment_responses" => ["programs"],
    "interest_votes" => ["companion_formats"],
    "feedback_responses" => ["programs"],
    "item_stats" => ["items"]
  }

  setup do
    %{columns: columns()}
  end

  test "all five tables exist", %{columns: columns} do
    assert columns |> Map.keys() |> Enum.sort() == Enum.sort(@tables)
  end

  test "the anonymous tables hold no user_id column", %{columns: columns} do
    for table <- @anonymous_tables do
      refute "user_id" in columns[table], table
    end
  end

  test "the anonymous tables hold no foreign key to users, only to their catalog row" do
    keys = foreign_keys(@anonymous_tables)

    for table <- @anonymous_tables do
      targets = keys |> Map.get(table, []) |> Enum.map(& &1.target) |> Enum.sort()
      refute "users" in targets, table
      assert targets == @references[table], table
    end
  end

  test "the anonymous tables and participation_markers hold no timestamps",
       %{columns: columns} do
    for table <- @untimed_tables, column <- ~w(inserted_at updated_at) do
      refute column in columns[table], "#{table}.#{column}"
    end
  end

  test "participation_markers holds the user, the subject and nothing else", %{columns: columns} do
    assert Enum.sort(columns["participation_markers"]) ==
             ~w(id subject_id subject_type user_id)
  end

  test "participation_markers has the unique index on (user_id, subject_type, subject_id)" do
    assert ["user_id", "subject_type", "subject_id"] in unique_indexes("participation_markers")
  end

  test "participation_markers references users with ON DELETE CASCADE" do
    assert [%{column: "user_id", target: "users", on_delete: "c"}] =
             foreign_keys(["participation_markers"])["participation_markers"]
  end

  test "deleting a user deletes the user's markers" do
    user = user_fixture()

    assert {:ok, :done} =
             Insights.record_once(
               scope_for(user),
               {:feedback, Ecto.UUID.generate()},
               fn -> {:ok, :done} end
             )

    Repo.delete!(user)

    assert Repo.aggregate(ParticipationMarker, :count) == 0
  end

  test "a row inserted into each anonymous table gets a UUID of version 4" do
    put_insights(feedback_free_text: false)
    put_learning(insights_org_unit: false)
    program = publish_demo!()
    scope = scope_for(user_fixture())
    item = item!(program, "m1-how-models-write")

    assert {:ok, %{already_recorded: false}} =
             Insights.record_self_assessment(scope, demo_slug(), "daily-users")

    assert {:ok, %{already_recorded: false}} =
             Insights.vote_format(scope, format!(program, "workshop").id, "would_use")

    assert {:ok, %{already_recorded: false}} =
             Insights.record_feedback(scope, demo_slug(), %{"usefulness" => "very-useful"})

    assert :ok = Insights.count_item_answer(item.id, true, nil)

    for table <- @anonymous_tables ++ ["participation_markers"] do
      ids = ids(table)
      assert ids != [], table

      for id <- ids do
        assert version_digit(id) == "4", "#{table}: #{id}"
      end
    end
  end

  # The 13th hexadecimal digit of a UUID in its text form: the version.
  defp version_digit(uuid), do: uuid |> String.replace("-", "") |> String.at(12)

  # The ids of `table` as the database stores them, in text form.
  defp ids(table) do
    %{rows: rows} = Repo.query!("SELECT id::text FROM #{table}", [])
    List.flatten(rows)
  end

  # Table name to the list of its column names, from information_schema.
  defp columns do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = ANY($1)
        """,
        [@tables]
      )

    Enum.group_by(rows, &Enum.at(&1, 0), &Enum.at(&1, 1))
  end

  # Table name to its foreign keys from pg_constraint, each as
  # `%{column, target, on_delete}` with `confdeltype` as `on_delete`.
  defp foreign_keys(tables) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT t.relname, a.attname, r.relname, c.confdeltype::text
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_class r ON r.oid = c.confrelid
        CROSS JOIN LATERAL unnest(c.conkey) AS k(attnum)
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
        WHERE c.contype = 'f' AND n.nspname = current_schema() AND t.relname = ANY($1)
        """,
        [tables]
      )

    Enum.group_by(rows, &Enum.at(&1, 0), fn [_table, column, target, on_delete] ->
      %{column: column, target: target, on_delete: on_delete}
    end)
  end

  # The column lists of the unique indexes of `table` other than its
  # primary key, each in index order.
  defp unique_indexes(table) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT array_agg(a.attname ORDER BY k.ord)
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
        WHERE i.indisunique AND NOT i.indisprimary
          AND n.nspname = current_schema() AND t.relname = $1
        GROUP BY i.indexrelid
        """,
        [table]
      )

    Enum.map(rows, &hd/1)
  end
end
