defmodule Espalier.Learning.PassRuleTest do
  @moduledoc """
  The pass rule of README section 7, rule 5: a wrong core item fails the
  attempt whatever `core_required` says, and otherwise the attempt passes
  exactly when at most `max_wrong` answers are wrong.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Espalier.Learning.PassRule

  @assessment %{max_wrong: 1, core_required: true}

  property "any wrong core item yields failed_core, whatever the wrong count and max_wrong" do
    check all(
            before <- list_of(result()),
            rest <- list_of(result()),
            max_wrong <- non_negative_integer(),
            core_required <- boolean()
          ) do
      results = before ++ [%{core: true, correct: false}] ++ rest
      assessment = %{max_wrong: max_wrong, core_required: core_required}

      assert PassRule.evaluate(results, assessment) == :failed_core
    end
  end

  property "with no core item wrong, the attempt passes exactly when at most max_wrong are wrong" do
    check all(
            results <- list_of(result_without_wrong_core(), max_length: 20),
            max_wrong <- integer(0..10),
            core_required <- boolean()
          ) do
      wrong = Enum.count(results, &(&1.correct == false))
      expected = if wrong <= max_wrong, do: :passed, else: :failed_errors

      assert PassRule.evaluate(results, %{max_wrong: max_wrong, core_required: core_required}) ==
               expected
    end
  end

  describe "evaluate/2 on the demo exam (4 items, one core, max_wrong 1)" do
    test "a wrong core item fails with failed_core" do
      assert PassRule.evaluate(demo([false, true, true, true]), @assessment) == :failed_core
    end

    test "one wrong item that is no core item passes" do
      assert PassRule.evaluate(demo([true, false, true, true]), @assessment) == :passed
    end

    test "two wrong items that are no core items fail with failed_errors" do
      assert PassRule.evaluate(demo([true, false, false, true]), @assessment) == :failed_errors
    end

    test "every item correct passes" do
      assert PassRule.evaluate(demo([true, true, true, true]), @assessment) == :passed
    end
  end

  describe "wrong_count/1 and core_failed?/1" do
    test "wrong_count/1 counts false only, not nil" do
      results = [
        %{core: false, correct: false},
        %{core: true, correct: false},
        %{core: false, correct: nil},
        %{core: false, correct: true}
      ]

      assert PassRule.wrong_count(results) == 2
      assert PassRule.wrong_count([]) == 0
    end

    test "core_failed?/1 is true only for a core item that is false" do
      assert PassRule.core_failed?([%{core: true, correct: false}])
      refute PassRule.core_failed?([%{core: true, correct: nil}, %{core: true, correct: true}])
      refute PassRule.core_failed?([%{core: false, correct: false}])
      refute PassRule.core_failed?([])
    end
  end

  test "an assessment without an integer max_wrong raises instead of passing" do
    # The value comes through the process dictionary, so that the type checker
    # sees no literal call that it knows to fail.
    Process.put(:max_wrong, nil)

    assert_raise FunctionClauseError, fn ->
      PassRule.evaluate([%{core: false, correct: false}], %{max_wrong: Process.get(:max_wrong)})
    end
  end

  # Results of the demo exam: the first item is the core item.
  defp demo(correct) do
    correct
    |> Enum.with_index()
    |> Enum.map(fn {correct, index} -> %{core: index == 0, correct: correct} end)
  end

  defp result do
    fixed_map(%{core: boolean(), correct: member_of([true, false, nil])})
  end

  defp result_without_wrong_core do
    one_of([
      fixed_map(%{core: constant(false), correct: member_of([true, false, nil])}),
      fixed_map(%{core: constant(true), correct: member_of([true, nil])})
    ])
  end
end
