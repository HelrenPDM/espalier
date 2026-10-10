defmodule Espalier.Learning.EvaluatorTest do
  @moduledoc """
  The evaluator per item kind on in-memory items: correctness, feedback for
  chosen and unchosen options, the linked rules, and the reveals of a wrong
  answer only. The items carry their options in position order, as the
  catalog preloads them.
  """
  use ExUnit.Case, async: true

  alias Espalier.Catalog.{Item, Lesson, Option, Rule}
  alias Espalier.Learning.Evaluator

  @result_keys [:correct, :option_feedback, :reveals, :rules]

  @slot_config %{
    "slots" => [
      %{
        "key" => "task",
        "label" => "Task",
        "options" => [
          %{
            "key" => "task-clear",
            "label" => "Clear task",
            "correct" => true,
            "feedback" => "Feedback task-clear"
          },
          %{
            "key" => "task-vague",
            "label" => "Vague task",
            "correct" => false,
            "feedback" => "Feedback task-vague"
          }
        ]
      },
      %{
        "key" => "context",
        "label" => "Context",
        "options" => [
          %{
            "key" => "context-team",
            "label" => "Team context",
            "correct" => true,
            "feedback" => "Feedback context-team"
          },
          %{
            "key" => "context-none",
            "label" => "No context",
            "correct" => false,
            "feedback" => "Feedback context-none"
          }
        ]
      }
    ]
  }

  @classification_config %{
    "categories" => [
      %{"key" => "needs-source", "label" => "Check against a source"},
      %{"key" => "needs-rewrite", "label" => "Rewrite or remove"},
      %{"key" => "ready", "label" => "Ready to use"}
    ],
    "cases" => [
      %{"key" => "case-figure", "text" => "A figure", "feedback" => "Feedback case-figure"},
      %{"key" => "case-claim", "text" => "A claim", "feedback" => "Feedback case-claim"},
      %{"key" => "case-thanks", "text" => "A thank you", "feedback" => "Feedback case-thanks"}
    ],
    "expected" => %{
      "case-figure" => "needs-source",
      "case-claim" => "needs-rewrite",
      "case-thanks" => "ready"
    }
  }

  @checklist_config %{
    "checks" => [
      %{"key" => "facts-checked", "label" => "Facts checked", "required" => true},
      %{"key" => "sources-named", "label" => "Sources named", "required" => true},
      %{"key" => "second-reader", "label" => "Second reader", "required" => false}
    ]
  }

  @expected_cases %{
    "case-figure" => "needs-source",
    "case-claim" => "needs-rewrite",
    "case-thanks" => "ready"
  }

  setup do
    rules = [rule(3), rule(1), rule(2)]
    reveals = [lesson("02-second-lesson", 2), lesson("01-first-lesson", 1)]

    %{
      rules: rules,
      reveals: reveals,
      rule_ids: rules |> Enum.sort_by(& &1.number) |> Enum.map(& &1.id),
      reveal_ids: reveals |> Enum.sort_by(& &1.position) |> Enum.map(& &1.id)
    }
  end

  describe "evaluate/2 on a single_choice item" do
    setup ctx do
      options = [option("c", 1, false), option("a", 2, true), option("b", 3, false)]
      %{item: item(:single_choice, ctx, options: options)}
    end

    test "the correct option is correct and every option carries its feedback", %{item: item} do
      result = Evaluator.evaluate(item, %{options: ["a"]})

      assert result.correct == true

      assert result.option_feedback == [
               %{key: "c", selected: false, correct: false, feedback: "Feedback c"},
               %{key: "a", selected: true, correct: true, feedback: "Feedback a"},
               %{key: "b", selected: false, correct: false, feedback: "Feedback b"}
             ]

      assert result.reveals == []
    end

    test "a wrong option is wrong, the unchosen correct option keeps its feedback, reveals by position",
         %{item: item, reveal_ids: reveal_ids} do
      result = Evaluator.evaluate(item, %{options: ["b"]})

      assert result.correct == false

      assert result.option_feedback == [
               %{key: "c", selected: false, correct: false, feedback: "Feedback c"},
               %{key: "a", selected: false, correct: true, feedback: "Feedback a"},
               %{key: "b", selected: true, correct: false, feedback: "Feedback b"}
             ]

      assert result.reveals == reveal_ids
    end

    test "option_feedback follows the position order of the options", %{item: item} do
      result = Evaluator.evaluate(item, %{options: ["a"]})

      assert Enum.map(result.option_feedback, & &1.key) ==
               item.options |> Enum.sort_by(& &1.position) |> Enum.map(& &1.key)
    end
  end

  describe "evaluate/2 on a multiple_choice item" do
    setup ctx do
      options = [
        option("d", 1, true),
        option("b", 2, false),
        option("e", 3, true),
        option("a", 4, false)
      ]

      %{item: item(:multiple_choice, ctx, options: options)}
    end

    test "the set of correct options is correct in any order", %{item: item} do
      result = Evaluator.evaluate(item, %{options: ["e", "d"]})

      assert result.correct == true

      assert result.option_feedback == [
               %{key: "d", selected: true, correct: true, feedback: "Feedback d"},
               %{key: "b", selected: false, correct: false, feedback: "Feedback b"},
               %{key: "e", selected: true, correct: true, feedback: "Feedback e"},
               %{key: "a", selected: false, correct: false, feedback: "Feedback a"}
             ]

      assert result.reveals == []
    end

    test "a subset, a superset and an empty choice are wrong", %{
      item: item,
      reveal_ids: reveal_ids
    } do
      for chosen <- [["d"], ["d", "e", "b"], []] do
        result = Evaluator.evaluate(item, %{options: chosen})

        assert result.correct == false, inspect(chosen)
        assert result.reveals == reveal_ids
      end
    end

    test "every option carries its feedback on a wrong answer", %{item: item} do
      result = Evaluator.evaluate(item, %{options: ["d", "b"]})

      assert result.option_feedback == [
               %{key: "d", selected: true, correct: true, feedback: "Feedback d"},
               %{key: "b", selected: true, correct: false, feedback: "Feedback b"},
               %{key: "e", selected: false, correct: true, feedback: "Feedback e"},
               %{key: "a", selected: false, correct: false, feedback: "Feedback a"}
             ]
    end
  end

  describe "evaluate/2 on a slot_builder item" do
    setup ctx do
      %{item: item(:slot_builder, ctx, config: @slot_config)}
    end

    test "a correct option in every slot is correct, with feedback per slot", %{item: item} do
      result =
        Evaluator.evaluate(item, %{slots: %{"task" => "task-clear", "context" => "context-team"}})

      assert result.correct == true

      assert result.option_feedback == [
               %{
                 key: "task",
                 choice: "task-clear",
                 correct: true,
                 feedback: "Feedback task-clear"
               },
               %{
                 key: "context",
                 choice: "context-team",
                 correct: true,
                 feedback: "Feedback context-team"
               }
             ]

      assert result.reveals == []
    end

    test "one wrong slot makes the answer wrong and carries the feedback of the chosen option",
         %{item: item, reveal_ids: reveal_ids} do
      result =
        Evaluator.evaluate(item, %{slots: %{"task" => "task-clear", "context" => "context-none"}})

      assert result.correct == false

      assert result.option_feedback == [
               %{
                 key: "task",
                 choice: "task-clear",
                 correct: true,
                 feedback: "Feedback task-clear"
               },
               %{
                 key: "context",
                 choice: "context-none",
                 correct: false,
                 feedback: "Feedback context-none"
               }
             ]

      assert result.reveals == reveal_ids
    end

    test "a slot without a choice is wrong and has no feedback", %{item: item} do
      result = Evaluator.evaluate(item, %{slots: %{"task" => "task-clear"}})

      assert result.correct == false

      assert List.last(result.option_feedback) == %{
               key: "context",
               choice: nil,
               correct: false,
               feedback: nil
             }
    end
  end

  describe "evaluate/2 on a classification item" do
    setup ctx do
      %{item: item(:classification, ctx, config: @classification_config)}
    end

    test "the expected mapping is correct, with feedback per case", %{item: item} do
      result = Evaluator.evaluate(item, %{cases: @expected_cases})

      assert result.correct == true

      assert result.option_feedback == [
               %{
                 key: "case-figure",
                 choice: "needs-source",
                 expected: "needs-source",
                 correct: true,
                 feedback: "Feedback case-figure"
               },
               %{
                 key: "case-claim",
                 choice: "needs-rewrite",
                 expected: "needs-rewrite",
                 correct: true,
                 feedback: "Feedback case-claim"
               },
               %{
                 key: "case-thanks",
                 choice: "ready",
                 expected: "ready",
                 correct: true,
                 feedback: "Feedback case-thanks"
               }
             ]

      assert result.reveals == []
    end

    test "one case in another category makes the answer wrong", %{
      item: item,
      reveal_ids: reveal_ids
    } do
      cases = Map.put(@expected_cases, "case-claim", "ready")
      result = Evaluator.evaluate(item, %{cases: cases})

      assert result.correct == false

      assert Enum.at(result.option_feedback, 1) == %{
               key: "case-claim",
               choice: "ready",
               expected: "needs-rewrite",
               correct: false,
               feedback: "Feedback case-claim"
             }

      assert Enum.map(result.option_feedback, & &1.correct) == [true, false, true]
      assert result.reveals == reveal_ids
    end

    test "a case without a choice is wrong and keeps its feedback", %{item: item} do
      cases = Map.delete(@expected_cases, "case-thanks")
      result = Evaluator.evaluate(item, %{cases: cases})

      assert result.correct == false

      assert List.last(result.option_feedback) == %{
               key: "case-thanks",
               choice: nil,
               expected: "ready",
               correct: false,
               feedback: "Feedback case-thanks"
             }
    end
  end

  describe "evaluate/2 on a checklist_drill item" do
    setup ctx do
      %{item: item(:checklist_drill, ctx, config: @checklist_config)}
    end

    test "every required check and initials are correct, the optional check does not matter",
         %{item: item} do
      result =
        Evaluator.evaluate(item, %{checks: ["facts-checked", "sources-named"], initials: "SG"})

      assert result.correct == true

      assert result.option_feedback == [
               %{key: "facts-checked", selected: true, required: true, correct: true},
               %{key: "sources-named", selected: true, required: true, correct: true},
               %{key: "second-reader", selected: false, required: false, correct: true}
             ]

      assert result.reveals == []

      all_checks = %{checks: ["second-reader", "sources-named", "facts-checked"], initials: "SG"}
      assert Evaluator.evaluate(item, all_checks).correct == true
    end

    test "a missing required check is wrong, even with the optional check set", %{
      item: item,
      reveal_ids: reveal_ids
    } do
      result =
        Evaluator.evaluate(item, %{checks: ["facts-checked", "second-reader"], initials: "SG"})

      assert result.correct == false

      assert result.option_feedback == [
               %{key: "facts-checked", selected: true, required: true, correct: true},
               %{key: "sources-named", selected: false, required: true, correct: false},
               %{key: "second-reader", selected: true, required: false, correct: true}
             ]

      assert result.reveals == reveal_ids
    end

    test "the trimmed initials need 2 to 5 characters", %{item: item} do
      checks = ["facts-checked", "sources-named"]

      for {initials, correct} <- [
            {"S", false},
            {"SG", true},
            {"ABCDE", true},
            {"ABCDEF", false},
            {"   ", false},
            {"", false},
            {" S ", false},
            {"  SG  ", true},
            {" ABCDE ", true},
            {"ÄÖÜÉÈ", true},
            {nil, false}
          ] do
        assert Evaluator.evaluate(item, %{checks: checks, initials: initials}).correct == correct,
               inspect(initials)
      end
    end

    test "an answer without initials is wrong", %{item: item} do
      assert Evaluator.evaluate(item, %{checks: ["facts-checked", "sources-named"]}).correct ==
               false
    end
  end

  describe "evaluate/2 on a poll" do
    setup ctx do
      options = [option("yes", 1, false), option("no", 2, false)]
      %{item: item(:poll, ctx, options: options)}
    end

    test "has no correct value, no feedback and no reveals", %{item: item, rule_ids: rule_ids} do
      result = Evaluator.evaluate(item, %{options: ["yes"]})

      assert result.correct == nil
      assert result.option_feedback == []
      assert result.reveals == []
      assert Enum.map(result.rules, & &1.id) == rule_ids
    end
  end

  describe "evaluate/2 rules and result shape" do
    test "rules are sorted by number and carry id, number, statement and action only", ctx do
      item = item(:single_choice, ctx, options: [option("a", 1, true), option("b", 2, false)])

      for answer <- [%{options: ["a"]}, %{options: ["b"]}] do
        result = Evaluator.evaluate(item, answer)

        assert Enum.map(result.rules, & &1.id) == ctx.rule_ids

        assert result.rules == [
                 %{
                   id: Enum.at(ctx.rule_ids, 0),
                   number: 1,
                   statement: "Statement 1",
                   action: "Action 1"
                 },
                 %{
                   id: Enum.at(ctx.rule_ids, 1),
                   number: 2,
                   statement: "Statement 2",
                   action: "Action 2"
                 },
                 %{
                   id: Enum.at(ctx.rule_ids, 2),
                   number: 3,
                   statement: "Statement 3",
                   action: "Action 3"
                 }
               ]
      end
    end

    test "an item without rules or reveals gives empty lists", ctx do
      item =
        item(:single_choice, ctx, options: [option("a", 1, true)], rules: [], reveals: [])

      assert %{rules: [], reveals: []} = Evaluator.evaluate(item, %{options: []})
    end

    test "no result carries the config or any part of it", ctx do
      for {item, answers} <- sample_items(ctx), answer <- answers do
        result = Evaluator.evaluate(item, answer)
        terms = subterms(result)

        assert result |> Map.keys() |> Enum.sort() == @result_keys

        refute item.config in terms
        for {_key, value} <- item.config, do: refute(value in terms)

        refute Enum.any?(
                 terms,
                 &(is_map(&1) and (Map.has_key?(&1, :config) or Map.has_key?(&1, "config")))
               )
      end
    end
  end

  describe "validate/2" do
    test "accepts an answer with the members of each kind", ctx do
      for {item, answers} <- sample_items(ctx), answer <- answers do
        assert Evaluator.validate(item, answer) == :ok, inspect({item.kind, answer})
      end
    end

    test "rejects a member of another kind", ctx do
      %{
        single_choice: single,
        poll: poll,
        slot_builder: slots,
        classification: classification,
        checklist_drill: checklist
      } = items(ctx)

      for {item, answer} <- [
            {single, %{options: ["a"], slots: %{"task" => "task-clear"}}},
            {single, %{options: ["a"], initials: "SG"}},
            {poll, %{options: ["yes"], checks: []}},
            {slots, %{slots: %{"task" => "task-clear"}, cases: %{}}},
            {classification, %{cases: @expected_cases, options: []}},
            {checklist, %{checks: ["facts-checked"], initials: "SG", options: ["a"]}}
          ] do
        assert Evaluator.validate(item, answer) == {:error, :invalid_answer},
               inspect({item.kind, answer})
      end
    end

    test "rejects an answer without the required member", ctx do
      %{
        single_choice: single,
        multiple_choice: multiple,
        slot_builder: slots,
        classification: classification,
        checklist_drill: checklist
      } = items(ctx)

      for {item, answer} <- [
            {single, %{}},
            {single, %{options: nil}},
            {multiple, %{}},
            {slots, %{slots: nil}},
            {classification, %{}},
            {checklist, %{initials: "SG"}},
            {checklist, %{checks: nil, initials: "SG"}}
          ] do
        assert Evaluator.validate(item, answer) == {:error, :invalid_answer},
               inspect({item.kind, answer})
      end
    end

    test "rejects unknown and duplicate option keys", ctx do
      %{single_choice: single, multiple_choice: multiple, poll: poll} = items(ctx)

      for {item, answer} <- [
            {single, %{options: ["z"]}},
            {multiple, %{options: ["d", "z"]}},
            {multiple, %{options: ["d", "d"]}},
            {poll, %{options: ["maybe"]}}
          ] do
        assert Evaluator.validate(item, answer) == {:error, :invalid_answer},
               inspect({item.kind, answer})
      end
    end

    test "rejects an unknown slot key and an option of another slot", ctx do
      %{slot_builder: item} = items(ctx)

      for slots <- [
            %{"audience" => "task-clear"},
            %{"task" => "task-unknown"},
            %{"task" => "context-team"}
          ] do
        assert Evaluator.validate(item, %{slots: slots}) == {:error, :invalid_answer},
               inspect(slots)
      end
    end

    test "rejects an unknown case key and an unknown category key", ctx do
      %{classification: item} = items(ctx)

      for cases <- [
            Map.put(@expected_cases, "case-unknown", "ready"),
            Map.put(@expected_cases, "case-figure", "category-unknown")
          ] do
        assert Evaluator.validate(item, %{cases: cases}) == {:error, :invalid_answer},
               inspect(cases)
      end
    end

    test "rejects unknown and duplicate check keys", ctx do
      %{checklist_drill: item} = items(ctx)

      for checks <- [["facts-checked", "check-unknown"], ["facts-checked", "facts-checked"]] do
        assert Evaluator.validate(item, %{checks: checks, initials: "SG"}) ==
                 {:error, :invalid_answer},
               inspect(checks)
      end
    end

    test "rejects members of the wrong type and an answer that is no map", ctx do
      %{single_choice: single, slot_builder: slots, checklist_drill: checklist} = items(ctx)

      for {item, answer} <- [
            {single, %{options: "a"}},
            {slots, %{slots: [{"task", "task-clear"}]}},
            {checklist, %{checks: ["facts-checked"], initials: 12}},
            {single, ["a"]}
          ] do
        assert Evaluator.validate(item, answer) == {:error, :invalid_answer},
               inspect({item.kind, answer})
      end
    end

    test "rejects a checklist answer without initials, because the answer always includes them",
         ctx do
      %{checklist_drill: item} = items(ctx)
      answer = %{checks: ["facts-checked", "sources-named"]}

      assert Evaluator.validate(item, answer) == {:error, :invalid_answer}

      assert Evaluator.validate(item, Map.put(answer, :initials, nil)) ==
               {:error, :invalid_answer}

      assert Evaluator.validate(item, Map.put(answer, :initials, "")) == :ok
      assert Evaluator.evaluate(item, Map.put(answer, :initials, "")).correct == false
    end
  end

  defp items(ctx) do
    %{
      single_choice:
        item(:single_choice, ctx,
          options: [option("c", 1, false), option("a", 2, true), option("b", 3, false)]
        ),
      multiple_choice:
        item(:multiple_choice, ctx,
          options: [option("d", 1, true), option("b", 2, false), option("e", 3, true)]
        ),
      slot_builder: item(:slot_builder, ctx, config: @slot_config),
      classification: item(:classification, ctx, config: @classification_config),
      checklist_drill: item(:checklist_drill, ctx, config: @checklist_config),
      poll: item(:poll, ctx, options: [option("yes", 1, false), option("no", 2, false)])
    }
  end

  # Each item of `items/1` with a correct and a wrong answer that pass `validate/2`.
  defp sample_items(ctx) do
    items = items(ctx)

    [
      {items.single_choice, [%{options: ["a"]}, %{options: ["b"]}]},
      {items.multiple_choice, [%{options: ["d", "e"]}, %{options: []}]},
      {items.slot_builder,
       [
         %{slots: %{"task" => "task-clear", "context" => "context-team"}},
         %{slots: %{"task" => "task-vague"}}
       ]},
      {items.classification, [%{cases: @expected_cases}, %{cases: %{"case-figure" => "ready"}}]},
      {items.checklist_drill,
       [
         %{checks: ["facts-checked", "sources-named"], initials: "SG"},
         %{checks: ["second-reader"], initials: "S"}
       ]},
      {items.poll, [%{options: ["yes"]}, %{options: []}]}
    ]
  end

  defp item(kind, ctx, attrs) do
    struct!(
      %Item{
        id: Ecto.UUID.generate(),
        key: "#{kind}-item",
        kind: kind,
        stem: "Stem of #{kind}",
        config: %{},
        options: [],
        rules: ctx.rules,
        reveals: ctx.reveals
      },
      attrs
    )
  end

  defp option(key, position, correct) do
    %Option{
      id: Ecto.UUID.generate(),
      key: key,
      label: "Label #{key}",
      correct: correct,
      feedback: "Feedback #{key}",
      position: position
    }
  end

  defp rule(number) do
    %Rule{
      id: Ecto.UUID.generate(),
      number: number,
      statement: "Statement #{number}",
      action: "Action #{number}"
    }
  end

  defp lesson(key, position) do
    %Lesson{id: Ecto.UUID.generate(), key: key, position: position, title: "Title #{key}"}
  end

  # Every term nested in maps and lists of `term`, the term itself included.
  defp subterms(term) when is_map(term) and not is_struct(term) do
    [term | Enum.flat_map(term, fn {key, value} -> subterms(key) ++ subterms(value) end)]
  end

  defp subterms(term) when is_list(term), do: [term | Enum.flat_map(term, &subterms/1)]
  defp subterms(term), do: [term]
end
