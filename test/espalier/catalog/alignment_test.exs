defmodule Espalier.Catalog.AlignmentTest do
  # The alignment checks of task 0008 step 13 on fixture packs (step 15,
  # "Alignment"): each case runs `Alignment.check/1` on the payload of
  # `Validator.run/1` and `Validator.validate/1` on the loaded pack, which
  # places the finding at the path in the pack and the line of the entry.
  use ExUnit.Case, async: true

  import Espalier.PackFixtures

  alias Espalier.Catalog.Alignment
  alias Espalier.Catalog.Pack.{Loader, Validator}

  @module1 "modules/01-basics/module.yaml"
  @module2 "modules/02-checking/module.yaml"
  @objectives1 "modules/01-basics/objectives.yaml"
  @objectives2 "modules/02-checking/objectives.yaml"
  @items1 "modules/01-basics/items.yaml"
  @assessment1 "modules/01-basics/assessment.yaml"
  @check_lesson "modules/02-checking/lessons/01-check.md"
  @other_lesson "modules/02-checking/lessons/02-other.md"

  @modes [:strict, :warn]

  describe "check 1" do
    test "an objective with an empty taught_in is an error in strict and a warning in warn mode" do
      for mode <- @modes do
        pack = pack(mode)
        # The first `taught_in: [02-practice]` belongs to m1-method-build-prompt.
        replace!(pack, @objectives1, "taught_in: [02-practice]", "taught_in: []")

        finding =
          assert_one_finding(
            pack,
            grade(mode),
            %{check: 1, module: 1, file: "objectives.yaml", key: "m1-method-build-prompt"},
            @objectives1,
            line_of!(pack, @objectives1, "key: m1-method-build-prompt")
          )

        assert finding.message ==
                 "objective `m1-method-build-prompt` names no teaching lesson in `taught_in`"
      end
    end

    test "an objective whose only links are a poll outside every assessment and a format without attendance" do
      for mode <- @modes do
        pack = pack(mode)
        append!(pack, @objectives1, objective_yaml("m1-subject-anchored", "subject", "know"))
        # m1-poll is the only item with the phase `orient`, and no assessment lists it.
        replace!(
          pack,
          @items1,
          "phase: orient\n",
          "phase: orient\n  objectives: [m1-subject-anchored]\n"
        )

        replace!(
          pack,
          "formats.yaml",
          "attendance_counts: false\n",
          "attendance_counts: false\n  objectives: [m1-subject-anchored]\n"
        )

        payload = payload!(pack)
        assert %{"kind" => "poll", "lesson" => "01-intro"} = item(payload, "m1-poll")
        assert item(payload, "m1-poll")["objectives"] == ["m1-subject-anchored"]
        refute "m1-poll" in assessed_items(payload)
        assert %{"attendance_counts" => false} = format(payload, "handbook")
        assert format(payload, "handbook")["objectives"] == ["m1-subject-anchored"]

        finding =
          assert_one_finding(
            pack,
            grade(mode),
            %{check: 1, module: 1, file: "objectives.yaml", key: "m1-subject-anchored"},
            @objectives1,
            line_of!(pack, @objectives1, "key: m1-subject-anchored")
          )

        assert finding.message ==
                 "objective `m1-subject-anchored` has no evidence: no item of an assessment, " <>
                   "no item with a correct answer and no format with `attendance_counts: true` " <>
                   "names it"
      end
    end

    test "an objective whose only evidence is a format with attendance_counts true has no finding" do
      for mode <- @modes do
        pack = pack(mode)
        append!(pack, @objectives1, objective_yaml("m1-self-reflect", "self", "judge"))
        append!(pack, "formats.yaml", format_yaml("peer-review", true, ["m1-self-reflect"]))

        payload = payload!(pack)
        refute Enum.any?(all_items(payload), &("m1-self-reflect" in &1["objectives"]))
        assert no_findings?(pack)

        # The same format without attendance provides no evidence.
        replace!(
          pack,
          "formats.yaml",
          "attendance_counts: true\n  objectives: [m1-self-reflect]",
          "attendance_counts: false\n  objectives: [m1-self-reflect]"
        )

        assert_one_finding(
          pack,
          grade(mode),
          %{check: 1, module: 1, file: "objectives.yaml", key: "m1-self-reflect"},
          @objectives1,
          line_of!(pack, @objectives1, "key: m1-self-reflect")
        )
      end
    end

    test "an objective whose only evidence is a checklist_drill has no finding" do
      for mode <- @modes do
        pack = pack(mode)
        payload = payload!(pack)

        assert [%{"key" => "m2-drill", "kind" => "checklist_drill", "lesson" => "01-check"}] =
                 Enum.filter(all_items(payload), &("m2-method-release-check" in &1["objectives"]))

        refute "m2-drill" in assessed_items(payload)

        refute Enum.any?(
                 payload["formats"],
                 &("m2-method-release-check" in &1["objectives"])
               )

        assert no_findings?(pack)
      end
    end
  end

  describe "check 2" do
    test "an orphan exam item is an error in strict and a warning in warn mode" do
      for mode <- @modes do
        pack = pack(mode)
        orphan_exam_item!(pack)

        payload = payload!(pack)

        assert %{"key" => "m1-exam", "counts_for_credential" => true, "items" => items} =
                 assessment(payload, "m1-exam")

        assert "m1-exam-2" in items
        assert item(payload, "m1-exam-2")["objectives"] == []

        finding =
          assert_one_finding(
            pack,
            grade(mode),
            %{check: 2, module: 1, file: "items.yaml", key: "m1-exam-2"},
            @items1,
            line_of!(pack, @items1, "key: m1-exam-2")
          )

        assert finding.message ==
                 "item `m1-exam-2` names no objective in `objectives`, but the assessment " <>
                   "`m1-exam` lists it and counts for a credential"
      end
    end

    test "the same item in an assessment with counts_for_credential false has no finding" do
      for mode <- @modes do
        pack = pack(mode)
        orphan_exam_item!(pack)

        replace!(
          pack,
          @assessment1,
          "counts_for_credential: true",
          "counts_for_credential: false"
        )

        assert %{"counts_for_credential" => false, "items" => ["m1-exam-1", "m1-exam-2"]} =
                 assessment(payload!(pack), "m1-exam")

        assert no_findings?(pack)
      end
    end
  end

  describe "check 3" do
    test "a module without a social objective and without areas_elsewhere is an error in strict and a warning in warn mode" do
      for mode <- @modes do
        pack = pack(mode)
        # Module 2 covers `self` with an objective of its own, so that only
        # `social` stays open once `areas_elsewhere` is gone.
        append!(
          pack,
          @objectives2,
          objective_yaml("m2-self-check-habits", "self", "judge", "01-check")
        )

        replace!(
          pack,
          "formats.yaml",
          "objectives: [m1-self-judge-tasks, m1-social-agree-team]",
          "objectives: [m1-self-judge-tasks, m1-social-agree-team, m2-self-check-habits]"
        )

        [head, _areas] = String.split(read!(pack, @module2), "areas_elsewhere:\n", parts: 2)
        write!(pack, @module2, head)

        assert %{"areas_elsewhere" => areas} = module(payload!(pack), 2)
        assert areas == %{}

        finding =
          assert_one_finding(
            pack,
            grade(mode),
            %{check: 3, module: 2, file: "module.yaml", key: "social"},
            @module2,
            1
          )

        assert finding.message ==
                 "no objective of module 2 has the area `social`, and `areas_elsewhere` does " <>
                   "not name the area"
      end
    end

    test "social named as format:workshop passes when the workshop names a social objective" do
      for mode <- @modes do
        pack = pack(mode)
        elsewhere_workshop!(pack)

        payload = payload!(pack)
        assert %{"where" => "format:workshop"} = module(payload, 2)["areas_elsewhere"]["social"]
        assert "m1-social-agree-team" in format(payload, "workshop")["objectives"]
        assert objective(payload, "m1-social-agree-team")["area"] == "social"
        refute Enum.any?(module(payload, 2)["objectives"], &(&1["area"] == "social"))

        assert no_findings?(pack)
      end
    end

    test "social named as format:workshop gives the finding when the workshop names no social objective" do
      for mode <- @modes do
        pack = pack(mode)
        elsewhere_workshop!(pack)
        # The social objective of module 1 keeps its evidence at another format.
        replace!(
          pack,
          "formats.yaml",
          "objectives: [m1-self-judge-tasks, m1-social-agree-team]",
          "objectives: [m1-self-judge-tasks]"
        )

        append!(pack, "formats.yaml", format_yaml("team-session", true, ["m1-social-agree-team"]))

        finding =
          assert_one_finding(
            pack,
            grade(mode),
            %{check: 3, module: 2, file: "module.yaml", key: "social"},
            @module2,
            line_of!(pack, @module2, "social:")
          )

        assert finding.message ==
                 "no objective of module 2 has the area `social`, and `format:workshop` named " <>
                   "in `areas_elsewhere` carries no `social` objective"
      end
    end

    test "social named as module:<number> passes when that module has a social objective" do
      for mode <- @modes do
        pack = pack(mode)

        payload = payload!(pack)
        assert %{"where" => "module:1"} = module(payload, 2)["areas_elsewhere"]["social"]
        assert objective(payload, "m1-social-agree-team")["area"] == "social"
        refute Enum.any?(module(payload, 2)["objectives"], &(&1["area"] == "social"))

        assert no_findings?(pack)
      end
    end

    test "social named as module:<number> gives the finding when that module has no social objective" do
      for mode <- @modes do
        pack = pack(mode)
        replace!(pack, @objectives1, "area: social", "area: self")

        assert {graded, []} = by_grade(grade(mode), Alignment.check(payload!(pack)))

        assert [
                 %{check: 3, module: 1, file: "module.yaml", key: "social"} = module_1,
                 %{check: 3, module: 2, file: "module.yaml", key: "social"} = module_2
               ] = graded

        assert module_1.message ==
                 "no objective of module 1 has the area `social`, and `areas_elsewhere` does " <>
                   "not name the area"

        assert module_2.message ==
                 "no objective of module 2 has the area `social`, and `module:1` named in " <>
                   "`areas_elsewhere` carries no `social` objective"

        assert by_grade(grade(mode), validate!(pack)) ==
                 {[
                    entry(module_1, @module1, 1),
                    entry(module_2, @module2, line_of!(pack, @module2, "social:"))
                  ], []}
      end
    end
  end

  describe "check 4" do
    test "a know objective whose only evidence is a checklist_drill is a warning in both modes and no error" do
      for mode <- @modes do
        pack = pack(mode)
        replace!(pack, @objectives2, "depth: apply", "depth: know")

        assert %{"depth" => "know"} = objective(payload!(pack), "m2-method-release-check")

        finding =
          assert_one_finding(
            pack,
            :warning,
            %{check: 4, module: 2, file: "objectives.yaml", key: "m2-method-release-check"},
            @objectives2,
            line_of!(pack, @objectives2, "key: m2-method-release-check")
          )

        assert finding.message ==
                 "evidence of objective `m2-method-release-check` has the kinds " <>
                   "`checklist_drill`, none of which fits the depth `know` (`single_choice` or " <>
                   "`multiple_choice`)"
      end
    end

    test "an apply objective whose only evidence is a format is a warning" do
      for mode <- @modes do
        pack = pack(mode)
        # The first `depth: judge` belongs to m1-self-judge-tasks, whose only
        # evidence is the workshop.
        replace!(pack, @objectives1, "depth: judge", "depth: apply")

        payload = payload!(pack)
        assert %{"depth" => "apply"} = objective(payload, "m1-self-judge-tasks")
        refute Enum.any?(all_items(payload), &("m1-self-judge-tasks" in &1["objectives"]))

        finding =
          assert_one_finding(
            pack,
            :warning,
            %{check: 4, module: 1, file: "objectives.yaml", key: "m1-self-judge-tasks"},
            @objectives1,
            line_of!(pack, @objectives1, "key: m1-self-judge-tasks")
          )

        assert finding.message ==
                 "evidence of objective `m1-self-judge-tasks` has the kinds `format`, none of " <>
                   "which fits the depth `apply` (`slot_builder`, `classification` or " <>
                   "`checklist_drill`)"
      end
    end

    test "a judge objective with a classification item is a warning without a case_comparison block in a teaching lesson" do
      for mode <- @modes do
        pack = pack(mode)
        replace!(pack, @check_lesson, ":::case_comparison{", ":::example{")
        # The module still holds a case comparison, in a lesson that does not
        # teach the objective.
        write!(pack, @other_lesson, other_lesson_md())

        payload = payload!(pack)

        assert %{"depth" => "judge", "taught_in" => ["01-check"]} =
                 objective(payload, "m2-subject-judge-drafts")

        assert %{"kind" => "classification", "objectives" => ["m2-subject-judge-drafts"]} =
                 item(payload, "m2-classify")

        assert [%{"key" => "01-check"} = check, %{"key" => "02-other"} = other] =
                 module(payload, 2)["lessons"]

        assert Enum.map(check["blocks"], & &1["kind"]) == ["example"]
        assert Enum.map(other["blocks"], & &1["kind"]) == ["case_comparison"]

        finding =
          assert_one_finding(
            pack,
            :warning,
            %{check: 4, module: 2, file: "objectives.yaml", key: "m2-subject-judge-drafts"},
            @objectives2,
            line_of!(pack, @objectives2, "key: m2-subject-judge-drafts")
          )

        assert finding.message ==
                 "evidence of objective `m2-subject-judge-drafts` has the kinds " <>
                   "`classification`, none of which fits the depth `judge` " <>
                   "(`classification_with_case_comparison` or `format`)"
      end
    end

    test "a judge objective with a classification item has no finding with a case_comparison block in a teaching lesson" do
      for mode <- @modes do
        pack = pack(mode)

        assert [%{"key" => "01-check", "blocks" => [%{"kind" => "case_comparison"}]}] =
                 module(payload!(pack), 2)["lessons"]

        assert no_findings?(pack)

        # The block may sit in any lesson of `taught_in`.
        replace!(pack, @check_lesson, ":::case_comparison{", ":::example{")
        write!(pack, @other_lesson, other_lesson_md())

        replace!(
          pack,
          @objectives2,
          "phase: apply\n  taught_in: [01-check]",
          "phase: apply\n  taught_in: [01-check, 02-other]"
        )

        assert objective(payload!(pack), "m2-subject-judge-drafts")["taught_in"] ==
                 ["01-check", "02-other"]

        assert no_findings?(pack)
      end
    end
  end

  describe "the alignment setting" do
    test "a pack.yaml without alignment behaves as alignment strict" do
      [default, strict, warn] =
        for mode <- [nil, :strict, :warn] do
          pack = if mode, do: pack(mode), else: copy_pack!("minimal")
          orphan_exam_item!(pack)
          replace!(pack, @objectives2, "depth: apply", "depth: know")
          pack
        end

      refute read!(default, "pack.yaml") =~ "alignment"
      assert payload!(default)["alignment"] == "strict"
      assert payload!(strict)["alignment"] == "strict"
      assert payload!(warn)["alignment"] == "warn"

      assert {[orphan], [depth]} = Alignment.check(payload!(default))
      assert %{check: 2, module: 1, file: "items.yaml", key: "m1-exam-2"} = orphan

      assert %{check: 4, module: 2, file: "objectives.yaml", key: "m2-method-release-check"} =
               depth

      assert Alignment.check(payload!(strict)) == {[orphan], [depth]}
      assert Alignment.check(payload!(warn)) == {[], [orphan, depth]}

      orphan_entry = entry(orphan, @items1, line_of!(default, @items1, "key: m1-exam-2"))

      depth_entry =
        entry(
          depth,
          @objectives2,
          line_of!(default, @objectives2, "key: m2-method-release-check")
        )

      assert validate!(default) == {[orphan_entry], [depth_entry]}
      assert validate!(strict) == {[orphan_entry], [depth_entry]}
      assert validate!(warn) == {[], [orphan_entry, depth_entry]}
    end
  end

  ## Packs

  # A copy of the minimal pack with `alignment` set to `mode`. The minimal
  # pack passes all four checks.
  defp pack(mode) do
    pack = copy_pack!("minimal")
    replace!(pack, "pack.yaml", "version: 0.1.0", "version: 0.1.0\nalignment: #{mode}")
    pack
  end

  # Removes the objectives of the exam item m1-exam-2, which the exam
  # m1-exam lists with `counts_for_credential: true`.
  defp orphan_exam_item!(pack) do
    number = line_of!(pack, @items1, "objectives:", after: "key: m1-exam-2")
    lines = pack |> read!(@items1) |> String.split("\n") |> List.delete_at(number - 1)
    write!(pack, @items1, Enum.join(lines, "\n"))
  end

  # Names the workshop as the place of `social` in `areas_elsewhere` of
  # module 2, where the minimal pack names module 1.
  defp elsewhere_workshop!(pack) do
    replace!(pack, @module2, "where: module:1", "where: format:workshop")

    replace!(
      pack,
      @module2,
      "reason: Module 1 covers agreeing in a team how assistant use is made visible.",
      "reason: The workshop practises agreeing in a team how assistant use is made visible."
    )
  end

  defp append!(pack, rel, text), do: write!(pack, rel, read!(pack, rel) <> text)

  defp objective_yaml(key, area, depth, lesson \\ "02-practice") do
    """
    - key: #{key}
      statement: Learners can do what #{key} names.
      area: #{area}
      depth: #{depth}
      phase: anchor
      taught_in: [#{lesson}]
    """
  end

  defp format_yaml(key, attendance_counts, objectives) do
    """
    - key: #{key}
      title: Format #{key}
      description: A companion format for the test.
      phases: [anchor]
      attendance_counts: #{attendance_counts}
      objectives: [#{Enum.join(objectives, ", ")}]
    """
  end

  defp other_lesson_md do
    """
    ---
    title: Other drafts
    position: 2
    ---

    :::case_comparison{provenance=invented}
    Draft C names its source. Draft D names none.
    :::
    """
  end

  ## Running the checks

  defp load!(pack) do
    assert {:ok, loaded} = Loader.load(pack)
    loaded
  end

  # The payload of `Validator.run/1`, which exists once the checks before
  # the alignment report no error.
  defp payload!(pack) do
    assert %{payload: payload} = pack |> load!() |> Validator.run()
    assert is_map(payload)
    payload
  end

  defp validate!(pack), do: pack |> load!() |> Validator.validate()

  defp no_findings?(pack) do
    assert Alignment.check(payload!(pack)) == {[], []}
    assert validate!(pack) == {[], []}
    true
  end

  # Asserts that `check/1` on the payload of `pack` gives exactly one
  # finding, graded as `grade`, with the members of `expected`, and that
  # `validate/1` gives exactly the entry of that finding at `file` and
  # `line`. Returns the finding.
  defp assert_one_finding(pack, grade, expected, file, line) do
    assert {[finding], []} = by_grade(grade, Alignment.check(payload!(pack)))
    assert Map.take(finding, [:check, :module, :file, :key]) == expected
    assert is_binary(finding.message) and finding.message != ""
    assert by_grade(grade, validate!(pack)) == {[entry(finding, file, line)], []}
    finding
  end

  # Returns `{graded, other}`: the list of the grade first.
  defp by_grade(:error, {errors, warnings}), do: {errors, warnings}
  defp by_grade(:warning, {errors, warnings}), do: {warnings, errors}

  defp grade(:strict), do: :error
  defp grade(:warn), do: :warning

  defp entry(finding, file, line) do
    %{
      file: file,
      line: line,
      check: finding.check,
      module: finding.module,
      key: finding.key,
      message: finding.message
    }
  end

  ## Payload lookups

  defp module(payload, number), do: Enum.find(payload["modules"], &(&1["number"] == number))

  defp all_items(payload), do: Enum.flat_map(payload["modules"], & &1["items"])

  defp item(payload, key), do: Enum.find(all_items(payload), &(&1["key"] == key))

  defp objective(payload, key) do
    payload["modules"] |> Enum.flat_map(& &1["objectives"]) |> Enum.find(&(&1["key"] == key))
  end

  defp assessment(payload, key) do
    payload["modules"] |> Enum.flat_map(& &1["assessments"]) |> Enum.find(&(&1["key"] == key))
  end

  defp assessed_items(payload) do
    for module <- payload["modules"],
        assessment <- module["assessments"],
        key <- assessment["items"],
        do: key
  end

  defp format(payload, key), do: Enum.find(payload["formats"], &(&1["key"] == key))
end
