defmodule Espalier.Learning.EvaluatorParityTest do
  @moduledoc """
  The shared fixture `test/fixtures/evaluator_cases.json` (task 0015, step
  9): `Espalier.Learning.Evaluator` and `Espalier.Learning.PassRule` return
  the results that the fixture expects, and the Vitest test
  `frontend/src/player/evaluate.test.ts` expects the same results of the
  TypeScript port in `frontend/src/player/evaluate.ts`.

  The items of the fixture have the shape of the normalized pack payload.
  The test builds `%Espalier.Catalog.Item{}` structs from them, as the
  catalog loads them for the evaluator: the options in file order with their
  positions, the rules that `rules` names and the lessons that `reveals`
  names, both from `context`. An answer becomes the map with the members
  `options`, `slots`, `cases`, `checks` and `initials` that the API casts,
  each `nil` when absent. Results are compared after a JSON round trip, so
  that both suites compare the same JSON values.
  """
  use ExUnit.Case, async: true

  alias Espalier.Catalog.{Item, Lesson, Option, Rule}
  alias Espalier.Learning.{Evaluator, PassRule}

  @path Path.expand("../../fixtures/evaluator_cases.json", __DIR__)
  @external_resource @path
  @fixture @path |> File.read!() |> JSON.decode!()

  @kinds %{
    "single_choice" => :single_choice,
    "multiple_choice" => :multiple_choice,
    "slot_builder" => :slot_builder,
    "classification" => :classification,
    "checklist_drill" => :checklist_drill,
    "poll" => :poll
  }

  test "the fixture holds at least 30 item cases and covers every item kind and the pass rule" do
    kinds =
      @fixture["cases"]
      |> Enum.map(&@fixture["items"][&1["item"]]["kind"])
      |> MapSet.new()

    assert length(@fixture["cases"]) >= 30
    assert kinds == @kinds |> Map.keys() |> MapSet.new()

    outcomes = @fixture["attempts"] |> Enum.map(& &1["expected"]["outcome"]) |> MapSet.new()
    assert outcomes == MapSet.new(["passed", "failed_core", "failed_errors"])

    assert @fixture["attempts"]
           |> Enum.map(& &1["assessment"]["core_required"])
           |> Enum.uniq()
           |> Enum.sort() ==
             [false, true]
  end

  for {fixture_case, index} <- Enum.with_index(@fixture["cases"]) do
    @fixture_case fixture_case
    test "case #{index + 1}: #{fixture_case["name"]}" do
      fixture_case = @fixture_case
      item = item(@fixture["items"][fixture_case["item"]])
      answer = answer(fixture_case["answer"])

      if fixture_case["valid"] do
        assert Evaluator.validate(item, answer) == :ok
        assert json(Evaluator.evaluate(item, answer)) == fixture_case["expected"]
      else
        assert Evaluator.validate(item, answer) == {:error, :invalid_answer}
      end
    end
  end

  for {attempt, index} <- Enum.with_index(@fixture["attempts"]) do
    @attempt attempt
    test "attempt #{index + 1}: #{attempt["name"]}" do
      attempt = @attempt
      items = Enum.map(attempt["items"], &item(@fixture["items"][&1]))

      results =
        for item <- items do
          answer = answer(attempt["answers"][item.key])
          assert Evaluator.validate(item, answer) == :ok
          {item, Evaluator.evaluate(item, answer)}
        end

      graded = for {item, result} <- results, do: %{core: item.core, correct: result.correct}
      assessment = %{max_wrong: attempt["assessment"]["max_wrong"]}

      assert json(%{
               correct: Enum.map(graded, & &1.correct),
               wrong_count: PassRule.wrong_count(graded),
               core_failed: PassRule.core_failed?(graded),
               outcome: PassRule.evaluate(graded, assessment)
             }) == attempt["expected"]
    end
  end

  defp item(payload) do
    numbers = MapSet.new(payload["rules"])
    keys = MapSet.new(payload["reveals"])

    %Item{
      id: "item-" <> payload["key"],
      key: payload["key"],
      kind: Map.fetch!(@kinds, payload["kind"]),
      stem: payload["stem"],
      core: payload["core"] == true,
      config: payload["config"],
      options:
        payload["options"]
        |> Enum.with_index(1)
        |> Enum.map(fn {option, position} ->
          %Option{
            key: option["key"],
            label: option["label"],
            correct: option["correct"],
            feedback: option["feedback"],
            position: position
          }
        end),
      rules:
        for rule <- @fixture["context"]["rules"], MapSet.member?(numbers, rule["number"]) do
          %Rule{
            id: rule["id"],
            number: rule["number"],
            statement: rule["statement"],
            action: rule["action"]
          }
        end,
      reveals:
        for lesson <- @fixture["context"]["lessons"], MapSet.member?(keys, lesson["key"]) do
          %Lesson{id: lesson["id"], key: lesson["key"], position: lesson["position"]}
        end
    }
  end

  defp answer(answer) do
    %{
      options: answer["options"],
      slots: answer["slots"],
      cases: answer["cases"],
      checks: answer["checks"],
      initials: answer["initials"]
    }
  end

  defp json(term), do: term |> JSON.encode!() |> JSON.decode!()
end
