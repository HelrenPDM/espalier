defmodule Espalier.Insights.RetentionWorkerTest do
  @moduledoc """
  Task 0014, steps 10 and 13 and the Acceptance cases on retention:
  `Espalier.Insights.RetentionWorker`, each job run with `perform_job/3` in
  the test process.

  With every retention variable unset, a run deletes no row from the tables
  it covers and logs `unset` for each variable. Each variable that is set
  deletes the rows of its tables older than the limit, keeps the rows on the
  cutoff day and newer, and logs the deleted count per table.
  `RETENTION_ATTEMPTS_DAYS` keeps the newest passed attempt per user and
  assessment that an `assessment_passed` requirement of an `active` or
  `refresh_due` credential depends on, and the attempt of one user keeps
  no attempt of another. On every run, the job rewrites and clusters the
  three anonymous tables and `participation_markers`: the rows keep their
  values, the physical order follows the random keys,
  `pg_index.indisclustered` is set, and all rows of a table share one
  transaction id that no row carried before the run, so that the id no
  longer matches an anonymous row to its participation marker.

  The tests read the date and the time right before they seed rows at the
  boundary of a limit. The job reads its own, so when the UTC day changes
  in between, the assertions on the cutoff day of the date columns allow
  the cutoff of the next day.

  `Espalier.Insights.RetentionWorkerLockTest` below shows on connections of
  its own that the deletion of the attempts waits for the evaluation lock
  of the user.
  """
  # Application.put_env/3 and Logger.put_module_level/2 change the node.
  use Espalier.DataCase, async: false

  import ExUnit.CaptureLog
  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures
  import Espalier.InsightsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Audit.AuditEvent
  alias Espalier.Insights
  alias Espalier.Insights.{FeedbackResponse, InterestVote, ParticipationMarker, RetentionWorker}
  alias Espalier.Insights.SelfAssessmentResponse
  alias Espalier.Learning.{AssessmentAttempt, ItemResponse}

  @anonymous ~w(self_assessment_responses interest_votes feedback_responses)

  # The tables that the job reorders on every run.
  @clustered @anonymous ++ ["participation_markers"]

  # The tables whose limit counts in days of a date column.
  @date_tables ["item_responses" | @anonymous]

  # The tables that the retention variables cover.
  @tables @date_tables ++ ["audit_events", "assessment_attempts"]

  @variables [
    {"RETENTION_ITEM_RESPONSES_DAYS", :retention_item_responses_days, ["item_responses"]},
    {"RETENTION_ANONYMOUS_DAYS", :retention_anonymous_days, @anonymous},
    {"RETENTION_AUDIT_DAYS", :retention_audit_days, ["audit_events"]},
    {"RETENTION_ATTEMPTS_DAYS", :retention_attempts_days, ["assessment_attempts"]}
  ]

  @names for {name, _key, _tables} <- @variables, do: name
  @unset for {_name, key, _tables} <- @variables, do: {key, nil}

  @segments ~w(daily-users occasional-users non-users stopped-users)

  setup do
    Logger.put_module_level(RetentionWorker, :info)
    on_exit(fn -> Logger.delete_module_level(RetentionWorker) end)

    put_retention([])

    # The flag of an earlier committed CLUSTER would hide whether this run
    # sets it; the sandbox rolls the change back with the test.
    for table <- @clustered, do: Repo.query!("ALTER TABLE #{table} SET WITHOUT CLUSTER")

    program = publish_demo!()
    {_user, enrollment} = learner!(program)

    %{
      program: program,
      enrollment: enrollment,
      item: item!(program, "m1-how-models-write"),
      assessment: assessment!(program),
      format: format!(program, "handbook"),
      today: Date.utc_today(),
      now: DateTime.utc_now(:second)
    }
  end

  # Sets the four retention periods of `config :espalier, :insights`, unset
  # unless named in `periods`, and restores the previous value on exit.
  defp put_retention(periods) do
    settings =
      :espalier
      |> Application.get_env(:insights, [])
      |> Keyword.merge(@unset)
      |> Keyword.merge(periods)

    put_setting!(:insights, settings)
  end

  # Replaces an application setting with Application.put_env/3 and restores
  # the previous value on exit.
  defp put_setting!(key, value) do
    previous = Application.fetch_env(:espalier, key)
    Application.put_env(:espalier, key, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, key, value)
        :error -> Application.delete_env(:espalier, key)
      end
    end)
  end

  defp days_before(%DateTime{} = at, days), do: DateTime.add(at, -days, :day)

  # Runs the job and returns its log.
  defp run! do
    capture_log([level: :info], fn -> assert :ok = perform_job(RetentionWorker, %{}) end)
  end

  defp learner!(program) do
    user = user_fixture()
    {user, enroll!(scope_for(user), "short", program.slug)}
  end

  defp item_response!(enrollment, item, answered_on) do
    Repo.insert!(%ItemResponse{
      enrollment_id: enrollment.id,
      item_id: item.id,
      user_id: enrollment.user_id,
      correct: true,
      attempt_no: System.unique_integer([:positive]),
      answered_on: answered_on
    })
  end

  defp attempt!(enrollment, assessment, outcome, submitted_at, number \\ nil) do
    Repo.insert!(%AssessmentAttempt{
      enrollment_id: enrollment.id,
      assessment_id: assessment.id,
      user_id: enrollment.user_id,
      number: number || System.unique_integer([:positive]),
      wrong_count: if(outcome == :passed, do: 0, else: 3),
      core_failed: false,
      outcome: outcome,
      submitted_at: submitted_at
    })
  end

  # Inserts one row into each table that a retention variable covers, with
  # `date` in the date columns and `at` in the timestamp columns, and
  # returns the ids by table. The attempt failed, so no credential keeps it.
  defp seed!(ctx, date, at) do
    [self_assessment] = self_assessment_rows!(ctx.program, "daily-users", 1, recorded_on: date)
    [vote] = vote_rows!(ctx.format, 1, recorded_on: date)
    feedback = feedback_row!(ctx.program, %{"usefulness" => "very-useful"}, recorded_on: date)

    %{
      "item_responses" => item_response!(ctx.enrollment, ctx.item, date).id,
      "self_assessment_responses" => self_assessment.id,
      "interest_votes" => vote.id,
      "feedback_responses" => feedback.id,
      "audit_events" => Repo.insert!(%AuditEvent{action: "retention_test", at: at}).id,
      "assessment_attempts" => attempt!(ctx.enrollment, ctx.assessment, :failed_errors, at).id
    }
  end

  # The tables in which the seeded row still exists, sorted.
  defp kept(ids) do
    ids
    |> Enum.filter(fn {table, id} ->
      Repo.exists?(from r in table, where: r.id == type(^id, Ecto.UUID))
    end)
    |> Enum.map(fn {table, _id} -> table end)
    |> Enum.sort()
  end

  defp counts, do: Map.new(@tables ++ @clustered, &{&1, Repo.aggregate(&1, :count)})

  defp exists?(%{__struct__: schema, id: id}),
    do: Repo.exists?(from r in schema, where: r.id == ^id)

  defp clustered?(table) do
    %{rows: [[clustered]]} =
      Repo.query!(
        "SELECT indisclustered FROM pg_index WHERE indexrelid = '#{table}_pkey'::regclass"
      )

    clustered
  end

  defp ids_in(table, order) do
    Repo.query!("SELECT id::text FROM #{table} ORDER BY #{order}").rows |> List.flatten()
  end

  defp xmins(table) do
    "SELECT DISTINCT xmin::text FROM #{table}"
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  # Every anonymous row and participation marker, ordered by key.
  defp snapshot do
    for schema <- [SelfAssessmentResponse, InterestVote, FeedbackResponse, ParticipationMarker] do
      Repo.all(from r in schema, order_by: r.id)
    end
  end

  # Records the three anonymous answers of a new user through
  # `Insights.record_once/3`, so that each anonymous row and its marker are
  # written in one transaction, as the insights endpoints write them.
  defp answer!(ctx, n) do
    scope = scope_for(user_fixture())
    recorded_on = Date.add(ctx.today, -n)

    {:ok, _rows} =
      Insights.record_once(scope, {:self_assessment, ctx.program.id}, fn ->
        segment = Enum.at(@segments, rem(n, length(@segments)))

        {:ok,
         self_assessment_rows!(ctx.program, segment, 1,
           org_unit: "Unit #{n}",
           recorded_on: recorded_on
         )}
      end)

    {:ok, _rows} =
      Insights.record_once(scope, {:format_vote, ctx.format.id}, fn ->
        {:ok, vote_rows!(ctx.format, 1, recorded_on: recorded_on)}
      end)

    {:ok, _row} =
      Insights.record_once(scope, {:feedback, ctx.program.id}, fn ->
        answers = %{
          "usefulness" => "somewhat-useful",
          "clarity" => rem(n, 5) + 1,
          "suggestion" => "Suggestion #{n}"
        }

        {:ok, feedback_row!(ctx.program, answers, recorded_on: recorded_on)}
      end)
  end

  describe "with every retention variable unset" do
    test "a run deletes no row, logs unset for each variable and clusters the anonymous tables",
         ctx do
      ids = seed!(ctx, Date.add(ctx.today, -3_650), DateTime.add(ctx.now, -3_650, :day))
      answer!(ctx, 1)
      before = counts()

      for table <- @clustered, do: refute(clustered?(table), table)

      log = run!()

      assert kept(ids) == Enum.sort(@tables)
      assert counts() == before

      for name <- @names, do: assert(log =~ "retention #{name} unset", name)
      refute log =~ "retention deleted"

      for table <- @clustered, do: assert(clustered?(table), table)
    end

    test "a variable without a key in config :espalier, :insights counts as unset", ctx do
      put_setting!(:insights, [])
      ids = seed!(ctx, Date.add(ctx.today, -3_650), DateTime.add(ctx.now, -3_650, :day))

      log = run!()

      assert kept(ids) == Enum.sort(@tables)
      for name <- @names, do: assert(log =~ "retention #{name} unset", name)
      refute log =~ "retention deleted"
    end
  end

  describe "with one retention variable set" do
    for {name, key, tables} <- @variables do
      test "#{name} deletes the rows older than the limit from #{Enum.join(tables, ", ")} and no other row",
           ctx do
        put_retention([{unquote(key), 30}])
        limit = 30 * 86_400
        answer!(ctx, 0)
        markers = Repo.aggregate(ParticipationMarker, :count)

        # The older rows lie one day before the cutoff day in the date
        # columns and one minute beyond the limit in the timestamp columns.
        # The rows on the cutoff day lie one hour within the limit in the
        # timestamp columns, and the newer rows one day after the cutoff day.
        today = Date.utc_today()
        now = DateTime.utc_now(:second)
        older = seed!(ctx, Date.add(today, -31), DateTime.add(now, -limit - 60, :second))
        on_cutoff = seed!(ctx, Date.add(today, -30), DateTime.add(now, -limit + 3_600, :second))
        newer = seed!(ctx, Date.add(today, -29), DateTime.add(now, -29, :day))

        log = run!()

        # When the UTC day changed after `today` was read, the job may have
        # read the next day, whose cutoff day holds the newer rows. The rows
        # on the earlier cutoff day of the date columns may then be deleted
        # as well; the older rows are deleted and the newer rows kept with
        # either day.
        shifted =
          if Date.utc_today() == today,
            do: [],
            else: Enum.filter(unquote(tables), &(&1 in @date_tables))

        assert kept(older) == Enum.sort(@tables -- unquote(tables))
        assert kept(on_cutoff) -- shifted == Enum.sort(@tables -- shifted)
        assert kept(newer) == Enum.sort(@tables)

        # The participation markers are no retention target.
        assert Repo.aggregate(ParticipationMarker, :count) == markers

        for table <- unquote(tables) do
          count = if table in shifted, do: "[12]", else: "1"
          assert log =~ ~r/retention deleted #{count} rows from #{table}\b/, table
        end

        for table <- @tables -- unquote(tables), do: refute(log =~ "rows from #{table}", table)
        refute log =~ "retention #{unquote(name)} unset"
        for other <- @names -- [unquote(name)], do: assert(log =~ "retention #{other} unset")

        for table <- @clustered, do: assert(clustered?(table), table)
      end
    end
  end

  describe "RETENTION_ATTEMPTS_DAYS and the attempts that credentials depend on" do
    setup ctx do
      put_retention(retention_attempts_days: 30)

      %{
        basics: qualification!(ctx.program, "basics"),
        workshop: qualification!(ctx.program, "workshop"),
        old: DateTime.add(ctx.now, -90, :day)
      }
    end

    test "keeps the newest passed attempt for an active or a refresh_due credential and deletes the older ones",
         ctx do
      {active_user, active} = learner!(ctx.program)
      credential_fixture(active_user, ctx.basics, status: :active)
      first_failed = attempt!(active, ctx.assessment, :failed_core, days_before(ctx.old, 10), 1)
      older_passed = attempt!(active, ctx.assessment, :passed, ctx.old, 2)
      newest_passed = attempt!(active, ctx.assessment, :passed, days_before(ctx.old, -10), 3)

      later_failed =
        attempt!(active, ctx.assessment, :failed_errors, days_before(ctx.old, -20), 4)

      {refresh_user, refresh} = learner!(ctx.program)
      credential_fixture(refresh_user, ctx.basics, status: :refresh_due, refresh_due_at: ctx.now)
      refresh_passed = attempt!(refresh, ctx.assessment, :passed, ctx.old, 1)

      log = run!()

      assert exists?(newest_passed)
      assert exists?(refresh_passed)
      refute exists?(first_failed)
      refute exists?(older_passed)
      refute exists?(later_failed)
      assert log =~ ~r/retention deleted 3 rows from assessment_attempts\b/
    end

    test "keeps the newest passed attempt of each user, so that the attempt of one user keeps no attempt of another",
         ctx do
      {first_user, first} = learner!(ctx.program)
      credential_fixture(first_user, ctx.basics, status: :active)
      first_older = attempt!(first, ctx.assessment, :passed, ctx.old, 1)
      first_newest = attempt!(first, ctx.assessment, :passed, days_before(ctx.old, -5), 2)

      # The newest passed attempt of the second holder is older than both
      # attempts of the first holder, and a failed attempt follows it.
      {second_user, second} = learner!(ctx.program)
      credential_fixture(second_user, ctx.basics, status: :active)
      second_older = attempt!(second, ctx.assessment, :passed, days_before(ctx.old, 20), 1)
      second_newest = attempt!(second, ctx.assessment, :passed, days_before(ctx.old, 10), 2)

      second_failed =
        attempt!(second, ctx.assessment, :failed_errors, days_before(ctx.old, -8), 3)

      # Without a credential, the newest old passed attempt of all is
      # deleted, and an attempt within the limit stays.
      {_third_user, third} = learner!(ctx.program)
      third_passed = attempt!(third, ctx.assessment, :passed, days_before(ctx.old, -10), 1)
      third_recent = attempt!(third, ctx.assessment, :failed_errors, days_before(ctx.now, 1), 2)

      log = run!()

      for attempt <- [first_newest, second_newest, third_recent], do: assert(exists?(attempt))

      for attempt <- [first_older, second_older, second_failed, third_passed],
          do: refute(exists?(attempt))

      assert log =~ ~r/retention deleted 4 rows from assessment_attempts\b/
    end

    test "deletes the old passed attempt without a credential in force that requires the assessment",
         ctx do
      # A holder of an active credential, so that the rule keeps attempts of
      # the holder alone.
      {holder, holder_enrollment} = learner!(ctx.program)
      credential_fixture(holder, ctx.basics, status: :active)
      held = attempt!(holder_enrollment, ctx.assessment, :passed, ctx.old, 1)

      # An expired and a revoked credential, no credential, and an active
      # credential of a qualification without an assessment_passed
      # requirement.
      deleted =
        for credential <- [
              {ctx.basics, :expired},
              {ctx.basics, :revoked},
              :none,
              {ctx.workshop, :active}
            ] do
          {user, enrollment} = learner!(ctx.program)

          case credential do
            {qualification, status} -> credential_fixture(user, qualification, status: status)
            :none -> nil
          end

          attempt!(enrollment, ctx.assessment, :passed, ctx.old, 1)
        end

      {_user, recent_enrollment} = learner!(ctx.program)
      recent = attempt!(recent_enrollment, ctx.assessment, :passed, days_before(ctx.now, 29), 1)

      log = run!()

      assert exists?(held)
      assert exists?(recent)
      for attempt <- deleted, do: refute(exists?(attempt))
      assert log =~ ~r/retention deleted 4 rows from assessment_attempts\b/
    end

    test "keeps the passed exam of a credential earned in the program until the credential is revoked",
         ctx do
      user = user_fixture()
      credential = qualify_basics!(scope_for(user), ctx.program)
      assert credential.status == :active

      [attempt] = Repo.all(from a in AssessmentAttempt, where: a.user_id == ^user.id)
      assert attempt.outcome == :passed

      {1, _rows} =
        Repo.update_all(from(a in AssessmentAttempt, where: a.id == ^attempt.id),
          set: [submitted_at: ctx.old]
        )

      run!()
      assert exists?(attempt)

      put_credential!(credential, status: :revoked)
      log = run!()

      refute exists?(attempt)
      assert log =~ ~r/retention deleted 1 rows from assessment_attempts\b/
    end
  end

  describe "the rewrite and reorder step" do
    setup ctx do
      for n <- 1..6, do: answer!(ctx, n)
      :ok
    end

    test "keeps the values of every anonymous row and participation marker" do
      before = snapshot()
      assert Enum.all?(before, &(length(&1) >= 6))

      run!()

      assert snapshot() == before
    end

    test "orders each table physically by its primary key" do
      run!()

      for table <- @clustered do
        assert ids_in(table, "ctid") == ids_in(table, "id"), table
      end
    end

    test "gives all rows of a table one transaction id that no row carried before the run and no participation marker shares" do
      # record_once/3 writes an anonymous row and its marker in one
      # transaction, so before the run they share the transaction id.
      for table <- @anonymous do
        refute MapSet.disjoint?(
                 MapSet.new(xmins(table)),
                 MapSet.new(xmins("participation_markers"))
               )
      end

      before = MapSet.new(Enum.flat_map(@clustered, &xmins/1))

      run!()

      # In production, each UPDATE commits in a transaction of its own. In
      # the sandbox, the job runs inside the transaction of the test, where
      # each statement writes with a subtransaction id of its own.
      for table <- @clustered do
        assert [xmin] = xmins(table), table
        refute xmin in before, table
      end

      [marker_xmin] = xmins("participation_markers")
      for table <- @anonymous, do: refute(marker_xmin in xmins(table), table)
    end
  end
end

defmodule Espalier.Insights.RetentionWorkerLockTest do
  @moduledoc """
  Task 0014, step 10: `Espalier.Insights.RetentionWorker` deletes the old
  assessment attempts of a user only once it holds the evaluation lock of
  the user (`Espalier.Credentials.lock_evaluation!/1`), so that the
  deletion sees a credential that a running evaluation issues and keeps the
  attempt that the credential depends on.

  The SQL sandbox serves every process of a test through one connection,
  so it cannot show a lock wait. As in `Espalier.Credentials.LockOrderTest`,
  each transaction runs on a connection of its own through
  `Ecto.Adapters.SQL.Sandbox.unboxed_run/2`, the rows are committed and
  deleted again on exit, and the module is synchronous, so no sandboxed
  test sees them. The job runs its reorder step on these connections as
  well.

  The scenario: a learner has an old passed attempt of an exam that an
  `assessment_passed` requirement names, an old failed attempt and no
  credential, and another learner has an old failed attempt. A transaction
  in place of an evaluation takes the lock of the learner and issues the
  credential. The job starts and waits for the lock; then the transaction
  commits. The job keeps the passed attempt and deletes both failed ones.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Espalier.Accounts.User
  alias Espalier.{AccountsFixtures, Credentials, CredentialsFixtures, Repo}
  alias Espalier.Catalog.{Assessment, Program, Qualification, Requirement}
  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Insights.RetentionWorker
  alias Espalier.Learning.{AssessmentAttempt, Enrollment}

  # How long the test waits for the job to reach its lock wait.
  @wait_ms 5_000

  # A lock wait of another session on the evaluation lock of a user, in
  # the database of this session: the two-key form of the advisory lock
  # stores its keys in classid and objid, with objsubid 2.
  @waiting_sql """
  SELECT count(*) FROM pg_locks
  WHERE locktype = 'advisory' AND NOT granted
    AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND classid = 13 AND objid = hashtext($1)::oid AND objsubid = 2
  """

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  setup do
    previous = Application.fetch_env(:espalier, :insights)

    Application.put_env(
      :espalier,
      :insights,
      :espalier
      |> Application.get_env(:insights, [])
      |> Keyword.merge(
        retention_item_responses_days: nil,
        retention_anonymous_days: nil,
        retention_audit_days: nil,
        retention_attempts_days: 30
      )
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, :insights, value)
        :error -> Application.delete_env(:espalier, :insights)
      end
    end)

    data = unboxed(&insert_scenario!/0)
    on_exit(fn -> unboxed(fn -> delete_scenario!(data) end) end)
    data
  end

  defp insert_scenario! do
    suffix = System.unique_integer([:positive])
    now = DateTime.utc_now(:second)
    old = DateTime.add(now, -90, :day)

    program =
      Repo.insert!(%Program{
        slug: "retention-lock-#{suffix}",
        title: "Retention lock",
        locale: "en",
        status: :published,
        pack_version: "1.0.0"
      })

    module =
      Repo.insert!(%CatalogModule{program_id: program.id, number: 1, title: "Module 1"})

    exam =
      Repo.insert!(%Assessment{
        program_id: program.id,
        module_id: module.id,
        key: "exam",
        title: "Exam",
        kind: :exam
      })

    qualification =
      Repo.insert!(%Qualification{
        program_id: program.id,
        code: "basics",
        title: "Basics",
        audience: "Everyone",
        unlocks: ["A task"],
        add_on: false,
        validity_kind: :months,
        validity_months: 12,
        refresher_mode: :update_unit
      })

    Repo.insert!(%Requirement{
      qualification_id: qualification.id,
      kind: :assessment_passed,
      target_key: exam.key
    })

    learner = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    attempt = attempt_fn(program, exam, now)

    %{
      program: program,
      module: module,
      exam: exam,
      qualification: qualification,
      users: [learner, other],
      learner: learner,
      passed: attempt.(learner, :passed, old, 1),
      failed: attempt.(learner, :failed_errors, DateTime.add(old, 1, :day), 2),
      other_failed: attempt.(other, :failed_errors, old, 1)
    }
  end

  # A function that inserts an attempt of a user at the exam, enrolling the
  # user on the first call.
  defp attempt_fn(program, exam, now) do
    fn user, outcome, submitted_at, number ->
      enrollment =
        Repo.get_by(Enrollment, user_id: user.id, program_id: program.id) ||
          Repo.insert!(%Enrollment{
            user_id: user.id,
            program_id: program.id,
            path: :short,
            started_at: now
          })

      Repo.insert!(%AssessmentAttempt{
        enrollment_id: enrollment.id,
        assessment_id: exam.id,
        user_id: user.id,
        number: number,
        wrong_count: if(outcome == :passed, do: 0, else: 3),
        core_failed: false,
        outcome: outcome,
        submitted_at: submitted_at
      })
    end
  end

  # Deleting the users removes their enrollments, attempts and credentials.
  defp delete_scenario!(data) do
    user_ids = Enum.map(data.users, & &1.id)
    Repo.delete_all(from u in User, where: u.id in ^user_ids)
    Repo.delete_all(from q in Qualification, where: q.id == ^data.qualification.id)
    Repo.delete_all(from a in Assessment, where: a.id == ^data.exam.id)
    Repo.delete_all(from m in CatalogModule, where: m.id == ^data.module.id)
    Repo.delete_all(from p in Program, where: p.id == ^data.program.id)
  end

  defp exists?(%AssessmentAttempt{id: id}),
    do: unboxed(fn -> Repo.exists?(from a in AssessmentAttempt, where: a.id == ^id) end)

  # Polls pg_locks until a session waits for the evaluation lock of the
  # user, and returns false when none does within @wait_ms.
  defp await_lock_wait(user_id, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + @wait_ms
    %{rows: [[waiting]]} = unboxed(fn -> Repo.query!(@waiting_sql, [user_id]) end)

    cond do
      waiting > 0 ->
        true

      System.monotonic_time(:millisecond) > deadline ->
        false

      true ->
        Process.sleep(20)
        await_lock_wait(user_id, deadline)
    end
  end

  test "the deletion of the attempts waits for the evaluation lock and keeps the attempt of the credential issued meanwhile",
       data do
    parent = self()

    evaluation =
      Task.async(fn ->
        unboxed(fn ->
          Repo.transact(fn ->
            :ok = Credentials.lock_evaluation!(data.learner.id)
            credential = CredentialsFixtures.credential_fixture(data.learner, data.qualification)
            send(parent, :issued)

            receive do
              :commit -> {:ok, credential}
            end
          end)
        end)
      end)

    assert_receive :issued, 5_000

    job = Task.async(fn -> unboxed(fn -> RetentionWorker.perform(%Oban.Job{}) end) end)

    assert await_lock_wait(data.learner.id)
    assert exists?(data.passed)
    assert exists?(data.failed)
    assert Task.yield(job, 0) == nil

    send(evaluation.pid, :commit)
    assert {:ok, _credential} = Task.await(evaluation, 10_000)
    assert :ok = Task.await(job, 15_000)

    assert exists?(data.passed)
    refute exists?(data.failed)
    refute exists?(data.other_failed)
  end
end
