defmodule Espalier.Learning.PassRule do
  @moduledoc """
  The pass rule of an exam attempt (README section 7, domain rule 5): the
  attempt fails with `failed_core` when a core item is wrong, fails with
  `failed_errors` when more than `max_wrong` answers are wrong, and passes
  otherwise. A wrong core item fails the attempt whatever `core_required`
  says; in task 0008, `core_required` only demands that an exam has a core
  item.

  A result is a map with `core` (the item is a core item) and `correct`
  (`true`, `false`, or `nil` for an item without a correct answer). Only
  `false` counts as wrong.
  """

  @type result :: %{required(:core) => boolean(), required(:correct) => boolean() | nil}
  @type outcome :: :passed | :failed_core | :failed_errors

  @doc """
  Returns the outcome of `results` under the pass rule of `assessment`.
  `max_wrong` must be an integer; a missing value raises instead of letting
  every attempt pass.
  """
  @spec evaluate([result()], %{required(:max_wrong) => non_neg_integer()}) :: outcome()
  def evaluate(results, %{max_wrong: max_wrong})
      when is_list(results) and is_integer(max_wrong) do
    cond do
      core_failed?(results) -> :failed_core
      wrong_count(results) > max_wrong -> :failed_errors
      true -> :passed
    end
  end

  @doc "Counts the wrong answers of `results`."
  @spec wrong_count([result()]) :: non_neg_integer()
  def wrong_count(results), do: Enum.count(results, &(&1.correct == false))

  @doc "True when a core item of `results` is wrong."
  @spec core_failed?([result()]) :: boolean()
  def core_failed?(results), do: Enum.any?(results, &(&1.core == true and &1.correct == false))
end
