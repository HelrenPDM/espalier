defmodule EspalierWeb.LearningJSON do
  @moduledoc """
  Views of the learner's own records and of evaluation results. Every view
  names its members explicitly; `docs/security/authentication.md`
  (section "Learner data access") lists them per route.
  """

  alias Espalier.Learning.{AssessmentAttempt, Enrollment, ModuleCompletion}

  @doc "Renders an enrollment (schema `EnrollmentView`)."
  def enrollment(%{enrollment: %Enrollment{} = enrollment}) do
    %{
      id: enrollment.id,
      program_id: enrollment.program_id,
      path: enrollment.path,
      path_chosen_manually: enrollment.path_chosen_manually,
      started_at: enrollment.started_at
    }
  end

  @doc "Renders the evaluation of an answer (schema `ItemResult`)."
  def item_result(%{item_id: item_id, result: result}) do
    %{
      item_id: item_id,
      correct: result.correct,
      option_feedback: result.option_feedback,
      rules: result.rules,
      reveals: result.reveals
    }
  end

  @doc "Renders an exam attempt with the evaluation per item (schema `AttemptResult`)."
  def attempt(%{attempt: %AssessmentAttempt{} = attempt, results: results}) do
    %{
      id: attempt.id,
      assessment_id: attempt.assessment_id,
      number: attempt.number,
      outcome: attempt.outcome,
      wrong_count: attempt.wrong_count,
      core_failed: attempt.core_failed,
      submitted_at: attempt.submitted_at,
      results:
        Enum.map(results, fn {item, result} ->
          item_result(%{item_id: item.id, result: result})
        end)
    }
  end

  @doc "Renders a module completion (schema `ModuleCompletionView`)."
  def completion(%{completion: %ModuleCompletion{} = completion}) do
    %{module_id: completion.module_id, completed_at: completion.completed_at}
  end

  @doc "Renders the open exams of a module (schema `AssessmentsOpenError`)."
  def assessments_open(%{assessments: assessments}) do
    %{
      error: "assessments_open",
      assessments: Enum.map(assessments, &%{id: &1.id, key: &1.key, title: &1.title})
    }
  end

  @doc "Renders the progress of the learner (schema `Progress`)."
  def progress(%{progress: progress}) do
    rendered = %{
      enrollment:
        progress.enrollment &&
          %{
            id: progress.enrollment.id,
            path: progress.enrollment.path,
            path_chosen_manually: progress.enrollment.path_chosen_manually
          },
      completed_module_ids: progress.completed_module_ids,
      exams: progress.exams,
      objectives: progress.objectives
    }

    case Map.fetch(progress, :answered_item_ids) do
      {:ok, ids} -> Map.put(rendered, :answered_item_ids, ids)
      :error -> rendered
    end
  end
end
