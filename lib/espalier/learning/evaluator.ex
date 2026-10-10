defmodule Espalier.Learning.Evaluator do
  @moduledoc """
  Server-side evaluation of an answer to an item (README section 7, domain
  rules 3 and 4). It is the only code that reads the answer key: `correct`
  and `feedback` of the options, the `correct` options and `feedback` of the
  slots in `config`, and `expected` and the case `feedback` of a
  classification. The catalog views never carry these values.

  An answer is a map with the members `options`, `slots`, `cases`, `checks`
  and `initials`, each `nil` when absent. `validate/2` checks that the
  answer uses only the members of the item's kind and names only keys of the
  item:

  | Kind | Members | Correct when |
  |---|---|---|
  | `single_choice`, `multiple_choice` | `options` (option keys) | the chosen set equals the set of correct options |
  | `slot_builder` | `slots` (slot key to option key) | every slot has an option flagged correct |
  | `classification` | `cases` (case key to category key) | the mapping equals the expected mapping |
  | `checklist_drill` | `checks` (check keys), `initials` | every required check is set and the trimmed initials have 2 to 5 characters |
  | `poll` | `options` (option keys) | never; `correct` is `nil` |

  `evaluate/2` returns `correct`, the feedback entries, the rules linked
  through `item_rules` and, for a wrong answer only, the ids of the lessons
  of `item_reveals`. The client decides from the path whether to expand them
  (README section 7, rule 3).
  """

  alias Espalier.Catalog.Item

  @members [:options, :slots, :cases, :checks, :initials]

  @kind_members %{
    single_choice: [:options],
    multiple_choice: [:options],
    poll: [:options],
    slot_builder: [:slots],
    classification: [:cases],
    checklist_drill: [:checks, :initials]
  }

  @type answer :: %{optional(atom()) => term()}

  @type result :: %{
          correct: boolean() | nil,
          option_feedback: [map()],
          rules: [map()],
          reveals: [Ecto.UUID.t()]
        }

  @doc """
  Returns `:ok` when `answer` uses the members of the item's kind and names
  only keys of the item, and `{:error, :invalid_answer}` otherwise. The
  answer of a checklist drill always includes `checks` and `initials`.
  """
  @spec validate(struct(), answer()) :: :ok | {:error, :invalid_answer}
  def validate(%Item{kind: kind} = item, answer) when is_map(answer) do
    allowed = Map.fetch!(@kind_members, kind)

    if extra_members?(answer, allowed) or Enum.any?(allowed, &is_nil(Map.get(answer, &1))) or
         not keys_valid?(item, answer),
       do: {:error, :invalid_answer},
       else: :ok
  end

  def validate(_item, _answer), do: {:error, :invalid_answer}

  defp extra_members?(answer, allowed) do
    Enum.any?(@members -- allowed, &(not is_nil(Map.get(answer, &1))))
  end

  defp keys_valid?(%Item{kind: kind} = item, %{options: chosen})
       when kind in [:single_choice, :multiple_choice, :poll] do
    keys = MapSet.new(item.options, & &1.key)
    distinct_subset?(chosen, keys)
  end

  defp keys_valid?(%Item{kind: :slot_builder, config: config}, %{slots: chosen}) do
    slots = Map.new(list(config, "slots"), &{&1["key"], option_keys(&1)})

    is_map(chosen) and
      Enum.all?(chosen, fn {slot, option} ->
        is_binary(option) and MapSet.member?(Map.get(slots, slot, MapSet.new()), option)
      end)
  end

  defp keys_valid?(%Item{kind: :classification, config: config}, %{cases: chosen}) do
    cases = config |> list("cases") |> MapSet.new(& &1["key"])
    categories = config |> list("categories") |> MapSet.new(& &1["key"])

    is_map(chosen) and
      Enum.all?(chosen, fn {case_key, category} ->
        MapSet.member?(cases, case_key) and MapSet.member?(categories, category)
      end)
  end

  defp keys_valid?(%Item{kind: :checklist_drill, config: config}, %{checks: chosen} = answer) do
    checks = config |> list("checks") |> MapSet.new(& &1["key"])
    initials = Map.get(answer, :initials)
    distinct_subset?(chosen, checks) and is_binary(initials)
  end

  defp keys_valid?(_item, _answer), do: false

  defp distinct_subset?(chosen, keys) when is_list(chosen) do
    Enum.all?(chosen, &MapSet.member?(keys, &1)) and length(Enum.uniq(chosen)) == length(chosen)
  end

  defp distinct_subset?(_chosen, _keys), do: false

  defp option_keys(slot), do: slot |> list("options") |> MapSet.new(& &1["key"])

  @doc """
  Evaluates a valid `answer` (see `validate/2`) to `item`.

  The item carries its `options` in position order, its `rules` and its
  `reveals`. The result holds:

    * `correct`: a boolean, or `nil` for a poll;
    * `option_feedback`: for a choice item every option in order with
      `key`, `selected`, `correct` and `feedback`, chosen or unchosen; for a
      slot builder every slot with `key`, `choice`, `correct` and the
      `feedback` of the chosen option; for a classification every case with
      `key`, `choice`, `expected`, `correct` and its `feedback`; for a
      checklist drill every check with `key`, `selected`, `required` and
      `correct`; for a poll nothing;
    * `rules`: the linked rules with `id`, `number`, `statement` and
      `action`, by number;
    * `reveals`: the lesson ids of `item_reveals`, only when `correct` is
      `false`.
  """
  @spec evaluate(struct(), answer()) :: result()
  def evaluate(%Item{} = item, answer) when is_map(answer) do
    {correct, feedback} = grade(item, answer)

    %{
      correct: correct,
      option_feedback: feedback,
      rules: rules(item),
      reveals: if(correct == false, do: reveals(item), else: [])
    }
  end

  defp grade(%Item{kind: :poll}, _answer), do: {nil, []}

  defp grade(%Item{kind: kind, options: options}, answer)
       when kind in [:single_choice, :multiple_choice] do
    chosen = answer |> Map.get(:options) |> List.wrap() |> MapSet.new()
    correct_keys = for option <- options, option.correct, into: MapSet.new(), do: option.key

    feedback =
      for option <- options do
        %{
          key: option.key,
          selected: MapSet.member?(chosen, option.key),
          correct: option.correct,
          feedback: option.feedback
        }
      end

    {MapSet.equal?(chosen, correct_keys), feedback}
  end

  defp grade(%Item{kind: :slot_builder, config: config}, answer) do
    chosen = Map.get(answer, :slots) || %{}

    feedback =
      for slot <- list(config, "slots") do
        choice = Map.get(chosen, slot["key"])
        option = Enum.find(list(slot, "options"), &(&1["key"] == choice))

        %{
          key: slot["key"],
          choice: choice,
          correct: option != nil and option["correct"] == true,
          feedback: option && option["feedback"]
        }
      end

    {feedback != [] and Enum.all?(feedback, & &1.correct), feedback}
  end

  defp grade(%Item{kind: :classification, config: config}, answer) do
    chosen = Map.get(answer, :cases) || %{}
    expected = Map.get(config || %{}, "expected") || %{}

    feedback =
      for case_entry <- list(config, "cases") do
        key = case_entry["key"]
        choice = Map.get(chosen, key)
        expected_category = Map.get(expected, key)

        %{
          key: key,
          choice: choice,
          expected: expected_category,
          correct: choice != nil and choice == expected_category,
          feedback: case_entry["feedback"]
        }
      end

    {feedback != [] and Enum.all?(feedback, & &1.correct), feedback}
  end

  defp grade(%Item{kind: :checklist_drill, config: config}, answer) do
    chosen = answer |> Map.get(:checks) |> List.wrap() |> MapSet.new()

    feedback =
      for check <- list(config, "checks") do
        selected = MapSet.member?(chosen, check["key"])
        required = check["required"] == true

        %{
          key: check["key"],
          selected: selected,
          required: required,
          correct: selected or not required
        }
      end

    {Enum.all?(feedback, & &1.correct) and initials?(Map.get(answer, :initials)), feedback}
  end

  defp initials?(initials) when is_binary(initials) do
    String.length(String.trim(initials)) in 2..5
  end

  defp initials?(_initials), do: false

  defp rules(%Item{rules: rules}) when is_list(rules) do
    rules
    |> Enum.sort_by(& &1.number)
    |> Enum.map(&%{id: &1.id, number: &1.number, statement: &1.statement, action: &1.action})
  end

  defp reveals(%Item{reveals: lessons}) when is_list(lessons) do
    lessons |> Enum.sort_by(&{&1.position, &1.key}) |> Enum.map(& &1.id)
  end

  defp list(map, key) when is_map(map) do
    case Map.get(map, key) do
      entries when is_list(entries) -> Enum.filter(entries, &is_map/1)
      _other -> []
    end
  end

  defp list(_map, _key), do: []
end
