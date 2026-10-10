defmodule Espalier.LearningTest do
  # put_setting/2 changes :learning for the node.
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures
  import Espalier.LearningFixtures
  import EspalierWeb.ConnCase, only: [put_setting: 2]

  alias Espalier.Insights.ItemStat
  alias Espalier.Learning
  alias Espalier.Learning.{AssessmentAttempt, Enrollment, ItemResponse, ModuleCompletion}

  setup do
    put_setting(:learning, tracking_detail: :minimal, insights_org_unit: false)
    program = publish_demo!()
    scope = scope_for(user_fixture())
    %{program: program, scope: scope}
  end

  defp standard!, do: put_setting(:learning, tracking_detail: :standard, insights_org_unit: false)

  defp respond(scope, item, answer), do: Learning.respond(scope, item.id, cast_answer(answer))

  defp submit(scope, exam, answers) do
    Learning.submit_attempt(
      scope,
      exam.id,
      Map.new(answers, fn {id, a} -> {id, cast_answer(a)} end)
    )
  end

  defp stats(item), do: Repo.all(from s in ItemStat, where: s.item_id == ^item.id)

  describe "enroll/3 and update_path/3" do
    test "creates the enrollment once and keeps a manual path", %{program: program, scope: scope} do
      assert {:ok, :created, enrollment} = Learning.enroll(scope, demo_slug(), "short")
      assert enrollment.path == :short
      refute enrollment.path_chosen_manually
      assert enrollment.started_at
      assert enrollment.program_id == program.id

      assert {:ok, :existing, again} = Learning.enroll(scope, demo_slug(), "full")
      assert again.id == enrollment.id
      assert again.path == :full

      assert {:ok, manual} = Learning.update_path(scope, enrollment.id, "short")
      assert manual.path_chosen_manually

      assert {:ok, :existing, kept} = Learning.enroll(scope, demo_slug(), "full")
      assert kept.path == :short
      assert Repo.aggregate(Enrollment, :count) == 1
    end

    test "a program that is not published answers not_found", %{program: program, scope: scope} do
      program |> Ecto.Changeset.change(status: :archived) |> Repo.update!()
      assert Learning.enroll(scope, demo_slug(), "short") == {:error, :not_found}
      assert Learning.enroll(scope, "unknown-program", "short") == {:error, :not_found}
    end

    test "the enrollment of another user answers not_found", %{scope: scope} do
      enrollment = enroll!(scope)
      other = scope_for(user_fixture())

      assert Learning.update_path(other, enrollment.id, "full") == {:error, :not_found}
      assert Repo.reload!(enrollment).path == :short
    end
  end

  describe "respond/3" do
    setup %{program: program, scope: scope} do
      %{enrollment: enroll!(scope), item: item!(program, "m1-how-models-write")}
    end

    test "with minimal, increments item_stats and stores no item response",
         %{scope: scope, item: item} do
      assert {:ok, %{correct: true, reveals: []}} = respond(scope, item, correct_answer(item))

      assert {:ok, %{correct: false, reveals: [_lesson]}} =
               respond(scope, item, wrong_answer(item))

      assert [%ItemStat{attempts: 2, correct: 1, org_unit: nil, period: period}] = stats(item)
      assert period == Date.beginning_of_month(Date.utc_today())
      assert Repo.aggregate(ItemResponse, :count) == 0
    end

    test "with standard, also stores the correctness with the next attempt number",
         %{scope: scope, item: item, enrollment: enrollment} do
      standard!()

      assert {:ok, %{correct: false}} = respond(scope, item, wrong_answer(item))
      assert {:ok, %{correct: true}} = respond(scope, item, correct_answer(item))

      responses =
        Repo.all(from r in ItemResponse, where: r.item_id == ^item.id, order_by: r.attempt_no)

      today = Date.utc_today()

      assert [
               %{attempt_no: 1, correct: false, answered_on: ^today},
               %{attempt_no: 2, correct: true, answered_on: ^today}
             ] = responses

      assert Enum.all?(responses, &(&1.enrollment_id == enrollment.id))
      assert Enum.all?(responses, &(&1.user_id == scope.user.id))
      assert [%ItemStat{attempts: 2, correct: 1}] = stats(item)
    end

    test "a poll increments attempts only and stores no item response",
         %{program: program, scope: scope} do
      standard!()
      poll = item!(program, "m1-first-task-poll")

      assert {:ok, %{correct: nil, option_feedback: []}} =
               respond(scope, poll, correct_answer(poll))

      assert [%ItemStat{attempts: 1, correct: 0}] = stats(poll)
      assert Repo.aggregate(ItemResponse, :count) == 0
    end

    test "the org unit reaches item_stats only with INSIGHTS_ORG_UNIT=true", %{item: item} do
      user = user_fixture() |> Ecto.Changeset.change(org_unit: "Unit A") |> Repo.update!()
      scope = scope_for(user)
      enroll!(scope)

      assert {:ok, _result} = respond(scope, item, correct_answer(item))
      assert [%ItemStat{org_unit: nil}] = stats(item)

      put_setting(:learning, tracking_detail: :minimal, insights_org_unit: true)
      assert {:ok, _result} = respond(scope, item, correct_answer(item))

      assert stats(item) |> Enum.map(&{&1.org_unit, &1.attempts}) |> Enum.sort() ==
               [{nil, 1}, {"Unit A", 1}]
    end

    test "the org unit of a counter is trimmed and cut to 255 code points", %{item: item} do
      put_setting(:learning, tracking_detail: :minimal, insights_org_unit: true)
      long = String.duplicate("ä", 300)

      for org_unit <- ["  " <> long <> "  ", "   ", "Unit\u0000B"] do
        user = user_fixture() |> Ecto.Changeset.change(org_unit: org_unit) |> Repo.update!()
        scope = scope_for(user)
        enroll!(scope)
        assert {:ok, _result} = respond(scope, item, correct_answer(item))
      end

      assert stats(item) |> Enum.map(&{&1.org_unit, &1.attempts}) |> Enum.sort() ==
               [{nil, 2}, {String.duplicate("ä", 255), 1}]
    end

    test "answers of users without an org unit share one counter",
         %{scope: scope, item: item} do
      other = scope_for(user_fixture())
      enroll!(other)

      assert {:ok, _result} = respond(scope, item, correct_answer(item))
      assert {:ok, _result} = respond(other, item, wrong_answer(item))
      assert [%ItemStat{attempts: 2, correct: 1, org_unit: nil}] = stats(item)
    end

    test "an exam item answers not_found and counts nothing", %{program: program, scope: scope} do
      item = item!(program, "m1-exam-check-claims")
      assert respond(scope, item, correct_answer(item)) == {:error, :not_found}
      assert stats(item) == []
    end

    test "a user without an enrollment answers not_enrolled", %{item: item} do
      scope = scope_for(user_fixture())
      assert respond(scope, item, correct_answer(item)) == {:error, :not_enrolled}
      assert stats(item) == []
    end

    test "an answer that does not fit the item answers invalid_answer",
         %{scope: scope, item: item} do
      for answer <- [
            %{"options" => ["no-such-option"]},
            %{"slots" => %{"task" => "task-clear"}},
            %{"options" => ["likely-words"], "initials" => "AB"},
            %{}
          ] do
        assert respond(scope, item, answer) == {:error, :invalid_answer}, inspect(answer)
      end

      assert stats(item) == []
    end

    test "every kind of the demo pack is evaluated", %{program: program, scope: scope} do
      for key <- [
            "m2-prompt-builder",
            "m2-judge-drafts",
            "m2-release-drill",
            "m1-why-answers-vary"
          ] do
        item = item!(program, key)
        assert {:ok, %{correct: true}} = respond(scope, item, correct_answer(item)), key
        assert {:ok, %{correct: false}} = respond(scope, item, wrong_answer(item)), key
      end
    end
  end

  describe "submit_attempt/3" do
    setup %{program: program, scope: scope} do
      %{enrollment: enroll!(scope), exam: assessment!(program)}
    end

    test "applies the pass rule to the demo exam", %{scope: scope, exam: exam} do
      assert {:ok, %AssessmentAttempt{outcome: :failed_core, core_failed: true, wrong_count: 1},
              _results} = submit(scope, exam, exam_answers(exam, ["m1-exam-check-claims"]))

      assert {:ok, %AssessmentAttempt{outcome: :passed, core_failed: false, wrong_count: 1},
              _results} = submit(scope, exam, exam_answers(exam, ["m1-exam-next-word"]))

      assert {:ok, %AssessmentAttempt{outcome: :failed_errors, wrong_count: 2}, _results} =
               submit(
                 scope,
                 exam,
                 exam_answers(exam, ["m1-exam-next-word", "m1-exam-varying-answers"])
               )

      numbers = Repo.all(from a in AssessmentAttempt, order_by: a.number, select: a.number)
      assert numbers == [1, 2, 3]
    end

    test "returns the evaluation per item in exam order", %{scope: scope, exam: exam} do
      assert {:ok, attempt, results} = submit(scope, exam, exam_answers(exam))
      assert attempt.outcome == :passed

      assert Enum.map(results, fn {item, _result} -> item.id end) ==
               Enum.map(exam_items!(exam), & &1.id)

      assert Enum.all?(results, fn {_item, result} -> result.correct == true end)
    end

    test "a missing or unknown item id answers incomplete", %{scope: scope, exam: exam} do
      answers = exam_answers(exam)
      [first | _] = Map.keys(answers)

      assert submit(scope, exam, Map.delete(answers, first)) == {:error, {:answers, "incomplete"}}

      assert submit(scope, exam, Map.put(answers, Ecto.UUID.generate(), %{"options" => []})) ==
               {:error, {:answers, "incomplete"}}

      assert submit(scope, exam, Map.put(answers, first, %{"options" => ["nope"]})) ==
               {:error, {:answers, "invalid"}}

      assert Repo.aggregate(AssessmentAttempt, :count) == 0
    end

    test "only live exams accept attempts", %{scope: scope, exam: exam} do
      assert submit(scope, %{id: Ecto.UUID.generate()}, %{}) == {:error, :not_found}
      exam |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update!()
      assert submit(scope, exam, exam_answers(exam)) == {:error, :not_found}
    end

    test "a user without an enrollment answers not_enrolled", %{exam: exam} do
      scope = scope_for(user_fixture())
      assert submit(scope, exam, exam_answers(exam)) == {:error, :not_enrolled}
    end
  end

  describe "complete_module/2" do
    setup %{scope: scope} do
      %{enrollment: enroll!(scope)}
    end

    test "module 1 completes only after a passed exam", %{program: program, scope: scope} do
      module = module!(program, 1)
      exam = assessment!(program)

      assert {:error, {:assessments_open, [open]}} = Learning.complete_module(scope, module.id)
      assert open.id == exam.id

      assert {:ok, %{outcome: :failed_core}, _results} =
               submit(scope, exam, exam_answers(exam, ["m1-exam-check-claims"]))

      assert {:error, {:assessments_open, [_open]}} = Learning.complete_module(scope, module.id)

      assert {:ok, %{outcome: :passed}, _results} = submit(scope, exam, exam_answers(exam))
      assert {:ok, %ModuleCompletion{} = completion} = Learning.complete_module(scope, module.id)
      assert {:ok, ^completion} = Learning.complete_module(scope, module.id)
      assert Repo.aggregate(ModuleCompletion, :count) == 1
    end

    test "a module without an exam completes at once", %{program: program, scope: scope} do
      assert {:ok, %ModuleCompletion{}} = Learning.complete_module(scope, module!(program, 2).id)
    end

    test "a passed attempt of another user does not count", %{program: program, scope: scope} do
      other = scope_for(user_fixture())
      enroll!(other)
      exam = assessment!(program)
      assert {:ok, %{outcome: :passed}, _results} = submit(other, exam, exam_answers(exam))

      assert {:error, {:assessments_open, [_open]}} =
               Learning.complete_module(scope, module!(program, 1).id)
    end
  end

  describe "progress/2" do
    test "reports per exam passed when any attempt passed, otherwise the latest outcome",
         %{program: program, scope: scope} do
      enroll!(scope)
      exam = assessment!(program)

      submit(scope, exam, exam_answers(exam, ["m1-exam-check-claims"]))
      assert {:ok, %{exams: [%{outcome: :failed_core}]}} = Learning.progress(scope, demo_slug())

      submit(scope, exam, exam_answers(exam, ["m1-exam-next-word", "m1-exam-varying-answers"]))
      assert {:ok, %{exams: [%{outcome: :failed_errors}]}} = Learning.progress(scope, demo_slug())

      submit(scope, exam, exam_answers(exam))
      submit(scope, exam, exam_answers(exam, ["m1-exam-check-claims"]))

      assert {:ok, %{exams: [%{assessment_id: id, outcome: :passed}]} = progress} =
               Learning.progress(scope, demo_slug())

      assert id == exam.id
      refute Map.has_key?(progress, :answered_item_ids)
    end

    test "with standard, lists the answered items", %{program: program, scope: scope} do
      standard!()
      enroll!(scope)
      item = item!(program, "m1-how-models-write")
      respond(scope, item, wrong_answer(item))

      assert {:ok, %{answered_item_ids: [id]}} = Learning.progress(scope, demo_slug())
      assert id == item.id
    end
  end
end
