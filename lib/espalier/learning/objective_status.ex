defmodule Espalier.Learning.ObjectiveStatus do
  @moduledoc """
  Derives the status of each learning objective from the learner's own
  records (README section 7, domain rule 15). No table stores the status;
  `Espalier.Learning.objective_status/2` collects the facts per request and
  calls `derive/2`.

  An objective is `evidenced` when one of its `assessment_ids` lies in
  `passed_assessment_ids`, when one of its `format_ids` lies in
  `attended_format_ids`, or when one of its `item_ids` lies in
  `correct_item_ids`. Every other objective is `open`. The SPA adds the
  status `practised` from its local practice state (task 0012).
  """

  @type facts :: %{
          passed_assessment_ids: Enumerable.t(),
          attended_format_ids: Enumerable.t(),
          correct_item_ids: Enumerable.t()
        }

  @type entry :: %{key: String.t(), status: :evidenced | :open}

  @doc """
  Returns one entry per element of `links` (the result of
  `Espalier.Catalog.objective_links/2`), in the same order, with the key of
  the objective and its status.
  """
  @spec derive([map()], facts()) :: [entry()]
  def derive(links, facts) when is_list(links) do
    passed = MapSet.new(facts.passed_assessment_ids)
    attended = MapSet.new(facts.attended_format_ids)
    correct = MapSet.new(facts.correct_item_ids)

    for link <- links do
      evidenced? =
        Enum.any?(link.assessment_ids, &MapSet.member?(passed, &1)) or
          Enum.any?(link.format_ids, &MapSet.member?(attended, &1)) or
          Enum.any?(link.item_ids, &MapSet.member?(correct, &1))

      %{key: link.objective.key, status: if(evidenced?, do: :evidenced, else: :open)}
    end
  end
end
