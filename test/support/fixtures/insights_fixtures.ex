defmodule Espalier.InsightsFixtures do
  @moduledoc """
  Test helpers for the anonymous insights of task 0014: rows of the
  anonymous tables inserted directly, so that a report test controls the
  months, the org units and the counts, and the settings of
  `config :espalier, :insights` and `:learning` for one test.

  A module that calls `put_insights/1` or `put_learning/1` changes global
  application settings and sets `async: false`.
  """

  alias Espalier.Insights.{FeedbackResponse, InterestVote, ItemStat, SelfAssessmentResponse}
  alias Espalier.Repo

  @doc """
  Inserts an `item_stats` row for `item` in the month of `period` with the
  given counts. `opts[:org_unit]` sets the org unit (default `nil`).
  """
  def item_stat!(item, period, attempts, correct, opts \\ []) do
    %ItemStat{
      item_id: item.id,
      period: Date.beginning_of_month(period),
      org_unit: Keyword.get(opts, :org_unit),
      attempts: attempts,
      correct: correct
    }
    |> ItemStat.changeset()
    |> Repo.insert!()
  end

  @doc """
  Inserts `count` self-assessment rows of `program` for the segment
  `segment_key`, recorded on `recorded_on` (default today).
  `opts[:org_unit]` sets the org unit (default `nil`).
  """
  def self_assessment_rows!(program, segment_key, count, opts \\ []) do
    for _ <- 1..count//1 do
      %SelfAssessmentResponse{
        program_id: program.id,
        segment_key: segment_key,
        org_unit: Keyword.get(opts, :org_unit),
        recorded_on: Keyword.get(opts, :recorded_on, Date.utc_today())
      }
      |> SelfAssessmentResponse.changeset()
      |> Repo.insert!()
    end
  end

  @doc "Inserts `count` \"would use\" votes for `format`, recorded on `opts[:recorded_on]`."
  def vote_rows!(format, count, opts \\ []) do
    for _ <- 1..count//1 do
      %InterestVote{
        companion_format_id: format.id,
        choice: :would_use,
        recorded_on: Keyword.get(opts, :recorded_on, Date.utc_today())
      }
      |> InterestVote.changeset()
      |> Repo.insert!()
    end
  end

  @doc "Inserts one feedback row of `program` with `answers` (string keys)."
  def feedback_row!(program, answers, opts \\ []) do
    %FeedbackResponse{
      program_id: program.id,
      answers: answers,
      recorded_on: Keyword.get(opts, :recorded_on, Date.utc_today())
    }
    |> FeedbackResponse.changeset()
    |> Repo.insert!()
  end

  @doc """
  Merges `settings` into `config :espalier, :insights` for one test and
  restores the previous value on exit, for example
  `put_insights(min_group_size: 2, feedback_free_text: true)`.
  """
  def put_insights(settings), do: put_merged(:insights, settings)

  @doc """
  Merges `settings` into `config :espalier, :learning` for one test and
  restores the previous value on exit, for example
  `put_learning(insights_org_unit: true)`.
  """
  def put_learning(settings), do: put_merged(:learning, settings)

  defp put_merged(key, settings) do
    previous = Application.fetch_env(:espalier, key)
    current = Application.get_env(:espalier, key, [])
    Application.put_env(:espalier, key, Keyword.merge(current, settings))

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, key, value)
        :error -> Application.delete_env(:espalier, key)
      end
    end)
  end
end
