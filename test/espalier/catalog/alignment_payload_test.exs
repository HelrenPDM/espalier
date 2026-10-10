defmodule Espalier.Catalog.AlignmentPayloadTest do
  use Espalier.DataCase, async: true

  alias Ecto.UUID

  alias Espalier.Catalog.{
    Alignment,
    Assessment,
    AssessmentItem,
    Block,
    CompanionFormat,
    Item,
    LearningObjective,
    Lesson,
    Program
  }

  alias Espalier.Catalog.Module, as: CatalogModule

  @areas ~w(subject method self social)
  @depths ~w(know apply judge)

  describe "check/1" do
    test "an aligned payload has no findings" do
      assert Alignment.check(aligned_payload()) == {[], []}
    end

    test "check 1: an objective with an empty taught_in is an error in strict and a warning in warn mode" do
      payload = update_objective(aligned_payload(), "m1-subject", &Map.put(&1, "taught_in", []))

      assert {[finding], []} = Alignment.check(payload)

      assert %{check: 1, module: 1, file: "objectives.yaml", key: "m1-subject", message: message} =
               finding

      assert message =~ "`taught_in`"
      assert Alignment.check(warn(payload)) == {[], [finding]}
    end

    test "check 1: a poll outside every assessment and a format without attendance are no evidence" do
      payload =
        aligned_payload()
        |> add_objective(1, objective("m1-anchored", "subject", "know", ["01-intro"]))
        |> update_item("m1-poll", &Map.put(&1, "objectives", ["m1-anchored"]))
        |> update_format("handbook", &Map.put(&1, "objectives", ["m1-anchored"]))

      assert {[finding], []} = Alignment.check(payload)

      assert %{check: 1, module: 1, file: "objectives.yaml", key: "m1-anchored", message: message} =
               finding

      assert message =~ "no evidence"
      assert Alignment.check(warn(payload)) == {[], [finding]}
    end

    test "check 1: an objective without lesson and evidence gives one finding per missing part" do
      payload = add_objective(aligned_payload(), 2, objective("m2-bare", "subject", "know", []))

      assert {[lesson_gap, evidence_gap], []} = Alignment.check(payload)
      assert %{check: 1, module: 2, key: "m2-bare", file: "objectives.yaml"} = lesson_gap
      assert %{check: 1, module: 2, key: "m2-bare", file: "objectives.yaml"} = evidence_gap
      assert lesson_gap.message =~ "`taught_in`"
      assert evidence_gap.message =~ "no evidence"
    end

    test "check 1: a format with attendance, a checklist drill and any item of an assessment are evidence" do
      payload =
        aligned_payload()
        |> add_objective(1, objective("m1-attended", "self", "judge", ["01-intro"]))
        |> add_objective(1, objective("m1-drilled", "method", "apply", ["01-intro"]))
        |> add_objective(1, objective("m1-polled", "social", "judge", ["01-intro"]))
        |> update_format(
          "workshop",
          &Map.update!(&1, "objectives", fn keys -> ["m1-attended" | keys] end)
        )
        |> add_item(1, item("m1-drill-2", "checklist_drill", ["m1-drilled"]))
        |> add_item(1, item("m1-poll-2", "poll", ["m1-polled"]))
        |> add_assessment(1, assessment("m1-survey", false, ["m1-poll-2"]))

      # The poll of the practice set is evidence, and its kind fits no depth.
      assert {[], [%{check: 4, key: "m1-polled"}]} = Alignment.check(payload)
    end

    test "check 2: an exam item without objectives is an error in strict and a warning in warn mode" do
      payload = add_orphan_exam_item(aligned_payload(), true)

      assert {[finding], []} = Alignment.check(payload)

      assert %{check: 2, module: 1, file: "items.yaml", key: "m1-exam-orphan", message: message} =
               finding

      assert message =~ "`m1-exam`"
      assert Alignment.check(warn(payload)) == {[], [finding]}
    end

    test "check 2: the same item in an assessment that does not count for a credential passes" do
      assert Alignment.check(add_orphan_exam_item(aligned_payload(), false)) == {[], []}
    end

    test "check 2: an item listed by two credential assessments gives one finding that names both" do
      payload =
        aligned_payload()
        |> add_orphan_exam_item(true)
        |> add_assessment(1, assessment("m1-final", true, ["m1-exam-orphan"]))

      assert {[%{check: 2, key: "m1-exam-orphan", message: message}], []} =
               Alignment.check(payload)

      assert message =~ "`m1-exam` and `m1-final`"
    end

    test "check 3: a module without a social objective and without areas_elsewhere" do
      payload =
        update_module(aligned_payload(), 2, fn module ->
          Map.update!(module, "areas_elsewhere", &Map.delete(&1, "social"))
        end)

      assert {[finding], []} = Alignment.check(payload)

      assert %{check: 3, module: 2, file: "module.yaml", key: "social", message: message} =
               finding

      assert message =~ "`social`"
      assert message =~ "`areas_elsewhere` does not name the area"
      assert Alignment.check(warn(payload)) == {[], [finding]}
    end

    test "check 3: a format named in areas_elsewhere covers the area only with an objective of that area" do
      covered = put_elsewhere(aligned_payload(), 2, "social", "format:workshop")
      assert Alignment.check(covered) == {[], []}

      uncovered = put_elsewhere(aligned_payload(), 2, "social", "format:help-desk")

      assert {[%{check: 3, module: 2, file: "module.yaml", key: "social", message: message}], []} =
               Alignment.check(uncovered)

      assert message =~ "`format:help-desk`"
      assert message =~ "`social`"

      # A format carries an area through the objectives it names, whether or
      # not its attendance counts.
      anchored =
        uncovered
        |> update_format("help-desk", &Map.put(&1, "objectives", ["m1-social"]))

      assert Alignment.check(anchored) == {[], []}
    end

    test "check 3: a module named in areas_elsewhere covers the area only with an objective of that area" do
      assert Alignment.check(put_elsewhere(aligned_payload(), 2, "social", "module:1")) ==
               {[], []}

      payload =
        aligned_payload()
        |> remove_social_of_module_1()
        |> put_elsewhere(2, "social", "module:1")

      assert {[module_1, module_2], []} = Alignment.check(payload)
      assert %{check: 3, module: 1, key: "social"} = module_1
      assert %{check: 3, module: 2, key: "social", message: message} = module_2
      assert message =~ "`module:1`"
    end

    test "check 4: a know objective whose only evidence is a checklist drill warns in both modes" do
      payload =
        aligned_payload()
        |> add_objective(1, objective("m1-know-drill", "subject", "know", ["01-intro"]))
        |> add_item(1, item("m1-drill-2", "checklist_drill", ["m1-know-drill"]))

      expected = [
        %{
          check: 4,
          module: 1,
          file: "objectives.yaml",
          key: "m1-know-drill",
          message:
            "evidence of objective `m1-know-drill` has the kinds `checklist_drill`, " <>
              "none of which fits the depth `know` (`single_choice` or `multiple_choice`)"
        }
      ]

      assert Alignment.check(payload) == {[], expected}
      assert Alignment.check(warn(payload)) == {[], expected}
    end

    test "check 4: an apply objective whose only evidence is a format warns" do
      payload =
        aligned_payload()
        |> add_objective(1, objective("m1-apply-format", "method", "apply", ["01-intro"]))
        |> update_format(
          "workshop",
          &Map.update!(&1, "objectives", fn keys -> ["m1-apply-format" | keys] end)
        )

      assert {[], [%{check: 4, key: "m1-apply-format", message: message}]} =
               Alignment.check(payload)

      assert message =~ "`apply`"
      assert message =~ "`format`"
    end

    test "check 4: a judge objective with a classification item needs a case comparison in its teaching lessons" do
      assert Alignment.check(aligned_payload()) == {[], []}

      # The module still holds a case comparison, but in a lesson that does
      # not teach the objective.
      payload =
        aligned_payload()
        |> add_lesson(2, lesson("02-other", 2, ["case_comparison"]))
        |> update_lesson(2, "01-compare", &Map.put(&1, "blocks", [block("text")]))

      assert {[], [%{check: 4, module: 2, key: "m2-method", message: message}]} =
               Alignment.check(payload)

      assert message ==
               "evidence of objective `m2-method` has the kinds `classification`, none of " <>
                 "which fits the depth `judge` (`classification_with_case_comparison` or `format`)"
    end

    test "check 4: an objective without evidence gets no finding from check 4" do
      payload =
        add_objective(
          aligned_payload(),
          1,
          objective("m1-empty", "subject", "judge", ["01-intro"])
        )

      assert {[%{check: 1, key: "m1-empty"}], []} = Alignment.check(payload)
    end

    test "a payload without alignment behaves as alignment strict" do
      payload = aligned_payload() |> add_orphan_exam_item(true) |> Map.delete("alignment")

      assert {[%{check: 2, key: "m1-exam-orphan"}], []} = Alignment.check(payload)
    end

    test "findings are sorted by module number, check and key" do
      payload =
        aligned_payload()
        |> add_objective(2, objective("m2-z", "subject", "know", []))
        |> add_objective(2, objective("m2-a", "subject", "know", ["01-compare"]))
        |> add_orphan_exam_item(true)
        |> remove_social_of_module_1()
        |> add_objective(1, objective("m1-know-drill", "subject", "know", ["01-intro"]))
        |> add_item(1, item("m1-drill-2", "checklist_drill", ["m1-know-drill"]))
        |> warn()

      assert {[], warnings} = Alignment.check(payload)

      assert Enum.map(warnings, &{&1.module, &1.check, &1.key}) == [
               {1, 2, "m1-exam-orphan"},
               {1, 3, "social"},
               {1, 4, "m1-know-drill"},
               {2, 1, "m2-a"},
               {2, 1, "m2-z"},
               {2, 1, "m2-z"},
               {2, 3, "social"}
             ]

      assert [_m2_a, %{message: lesson_gap}, %{message: evidence_gap}, _social] =
               Enum.filter(warnings, &(&1.module == 2))

      assert lesson_gap =~ "`taught_in`"
      assert evidence_gap =~ "no evidence"
    end

    test "an item of another module provides evidence for the objective's module" do
      payload =
        aligned_payload()
        |> add_objective(1, objective("m1-elsewhere", "subject", "know", ["01-intro"]))
        |> add_item(2, item("m2-choice", "single_choice", ["m1-elsewhere"]))

      assert Alignment.check(payload) == {[], []}

      rows = Alignment.matrix(payload)
      assert "item:m2-choice" in row(rows, 1, "subject", "know").evidence
      refute Enum.any?(rows, &(&1.module == 2 and "item:m2-choice" in &1.evidence))
    end
  end

  describe "matrix/1 on a payload" do
    test "has twelve rows per module, modules in number order, then areas and depths" do
      payload = Map.update!(aligned_payload(), "modules", &Enum.reverse/1)
      rows = Alignment.matrix(payload)

      assert length(rows) == 24

      assert Enum.map(rows, &{&1.module, &1.area, &1.depth}) ==
               for(module <- [1, 2], area <- @areas, depth <- @depths, do: {module, area, depth})
    end

    test "lists the objectives, their lessons and their evidence" do
      rows = Alignment.matrix(aligned_payload())

      assert row(rows, 1, "subject", "know") == %{
               module: 1,
               area: "subject",
               depth: "know",
               objectives: ["m1-subject"],
               lessons: ["01-intro"],
               evidence: ["item:m1-choice", "item:m1-exam-a"],
               elsewhere: nil
             }

      assert row(rows, 1, "self", "judge").evidence == ["format:workshop"]
      assert row(rows, 1, "method", "apply").evidence == ["item:m1-drill"]
      assert row(rows, 2, "method", "judge").evidence == ["item:m2-sort"]
      assert row(rows, 1, "subject", "apply").objectives == []
      assert row(rows, 1, "subject", "apply").evidence == []
    end

    test "sorts every list and removes duplicates" do
      payload =
        aligned_payload()
        |> add_objective(1, objective("m1-b", "method", "know", ["02-practice", "01-intro"]))
        |> add_objective(1, objective("m1-a", "method", "know", ["01-intro", "01-intro"]))
        |> add_item(1, item("m1-z", "single_choice", ["m1-a", "m1-b"]))
        |> add_item(1, item("m1-y", "multiple_choice", ["m1-b", "m1-b"]))

      assert %{
               objectives: ["m1-a", "m1-b"],
               lessons: ["01-intro", "02-practice"],
               evidence: ["item:m1-y", "item:m1-z"]
             } = row(Alignment.matrix(payload), 1, "method", "know")
    end

    test "leaves out polls outside every assessment and formats without attendance" do
      payload =
        aligned_payload()
        |> update_item("m1-poll", &Map.put(&1, "objectives", ["m1-social"]))
        |> update_format("handbook", &Map.put(&1, "objectives", ["m1-social"]))

      assert row(Alignment.matrix(payload), 1, "social", "judge").evidence == ["format:workshop"]
    end

    test "sets elsewhere only for an area without an objective of the module" do
      rows =
        aligned_payload()
        |> put_elsewhere(2, "social", "module:1")
        |> put_elsewhere(2, "subject", "module:1")
        |> Alignment.matrix()

      for depth <- @depths do
        assert row(rows, 2, "self", depth).elsewhere == "format:workshop"
        assert row(rows, 2, "social", depth).elsewhere == "module:1"
        assert row(rows, 2, "subject", depth).elsewhere == nil
        assert row(rows, 1, "social", depth).elsewhere == nil
      end

      assert row(rows, 2, "social", "judge") == %{
               module: 2,
               area: "social",
               depth: "judge",
               objectives: [],
               lessons: [],
               evidence: [],
               elsewhere: "module:1"
             }
    end
  end

  describe "matrix/1 on a program" do
    test "reads the live rows and gives the rows of the payload of the same pack" do
      program = insert_program_with_archived_rows()
      rows = Alignment.matrix(program)

      assert rows == Alignment.matrix(live_payload())
      assert Enum.map(rows, & &1.module) |> Enum.uniq() == [1, 2]

      listed = Enum.flat_map(rows, &(&1.objectives ++ &1.lessons ++ &1.evidence))

      for archived <- [
            "m1-retired",
            "m3-gone",
            "02-retired",
            "01-gone",
            "item:m1-retired-item",
            "item:m3-gone-item",
            "format:retired-format"
          ] do
        refute archived in listed
      end

      assert row(rows, 1, "subject", "know") == %{
               module: 1,
               area: "subject",
               depth: "know",
               objectives: ["m1-subject"],
               lessons: ["01-intro"],
               evidence: ["item:m1-choice", "item:m1-exam-a"],
               elsewhere: nil
             }

      assert row(rows, 2, "social", "know").elsewhere == "format:workshop"
    end
  end

  ## Payloads

  # Two modules that pass all four checks. Module 1 covers the four areas;
  # module 2 covers `subject` and `method` and names `self` and `social` in
  # `areas_elsewhere`.
  defp aligned_payload do
    %{
      "schema" => 1,
      "key" => "alignment-fixture",
      "alignment" => "strict",
      "formats" => [
        format("handbook", false, []),
        format("workshop", true, ["m1-self", "m1-social"]),
        format("help-desk", false, [])
      ],
      "modules" => [
        %{
          "number" => 1,
          "areas_elsewhere" => %{},
          "lessons" => [
            lesson("01-intro", 1, ["text"]),
            lesson("02-practice", 2, ["text", "example"])
          ],
          "objectives" => [
            objective("m1-subject", "subject", "know", ["01-intro"]),
            objective("m1-method", "method", "apply", ["02-practice"]),
            objective("m1-self", "self", "judge", ["02-practice"]),
            objective("m1-social", "social", "judge", ["02-practice"])
          ],
          "items" => [
            item("m1-choice", "single_choice", ["m1-subject"]),
            item("m1-drill", "checklist_drill", ["m1-method"]),
            item("m1-poll", "poll", []),
            Map.put(item("m1-exam-a", "multiple_choice", ["m1-subject"]), "lesson", nil)
          ],
          "assessments" => [assessment("m1-exam", true, ["m1-exam-a"])]
        },
        %{
          "number" => 2,
          "areas_elsewhere" => %{
            "self" => elsewhere("format:workshop"),
            "social" => elsewhere("format:workshop")
          },
          "lessons" => [lesson("01-compare", 1, ["text", "case_comparison"])],
          "objectives" => [
            objective("m2-subject", "subject", "apply", ["01-compare"]),
            objective("m2-method", "method", "judge", ["01-compare"])
          ],
          "items" => [
            item("m2-slots", "slot_builder", ["m2-subject"]),
            item("m2-sort", "classification", ["m2-method"])
          ],
          "assessments" => []
        }
      ]
    }
  end

  defp objective(key, area, depth, taught_in) do
    %{
      "key" => key,
      "statement" => "Learners can do what #{key} names.",
      "area" => area,
      "depth" => depth,
      "phase" => "understand",
      "domain" => nil,
      "taught_in" => taught_in
    }
  end

  defp item(key, kind, objectives) do
    %{
      "key" => key,
      "kind" => kind,
      "lesson" => "01-intro",
      "stem" => "Stem of #{key}",
      "core" => false,
      "phase" => "apply",
      "provenance" => "invented",
      "objectives" => objectives,
      "rules" => [],
      "reveals" => [],
      "cite" => [],
      "options" => [],
      "config" => %{}
    }
  end

  defp lesson(key, position, block_kinds) do
    %{
      "key" => key,
      "title" => "Lesson #{key}",
      "position" => position,
      "blocks" => Enum.map(block_kinds, &block/1)
    }
  end

  defp block(kind) do
    %{
      "kind" => kind,
      "body" => "Body",
      "provenance" => "invented",
      "collapsed_on" => [],
      "placeholder_key" => nil,
      "cite" => []
    }
  end

  defp assessment(key, counts_for_credential, items) do
    %{
      "key" => key,
      "title" => "Assessment #{key}",
      "kind" => if(counts_for_credential, do: "exam", else: "practice"),
      "counts_for_credential" => counts_for_credential,
      "max_wrong" => 0,
      "core_required" => false,
      "items" => items
    }
  end

  defp format(key, attendance_counts, objectives) do
    %{
      "key" => key,
      "title" => "Format #{key}",
      "description" => "Description of #{key}",
      "phases" => ["anchor"],
      "attendance_counts" => attendance_counts,
      "objectives" => objectives
    }
  end

  defp elsewhere(where), do: %{"where" => where, "reason" => "The place covers the area."}

  defp warn(payload), do: Map.put(payload, "alignment", "warn")

  defp add_orphan_exam_item(payload, counts_for_credential) do
    payload
    |> add_item(1, Map.put(item("m1-exam-orphan", "single_choice", []), "lesson", nil))
    |> update_module(1, fn module ->
      Map.put(module, "assessments", [
        assessment("m1-exam", counts_for_credential, ["m1-exam-a", "m1-exam-orphan"])
      ])
    end)
  end

  defp remove_social_of_module_1(payload) do
    payload
    |> update_module(1, fn module ->
      Map.update!(module, "objectives", fn objectives ->
        Enum.reject(objectives, &(&1["key"] == "m1-social"))
      end)
    end)
    |> update_format("workshop", &Map.put(&1, "objectives", ["m1-self"]))
  end

  defp put_elsewhere(payload, number, area, where) do
    update_module(payload, number, fn module ->
      Map.update!(module, "areas_elsewhere", &Map.put(&1, area, elsewhere(where)))
    end)
  end

  defp update_module(payload, number, fun) do
    Map.update!(payload, "modules", fn modules ->
      Enum.map(modules, &if(&1["number"] == number, do: fun.(&1), else: &1))
    end)
  end

  defp add_objective(payload, number, objective),
    do: append(payload, number, "objectives", objective)

  defp add_item(payload, number, item), do: append(payload, number, "items", item)
  defp add_lesson(payload, number, lesson), do: append(payload, number, "lessons", lesson)

  defp add_assessment(payload, number, assessment),
    do: append(payload, number, "assessments", assessment)

  defp append(payload, number, member, entry) do
    update_module(payload, number, &Map.update!(&1, member, fn entries -> entries ++ [entry] end))
  end

  defp update_objective(payload, key, fun) do
    update_entries(payload, "objectives", key, fun)
  end

  defp update_item(payload, key, fun), do: update_entries(payload, "items", key, fun)

  defp update_lesson(payload, number, key, fun) do
    update_module(
      payload,
      number,
      &Map.update!(&1, "lessons", fn lessons -> replace(lessons, key, fun) end)
    )
  end

  defp update_entries(payload, member, key, fun) do
    Map.update!(payload, "modules", fn modules ->
      Enum.map(modules, &Map.update!(&1, member, fn entries -> replace(entries, key, fun) end))
    end)
  end

  defp update_format(payload, key, fun) do
    Map.update!(payload, "formats", &replace(&1, key, fun))
  end

  defp replace(entries, key, fun) do
    Enum.map(entries, &if(&1["key"] == key, do: fun.(&1), else: &1))
  end

  defp row(rows, module, area, depth) do
    Enum.find(rows, &match?(%{module: ^module, area: ^area, depth: ^depth}, &1))
  end

  ## Program

  # The payload of the live rows that insert_program_with_archived_rows/0
  # writes.
  defp live_payload do
    %{
      "formats" => [
        format("workshop", true, ["m1-self", "m1-social"]),
        format("handbook", false, ["m1-social"])
      ],
      "modules" => [
        %{
          "number" => 1,
          "areas_elsewhere" => %{},
          "lessons" => [lesson("01-intro", 1, ["text"])],
          "objectives" => [
            objective("m1-subject", "subject", "know", ["01-intro"]),
            objective("m1-method", "method", "apply", ["01-intro"]),
            objective("m1-self", "self", "judge", ["01-intro"]),
            objective("m1-social", "social", "judge", ["01-intro"])
          ],
          "items" => [
            item("m1-choice", "single_choice", ["m1-subject"]),
            item("m1-drill", "checklist_drill", ["m1-method"]),
            item("m1-poll", "poll", ["m1-subject"]),
            item("m1-exam-a", "multiple_choice", ["m1-subject"])
          ],
          "assessments" => [assessment("m1-exam", true, ["m1-exam-a"])]
        },
        %{
          "number" => 2,
          "areas_elsewhere" => %{
            "self" => elsewhere("format:workshop"),
            "social" => elsewhere("format:workshop")
          },
          "lessons" => [lesson("01-compare", 1, ["case_comparison"])],
          "objectives" => [
            objective("m2-subject", "subject", "apply", ["01-compare"]),
            objective("m2-method", "method", "judge", ["01-compare"])
          ],
          "items" => [
            item("m2-slots", "slot_builder", ["m2-subject"]),
            item("m2-sort", "classification", ["m2-method"])
          ],
          "assessments" => []
        }
      ]
    }
  end

  # The live rows of live_payload/0, plus an archived module with a live
  # lesson and objective, an archived lesson, objective, item and format,
  # each with join rows that point to it.
  defp insert_program_with_archived_rows do
    archived = DateTime.utc_now(:second)

    program =
      Repo.insert!(%Program{
        slug: "alignment-matrix",
        title: "Alignment matrix",
        locale: "en",
        status: :published,
        pack_version: "1.0.0"
      })

    m1 = insert_module(program, 1, %{})

    m2 =
      insert_module(program, 2, %{
        "self" => elsewhere("format:workshop"),
        "social" => elsewhere("format:workshop")
      })

    m3 = insert_module(program, 3, %{}, archived)

    intro = insert_lesson(m1, "01-intro", 1)
    retired_lesson = insert_lesson(m1, "02-retired", 2, archived)
    compare = insert_lesson(m2, "01-compare", 1)
    gone_lesson = insert_lesson(m3, "01-gone", 1)

    Repo.insert!(%Block{
      lesson_id: intro.id,
      position: 1,
      kind: :text,
      body: "Body",
      provenance: :invented
    })

    Repo.insert!(%Block{
      lesson_id: compare.id,
      position: 1,
      kind: :case_comparison,
      body: "Body",
      provenance: :invented
    })

    subject = insert_objective(m1, "m1-subject", :subject, :know, 1)
    method = insert_objective(m1, "m1-method", :method, :apply, 2)
    own = insert_objective(m1, "m1-self", :self, :judge, 3)
    social = insert_objective(m1, "m1-social", :social, :judge, 4)
    retired = insert_objective(m1, "m1-retired", :subject, :know, 5, archived)
    m2_subject = insert_objective(m2, "m2-subject", :subject, :apply, 1)
    m2_method = insert_objective(m2, "m2-method", :method, :judge, 2)
    gone = insert_objective(m3, "m3-gone", :subject, :know, 1)

    for objective <- [subject, method, own, social, retired], do: link_lesson(objective, intro)
    link_lesson(subject, retired_lesson)
    link_lesson(m2_subject, compare)
    link_lesson(m2_method, compare)
    link_lesson(gone, gone_lesson)

    choice = insert_item(m1, "m1-choice", :single_choice, 1)
    drill = insert_item(m1, "m1-drill", :checklist_drill, 2)
    poll = insert_item(m1, "m1-poll", :poll, 3)
    exam_a = insert_item(m1, "m1-exam-a", :multiple_choice, 4)
    retired_item = insert_item(m1, "m1-retired-item", :single_choice, 5, archived)
    slots = insert_item(m2, "m2-slots", :slot_builder, 1)
    classification = insert_item(m2, "m2-sort", :classification, 2)
    gone_item = insert_item(m3, "m3-gone-item", :single_choice, 1)

    link_objectives(choice, [subject, retired])
    link_objectives(drill, [method])
    link_objectives(poll, [subject])
    link_objectives(exam_a, [subject])
    link_objectives(retired_item, [subject])
    link_objectives(slots, [m2_subject])
    link_objectives(classification, [m2_method])
    link_objectives(gone_item, [subject])

    exam =
      Repo.insert!(%Assessment{
        program_id: program.id,
        module_id: m1.id,
        key: "m1-exam",
        title: "Exam",
        kind: :exam,
        counts_for_credential: true,
        max_wrong: 0,
        core_required: false
      })

    for {item, position} <- [{exam_a, 1}, {retired_item, 2}, {gone_item, 3}] do
      Repo.insert!(%AssessmentItem{assessment_id: exam.id, item_id: item.id, position: position})
    end

    workshop = insert_format(program, "workshop", true, 1)
    handbook = insert_format(program, "handbook", false, 2)
    retired_format = insert_format(program, "retired-format", true, 3, archived)

    link_format(workshop, [own, social, retired])
    link_format(handbook, [social])
    link_format(retired_format, [subject])

    program
  end

  defp insert_module(program, number, areas_elsewhere, archived_at \\ nil) do
    Repo.insert!(%CatalogModule{
      program_id: program.id,
      number: number,
      title: "Module #{number}",
      summary: "Summary",
      areas_elsewhere: areas_elsewhere,
      archived_at: archived_at
    })
  end

  defp insert_lesson(module, key, position, archived_at \\ nil) do
    Repo.insert!(%Lesson{
      module_id: module.id,
      key: key,
      position: position,
      title: "Lesson #{key}",
      archived_at: archived_at
    })
  end

  defp insert_objective(module, key, area, depth, position, archived_at \\ nil) do
    Repo.insert!(%LearningObjective{
      program_id: module.program_id,
      module_id: module.id,
      key: key,
      statement: "Learners can do what #{key} names.",
      area: area,
      depth: depth,
      phase: :understand,
      position: position,
      archived_at: archived_at
    })
  end

  defp insert_item(module, key, kind, position, archived_at \\ nil) do
    Repo.insert!(%Item{
      program_id: module.program_id,
      module_id: module.id,
      key: key,
      kind: kind,
      stem: "Stem of #{key}",
      core: false,
      phase: :apply,
      provenance: :invented,
      position: position,
      archived_at: archived_at
    })
  end

  defp insert_format(program, key, attendance_counts, position, archived_at \\ nil) do
    Repo.insert!(%CompanionFormat{
      program_id: program.id,
      key: key,
      title: "Format #{key}",
      description: "Description of #{key}",
      attendance_counts: attendance_counts,
      position: position,
      archived_at: archived_at
    })
  end

  defp link_lesson(objective, lesson) do
    Repo.insert_all("objective_lessons", [
      %{learning_objective_id: UUID.dump!(objective.id), lesson_id: UUID.dump!(lesson.id)}
    ])
  end

  defp link_objectives(item, objectives) do
    Repo.insert_all(
      "item_objectives",
      for(
        objective <- objectives,
        do: %{item_id: UUID.dump!(item.id), learning_objective_id: UUID.dump!(objective.id)}
      )
    )
  end

  defp link_format(format, objectives) do
    Repo.insert_all(
      "format_objectives",
      for(
        objective <- objectives,
        do: %{
          companion_format_id: UUID.dump!(format.id),
          learning_objective_id: UUID.dump!(objective.id)
        }
      )
    )
  end
end
