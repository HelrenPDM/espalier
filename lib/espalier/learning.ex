defmodule Espalier.Learning do
  @moduledoc """
  The Learning context: enrollment and path, item evaluation, exam attempts,
  module completion and the progress of the signed-in learner (README
  section 7, domain rules 1 to 5 and 15).

  Every function takes the scope as its first argument and reads and writes
  the person-linked rows only through the scope user. `TRACKING_DETAIL`
  (`config :espalier, :learning`) decides whether practice answers create
  `ItemResponse` rows; `INSIGHTS_ORG_UNIT` decides whether the anonymous
  item statistics carry the user's org unit (README section 10). No answer
  is stored, and no table stores a status per objective and person.
  """

  import Ecto.Query, warn: false
  alias Ecto.Changeset
  alias Espalier.Accounts.Scope
  alias Espalier.Catalog
  alias Espalier.Catalog.Program
  alias Espalier.Credentials
  alias Espalier.Insights

  alias Espalier.Learning.{
    AssessmentAttempt,
    Enrollment,
    Evaluator,
    ItemResponse,
    ModuleCompletion,
    ObjectiveStatus,
    PassRule
  }

  alias Espalier.Repo

  @doc "The value of `TRACKING_DETAIL`: `:minimal` (default) or `:standard`."
  @spec tracking_detail() :: :minimal | :standard
  def tracking_detail do
    :espalier |> Application.get_env(:learning, []) |> Keyword.get(:tracking_detail, :minimal)
  end

  @doc "True with `INSIGHTS_ORG_UNIT=true`."
  @spec insights_org_unit?() :: boolean()
  def insights_org_unit? do
    :espalier |> Application.get_env(:learning, []) |> Keyword.get(:insights_org_unit, false)
  end

  ## Enrollment

  @doc "Returns the enrollment of the scope user in the program, or `nil`."
  def get_enrollment(%Scope{} = scope, program_id) do
    Repo.get_by(Enrollment, user_id: scope.user.id, program_id: program_id)
  end

  @doc """
  Enrolls the scope user in the published program `slug` with `path`.

  Returns `{:ok, :created, enrollment}` for a new enrollment with
  `started_at` set to now. For an existing enrollment it returns
  `{:ok, :existing, enrollment}` and applies `path` only while
  `path_chosen_manually` is false, so that a manual choice stays. Returns
  `{:error, :not_found}` for a program that is not published.
  """
  def enroll(%Scope{} = scope, slug, path) when is_binary(slug) do
    with %Program{} = program <- Catalog.get_published_program(slug) || {:error, :not_found},
         {:ok, {status, enrollment}} <- Repo.transact(fn -> enroll_in(scope, program, path) end) do
      {:ok, status, enrollment}
    end
  end

  defp enroll_in(scope, program, path) do
    existing =
      Repo.one(
        from e in Enrollment,
          where: e.user_id == ^scope.user.id and e.program_id == ^program.id,
          lock: "FOR UPDATE"
      )

    case existing do
      nil ->
        %Enrollment{}
        |> Enrollment.changeset(%{path: path}, scope)
        |> Changeset.put_change(:program_id, program.id)
        |> Changeset.put_change(:started_at, DateTime.utc_now(:second))
        |> Repo.insert()
        |> tag(:created)

      %Enrollment{path_chosen_manually: true} = enrollment ->
        {:ok, {:existing, enrollment}}

      enrollment ->
        enrollment
        |> Enrollment.changeset(%{path: path}, scope)
        |> Repo.update()
        |> tag(:existing)
    end
  end

  defp tag({:ok, value}, status), do: {:ok, {status, value}}
  defp tag({:error, _changeset} = error, _status), do: error

  @doc """
  Sets the path of an enrollment of the scope user and marks it as chosen
  by hand. An enrollment of another user, or of a program that is not
  published, answers `{:error, :not_found}`.
  """
  def update_path(%Scope{} = scope, enrollment_id, path) do
    Repo.transact(fn ->
      enrollment =
        Repo.one(
          from e in Enrollment,
            where: e.id == ^enrollment_id and e.user_id == ^scope.user.id,
            lock: "FOR UPDATE",
            preload: :program
        )

      case enrollment do
        %Enrollment{program: %Program{status: :published}} ->
          enrollment
          |> Enrollment.changeset(%{path: path}, scope)
          |> Changeset.put_change(:path_chosen_manually, true)
          |> Repo.update()

        _missing ->
          {:error, :not_found}
      end
    end)
  end

  ## Practice answers

  @doc """
  Evaluates a practice answer of the scope user and returns the result of
  `Espalier.Learning.Evaluator.evaluate/2`.

  Exam items answer `{:error, :not_found}`, because exam items are evaluated
  only inside an attempt. The user needs an enrollment in the item's program
  (`{:error, :not_enrolled}` otherwise), and an answer that does not fit the
  item answers `{:error, :invalid_answer}`.

  In one transaction, the function counts the answer in the anonymous item
  statistics of the current month and, with `TRACKING_DETAIL=standard` and
  an item other than a poll, inserts an `ItemResponse` with the next
  `attempt_no` and `answered_on` set to today. The answer itself is stored
  nowhere.
  """
  def respond(%Scope{} = scope, item_id, answer) do
    with {:ok, item, false} <- Catalog.learner_item(item_id),
         {:ok, enrollment} <- fetch_enrollment(scope, item.program_id),
         :ok <- Evaluator.validate(item, answer) do
      result = Evaluator.evaluate(item, answer)
      Repo.transact(fn -> record_answer(scope, enrollment, item, result) end)
    else
      {:ok, _item, true} -> {:error, :not_found}
      error -> error
    end
  end

  defp record_answer(scope, enrollment, item, result) do
    lock_enrollment!(enrollment)
    Insights.count_item_answer(item.id, result.correct, stat_org_unit(scope))

    with {:ok, _response} <- maybe_record_response(scope, enrollment, item, result) do
      {:ok, result}
    end
  end

  defp maybe_record_response(scope, enrollment, item, result) do
    if tracking_detail() == :standard and item.kind != :poll do
      attempt_no =
        Repo.one(
          from r in ItemResponse,
            where: r.enrollment_id == ^enrollment.id and r.item_id == ^item.id,
            select: coalesce(max(r.attempt_no), 0)
        ) + 1

      %ItemResponse{}
      |> ItemResponse.changeset(
        %{
          enrollment_id: enrollment.id,
          item_id: item.id,
          correct: result.correct == true,
          attempt_no: attempt_no,
          answered_on: Date.utc_today()
        },
        scope
      )
      |> Repo.insert()
    else
      {:ok, nil}
    end
  end

  defp stat_org_unit(%Scope{user: user}) do
    if insights_org_unit?(), do: Insights.org_unit(user.org_unit)
  end

  ## Exam attempts

  @doc """
  Evaluates an exam attempt of the scope user and stores it with the next
  `number`.

  `answers` maps every item id of the exam to an answer. A missing or
  unknown item id answers `{:error, {:answers, "incomplete"}}`, and an
  answer that does not fit its item `{:error, {:answers, "invalid"}}`.
  Assessments other than live exams answer `{:error, :not_found}`, and a
  user without an enrollment `{:error, :not_enrolled}`.

  Returns `{:ok, attempt, results}` with the evaluator result per item in
  exam order. The attempt row holds no answers. After a passed attempt the
  function calls `Espalier.Credentials.evaluate/2`.
  """
  def submit_attempt(%Scope{} = scope, assessment_id, answers) when is_map(answers) do
    with {:ok, exam, items} <- Catalog.learner_exam(assessment_id),
         {:ok, enrollment} <- fetch_enrollment(scope, exam.program_id),
         :ok <- check_answers(items, answers) do
      results =
        for item <- items, do: {item, Evaluator.evaluate(item, Map.fetch!(answers, item.id))}

      graded = for {item, result} <- results, do: %{core: item.core, correct: result.correct}

      attrs = %{
        enrollment_id: enrollment.id,
        assessment_id: exam.id,
        wrong_count: PassRule.wrong_count(graded),
        core_failed: PassRule.core_failed?(graded),
        outcome: PassRule.evaluate(graded, exam),
        submitted_at: DateTime.utc_now(:second)
      }

      store_attempt(scope, enrollment, exam, attrs, results)
    end
  end

  defp store_attempt(scope, enrollment, exam, attrs, results) do
    with {:ok, attempt} <- Repo.transact(fn -> insert_attempt(scope, enrollment, attrs) end) do
      if attempt.outcome == :passed, do: {:ok, _} = Credentials.evaluate(scope, exam.program)
      {:ok, attempt, results}
    end
  end

  defp check_answers(items, answers) do
    ids = MapSet.new(items, & &1.id)

    cond do
      not MapSet.equal?(ids, answers |> Map.keys() |> MapSet.new()) ->
        {:error, {:answers, "incomplete"}}

      Enum.all?(items, &(Evaluator.validate(&1, Map.fetch!(answers, &1.id)) == :ok)) ->
        :ok

      true ->
        {:error, {:answers, "invalid"}}
    end
  end

  defp insert_attempt(scope, enrollment, attrs) do
    lock_enrollment!(enrollment)

    number =
      Repo.one(
        from a in AssessmentAttempt,
          where: a.enrollment_id == ^enrollment.id and a.assessment_id == ^attrs.assessment_id,
          select: coalesce(max(a.number), 0)
      ) + 1

    %AssessmentAttempt{}
    |> AssessmentAttempt.changeset(Map.put(attrs, :number, number), scope)
    |> Repo.insert()
  end

  ## Module completion

  @doc """
  Completes a module for the scope user.

  Returns `{:ok, completion}` when every live exam of the module with
  `counts_for_credential: true` has a passed attempt of the enrollment; a
  repeated call returns the stored row. Otherwise it returns
  `{:error, {:assessments_open, exams}}` with the open exams. A module that
  is archived or whose program is not published answers
  `{:error, :not_found}`, and a user without an enrollment
  `{:error, :not_enrolled}`. After a new completion the function calls
  `Espalier.Credentials.evaluate/2`.
  """
  def complete_module(%Scope{} = scope, module_id) do
    with {:ok, module} <- Catalog.learner_module(module_id),
         {:ok, enrollment} <- fetch_enrollment(scope, module.program_id),
         {:ok, {status, completion}} <-
           Repo.transact(fn -> complete_in(scope, enrollment, module) end) do
      if status == :created, do: {:ok, _} = Credentials.evaluate(scope, module.program)
      {:ok, completion}
    end
  end

  defp complete_in(scope, enrollment, module) do
    lock_enrollment!(enrollment)

    case Repo.get_by(ModuleCompletion, enrollment_id: enrollment.id, module_id: module.id) do
      %ModuleCompletion{} = stored ->
        {:ok, {:existing, stored}}

      nil ->
        passed = passed_assessment_ids(enrollment)
        open = Enum.reject(Catalog.credential_exams(module.id), &MapSet.member?(passed, &1.id))

        if open == [] do
          %ModuleCompletion{}
          |> ModuleCompletion.changeset(
            %{
              enrollment_id: enrollment.id,
              module_id: module.id,
              completed_at: DateTime.utc_now(:second)
            },
            scope
          )
          |> Repo.insert()
          |> tag(:created)
        else
          {:error, {:assessments_open, open}}
        end
    end
  end

  ## Progress

  @doc """
  Returns the progress of the scope user in the published program `slug`,
  or `{:error, :not_found}`.

  The map holds `enrollment` (or `nil`), `completed_module_ids`, `exams`
  (per assessment with an attempt the outcome `passed` when any attempt
  passed, and otherwise the outcome of the latest attempt), `objectives`
  (`objective_status/2`) and, with `TRACKING_DETAIL=standard` only,
  `answered_item_ids`.
  """
  def progress(%Scope{} = scope, slug) when is_binary(slug) do
    case Catalog.get_published_program(slug) do
      nil ->
        {:error, :not_found}

      program ->
        enrollment = get_enrollment(scope, program.id)

        progress = %{
          enrollment: enrollment,
          completed_module_ids: completed_module_ids(enrollment),
          exams: exam_outcomes(enrollment),
          objectives: objective_status(scope, program)
        }

        progress =
          if tracking_detail() == :standard,
            do: Map.put(progress, :answered_item_ids, answered_item_ids(enrollment)),
            else: progress

        {:ok, progress}
    end
  end

  defp completed_module_ids(nil), do: []

  defp completed_module_ids(enrollment) do
    Repo.all(
      from c in ModuleCompletion,
        where: c.enrollment_id == ^enrollment.id,
        order_by: [c.completed_at, c.module_id],
        select: c.module_id
    )
  end

  defp exam_outcomes(nil), do: []

  defp exam_outcomes(enrollment) do
    Repo.all(
      from a in AssessmentAttempt,
        where: a.enrollment_id == ^enrollment.id,
        order_by: [a.assessment_id, a.number],
        select: {a.assessment_id, a.outcome}
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {assessment_id, outcomes} ->
      outcome = if :passed in outcomes, do: :passed, else: List.last(outcomes)
      %{assessment_id: assessment_id, outcome: outcome}
    end)
    |> Enum.sort_by(& &1.assessment_id)
  end

  defp answered_item_ids(nil), do: []

  defp answered_item_ids(enrollment) do
    Repo.all(
      from r in ItemResponse,
        where: r.enrollment_id == ^enrollment.id,
        distinct: true,
        order_by: r.item_id,
        select: r.item_id
    )
  end

  @doc """
  Derives the status of every live learning objective of `program` for the
  scope user: `evidenced` or `open`, ordered by module number and
  `position` (README section 7, domain rule 15).

  The facts come from the user's own records: the passed exam attempts of
  the enrollment, the attendance certificates of the user
  (`Espalier.Credentials.attended_format_ids/2`) and, with
  `TRACKING_DETAIL=standard` only, the correct item responses of the
  enrollment. Without an enrollment, only attendance counts. No table
  stores the result.
  """
  def objective_status(%Scope{} = scope, %Program{} = program) do
    enrollment = get_enrollment(scope, program.id)

    facts = %{
      passed_assessment_ids: passed_assessment_ids(enrollment),
      attended_format_ids: Credentials.attended_format_ids(scope, program),
      correct_item_ids: correct_item_ids(enrollment)
    }

    program.id |> Catalog.objective_links() |> ObjectiveStatus.derive(facts)
  end

  defp passed_assessment_ids(nil), do: MapSet.new()

  defp passed_assessment_ids(enrollment) do
    Repo.all(
      from a in AssessmentAttempt,
        where: a.enrollment_id == ^enrollment.id and a.outcome == :passed,
        distinct: true,
        select: a.assessment_id
    )
    |> MapSet.new()
  end

  defp correct_item_ids(nil), do: MapSet.new()

  defp correct_item_ids(enrollment) do
    if tracking_detail() == :standard do
      Repo.all(
        from r in ItemResponse,
          where: r.enrollment_id == ^enrollment.id and r.correct,
          distinct: true,
          select: r.item_id
      )
      |> MapSet.new()
    else
      MapSet.new()
    end
  end

  ## Helpers

  defp fetch_enrollment(scope, program_id) do
    case get_enrollment(scope, program_id) do
      nil -> {:error, :not_enrolled}
      enrollment -> {:ok, enrollment}
    end
  end

  # Serializes the writes of one enrollment, so that attempt numbers do not
  # race.
  defp lock_enrollment!(enrollment) do
    Repo.one!(
      from e in Enrollment, where: e.id == ^enrollment.id, lock: "FOR UPDATE", select: e.id
    )
  end
end
