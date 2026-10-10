defmodule Espalier.Catalog.AlignmentMatrixTest do
  use Espalier.DataCase, async: true

  import Espalier.PackFixtures

  alias Espalier.Catalog
  alias Espalier.Catalog.{Alignment, LearningObjective, PackImport}
  alias Espalier.Catalog.Pack.{Importer, Publisher}

  @slug "ai-assistant-basics-demo"
  @areas ~w(subject method self social)
  @depths ~w(know apply judge)
  @row_keys [:area, :depth, :elsewhere, :evidence, :lessons, :module, :objectives]

  @objectives "modules/01-basics/objectives.yaml"
  @items "modules/01-basics/items.yaml"

  describe "matrix/1 on the demo payload" do
    setup do
      %{payload: import!(demo_path()).payload}
    end

    test "has 24 rows: modules by number, then areas, then depths", %{payload: payload} do
      rows = Alignment.matrix(payload)

      assert length(rows) == 24

      assert Enum.map(rows, &{&1.module, &1.area, &1.depth}) ==
               for(module <- [1, 2], area <- @areas, depth <- @depths, do: {module, area, depth})

      for row <- rows, do: assert(row |> Map.keys() |> Enum.sort() == @row_keys)
    end

    test "every list of every row is sorted and free of duplicates", %{payload: payload} do
      assert_sorted_and_unique(Alignment.matrix(payload))
    end

    test "module 1, subject, know lists both subject objectives with lessons 1 and 2 and exam evidence",
         %{payload: payload} do
      row = row(Alignment.matrix(payload), 1, "subject", "know")

      assert row.objectives == ["m1-subject-next-word", "m1-subject-varying-answers"]
      assert row.lessons == ["01-first-lesson", "02-second-lesson"]

      assert row.evidence == [
               "item:m1-exam-confident-answer",
               "item:m1-exam-next-word",
               "item:m1-exam-varying-answers",
               "item:m1-fluent-figure",
               "item:m1-how-models-write",
               "item:m1-why-answers-vary"
             ]

      assert Enum.any?(row.evidence, &(&1 in exam_evidence(payload)))
      assert row.elsewhere == nil
    end

    test "module 1, method, know lists m1-method-check-claims with one practice item and exam evidence",
         %{payload: payload} do
      row = row(Alignment.matrix(payload), 1, "method", "know")

      assert row.objectives == ["m1-method-check-claims"]
      assert row.lessons == ["03-third-lesson"]
      assert row.evidence == ["item:m1-before-use", "item:m1-exam-check-claims"]

      assert Enum.filter(row.evidence, &(&1 in practice_evidence(payload))) == [
               "item:m1-before-use"
             ]

      assert Enum.filter(row.evidence, &(&1 in exam_evidence(payload))) == [
               "item:m1-exam-check-claims"
             ]

      assert row.elsewhere == nil
    end

    test "module 1, self, judge lists m1-self-own-responsibility with the evidence format:workshop",
         %{payload: payload} do
      assert row(Alignment.matrix(payload), 1, "self", "judge") == %{
               module: 1,
               area: "self",
               depth: "judge",
               objectives: ["m1-self-own-responsibility"],
               lessons: ["03-third-lesson"],
               evidence: ["format:workshop"],
               elsewhere: nil
             }
    end

    test "module 2, method, judge lists m2-method-judge-output with its classification item",
         %{payload: payload} do
      assert row(Alignment.matrix(payload), 2, "method", "judge") == %{
               module: 2,
               area: "method",
               depth: "judge",
               objectives: ["m2-method-judge-output"],
               lessons: ["02-second-lesson"],
               evidence: ["item:m2-judge-drafts"],
               elsewhere: nil
             }

      assert %{"kind" => "classification", "objectives" => ["m2-method-judge-output"]} =
               payload_item(payload, 2, "m2-judge-drafts")
    end

    test "the three social rows of module 2 have empty lists and elsewhere format:workshop",
         %{payload: payload} do
      rows = Alignment.matrix(payload)

      for depth <- @depths do
        assert row(rows, 2, "social", depth) == %{
                 module: 2,
                 area: "social",
                 depth: depth,
                 objectives: [],
                 lessons: [],
                 evidence: [],
                 elsewhere: "format:workshop"
               }
      end
    end

    test "gives the full matrix of the demo pack", %{payload: payload} do
      assert Alignment.matrix(payload) == demo_matrix()
    end
  end

  describe "matrix/1 on the published demo program" do
    test "equals matrix/1 on the payload after a publish" do
      pack_import = import!(demo_path())
      program = publish!(pack_import)
      rows = Alignment.matrix(program)

      assert rows == Alignment.matrix(pack_import.payload)
      assert rows == Alignment.matrix(Repo.get!(PackImport, pack_import.id).payload)
      assert rows == demo_matrix()
      assert_sorted_and_unique(rows)
    end

    test "after a second publish without m1-subject-varying-answers, no row lists it" do
      first = import!(demo_path())
      program = publish!(first)
      assert "m1-subject-varying-answers" in listed(Alignment.matrix(program))

      pack = copy_pack!(demo_path())

      update_yaml!(pack, @objectives, fn objectives ->
        Enum.reject(objectives, &(&1["key"] == "m1-subject-varying-answers"))
      end)

      replace!(
        pack,
        @items,
        "objectives: [m1-subject-varying-answers]",
        "objectives: [m1-subject-next-word]",
        global: true
      )

      refute read!(pack, @objectives) =~ "m1-subject-varying-answers"
      refute read!(pack, @items) =~ "m1-subject-varying-answers"

      second = import!(pack)
      assert publish!(second).id == program.id

      rows = Alignment.matrix(program)

      refute "m1-subject-varying-answers" in listed(rows)
      assert rows == Alignment.matrix(second.payload)
      assert rows != Alignment.matrix(first.payload)
      assert_sorted_and_unique(rows)

      assert row(rows, 1, "subject", "know") == %{
               module: 1,
               area: "subject",
               depth: "know",
               objectives: ["m1-subject-next-word"],
               lessons: ["01-first-lesson"],
               evidence: [
                 "item:m1-exam-confident-answer",
                 "item:m1-exam-next-word",
                 "item:m1-exam-varying-answers",
                 "item:m1-fluent-figure",
                 "item:m1-how-models-write",
                 "item:m1-why-answers-vary"
               ],
               elsewhere: nil
             }

      # The objective keeps its row with archived_at set, so the program
      # matrix leaves it out because it skips archived rows.
      archived =
        Repo.get_by!(LearningObjective,
          program_id: program.id,
          key: "m1-subject-varying-answers"
        )

      assert archived.archived_at
    end

    test "lessons and items shared by two objectives of a row appear once" do
      pack = copy_pack!(demo_path())

      replace!(
        pack,
        @objectives,
        "taught_in: [02-second-lesson]",
        "taught_in: [02-second-lesson, 01-first-lesson]"
      )

      replace!(
        pack,
        @items,
        "objectives: [m1-subject-varying-answers]",
        "objectives: [m1-subject-varying-answers, m1-subject-next-word]"
      )

      pack_import = import!(pack)
      program = publish!(pack_import)

      for rows <- [Alignment.matrix(pack_import.payload), Alignment.matrix(program)] do
        assert_sorted_and_unique(rows)

        assert %{
                 objectives: ["m1-subject-next-word", "m1-subject-varying-answers"],
                 lessons: ["01-first-lesson", "02-second-lesson"],
                 evidence: [
                   "item:m1-exam-confident-answer",
                   "item:m1-exam-next-word",
                   "item:m1-exam-varying-answers",
                   "item:m1-fluent-figure",
                   "item:m1-how-models-write",
                   "item:m1-why-answers-vary"
                 ]
               } = row(rows, 1, "subject", "know")
      end

      assert Alignment.matrix(program) == Alignment.matrix(pack_import.payload)
    end
  end

  ## Import and publish

  defp import!(pack) do
    assert {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(pack, nil)
    assert pack_import.report == %{"errors" => [], "warnings" => []}
    pack_import
  end

  defp publish!(pack_import) do
    assert {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    assert %Catalog.Program{} = program = Catalog.get_program_by_slug(@slug)
    program
  end

  ## Matrix

  # The 24 rows of the demo pack: module 1 covers the four areas with its own
  # objectives, and module 2 finds `self` and `social` at the workshop.
  defp demo_matrix do
    filled = %{
      {1, "subject", "know"} =>
        {["m1-subject-next-word", "m1-subject-varying-answers"],
         ["01-first-lesson", "02-second-lesson"],
         [
           "item:m1-exam-confident-answer",
           "item:m1-exam-next-word",
           "item:m1-exam-varying-answers",
           "item:m1-fluent-figure",
           "item:m1-how-models-write",
           "item:m1-why-answers-vary"
         ]},
      {1, "method", "know"} =>
        {["m1-method-check-claims"], ["03-third-lesson"],
         ["item:m1-before-use", "item:m1-exam-check-claims"]},
      {1, "self", "judge"} =>
        {["m1-self-own-responsibility"], ["03-third-lesson"], ["format:workshop"]},
      {1, "social", "judge"} =>
        {["m1-social-team-transparency"], ["03-third-lesson"], ["format:workshop"]},
      {2, "subject", "apply"} =>
        {["m2-subject-prompt-parts"], ["01-first-lesson"], ["item:m2-prompt-builder"]},
      {2, "method", "apply"} =>
        {["m2-method-release-check"], ["02-second-lesson"], ["item:m2-release-drill"]},
      {2, "method", "judge"} =>
        {["m2-method-judge-output"], ["02-second-lesson"], ["item:m2-judge-drafts"]}
    }

    elsewhere = %{{2, "self"} => "format:workshop", {2, "social"} => "format:workshop"}

    for module <- [1, 2], area <- @areas, depth <- @depths do
      {objectives, lessons, evidence} = Map.get(filled, {module, area, depth}, {[], [], []})

      %{
        module: module,
        area: area,
        depth: depth,
        objectives: objectives,
        lessons: lessons,
        evidence: evidence,
        elsewhere: Map.get(elsewhere, {module, area})
      }
    end
  end

  defp row(rows, module, area, depth) do
    Enum.find(rows, &match?(%{module: ^module, area: ^area, depth: ^depth}, &1))
  end

  defp listed(rows) do
    Enum.flat_map(rows, &(&1.objectives ++ &1.lessons ++ &1.evidence ++ [&1.elsewhere]))
  end

  defp assert_sorted_and_unique(rows) do
    for row <- rows, list <- [row.objectives, row.lessons, row.evidence] do
      assert list == list |> Enum.uniq() |> Enum.sort(),
             "#{inspect({row.module, row.area, row.depth})}: #{inspect(list)} is not sorted and unique"
    end
  end

  ## Payload

  defp payload_module(payload, number) do
    Enum.find(payload["modules"], &(&1["number"] == number))
  end

  defp payload_item(payload, number, key) do
    Enum.find(payload_module(payload, number)["items"], &(&1["key"] == key))
  end

  # `item:<key>` for every item of the exam `module-1-exam`.
  defp exam_evidence(payload) do
    exam = Enum.find(payload_module(payload, 1)["assessments"], &(&1["key"] == "module-1-exam"))
    assert exam["counts_for_credential"] == true
    assert length(exam["items"]) == 4
    Enum.map(exam["items"], &"item:#{&1}")
  end

  # `item:<key>` for every practice item of module 1: an item with a lesson.
  defp practice_evidence(payload) do
    for item <- payload_module(payload, 1)["items"], item["lesson"], do: "item:#{item["key"]}"
  end
end
