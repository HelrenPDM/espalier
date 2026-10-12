defmodule Espalier.Insights.RetentionWorker do
  @moduledoc """
  The nightly retention job (README section 10, task 0014, step 10): the
  crontab of `config :espalier, Oban` runs it at 03:30 UTC.

  Each retention variable of `config :espalier, :insights` that is set
  deletes the rows older than its limit in days, and an unset one leaves
  its tables untouched, so no record is deleted until an operator sets the
  periods that the GDPR workstream decides:

  | Variable | Table | Column |
  |---|---|---|
  | `RETENTION_ITEM_RESPONSES_DAYS` | `item_responses` | `answered_on` |
  | `RETENTION_ANONYMOUS_DAYS` | `self_assessment_responses`, `interest_votes`, `feedback_responses` | `recorded_on` |
  | `RETENTION_AUDIT_DAYS` | `audit_events` | `at` |
  | `RETENTION_ATTEMPTS_DAYS` | `assessment_attempts` | `submitted_at` |

  A row is older than the limit when its date lies before today minus the
  limit, or its timestamp before now minus the limit. The attempts keep the
  newest passed attempt per user and assessment that an `assessment_passed`
  requirement of an `active` or `refresh_due` credential depends on. The
  job deletes the attempts per user: for each user with an attempt older
  than the limit, one transaction takes the lock of
  `Espalier.Credentials.lock_evaluation!/1`, which every evaluation of the
  user takes as well, and then deletes the old attempts of the user except
  the kept ones. A running evaluation therefore ends before the deletion,
  and the deletion, a statement of its own after the lock, sees the
  credential that the evaluation committed and keeps the attempt that the
  credential depends on.

  The job logs the deleted count per table and `unset` for each variable
  without a value. Afterwards, on every run and whatever the settings, it
  reorders the three anonymous tables and `participation_markers`. An
  anonymous row and its participation marker are written in one
  transaction (`Espalier.Insights.record_once/3`), so they carry the same
  transaction id (`xmin`), the id of a marker tells when it was written,
  and the physical order of a table follows the order of the inserts. Per
  table, one `UPDATE` first gives every row a new version, so that all
  rows of the table carry the transaction id of that `UPDATE`, and then
  `CLUSTER <table> USING <table>_pkey` writes the table anew in the order
  of its random keys and drops the earlier versions. The two statements
  run outside a transaction, so each commits on its own: `CLUSTER` keeps
  the transaction id of every row it copies, and in the transaction of the
  `UPDATE` it would also copy the earlier versions, with their original
  ids, because their deletion is still in progress.

  The reorder leaves three traces of the original order and ids. `CLUSTER`
  copies the earlier versions that a snapshot older than the `UPDATE`, such
  as the snapshot of a report that was running, can still see, and they
  stay in the table until a later vacuum removes them. The write-ahead log
  holds the original inserts with their transaction ids until PostgreSQL
  recycles its segments. A WAL archive or a backup taken before the run
  holds them for as long as it is kept.
  """
  use Oban.Worker, queue: :default

  import Ecto.Query

  require Logger

  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.{Assessment, Qualification, Requirement}
  alias Espalier.Credentials
  alias Espalier.Credentials.Credential
  alias Espalier.Insights
  alias Espalier.Insights.{FeedbackResponse, InterestVote, SelfAssessmentResponse}
  alias Espalier.Learning.{AssessmentAttempt, ItemResponse}
  alias Espalier.Repo

  @anonymous [
    {"self_assessment_responses", SelfAssessmentResponse},
    {"interest_votes", InterestVote},
    {"feedback_responses", FeedbackResponse}
  ]

  # The statements of the reorder step per table, as literals.
  @reorder [
    {"UPDATE self_assessment_responses SET recorded_on = recorded_on",
     "CLUSTER self_assessment_responses USING self_assessment_responses_pkey"},
    {"UPDATE interest_votes SET recorded_on = recorded_on",
     "CLUSTER interest_votes USING interest_votes_pkey"},
    {"UPDATE feedback_responses SET recorded_on = recorded_on",
     "CLUSTER feedback_responses USING feedback_responses_pkey"},
    {"UPDATE participation_markers SET subject_id = subject_id",
     "CLUSTER participation_markers USING participation_markers_pkey"}
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    settings = Insights.settings()
    today = Date.utc_today()
    now = DateTime.utc_now(:second)

    with_limit(
      settings,
      :retention_item_responses_days,
      "RETENTION_ITEM_RESPONSES_DAYS",
      fn days ->
        cutoff = Date.add(today, -days)
        delete("item_responses", from(r in ItemResponse, where: r.answered_on < ^cutoff))
      end
    )

    with_limit(settings, :retention_anonymous_days, "RETENTION_ANONYMOUS_DAYS", fn days ->
      cutoff = Date.add(today, -days)

      for {table, schema} <- @anonymous do
        delete(table, from(r in schema, where: r.recorded_on < ^cutoff))
      end
    end)

    with_limit(settings, :retention_audit_days, "RETENTION_AUDIT_DAYS", fn days ->
      cutoff = DateTime.add(now, -days, :day)
      delete("audit_events", from(e in AuditEvent, where: e.at < ^cutoff))
    end)

    with_limit(settings, :retention_attempts_days, "RETENTION_ATTEMPTS_DAYS", fn days ->
      delete_attempts(DateTime.add(now, -days, :day))
    end)

    for {rewrite, cluster} <- @reorder, do: reorder!(rewrite, cluster)

    :ok
  end

  defp with_limit(settings, key, name, fun) do
    case Keyword.get(settings, key) do
      days when is_integer(days) and days > 0 -> fun.(days)
      _unset -> Logger.info("retention #{name} unset")
    end
  end

  defp delete(table, query) do
    {count, _rows} = Repo.delete_all(query)
    Logger.info("retention deleted #{count} rows from #{table}")
  end

  # Deletes the attempts submitted before `cutoff` per user and logs their
  # total count.
  defp delete_attempts(cutoff) do
    user_ids =
      Repo.all(
        from a in AssessmentAttempt,
          where: a.submitted_at < ^cutoff,
          distinct: true,
          select: a.user_id
      )

    count = user_ids |> Enum.map(&delete_attempts(&1, cutoff)) |> Enum.sum()
    Logger.info("retention deleted #{count} rows from assessment_attempts")
  end

  # Deletes the attempts of one user submitted before `cutoff`, except the
  # kept ones, and returns their count. The DELETE runs after the evaluation
  # lock of the user as a statement of its own, so under READ COMMITTED its
  # snapshot holds every credential that an evaluation committed before the
  # lock was granted.
  defp delete_attempts(user_id, cutoff) do
    {:ok, count} =
      Repo.transact(fn ->
        :ok = Credentials.lock_evaluation!(user_id)

        {count, _rows} =
          Repo.delete_all(
            from a in AssessmentAttempt,
              where: a.user_id == ^user_id and a.submitted_at < ^cutoff,
              where: a.id not in subquery(kept_attempts(user_id))
          )

        {:ok, count}
      end)

    count
  end

  # The ids of the user's newest passed attempt per assessment for every
  # assessment that an `assessment_passed` requirement of a qualification
  # names (by key in the program of the qualification), where the user
  # holds a credential of that qualification in force.
  defp kept_attempts(user_id) do
    in_force = Credential.in_force_statuses()

    from a in AssessmentAttempt,
      join: s in Assessment,
      on: s.id == a.assessment_id,
      join: r in Requirement,
      on: r.kind == :assessment_passed and r.target_key == s.key,
      join: q in Qualification,
      on: q.id == r.qualification_id and q.program_id == s.program_id,
      join: c in Credential,
      on: c.qualification_id == q.id and c.user_id == a.user_id,
      where: a.user_id == ^user_id and a.outcome == :passed and c.status in ^in_force,
      distinct: a.assessment_id,
      order_by: [a.assessment_id, desc: a.submitted_at, desc: a.number],
      select: a.id
  end

  # Gives every row of the table a new tuple version and then orders the
  # table by its random primary key. The two statements run outside a
  # transaction, so that each commits on its own: in one transaction,
  # CLUSTER would copy the versions that the UPDATE deleted, with their
  # original transaction ids, and on participation_markers its
  # ACCESS EXCLUSIVE lock would wait for a record_once/3 whose
  # INSERT ... ON CONFLICT DO NOTHING waits for the UPDATE, a deadlock. In
  # the test sandbox, both run inside the transaction of the test.
  # reorder!/2 receives only the literal statements of @reorder; no input
  # reaches the SQL.
  # sobelow_skip ["SQL.Query"]
  defp reorder!(rewrite, cluster) do
    Repo.query!(rewrite)
    Repo.query!(cluster)
    :ok
  end
end
