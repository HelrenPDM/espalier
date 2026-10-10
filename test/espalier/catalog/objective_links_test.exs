defmodule Espalier.Catalog.ObjectiveLinksTest do
  use Espalier.DataCase, async: true

  import Espalier.LearningFixtures
  import Espalier.PackFixtures

  alias Espalier.Catalog
  alias Espalier.Catalog.{Alignment, CompanionFormat, Item, Lesson}
  alias Espalier.Learning
  alias EspalierWeb.{CatalogJSON, LearningJSON}

  @objectives "modules/01-basics/objectives.yaml"
  @items "modules/01-basics/items.yaml"
  @objective_members ~w(area depth domain evidence key lesson_ids phase statement)
  @module_1_objectives ~w(
    m1-subject-next-word
    m1-subject-varying-answers
    m1-method-check-claims
    m1-self-own-responsibility
    m1-social-team-transparency
  )
  @module_2_objectives ~w(m2-subject-prompt-parts m2-method-judge-output m2-method-release-check)

  describe "the module views of the demo program" do
    setup do
      %{program: publish_demo!()}
    end

    test "module 1 carries its five objectives in position order as in objectives.yaml",
         %{program: program} do
      objectives = module_json(program, 1)["objectives"]

      assert Enum.map(objectives, & &1["key"]) == @module_1_objectives

      assert Enum.map(objectives, & &1["domain"]) ==
               ~w(research drafting research drafting drafting)

      for objective <- objectives do
        assert objective |> Map.keys() |> Enum.sort() == @objective_members
      end

      assert Enum.map(objectives, &described/1) ==
               Enum.map(yaml_objectives("01-basics"), &described/1)
    end

    test "every lesson of a module 1 objective is a lesson of module 1 that teaches it",
         %{program: program} do
      lessons = lessons_by_id(program)
      view = module_json(program, 1)
      taught_in = Map.new(yaml_objectives("01-basics"), &{&1["key"], &1["taught_in"]})

      assert Enum.map(view["lessons"], & &1["id"]) |> Enum.sort() ==
               for({id, {1, _key}} <- lessons, do: id) |> Enum.sort()

      for objective <- view["objectives"] do
        assert objective["lesson_ids"] != []

        for id <- objective["lesson_ids"] do
          assert {1, _key} = Map.fetch!(lessons, id)
        end

        assert Enum.map(objective["lesson_ids"], &elem(lessons[&1], 1)) ==
                 taught_in[objective["key"]]
      end
    end

    test "the self and social objectives of module 1 carry the workshop as their only evidence",
         %{program: program} do
      objectives = by_key(module_json(program, 1)["objectives"])
      workshop = format!(program, "workshop")

      for key <- ~w(m1-self-own-responsibility m1-social-team-transparency) do
        assert objectives[key]["evidence"] == [%{"kind" => "format", "id" => workshop.id}]
      end
    end

    test "m1-subject-next-word carries practice items and items of module-1-exam",
         %{program: program} do
      objective = by_key(module_json(program, 1)["objectives"])["m1-subject-next-word"]
      exam_item_ids = program |> assessment!("module-1-exam") |> exam_items!() |> ids()

      assert Enum.all?(objective["evidence"], &(&1["kind"] == "item"))
      assert Enum.any?(objective["evidence"], &(&1["id"] in exam_item_ids))

      assert evidence_labels(program, objective) == [
               "item:m1-exam-confident-answer",
               "item:m1-exam-next-word",
               "item:m1-fluent-figure",
               "item:m1-how-models-write"
             ]
    end

    test "evidence lists the items ordered by key, then the formats ordered by key",
         %{program: program} do
      assert_evidence_order(program)
    end

    test "module 2 carries three objectives, and the release check carries the checklist drill",
         %{program: program} do
      view = module_json(program, 2)
      objectives = view["objectives"]
      drill = item!(program, "m2-release-drill")

      assert Enum.map(objectives, & &1["key"]) == @module_2_objectives

      assert Enum.map(objectives, &described/1) ==
               Enum.map(yaml_objectives("02-checking"), &described/1)

      assert Enum.all?(objectives, &(&1["domain"] == nil))

      assert by_key(objectives)["m2-method-release-check"]["evidence"] == [
               %{"kind" => "item", "id" => drill.id}
             ]

      assert %{"kind" => "checklist_drill", "key" => "m2-release-drill"} =
               Enum.find(items_of(view), &(&1["id"] == drill.id))
    end

    test "every exam item names one objective, and the poll names none", %{program: program} do
      view = module_json(program, 1)
      assert [%{"key" => "module-1-exam", "items" => exam_items}] = view["exams"]
      assert length(exam_items) == 4

      for item <- exam_items do
        assert [_key] = item["objective_keys"]
      end

      assert %{"kind" => "poll", "objective_keys" => []} =
               Enum.find(view["practice_items"], &(&1["key"] == "m1-first-task-poll"))
    end

    test "the objective keys of every item are the sorted objectives of its items.yaml entry",
         %{program: program} do
      named = Map.new(yaml_items(), &{&1["key"], Enum.sort(&1["objectives"] || [])})
      rendered = Enum.flat_map([1, 2], &items_of(module_json(program, &1)))

      assert rendered |> Enum.map(& &1["key"]) |> Enum.sort() ==
               named |> Map.keys() |> Enum.sort()

      for item <- rendered do
        assert item["objective_keys"] == named[item["key"]], item["key"]
      end
    end

    test "the program view lists the three companion formats", %{program: program} do
      assert {:ok, view} = Catalog.program_view(demo_slug())
      formats = round_trip(CatalogJSON.show(%{program: view}))["companion_formats"]

      assert Enum.map(formats, & &1["key"]) == ~w(handbook workshop help-desk)

      assert formats ==
               for(
                 format <- read_yaml!(demo_path(), "formats.yaml"),
                 do: %{
                   "id" => format!(program, format["key"]).id,
                   "key" => format["key"],
                   "title" => format["title"],
                   "description" => format["description"],
                   "phases" => format["phases"],
                   "attendance_counts" => format["attendance_counts"]
                 }
               )
    end

    test "for every row of the alignment matrix, the module views carry the row's evidence",
         %{program: program} do
      assert_matrix_evidence(program)
    end
  end

  describe "a second publish" do
    test "with a format of each key and items on one objective, keeps items before formats" do
      pack = copy_pack!(demo_path())

      update_yaml!(pack, "formats.yaml", fn formats ->
        Enum.map(formats, fn
          %{"key" => "workshop"} = format ->
            Map.update!(format, "objectives", &(&1 ++ ["m1-subject-next-word"]))

          %{"key" => "help-desk"} = format ->
            Map.merge(format, %{
              "attendance_counts" => true,
              "objectives" => ["m1-subject-next-word"]
            })

          format ->
            format
        end)
      end)

      program = publish_demo!(pack)
      objective = by_key(module_json(program, 1)["objectives"])["m1-subject-next-word"]

      # Positions in items.yaml and formats.yaml differ from the key order.
      assert evidence_labels(program, objective) == [
               "item:m1-exam-confident-answer",
               "item:m1-exam-next-word",
               "item:m1-fluent-figure",
               "item:m1-how-models-write",
               "format:help-desk",
               "format:workshop"
             ]

      assert_evidence_order(program)
      assert_matrix_evidence(program)
    end

    test "without m1-subject-varying-answers names it in no view, key list, link or progress" do
      program = publish_demo!()
      assert "m1-subject-varying-answers" in link_keys(Catalog.objective_links(program.id))

      # A learner who passed the exam before the second publish.
      scope = scope_for(Espalier.AccountsFixtures.user_fixture())
      enroll!(scope)
      exam = assessment!(program)
      answers = Map.new(exam_answers(exam), fn {id, answer} -> {id, cast_answer(answer)} end)

      assert {:ok, %{outcome: :passed}, _results} =
               Learning.submit_attempt(scope, exam.id, answers)

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
      assert publish_demo!(pack).id == program.id

      # The objective keeps its row with archived_at set.
      assert objective!(program, "m1-subject-varying-answers").archived_at

      views = Enum.map([1, 2], &module_json(program, &1))

      for view <- views do
        refute JSON.encode!(view) =~ "m1-subject-varying-answers"

        for item <- items_of(view) do
          refute "m1-subject-varying-answers" in item["objective_keys"]
        end
      end

      [module_1, _module_2] = views

      assert Enum.map(module_1["objectives"], & &1["key"]) ==
               @module_1_objectives -- ["m1-subject-varying-answers"]

      for key <- ~w(m1-why-answers-vary m1-exam-varying-answers) do
        assert %{"objective_keys" => ["m1-subject-next-word"]} =
                 Enum.find(items_of(module_1), &(&1["key"] == key))
      end

      item_ids = Repo.all(from i in Item, where: i.program_id == ^program.id, select: i.id)

      for {_item_id, keys} <- Catalog.objective_keys(item_ids) do
        refute "m1-subject-varying-answers" in keys
      end

      links = Catalog.objective_links(program.id)
      refute "m1-subject-varying-answers" in link_keys(links)

      assert link_keys(links) ==
               (@module_1_objectives -- ["m1-subject-varying-answers"]) ++ @module_2_objectives

      module_1_id = module!(program, 1).id

      refute "m1-subject-varying-answers" in link_keys(
               Catalog.objective_links(program.id, module_id: module_1_id)
             )

      assert {:ok, progress} = Learning.progress(scope, demo_slug())

      refute JSON.encode!(LearningJSON.progress(%{progress: progress})) =~
               "m1-subject-varying-answers"

      assert Enum.map(progress.objectives, &{&1.key, &1.status}) ==
               [
                 {"m1-subject-next-word", :evidenced},
                 {"m1-method-check-claims", :evidenced},
                 {"m1-self-own-responsibility", :open},
                 {"m1-social-team-transparency", :open}
               ] ++ Enum.map(@module_2_objectives, &{&1, :open})

      assert {:ok, progress} = Learning.progress(scope, demo_slug())

      refute JSON.encode!(LearningJSON.progress(%{progress: progress})) =~
               "m1-subject-varying-answers"

      assert Enum.map(progress.objectives, &{&1.key, &1.status}) ==
               [
                 {"m1-subject-next-word", :evidenced},
                 {"m1-method-check-claims", :evidenced},
                 {"m1-self-own-responsibility", :open},
                 {"m1-social-team-transparency", :open}
               ] ++ Enum.map(@module_2_objectives, &{&1, :open})

      assert_matrix_evidence(program)
    end
  end

  describe "objective_links/2" do
    test "returns the objectives of the program, or of one module, in module and position order" do
      program = publish_demo!()

      assert link_keys(Catalog.objective_links(program.id)) ==
               @module_1_objectives ++ @module_2_objectives

      assert link_keys(Catalog.objective_links(program.id, module_id: module!(program, 1).id)) ==
               @module_1_objectives

      assert link_keys(Catalog.objective_links(program.id, module_id: module!(program, 2).id)) ==
               @module_2_objectives
    end

    test "runs the same number of queries for the program as for one module" do
      program = publish_demo!()
      module_1 = module!(program, 1)
      module_2 = module!(program, 2)
      ref = attach_query_counter!()

      {all, all_queries} = count_queries(ref, fn -> Catalog.objective_links(program.id) end)

      {first, first_queries} =
        count_queries(ref, fn -> Catalog.objective_links(program.id, module_id: module_1.id) end)

      {second, second_queries} =
        count_queries(ref, fn -> Catalog.objective_links(program.id, module_id: module_2.id) end)

      assert {length(all), length(first), length(second)} == {8, 5, 3}
      assert all_queries > 0
      assert first_queries == all_queries
      assert second_queries == all_queries
    end
  end

  ## Views

  defp module_json(program, number) do
    assert {:ok, view} = Catalog.module_view(module!(program, number).id)
    round_trip(CatalogJSON.module(%{view: view}))
  end

  # The JSON that a client receives: string keys and string values.
  defp round_trip(data), do: data |> JSON.encode!() |> JSON.decode!()

  defp items_of(view) do
    view["practice_items"] ++ Enum.flat_map(view["exams"], & &1["items"])
  end

  defp by_key(entries), do: Map.new(entries, &{&1["key"], &1})

  defp ids(rows), do: Enum.map(rows, & &1.id)

  defp link_keys(links), do: Enum.map(links, & &1.objective.key)

  defp described(objective) do
    Map.new(~w(key statement area depth phase domain), &{&1, objective[&1]})
  end

  ## Evidence

  # `{"item" | "format", id}` to `item:<key>` or `format:<key>`.
  defp labels(program) do
    items =
      Repo.all(from i in Item, where: i.program_id == ^program.id, select: {i.id, i.key})

    formats =
      Repo.all(
        from f in CompanionFormat, where: f.program_id == ^program.id, select: {f.id, f.key}
      )

    Map.new(
      for({id, key} <- items, do: {{"item", id}, "item:#{key}"}) ++
        for({id, key} <- formats, do: {{"format", id}, "format:#{key}"})
    )
  end

  defp evidence_labels(program, objective) do
    labels = labels(program)
    Enum.map(objective["evidence"], &Map.fetch!(labels, {&1["kind"], &1["id"]}))
  end

  defp assert_evidence_order(program) do
    labels = labels(program)

    for number <- [1, 2], objective <- module_json(program, number)["objectives"] do
      evidence = Enum.map(objective["evidence"], &Map.fetch!(labels, {&1["kind"], &1["id"]}))
      {items, formats} = Enum.split_while(evidence, &String.starts_with?(&1, "item:"))

      assert Enum.all?(formats, &String.starts_with?(&1, "format:")), inspect(evidence)
      assert items == Enum.sort(items), inspect(evidence)
      assert formats == Enum.sort(formats), inspect(evidence)
      assert evidence == Enum.uniq(evidence), inspect(evidence)
    end
  end

  defp assert_matrix_evidence(program) do
    labels = labels(program)
    views = Map.new([1, 2], &{&1, module_json(program, &1)})
    rows = Alignment.matrix(program)

    assert length(rows) == 24
    assert Enum.any?(rows, &(&1.evidence != []))

    for row <- rows do
      objectives = Enum.filter(views[row.module]["objectives"], &(&1["key"] in row.objectives))

      assert objectives |> Enum.map(& &1["key"]) |> Enum.sort() == row.objectives

      evidence =
        objectives
        |> Enum.flat_map(& &1["evidence"])
        |> Enum.map(&Map.fetch!(labels, {&1["kind"], &1["id"]}))
        |> Enum.uniq()
        |> Enum.sort()

      assert evidence == row.evidence, inspect({row.module, row.area, row.depth})
    end
  end

  ## Demo pack

  defp yaml_objectives(dir), do: read_yaml!(demo_path(), "modules/#{dir}/objectives.yaml")

  defp yaml_items do
    for file <- Path.wildcard(Path.join(demo_path(), "modules/*/items.yaml")),
        item <- file |> File.read!() |> YamlElixir.read_from_string!(),
        do: item
  end

  # Lesson id to `{module number, lesson key}` for every lesson of the program.
  defp lessons_by_id(program) do
    Repo.all(
      from l in Lesson,
        join: m in assoc(l, :module),
        where: m.program_id == ^program.id,
        select: {l.id, {m.number, l.key}}
    )
    |> Map.new()
  end

  ## Query count

  # Counts the queries of the test process only: other tests run their
  # queries in their own processes at the same time.
  defp attach_query_counter! do
    ref = make_ref()
    handler = {__MODULE__, ref}

    :ok =
      :telemetry.attach(handler, [:espalier, :repo, :query], &__MODULE__.handle_query/4, %{
        pid: self(),
        ref: ref
      })

    on_exit(fn -> :telemetry.detach(handler) end)
    ref
  end

  @doc false
  def handle_query(_event, _measurements, _metadata, %{pid: pid, ref: ref}) do
    if self() == pid, do: send(pid, {:query, ref})
  end

  # The handler runs in the process that sends the query, so every message
  # of `fun` is in the mailbox when it returns.
  defp count_queries(ref, fun) do
    _ = drain(ref, 0)
    result = fun.()
    {result, drain(ref, 0)}
  end

  defp drain(ref, count) do
    receive do
      {:query, ^ref} -> drain(ref, count + 1)
    after
      0 -> count
    end
  end
end
