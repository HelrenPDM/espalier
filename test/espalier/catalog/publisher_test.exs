defmodule Espalier.Catalog.PublisherTest do
  use Espalier.DataCase, async: true

  alias Espalier.Catalog.{
    Assessment,
    AssessmentItem,
    Block,
    Citation,
    CompanionFormat,
    GlossaryTerm,
    Item,
    LearningObjective,
    Lesson,
    Option,
    PackImport,
    Program,
    Qualification,
    Requirement,
    Rule,
    Segment,
    Source,
    Station
  }

  import Espalier.PackFixtures,
    only: [
      copy_pack!: 1,
      demo_path: 0,
      path: 2,
      read!: 2,
      read_yaml!: 2,
      replace!: 4,
      update_yaml!: 3,
      write!: 3
    ]

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Pack.{Importer, Publisher}

  @key "publisher-test"

  @demo_key "ai-assistant-basics-demo"
  @items1 "modules/01-basics/items.yaml"
  @items2 "modules/02-checking/items.yaml"
  @objectives1 "modules/01-basics/objectives.yaml"
  @objectives2 "modules/02-checking/objectives.yaml"

  # The counts of the Acceptance section of task 0008 for the demo pack: the
  # catalog tables, then the learning objectives and their join tables.
  @catalog_tables [
    :modules,
    :lessons,
    :rules,
    :items,
    :assessments,
    :qualifications,
    :requirements,
    :formats,
    :stations,
    :segments,
    :glossary,
    :sources
  ]
  @alignment_tables [:objectives, :objective_lessons, :item_objectives, :format_objectives]
  @demo_counts {"2|5|10|12|1|2|6|3|7|4|8|2", "8|8|11|2"}

  describe "publish/1" do
    test "applies the payload of a validated import to the catalog tables" do
      pack_import = validated(payload())
      assert {:ok, published} = Publisher.publish(pack_import)

      assert published.id == pack_import.id
      assert published.status == :published
      assert %DateTime{microsecond: {0, 0}} = published.published_at
      assert Repo.get!(PackImport, pack_import.id).status == :published

      program = program!()
      assert program.status == :published
      assert program.title == "Publisher test"
      assert program.locale == "en"
      assert program.pack_version == "1.0.0"

      assert counts(program) == %{
               modules: 2,
               lessons: 5,
               rules: 3,
               objectives: 4,
               items: 6,
               assessments: 1,
               qualifications: 2,
               requirements: 6,
               formats: 2,
               stations: 4,
               segments: 2,
               glossary: 2,
               sources: 2,
               blocks: 7,
               options: 10,
               citations: 4,
               item_rules: 7,
               item_reveals: 1,
               assessment_items: 2,
               prerequisites: 1,
               objective_lessons: 4,
               item_objectives: 6,
               format_objectives: 1
             }
    end

    test "writes positions, parents and the values of every row" do
      publish!(payload())
      program = program!()
      modules = module_ids(program)
      lessons = lesson_ids(program)

      [one, two] =
        Repo.all(from m in CatalogModule, where: m.program_id == ^program.id, order_by: m.number)

      assert one.areas_elsewhere == %{}
      assert one.domains == ["drafting", "research"]
      assert one.phases == [:orient, :understand]
      assert two.single_path and two.refresher_unit
      assert two.areas_elsewhere == module_two()["areas_elsewhere"]

      assert [
               {1, :self_assessment, nil, %{"question" => "How often do you use an assistant?"}},
               {2, :module, module_one_id, %{}},
               {3, :module, module_two_id, %{}},
               {4, :feedback, nil, %{"intro" => "Tell us what helped.", "questions" => [_]}}
             ] =
               Repo.all(
                 from s in Station,
                   where: s.program_id == ^program.id,
                   order_by: s.position,
                   select: {s.position, s.kind, s.module_id, s.config}
               )

      assert module_one_id == modules[1] and module_two_id == modules[2]

      assert [{"daily", 1, :short}, {"never", 2, :full}] =
               Repo.all(
                 from s in Segment,
                   where: s.program_id == ^program.id,
                   order_by: s.position,
                   select: {s.key, s.position, s.default_path}
               )

      assert %Source{url: nil, edition_date: ~D[2026-05-30], kind: :other} =
               Repo.get_by!(Source, program_id: program.id, key: "invented-guide")

      assert [{"m1-subject-next-word", 1}, {"m1-moving", 2}, {"m1-self-own-tasks", 3}] =
               Repo.all(
                 from o in LearningObjective,
                   where: o.module_id == ^modules[1],
                   order_by: o.position,
                   select: {o.key, o.position}
               )

      practice = item!(program, "m1-practice")
      assert practice.lesson_id == lessons[{1, "01-first-lesson"}]
      assert practice.module_id == modules[1]
      assert practice.position == 1
      assert practice.kind == :single_choice

      exam_one = item!(program, "m1-exam-one")
      assert exam_one.lesson_id == nil
      assert exam_one.core
      assert exam_one.position == 4

      drill = item!(program, "m2-release-drill")
      assert drill.module_id == modules[2]
      assert drill.lesson_id == lessons[{2, "02-second-lesson"}]
      assert [%{"key" => "sources", "required" => true}, _] = drill.config["checks"]

      assert [{"a", 1, true}, {"b", 2, false}] =
               Repo.all(
                 from o in Option,
                   where: o.item_id == ^practice.id,
                   order_by: o.position,
                   select: {o.key, o.position, o.correct}
               )

      assert [
               %Block{position: 1, kind: :text, provenance: :invented},
               %Block{position: 2, kind: :quote, collapsed_on: [:short]} = quote,
               %Block{position: 3, kind: :placeholder, placeholder_key: "input-rules"}
             ] =
               Repo.all(
                 from b in Block,
                   where: b.lesson_id == ^lessons[{1, "01-first-lesson"}],
                   order_by: b.position
               )

      assert citations(:block_id, quote.id) == [
               {"invented-guide", "p. 3"},
               {"invented-study", "Table 1"}
             ]

      rule_one = Repo.get_by!(Rule, module_id: modules[1], number: 1)
      assert citations(:rule_id, rule_one.id) == [{"invented-guide", "p. 4"}]
      assert citations(:item_id, exam_one.id) == [{"invented-guide", "p. 5"}]

      assert rule_numbers(exam_one.id) == [1, 2]
      assert reveal_ids(practice.id) == [lessons[{1, "02-second-lesson"}]]

      exam = Repo.get_by!(Assessment, program_id: program.id, key: "m1-exam")
      assert exam.module_id == modules[1]

      assert [{"m1-exam-two", 1}, {"m1-exam-one", 2}] =
               Repo.all(
                 from ai in AssessmentItem,
                   join: i in assoc(ai, :item),
                   where: ai.assessment_id == ^exam.id,
                   order_by: ai.position,
                   select: {i.key, ai.position}
               )

      basics = Repo.get_by!(Qualification, program_id: program.id, code: "basics")
      workshop = Repo.get_by!(Qualification, program_id: program.id, code: "workshop")
      assert basics.validity_kind == :months and basics.refresher_mode == :update_unit
      assert workshop.add_on and workshop.refresher_mode == nil

      assert Enum.sort(requirements(basics.id)) == [
               {:assessment_passed, "m1-exam"},
               {:module_completed, "1"},
               {:module_completed, "2"},
               {:policy_acknowledged, "usage-policy"}
             ]

      assert prerequisite_ids(workshop.id) == [basics.id]

      format = Repo.get_by!(CompanionFormat, program_id: program.id, key: "workshop")
      assert format.position == 2 and format.attendance_counts
      self_objective = objective!(program, "m1-self-own-tasks")
      assert format_objective_ids(format.id) == [self_objective.id]
      assert objective_lesson_ids(self_objective.id) == [lessons[{1, "03-third-lesson"}]]
    end

    test "a second publish keeps the ids of keyed rows and replaces the other rows" do
      publish!(payload())
      program = program!()
      before = snapshot(program)
      counts = counts(program)

      publish!(payload())

      assert program!().id == program.id
      assert snapshot(program) == before
      assert counts(program) == counts
      assert archived(program) == []
    end

    test "an item removed from the pack is archived and keeps its id when it returns" do
      publish!(payload())
      program = program!()
      dropped = item!(program, "m1-dropped")
      assert dropped.archived_at == nil

      payload()
      |> update_module(1, "items", &Enum.reject(&1, fn item -> item["key"] == "m1-dropped" end))
      |> publish!()

      archived = item!(program, "m1-dropped")
      assert archived.id == dropped.id
      assert %DateTime{} = archived.archived_at
      assert archived(program) == [{Item, "m1-dropped"}]

      publish!(payload())

      restored = item!(program, "m1-dropped")
      assert restored.id == dropped.id
      assert restored.archived_at == nil
      assert archived(program) == []
    end

    test "an item and an objective moved to another module keep their ids" do
      publish!(payload())
      program = program!()
      item = item!(program, "m1-moving-item")
      objective = objective!(program, "m1-moving")

      moved_item = %{
        item_payload(payload(), 1, "m1-moving-item")
        | "lesson" => "01-first-lesson",
          "rules" => [1]
      }

      moved_objective = %{
        objective_payload(payload(), 1, "m1-moving")
        | "taught_in" => ["01-first-lesson"]
      }

      payload()
      |> update_module(1, "items", &Enum.reject(&1, fn i -> i["key"] == "m1-moving-item" end))
      |> update_module(2, "items", &(&1 ++ [moved_item]))
      |> update_module(1, "objectives", &Enum.reject(&1, fn o -> o["key"] == "m1-moving" end))
      |> update_module(2, "objectives", &(&1 ++ [moved_objective]))
      |> publish!()

      modules = module_ids(program)
      lessons = lesson_ids(program)

      after_item = item!(program, "m1-moving-item")
      assert after_item.id == item.id
      assert after_item.module_id == modules[2]
      assert after_item.lesson_id == lessons[{2, "01-first-lesson"}]
      assert after_item.position == 2
      assert after_item.archived_at == nil
      assert rule_numbers(after_item.id) == [1]

      assert Repo.get!(Rule, hd(rule_ids(after_item.id))).module_id == modules[2]

      after_objective = objective!(program, "m1-moving")
      assert after_objective.id == objective.id
      assert after_objective.module_id == modules[2]
      assert after_objective.archived_at == nil
      assert objective_lesson_ids(objective.id) == [lessons[{2, "01-first-lesson"}]]

      assert archived(program) == []
    end

    test "an objective removed from the pack is archived" do
      publish!(payload())
      program = program!()
      objective = objective!(program, "m1-self-own-tasks")
      format = Repo.get_by!(CompanionFormat, program_id: program.id, key: "workshop")

      payload()
      |> update_module(
        1,
        "objectives",
        &Enum.reject(&1, fn o -> o["key"] == "m1-self-own-tasks" end)
      )
      |> update_in(["formats", Access.filter(&(&1["key"] == "workshop")), "objectives"], fn _ ->
        []
      end)
      |> publish!()

      archived = objective!(program, "m1-self-own-tasks")
      assert archived.id == objective.id
      assert %DateTime{} = archived.archived_at
      assert format_objective_ids(format.id) == []
      assert archived(program) == [{LearningObjective, "m1-self-own-tasks"}]
    end

    test "a changed objectives list and a changed taught_in replace their join rows" do
      publish!(payload())
      program = program!()
      practice = item!(program, "m1-practice")
      next_word = objective!(program, "m1-subject-next-word")
      lessons = lesson_ids(program)

      payload()
      |> update_item(
        1,
        "m1-practice",
        &%{&1 | "objectives" => ["m1-moving", "m1-self-own-tasks"]}
      )
      |> update_objective(
        1,
        "m1-subject-next-word",
        &%{&1 | "taught_in" => ["02-second-lesson", "03-third-lesson"]}
      )
      |> publish!()

      assert objective_ids(practice.id) ==
               Enum.sort([
                 objective!(program, "m1-moving").id,
                 objective!(program, "m1-self-own-tasks").id
               ])

      assert objective_lesson_ids(next_word.id) ==
               Enum.sort([lessons[{1, "02-second-lesson"}], lessons[{1, "03-third-lesson"}]])
    end

    test "a removed module archives its rows, which keep their ids" do
      publish!(payload())
      program = program!()
      before = snapshot(program)

      payload()
      |> Map.update!("modules", &Enum.reject(&1, fn module -> module["number"] == 2 end))
      |> Map.update!("stations", &Enum.reject(&1, fn station -> station["module"] == 2 end))
      |> update_in(
        ["qualifications", Access.filter(&(&1["code"] == "basics")), "requirements"],
        &Enum.reject(&1, fn requirement -> requirement["target"] == "2" end)
      )
      |> publish!()

      assert snapshot(program) == before

      assert archived(program) == [
               {Item, "m2-release-drill"},
               {LearningObjective, "m2-method-release-check"},
               {Lesson, "01-first-lesson"},
               {Lesson, "02-second-lesson"},
               {CatalogModule, 2},
               {Rule, 1}
             ]

      assert Repo.get!(CatalogModule, before.modules[2]).archived_at != nil
      assert Repo.get!(CatalogModule, before.modules[1]).archived_at == nil
    end

    test "every other keyed row missing from the payload is archived" do
      publish!(payload())
      program = program!()

      payload()
      |> Map.update!("segments", &Enum.reject(&1, fn s -> s["key"] == "never" end))
      |> Map.update!("glossary", &Enum.reject(&1, fn t -> t["slug"] == "prompt" end))
      |> Map.update!("formats", &Enum.reject(&1, fn f -> f["key"] == "handbook" end))
      |> Map.update!("qualifications", &Enum.reject(&1, fn q -> q["code"] == "workshop" end))
      |> update_module(1, "rules", &Enum.reject(&1, fn r -> r["number"] == 2 end))
      |> update_module(1, "items", fn items -> Enum.map(items, &%{&1 | "rules" => [1]}) end)
      |> update_module(1, "assessments", fn _ -> [] end)
      |> Map.update!("sources", &Enum.reject(&1, fn s -> s["key"] == "invented-study" end))
      |> update_module(1, "lessons", fn lessons ->
        Enum.map(lessons, fn lesson ->
          %{lesson | "blocks" => Enum.map(lesson["blocks"], &%{&1 | "cite" => []})}
        end)
      end)
      |> Map.update!("qualifications", fn [basics] ->
        [%{basics | "requirements" => [%{"kind" => "module_completed", "target" => "1"}]}]
      end)
      |> publish!()

      assert archived(program) == [
               {Assessment, "m1-exam"},
               {CompanionFormat, "handbook"},
               {GlossaryTerm, "prompt"},
               {Qualification, "workshop"},
               {Rule, 2},
               {Segment, "never"},
               {Source, "invented-study"}
             ]

      # Rows of a parent that the payload still holds are replaced; an archived
      # parent keeps its rows for the records that reference it.
      assert counts(program).citations == 2
      assert counts(program).assessment_items == 2
      assert counts(program).requirements == 3
    end

    test "publishing one pack leaves the rows of another program alone" do
      publish!(payload())
      program = program!()

      payload()
      |> Map.merge(%{"key" => "publisher-test-other", "title" => "Other"})
      |> Map.update!("modules", &Enum.take(&1, 1))
      |> Map.update!("stations", &Enum.reject(&1, fn station -> station["module"] == 2 end))
      |> publish!()

      other = Repo.get_by!(Program, slug: "publisher-test-other")
      assert other.id != program.id and other.status == :published
      assert archived(program) == []
      assert archived(other) == []
      assert counts(program).items == 6 and counts(other).items == 5
    end

    test "answers {:error, :not_validated} for an import that is not validated" do
      failed =
        Repo.insert!(%PackImport{
          pack_key: @key,
          status: :failed,
          report: %{"errors" => [], "warnings" => []}
        })

      assert Publisher.publish(failed) == {:error, :not_validated}
      assert Repo.get_by(Program, slug: @key) == nil

      published = publish!(payload())
      assert Publisher.publish(published) == {:error, :not_validated}

      # A stale struct: the row was published after the caller read it.
      stale = validated(payload())
      stale |> Ecto.Changeset.change(status: :published) |> Repo.update!()
      assert Publisher.publish(stale) == {:error, :not_validated}
      assert Repo.get!(PackImport, stale.id).published_at == nil
    end

    test "a payload that cannot be applied leaves the catalog unchanged" do
      broken = update_item(payload(), 1, "m1-practice", &%{&1 | "rules" => [9]})
      pack_import = validated(broken)

      assert_raise KeyError, fn -> Publisher.publish(pack_import) end

      assert Repo.get_by(Program, slug: @key) == nil
      assert Repo.get!(PackImport, pack_import.id).status == :validated
    end

    test "a value that the schema of a block rejects raises and leaves the catalog unchanged" do
      broken =
        update_module(payload(), 2, "lessons", fn [first | rest] ->
          [%{first | "blocks" => [block("unknown", "A block.", "invented")]} | rest]
        end)

      pack_import = validated(broken)

      assert_raise Ecto.InvalidChangesetError, ~r/kind/, fn -> Publisher.publish(pack_import) end

      assert Repo.get_by(Program, slug: @key) == nil
      assert Repo.get!(PackImport, pack_import.id).status == :validated
    end

    # One insert_all chunk of the publisher holds 6,553 blocks (ten fields),
    # 7,281 options (nine fields) or 8,191 citations (eight fields), so each
    # of these tables takes more than one chunk here.
    test "publishes several thousand blocks, options and citations, and replaces them" do
      published = publish!(large_payload())
      program = program!()
      lesson_id = lesson_ids(program)[{1, "01-first-lesson"}]
      practice = item!(program, "m1-practice")
      rule_two = Repo.get_by!(Rule, module_id: module_ids(program)[1], number: 2)

      assert %{blocks: 7_004, options: 8_008, citations: 16_502, requirements: 6, stations: 4} =
               counts(program)

      assert Repo.all(
               from b in Block,
                 where: b.lesson_id == ^lesson_id,
                 order_by: b.position,
                 select: {b.position, b.kind, b.body, b.collapsed_on}
             ) == for(n <- 1..7_000, do: {n, :text, "Block #{n}.", [:short]})

      assert Repo.all(
               from c in Citation,
                 join: b in assoc(c, :block),
                 join: s in assoc(c, :source),
                 where: b.lesson_id == ^lesson_id,
                 order_by: [b.position, s.key],
                 select: {b.position, s.key, c.locator}
             ) ==
               Enum.flat_map(1..7_000, fn n ->
                 [{n, "invented-guide", "p. #{n}"}, {n, "invented-study", nil}]
               end)

      assert Repo.all(
               from o in Option,
                 where: o.item_id == ^practice.id,
                 order_by: o.position,
                 select: {o.position, o.key, o.correct}
             ) == for(n <- 1..8_000, do: {n, "o#{n}", n == 1})

      assert length(citations(:item_id, practice.id)) == 1_000
      assert length(citations(:rule_id, rule_two.id)) == 1_500

      at = published.published_at
      assert child_timestamps(program) == [{at, at}]

      block_ids = Repo.all(from b in Block, where: b.lesson_id == ^lesson_id, select: b.id)
      second = publish!(large_payload())

      assert %{blocks: 7_004, options: 8_008, citations: 16_502} = counts(program)
      assert Repo.aggregate(from(b in Block, where: b.id in ^block_ids), :count) == 0
      assert child_timestamps(program) == [{second.published_at, second.published_at}]
    end
  end

  describe "publish/1 of the demo pack through the importer" do
    # PostgreSQL takes at most 65,535 parameters per statement, and a join
    # table with two columns reaches that at 32,768 rows.
    test "publishes more join rows of one table than one statement can carry" do
      pack = copy_pack!(demo_path())
      rules = "modules/01-basics/rules.yaml"
      items = "modules/01-basics/items.yaml"

      extra =
        Enum.map_join(7..5_000, "", fn number ->
          "- number: #{number}\n  statement: Rule #{number} holds.\n  action: Apply rule #{number}.\n"
        end)

      write!(pack, rules, read!(pack, rules) <> extra)
      numbers = "rules: [" <> Enum.map_join(1..5_000, ", ", &Integer.to_string/1) <> "]"

      write!(
        pack,
        items,
        Regex.replace(~r/^  rules: \[.*\]$/m, read!(pack, items), "  " <> numbers)
      )

      assert File.stat!(path(pack, items)).size < 1_048_576

      published = publish_pack!(pack)
      program = demo_program!()
      assert published.payload["key"] == program.slug

      item_ids =
        Repo.all(
          from i in Item, where: i.program_id == ^program.id, select: type(i.id, :binary_id)
        )

      rows =
        Repo.one(
          from r in "item_rules",
            where: r.item_id in type(^item_ids, {:array, :binary_id}),
            select: count()
        )

      expected =
        for module <- published.payload["modules"],
            item <- module["items"],
            reduce: 0,
            do: (count -> count + length(item["rules"]))

      assert expected > 32_768
      assert rows == expected
    end

    test "publishes the program, the import and every row of the demo pack" do
      pack_import = import!(copy_pack!(demo_path()))
      assert pack_import.payload["key"] == @demo_key

      assert {:ok, %PackImport{status: :published} = published} = Publisher.publish(pack_import)
      assert published.id == pack_import.id
      assert %DateTime{microsecond: {0, 0}} = published.published_at
      assert DateTime.diff(DateTime.utc_now(), published.published_at) in 0..60

      stored = Repo.get!(PackImport, pack_import.id)
      assert stored.status == :published
      assert stored.published_at == published.published_at

      program = demo_program!()
      assert program.status == :published
      assert program.title == "AI assistant basics (demo)"
      assert program.locale == "en"
      assert program.pack_version == "1.0.0"

      assert demo_counts(program) == @demo_counts

      modules = module_ids(program)
      assert Repo.get!(CatalogModule, modules[1]).areas_elsewhere == %{}

      assert %{
               "self" => %{"where" => "format:workshop"},
               "social" => %{"where" => "format:workshop"}
             } =
               Repo.get!(CatalogModule, modules[2]).areas_elsewhere
    end

    test "qualification_prerequisites holds the row workshop -> basics" do
      publish_pack!(copy_pack!(demo_path()))
      program = demo_program!()

      basics = Repo.get_by!(Qualification, program_id: program.id, code: "basics")
      workshop = Repo.get_by!(Qualification, program_id: program.id, code: "workshop")

      assert prerequisite_ids(workshop.id) == [basics.id]
      assert prerequisite_ids(basics.id) == []
      assert counts(program).prerequisites == 1
    end

    test "a second publish of the unchanged pack keeps every id, archives nothing and keeps the counts" do
      pack = copy_pack!(demo_path())
      publish_pack!(pack)
      program = demo_program!()
      before = snapshot(program)
      published_counts = counts(program)

      assert map_size(before.modules) == 2
      assert map_size(before.lessons) == 5
      assert map_size(before.objectives) == 8
      assert map_size(before.rules) == 10
      assert map_size(before.items) == 12
      assert map_size(before.assessments) == 1
      assert map_size(before.qualifications) == 2

      second = publish_pack!(pack)

      assert demo_program!().id == program.id
      assert snapshot(program) == before
      assert counts(program) == published_counts
      assert demo_counts(program) == @demo_counts
      assert archived(program) == []
      assert Repo.get!(PackImport, second.id).status == :published
    end

    test "publishing a published import answers {:error, :not_validated} and changes nothing" do
      pack_import = import!(copy_pack!(demo_path()))
      assert {:ok, published} = Publisher.publish(pack_import)
      program = demo_program!()
      before = snapshot(program)

      assert Publisher.publish(published) == {:error, :not_validated}

      # The struct that the importer returned still says `validated`.
      assert pack_import.status == :validated
      assert Publisher.publish(pack_import) == {:error, :not_validated}

      stored = Repo.get!(PackImport, pack_import.id)
      assert stored.status == :published
      assert stored.published_at == published.published_at
      assert snapshot(program) == before
      assert demo_counts(program) == @demo_counts
      assert archived(program) == []
    end

    test "publish/1 on a failed import answers {:error, :not_validated} and leaves the catalog alone" do
      pack = copy_pack!(demo_path())
      remove_pack_entry!(pack, @items1, "m1-fluent-figure")
      update_pack_entry!(pack, @items1, "m1-exam-check-claims", &Map.delete(&1, "objectives"))

      assert {:ok, %PackImport{status: :failed, payload: nil} = failed} =
               Importer.import(pack, nil)

      assert failed.pack_key == @demo_key
      assert [%{"check" => 2, "key" => "m1-exam-check-claims"}] = failed.report["errors"]

      assert Publisher.publish(failed) == {:error, :not_validated}
      assert Repo.get_by(Program, slug: @demo_key) == nil

      publish_pack!(copy_pack!(demo_path()))
      program = demo_program!()
      before = snapshot(program)

      assert Publisher.publish(failed) == {:error, :not_validated}

      stored = Repo.get!(PackImport, failed.id)
      assert stored.status == :failed
      assert stored.published_at == nil
      assert snapshot(program) == before
      assert demo_counts(program) == @demo_counts
      assert archived(program) == []
    end

    test "two validated imports of one pack, published one after the other, leave consistent rows" do
      first_pack = copy_pack!(demo_path())
      second_pack = copy_pack!(demo_path())
      replace!(second_pack, "pack.yaml", ~s(version: "1.0.0"), ~s(version: "1.1.0"))

      first = import!(first_pack)
      second = import!(second_pack)
      assert first.pack_version == "1.0.0"
      assert second.pack_version == "1.1.0"

      assert {:ok, %PackImport{status: :published}} = Publisher.publish(first)
      program = demo_program!()
      assert program.pack_version == "1.0.0"
      before = snapshot(program)

      assert {:ok, %PackImport{status: :published} = published} = Publisher.publish(second)
      assert %DateTime{} = published.published_at

      assert Repo.all(
               from i in PackImport,
                 where: i.id in ^[first.id, second.id],
                 select: {i.id, i.status}
             )
             |> Map.new() == %{first.id => :published, second.id => :published}

      assert Repo.aggregate(from(p in Program, where: p.slug == ^@demo_key), :count) == 1
      program = demo_program!()
      assert program.status == :published
      assert program.pack_version == "1.1.0"
      assert snapshot(program) == before
      assert demo_counts(program) == @demo_counts
      assert archived(program) == []
    end

    test "an item removed from the pack is archived and keeps its id when it is added back" do
      publish_pack!(copy_pack!(demo_path()))
      program = demo_program!()
      item = item!(program, "m1-fluent-figure")
      assert item.archived_at == nil

      removed = copy_pack!(demo_path())
      remove_pack_entry!(removed, @items1, "m1-fluent-figure")
      publish_pack!(removed)

      archived_item = item!(program, "m1-fluent-figure")
      assert archived_item.id == item.id
      assert %DateTime{} = archived_item.archived_at
      assert archived(program) == [{Item, "m1-fluent-figure"}]

      publish_pack!(copy_pack!(demo_path()))

      restored = item!(program, "m1-fluent-figure")
      assert restored.id == item.id
      assert restored.archived_at == nil
      assert restored.module_id == item.module_id
      assert restored.position == 2
      assert objective_ids(restored.id) == [objective!(program, "m1-subject-next-word").id]
      assert rule_numbers(restored.id) == [1, 3]
      assert archived(program) == []
      assert demo_counts(program) == @demo_counts
    end

    test "an item moved to another module keeps its id and gets the new module_id" do
      publish_pack!(copy_pack!(demo_path()))
      program = demo_program!()
      modules = module_ids(program)
      item = item!(program, "m1-fluent-figure")
      assert item.module_id == modules[1]

      pack = copy_pack!(demo_path())
      entry = pack_entry!(pack, @items1, "m1-fluent-figure")
      remove_pack_entry!(pack, @items1, "m1-fluent-figure")
      update_yaml!(pack, @items2, &(&1 ++ [entry]))
      publish_pack!(pack)

      lessons = lesson_ids(program)
      moved = item!(program, "m1-fluent-figure")
      assert moved.id == item.id
      assert moved.module_id == modules[2]
      assert moved.lesson_id == lessons[{2, "01-first-lesson"}]
      assert moved.position == 4
      assert moved.archived_at == nil

      assert Enum.sort(rule_ids(moved.id)) ==
               Enum.sort([
                 Repo.get_by!(Rule, module_id: modules[2], number: 1).id,
                 Repo.get_by!(Rule, module_id: modules[2], number: 3).id
               ])

      assert objective_ids(moved.id) == [objective!(program, "m1-subject-next-word").id]
      assert archived(program) == []
      assert demo_counts(program) == @demo_counts
    end

    test "an objective removed from the pack is archived and keeps its id" do
      publish_pack!(copy_pack!(demo_path()))
      program = demo_program!()
      objective = objective!(program, "m1-subject-varying-answers")
      next_word = objective!(program, "m1-subject-next-word")

      pack = copy_pack!(demo_path())
      remove_pack_entry!(pack, @objectives1, "m1-subject-varying-answers")

      for key <- ["m1-why-answers-vary", "m1-exam-varying-answers"] do
        update_pack_entry!(pack, @items1, key, &%{&1 | "objectives" => ["m1-subject-next-word"]})
      end

      publish_pack!(pack)

      archived_objective = objective!(program, "m1-subject-varying-answers")
      assert archived_objective.id == objective.id
      assert %DateTime{} = archived_objective.archived_at
      assert archived(program) == [{LearningObjective, "m1-subject-varying-answers"}]

      for key <- ["m1-why-answers-vary", "m1-exam-varying-answers"] do
        assert objective_ids(item!(program, key).id) == [next_word.id]
      end
    end

    test "an objective moved to another module keeps its id and gets the new module_id" do
      publish_pack!(copy_pack!(demo_path()))
      program = demo_program!()
      modules = module_ids(program)
      objective = objective!(program, "m1-subject-varying-answers")
      assert objective.module_id == modules[1]

      pack = copy_pack!(demo_path())

      moved_entry =
        pack
        |> pack_entry!(@objectives1, "m1-subject-varying-answers")
        |> Map.delete("domain")
        |> Map.put("taught_in", ["02-second-lesson"])

      remove_pack_entry!(pack, @objectives1, "m1-subject-varying-answers")
      update_yaml!(pack, @objectives2, &(&1 ++ [moved_entry]))
      publish_pack!(pack)

      lessons = lesson_ids(program)
      moved = objective!(program, "m1-subject-varying-answers")
      assert moved.id == objective.id
      assert moved.module_id == modules[2]
      assert moved.position == 4
      assert moved.domain == nil
      assert moved.archived_at == nil
      assert objective_lesson_ids(moved.id) == [lessons[{2, "02-second-lesson"}]]

      for key <- ["m1-why-answers-vary", "m1-exam-varying-answers"] do
        assert objective_ids(item!(program, key).id) == [objective.id]
      end

      assert archived(program) == []
      assert demo_counts(program) == @demo_counts
    end

    test "a changed objectives list of an item replaces its item_objectives rows" do
      publish_pack!(copy_pack!(demo_path()))
      program = demo_program!()
      item = item!(program, "m1-fluent-figure")
      next_word = objective!(program, "m1-subject-next-word")
      assert objective_ids(item.id) == [next_word.id]

      pack = copy_pack!(demo_path())

      update_pack_entry!(
        pack,
        @items1,
        "m1-fluent-figure",
        &%{&1 | "objectives" => ["m1-method-check-claims", "m1-subject-varying-answers"]}
      )

      publish_pack!(pack)

      assert objective_ids(item.id) ==
               Enum.sort([
                 objective!(program, "m1-method-check-claims").id,
                 objective!(program, "m1-subject-varying-answers").id
               ])

      assert objective_ids(item!(program, "m1-how-models-write").id) == [next_word.id]
      assert counts(program).item_objectives == 12
      assert archived(program) == []
    end

    test "a changed taught_in replaces the objective_lessons rows of its objective" do
      publish_pack!(copy_pack!(demo_path()))
      program = demo_program!()
      lessons = lesson_ids(program)
      objective = objective!(program, "m1-method-check-claims")
      assert objective_lesson_ids(objective.id) == [lessons[{1, "03-third-lesson"}]]

      pack = copy_pack!(demo_path())

      update_pack_entry!(
        pack,
        @objectives1,
        "m1-method-check-claims",
        &%{&1 | "taught_in" => ["01-first-lesson", "02-second-lesson"]}
      )

      publish_pack!(pack)

      assert objective_lesson_ids(objective.id) ==
               Enum.sort([lessons[{1, "01-first-lesson"}], lessons[{1, "02-second-lesson"}]])

      assert objective_lesson_ids(objective!(program, "m1-self-own-responsibility").id) ==
               [lessons[{1, "03-third-lesson"}]]

      assert counts(program).objective_lessons == 9
      assert archived(program) == []
    end
  end

  ## The demo pack through the importer

  defp import!(pack) do
    assert {:ok, %PackImport{status: :validated, pack_key: @demo_key} = pack_import} =
             Importer.import(pack, nil)

    pack_import
  end

  defp publish_pack!(pack) do
    assert {:ok, %PackImport{status: :published} = published} =
             pack |> import!() |> Publisher.publish()

    published
  end

  defp demo_program!, do: Repo.get_by!(Program, slug: @demo_key)

  # The counts of the program in the order of the Acceptance queries.
  defp demo_counts(program) do
    counts = counts(program)

    {Enum.map_join(@catalog_tables, "|", &counts[&1]),
     Enum.map_join(@alignment_tables, "|", &counts[&1])}
  end

  defp pack_entry!(pack, rel, key) do
    case Enum.find(read_yaml!(pack, rel), &(&1["key"] == key)) do
      nil -> raise ArgumentError, "#{rel} has no entry #{key}"
      entry -> entry
    end
  end

  defp update_pack_entry!(pack, rel, key, fun) do
    pack_entry!(pack, rel, key)

    update_yaml!(pack, rel, fn entries ->
      Enum.map(entries, &if(&1["key"] == key, do: fun.(&1), else: &1))
    end)
  end

  defp remove_pack_entry!(pack, rel, key) do
    pack_entry!(pack, rel, key)
    update_yaml!(pack, rel, &Enum.reject(&1, fn entry -> entry["key"] == key end))
  end

  ## Payload of a small two-module pack in the shape of the normalized map

  defp payload do
    %{
      "schema" => 1,
      "key" => @key,
      "title" => "Publisher test",
      "locale" => "en",
      "license" => "CC0-1.0",
      "version" => "1.0.0",
      "alignment" => "strict",
      "sources" => [
        %{
          "key" => "invented-guide",
          "title" => "Invented guide (fictional example)",
          "publisher" => "Invented publisher (fictional example)",
          "url" => nil,
          "edition_date" => "2026-05-30",
          "retrieved_on" => "2026-06-01",
          "kind" => "other"
        },
        %{
          "key" => "invented-study",
          "title" => "Invented study (fictional example)",
          "publisher" => "Invented institute (fictional example)",
          "url" => "https://example.org/study",
          "edition_date" => "2026-01-15",
          "retrieved_on" => "2026-06-01",
          "kind" => "study"
        }
      ],
      "glossary" => [
        %{"slug" => "llm", "label" => "language model", "short_text" => "Continues text."},
        %{"slug" => "prompt", "label" => "prompt", "short_text" => "The input to a model."}
      ],
      "segments" => [
        %{
          "key" => "daily",
          "label" => "Daily users",
          "description" => "Use an assistant every day.",
          "default_path" => "short"
        },
        %{
          "key" => "never",
          "label" => "Non-users",
          "description" => "Do not use an assistant at work.",
          "default_path" => "full"
        }
      ],
      "stations" => [
        %{
          "kind" => "self_assessment",
          "title" => "Where do you stand?",
          "module" => nil,
          "config" => %{"question" => "How often do you use an assistant?"}
        },
        %{"kind" => "module", "title" => "Module 1", "module" => 1, "config" => %{}},
        %{"kind" => "module", "title" => "Module 2", "module" => 2, "config" => %{}},
        %{
          "kind" => "feedback",
          "title" => "Feedback",
          "module" => nil,
          "config" => %{
            "intro" => "Tell us what helped.",
            "questions" => [
              %{"key" => "useful", "kind" => "scale", "label" => "How useful?", "options" => []}
            ]
          }
        }
      ],
      "qualifications" => [
        %{
          "code" => "basics",
          "title" => "Basics",
          "audience" => "Everyone who drafts texts.",
          "unlocks" => ["drafting letters", "summarizing notes"],
          "add_on" => false,
          "validity_kind" => "months",
          "validity_months" => 12,
          "refresher_mode" => "update_unit",
          "phases" => ["orient", "understand", "apply"],
          "requirements" => [
            %{"kind" => "assessment_passed", "target" => "m1-exam"},
            %{"kind" => "module_completed", "target" => "1"},
            %{"kind" => "module_completed", "target" => "2"},
            %{"kind" => "policy_acknowledged", "target" => "usage-policy"}
          ]
        },
        %{
          "code" => "workshop",
          "title" => "Workshop",
          "audience" => "Team leads.",
          "unlocks" => ["agreeing team rules"],
          "add_on" => true,
          "validity_kind" => "none",
          "validity_months" => nil,
          "refresher_mode" => nil,
          "phases" => ["anchor"],
          "requirements" => [
            %{"kind" => "attendance", "target" => "workshop"},
            %{"kind" => "qualification_held", "target" => "basics"}
          ]
        }
      ],
      "formats" => [
        %{
          "key" => "handbook",
          "title" => "Handbook",
          "description" => "The printable rules.",
          "phases" => ["anchor"],
          "attendance_counts" => false,
          "objectives" => []
        },
        %{
          "key" => "workshop",
          "title" => "Workshop",
          "description" => "A session in the team.",
          "phases" => ["anchor"],
          "attendance_counts" => true,
          "objectives" => ["m1-self-own-tasks"]
        }
      ],
      "modules" => [module_one(), module_two()]
    }
  end

  defp module_one do
    %{
      "number" => 1,
      "title" => "How language models work",
      "summary" => "What a language model does.",
      "phases" => ["orient", "understand"],
      "domains" => ["drafting", "research"],
      "single_path" => false,
      "refresher_unit" => false,
      "areas_elsewhere" => %{},
      "lessons" => [
        lesson("01-first-lesson", "First lesson", 1, [
          block("text", "A [[term:llm]] continues text.", "invented"),
          %{
            block("quote", "> A quoted sentence.", "sourced")
            | "collapsed_on" => ["short"],
              "cite" => ["invented-guide#p. 3", "invented-study#Table 1"]
          },
          %{
            block("placeholder", "Your rules for inputs go here.", "placeholder")
            | "placeholder_key" => "input-rules"
          }
        ]),
        lesson("02-second-lesson", "Second lesson", 2, [
          block("explanation", "Answers vary.", "invented")
        ]),
        lesson("03-third-lesson", "Third lesson", 3, [
          block("callout", "Check every claim.", "assumption")
        ])
      ],
      "objectives" => [
        objective("m1-subject-next-word", "subject", "know", "drafting", ["01-first-lesson"]),
        objective("m1-moving", "method", "know", nil, ["03-third-lesson"]),
        %{
          objective("m1-self-own-tasks", "self", "judge", nil, ["03-third-lesson"])
          | "phase" => "anchor"
        }
      ],
      "rules" => [rule(1, ["invented-guide#p. 4"]), rule(2, [])],
      "items" => [
        choice_item("m1-practice", "01-first-lesson", ["m1-subject-next-word"], [1], [
          "02-second-lesson"
        ]),
        choice_item("m1-moving-item", "03-third-lesson", ["m1-moving"], [2], []),
        choice_item("m1-dropped", "02-second-lesson", ["m1-subject-next-word"], [1], []),
        %{
          choice_item("m1-exam-one", nil, ["m1-subject-next-word"], [1, 2], [])
          | "core" => true,
            "cite" => ["invented-guide#p. 5"]
        },
        %{
          choice_item("m1-exam-two", nil, ["m1-moving"], [1], [])
          | "kind" => "multiple_choice"
        }
      ],
      "assessments" => [
        %{
          "key" => "m1-exam",
          "title" => "Module 1 exam",
          "kind" => "exam",
          "counts_for_credential" => true,
          "max_wrong" => 1,
          "core_required" => true,
          "items" => ["m1-exam-two", "m1-exam-one"]
        }
      ]
    }
  end

  defp module_two do
    %{
      "number" => 2,
      "title" => "Checking the output",
      "summary" => "How to check a generated text.",
      "phases" => ["apply", "anchor"],
      "domains" => [],
      "single_path" => true,
      "refresher_unit" => true,
      "areas_elsewhere" => %{
        "self" => %{
          "where" => "format:workshop",
          "reason" => "The workshop practises deciding which tasks an assistant may support."
        },
        "social" => %{
          "where" => "format:workshop",
          "reason" => "The workshop practises agreeing how the use of an assistant is shown."
        }
      },
      "lessons" => [
        lesson("01-first-lesson", "Prompt parts", 1, [
          block("example", "Task, context, format and constraint.", "invented")
        ]),
        lesson("02-second-lesson", "Release checks", 2, [
          block("case_comparison", "Draft A and draft B.", "invented")
        ])
      ],
      "objectives" => [
        %{
          objective("m2-method-release-check", "method", "apply", nil, ["02-second-lesson"])
          | "phase" => "anchor"
        }
      ],
      "rules" => [rule(1, [])],
      "items" => [
        %{
          "key" => "m2-release-drill",
          "kind" => "checklist_drill",
          "lesson" => "02-second-lesson",
          "stem" => "Run the release checks.",
          "core" => false,
          "phase" => "anchor",
          "provenance" => "invented",
          "objectives" => ["m2-method-release-check"],
          "rules" => [1],
          "reveals" => [],
          "cite" => [],
          "options" => [],
          "config" => %{
            "checks" => [
              %{"key" => "sources", "label" => "Sources checked", "required" => true},
              %{"key" => "names", "label" => "Names checked", "required" => false}
            ]
          }
        }
      ],
      "assessments" => []
    }
  end

  # The payload with 7,000 blocks of two citations each in the first lesson
  # of module 1, 8,000 options and 1,000 citations of the item m1-practice,
  # and 1,500 citations of rule 2 of module 1.
  defp large_payload do
    blocks =
      for n <- 1..7_000 do
        %{
          block("text", "Block #{n}.", "sourced")
          | "collapsed_on" => ["short"],
            "cite" => ["invented-guide#p. #{n}", "invented-study"]
        }
      end

    options =
      for n <- 1..8_000 do
        %{"key" => "o#{n}", "label" => "Option #{n}", "correct" => n == 1, "feedback" => nil}
      end

    item_cites = for n <- 1..1_000, do: "invented-guide#p. #{n}"
    rule_cites = for n <- 1..1_500, do: "invented-study#Table #{n}"

    payload()
    |> update_module(1, "lessons", fn [first | rest] -> [%{first | "blocks" => blocks} | rest] end)
    |> update_item(1, "m1-practice", &%{&1 | "options" => options, "cite" => item_cites})
    |> update_module(1, "rules", fn [one, two] -> [one, %{two | "cite" => rule_cites}] end)
  end

  defp lesson(key, title, position, blocks),
    do: %{"key" => key, "title" => title, "position" => position, "blocks" => blocks}

  defp block(kind, body, provenance) do
    %{
      "kind" => kind,
      "body" => body,
      "provenance" => provenance,
      "collapsed_on" => [],
      "placeholder_key" => nil,
      "cite" => []
    }
  end

  defp objective(key, area, depth, domain, taught_in) do
    %{
      "key" => key,
      "statement" => "Learners can work with #{key}.",
      "area" => area,
      "depth" => depth,
      "phase" => "understand",
      "domain" => domain,
      "taught_in" => taught_in
    }
  end

  defp rule(number, cite) do
    %{
      "number" => number,
      "statement" => "Rule #{number} holds.",
      "action" => "Act on rule #{number}.",
      "cite" => cite
    }
  end

  defp choice_item(key, lesson, objectives, rules, reveals) do
    %{
      "key" => key,
      "kind" => "single_choice",
      "lesson" => lesson,
      "stem" => "Which statement about #{key} is right?",
      "core" => false,
      "phase" => "understand",
      "provenance" => "invented",
      "objectives" => objectives,
      "rules" => rules,
      "reveals" => reveals,
      "cite" => [],
      "options" => [
        %{"key" => "a", "label" => "The right one", "correct" => true, "feedback" => "Yes."},
        %{"key" => "b", "label" => "The wrong one", "correct" => false, "feedback" => "No."}
      ],
      "config" => %{}
    }
  end

  defp update_module(payload, number, field, fun) do
    update_in(payload, ["modules", Access.filter(&(&1["number"] == number)), field], fun)
  end

  defp update_item(payload, number, key, fun) do
    update_module(payload, number, "items", fn items ->
      Enum.map(items, &if(&1["key"] == key, do: fun.(&1), else: &1))
    end)
  end

  defp update_objective(payload, number, key, fun) do
    update_module(payload, number, "objectives", fn objectives ->
      Enum.map(objectives, &if(&1["key"] == key, do: fun.(&1), else: &1))
    end)
  end

  defp item_payload(payload, number, key), do: entry(payload, number, "items", key)
  defp objective_payload(payload, number, key), do: entry(payload, number, "objectives", key)

  defp entry(payload, number, field, key) do
    module = Enum.find(payload["modules"], &(&1["number"] == number))
    Enum.find(module[field], &(&1["key"] == key))
  end

  ## Database helpers

  defp validated(payload) do
    Repo.insert!(%PackImport{
      pack_key: payload["key"],
      pack_version: payload["version"],
      status: :validated,
      report: %{"errors" => [], "warnings" => []},
      payload: payload
    })
  end

  defp publish!(payload) do
    assert {:ok, %PackImport{status: :published} = published} =
             payload |> validated() |> Publisher.publish()

    published
  end

  defp program!, do: Repo.get_by!(Program, slug: @key)

  defp item!(program, key), do: Repo.get_by!(Item, program_id: program.id, key: key)

  defp objective!(program, key),
    do: Repo.get_by!(LearningObjective, program_id: program.id, key: key)

  defp module_ids(program) do
    Map.new(
      Repo.all(
        from m in CatalogModule, where: m.program_id == ^program.id, select: {m.number, m.id}
      )
    )
  end

  defp lesson_ids(program) do
    Map.new(
      Repo.all(
        from l in Lesson,
          join: m in assoc(l, :module),
          where: m.program_id == ^program.id,
          select: {{m.number, l.key}, l.id}
      )
    )
  end

  defp snapshot(program) do
    %{
      program: program.id,
      modules: module_ids(program),
      lessons: lesson_ids(program),
      rules:
        keyed(
          from r in Rule,
            join: m in assoc(r, :module),
            where: m.program_id == ^program.id,
            select: {{m.number, r.number}, r.id}
        ),
      objectives: keyed_by_key(LearningObjective, program),
      items: keyed_by_key(Item, program),
      assessments: keyed_by_key(Assessment, program),
      formats: keyed_by_key(CompanionFormat, program),
      segments: keyed_by_key(Segment, program),
      sources: keyed_by_key(Source, program),
      glossary:
        keyed(from t in GlossaryTerm, where: t.program_id == ^program.id, select: {t.slug, t.id}),
      qualifications:
        keyed(from q in Qualification, where: q.program_id == ^program.id, select: {q.code, q.id})
    }
  end

  defp keyed(query), do: Map.new(Repo.all(query))

  defp keyed_by_key(schema, program) do
    keyed(from r in schema, where: r.program_id == ^program.id, select: {r.key, r.id})
  end

  # The keyed rows of the program with archived_at set, as {schema, key}.
  defp archived(program) do
    module_ids = from m in CatalogModule, where: m.program_id == ^program.id, select: m.id

    by_program =
      for schema <- [
            Assessment,
            CompanionFormat,
            Item,
            LearningObjective,
            Segment,
            Source
          ],
          key <-
            Repo.all(
              from r in schema,
                where: r.program_id == ^program.id and not is_nil(r.archived_at),
                select: r.key
            ),
          do: {schema, key}

    others =
      Enum.map(
        Repo.all(
          from t in GlossaryTerm,
            where: t.program_id == ^program.id and not is_nil(t.archived_at),
            select: t.slug
        ),
        &{GlossaryTerm, &1}
      ) ++
        Enum.map(
          Repo.all(
            from q in Qualification,
              where: q.program_id == ^program.id and not is_nil(q.archived_at),
              select: q.code
          ),
          &{Qualification, &1}
        ) ++
        Enum.map(
          Repo.all(
            from m in CatalogModule,
              where: m.program_id == ^program.id and not is_nil(m.archived_at),
              select: m.number
          ),
          &{CatalogModule, &1}
        ) ++
        Enum.map(
          Repo.all(
            from l in Lesson,
              where: l.module_id in subquery(module_ids) and not is_nil(l.archived_at),
              select: l.key
          ),
          &{Lesson, &1}
        ) ++
        Enum.map(
          Repo.all(
            from r in Rule,
              where: r.module_id in subquery(module_ids) and not is_nil(r.archived_at),
              select: r.number
          ),
          &{Rule, &1}
        )

    Enum.sort_by(by_program ++ others, fn {schema, key} -> {inspect(schema), key} end)
  end

  defp counts(program) do
    module_ids = from m in CatalogModule, where: m.program_id == ^program.id, select: m.id
    lesson_ids = from l in Lesson, where: l.module_id in subquery(module_ids), select: l.id
    item_ids = from i in Item, where: i.program_id == ^program.id, select: i.id

    %{
      modules: count(from m in CatalogModule, where: m.program_id == ^program.id),
      lessons: count(from l in Lesson, where: l.module_id in subquery(module_ids)),
      rules: count(from r in Rule, where: r.module_id in subquery(module_ids)),
      objectives: count(from o in LearningObjective, where: o.program_id == ^program.id),
      items: count(from i in Item, where: i.program_id == ^program.id),
      assessments: count(from a in Assessment, where: a.program_id == ^program.id),
      qualifications: count(from q in Qualification, where: q.program_id == ^program.id),
      requirements:
        count(
          from r in Requirement,
            join: q in assoc(r, :qualification),
            where: q.program_id == ^program.id
        ),
      formats: count(from f in CompanionFormat, where: f.program_id == ^program.id),
      stations: count(from s in Station, where: s.program_id == ^program.id),
      segments: count(from s in Segment, where: s.program_id == ^program.id),
      glossary: count(from t in GlossaryTerm, where: t.program_id == ^program.id),
      sources: count(from s in Source, where: s.program_id == ^program.id),
      blocks: count(from b in Block, where: b.lesson_id in subquery(lesson_ids)),
      options: count(from o in Option, where: o.item_id in subquery(item_ids)),
      citations:
        count(
          from c in Citation,
            join: s in assoc(c, :source),
            where: s.program_id == ^program.id
        ),
      item_rules: count(from r in "item_rules", where: r.item_id in subquery(item_ids)),
      item_reveals: count(from r in "item_reveals", where: r.item_id in subquery(item_ids)),
      assessment_items: count(from ai in AssessmentItem, where: ai.item_id in subquery(item_ids)),
      prerequisites:
        count(
          from p in "qualification_prerequisites",
            join: q in Qualification,
            on: q.id == p.qualification_id,
            where: q.program_id == ^program.id
        ),
      objective_lessons:
        count(from r in "objective_lessons", where: r.lesson_id in subquery(lesson_ids)),
      item_objectives: count(from r in "item_objectives", where: r.item_id in subquery(item_ids)),
      format_objectives:
        count(
          from r in "format_objectives",
            join: f in CompanionFormat,
            on: f.id == r.companion_format_id,
            where: f.program_id == ^program.id
        )
    }
  end

  defp count(query), do: Repo.aggregate(query, :count)

  # The distinct {inserted_at, updated_at} pairs of the blocks, options,
  # citations, requirements and stations of the program.
  defp child_timestamps(program) do
    module_ids = from m in CatalogModule, where: m.program_id == ^program.id, select: m.id
    lesson_ids = from l in Lesson, where: l.module_id in subquery(module_ids), select: l.id
    item_ids = from i in Item, where: i.program_id == ^program.id, select: i.id

    [
      from(b in Block, where: b.lesson_id in subquery(lesson_ids)),
      from(o in Option, where: o.item_id in subquery(item_ids)),
      from(c in Citation, join: s in assoc(c, :source), where: s.program_id == ^program.id),
      from(r in Requirement,
        join: q in assoc(r, :qualification),
        where: q.program_id == ^program.id
      ),
      from(s in Station, where: s.program_id == ^program.id)
    ]
    |> Enum.flat_map(
      &Repo.all(from r in &1, distinct: true, select: {r.inserted_at, r.updated_at})
    )
    |> Enum.uniq()
  end

  defp citations(parent_field, parent_id) do
    Repo.all(
      from c in Citation,
        join: s in assoc(c, :source),
        where: field(c, ^parent_field) == ^parent_id,
        order_by: [s.key, c.locator],
        select: {s.key, c.locator}
    )
  end

  defp rule_ids(item_id) do
    Repo.all(
      from r in "item_rules",
        where: r.item_id == type(^item_id, Ecto.UUID),
        select: type(r.rule_id, Ecto.UUID)
    )
  end

  defp rule_numbers(item_id) do
    Repo.all(
      from r in Rule,
        join: ir in "item_rules",
        on: ir.rule_id == r.id,
        where: ir.item_id == type(^item_id, Ecto.UUID),
        order_by: r.number,
        select: r.number
    )
  end

  defp reveal_ids(item_id), do: join_ids("item_reveals", :item_id, item_id, :lesson_id)

  defp objective_ids(item_id),
    do: join_ids("item_objectives", :item_id, item_id, :learning_objective_id)

  defp objective_lesson_ids(objective_id),
    do: join_ids("objective_lessons", :learning_objective_id, objective_id, :lesson_id)

  defp format_objective_ids(format_id),
    do: join_ids("format_objectives", :companion_format_id, format_id, :learning_objective_id)

  defp prerequisite_ids(qualification_id),
    do:
      join_ids(
        "qualification_prerequisites",
        :qualification_id,
        qualification_id,
        :prerequisite_id
      )

  defp join_ids(table, parent_column, parent_id, child_column) do
    table
    |> where([r], field(r, ^parent_column) == type(^parent_id, Ecto.UUID))
    |> select([r], type(field(r, ^child_column), Ecto.UUID))
    |> Repo.all()
    |> Enum.sort()
  end

  defp requirements(qualification_id) do
    Repo.all(
      from r in Requirement,
        where: r.qualification_id == ^qualification_id,
        select: {r.kind, r.target_key}
    )
  end
end

defmodule Espalier.Catalog.PublisherTimeoutTest do
  # The transaction timeout lives in the application environment, so these
  # tests run on their own.
  use Espalier.DataCase, async: false

  import Espalier.PackFixtures, only: [copy_pack!: 1, demo_path: 0]

  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.PackImport

  setup do
    on_exit(fn -> Application.delete_env(:espalier, Publisher) end)
  end

  defp put_timeout(timeout),
    do: Application.put_env(:espalier, Publisher, transaction_timeout: timeout)

  test "the transaction timeout is ten minutes unless the configuration sets it" do
    assert Publisher.transaction_timeout() == 600_000

    put_timeout(30_000)
    assert Publisher.transaction_timeout() == 30_000
  end

  # DBConnection applies the :timeout of a transaction to the whole
  # checkout, so a publish that takes longer than the configured timeout
  # loses its connection.
  test "the publish transaction runs under the configured timeout" do
    assert {:ok, %PackImport{status: :validated} = pack_import} =
             Importer.import(copy_pack!(demo_path()), nil)

    put_timeout(1)

    assert_raise DBConnection.ConnectionError, fn -> Publisher.publish(pack_import) end
  end
end
