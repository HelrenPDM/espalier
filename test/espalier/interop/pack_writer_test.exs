defmodule Espalier.Interop.PackWriterTest do
  use Espalier.DataCase, async: true

  import Espalier.PackFixtures,
    only: [copy_pack!: 1, demo_path: 0, read!: 2, read_yaml!: 2, update_yaml!: 3]

  alias Espalier.Catalog

  alias Espalier.Catalog.{
    Alignment,
    Assessment,
    CompanionFormat,
    GlossaryTerm,
    Item,
    LearningObjective,
    Lesson,
    PackImport,
    Program,
    Qualification,
    Rule,
    Segment,
    Source
  }

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Pack.{Importer, Loader, Publisher, Validator}
  alias Espalier.Interop.{PackWriter, Payload}

  # The tables whose rows a publish archives when the pack drops their key.
  @keyed [
    CatalogModule,
    Lesson,
    LearningObjective,
    Rule,
    Item,
    Assessment,
    Qualification,
    CompanionFormat,
    Source,
    GlossaryTerm,
    Segment
  ]

  @module1 "modules/01-how-language-models-work"
  @module2 "modules/02-checking-the-output"

  @workshop_objectives ["m1-self-own-responsibility", "m1-social-team-transparency"]

  # Strings that YAML would read as another type or another text if they
  # were written plainly or as a block scalar without care.
  @strings [
    "1.0.0",
    "2026-03-01",
    "yes",
    "no",
    "on",
    "off",
    "null",
    "~",
    "1",
    "1e3",
    "-",
    ": x",
    "# x",
    " leading space",
    "trailing space ",
    "true",
    "False",
    "Y",
    "n",
    "NULL",
    ".5",
    "-.5",
    "+1",
    "0x1F",
    "0o17",
    "1_000",
    "12:30",
    "2026-03-01T10:00:00Z",
    "2026-03-01 10:00:00",
    "-x",
    "1. Step one",
    ".inf",
    ".nan",
    ".NaN",
    "-.Inf",
    "+.inf",
    "=",
    "<<",
    "?x",
    "? x",
    ":x",
    "a: b",
    "a #b",
    "a:\tb",
    "tab\tinside",
    "\ttab first",
    "@at",
    "`tick",
    "'single'",
    "\"double\"",
    "it's",
    "back\\slash",
    "{flow}",
    "[list]",
    "*alias",
    "&anchor",
    "!tag",
    "%percent",
    "|pipe",
    ">fold",
    "---",
    "...",
    "Ünïcödé ✓ 日本語 🙂",
    "non\u00A0breaking",
    "next\u0085line",
    "line\u2028separator",
    "paragraph\u2029separator",
    "byte order\uFEFFmark",
    "carriage\rreturn",
    "c1\u0090control",
    "two\nlines",
    "ends with a line break\n",
    "ends with blank lines\n\n",
    "first\n  indented second",
    " indented first\nsecond",
    "blank\n\nline inside",
    "spaces\n   \nonly line",
    "tab\n\tindented",
    "# hash\nsecond",
    "---\n...\nmarkers",
    "quote \"inside\"\nand 'more'",
    "crlf\r\nline",
    "unicode\nÜnïcödé ✓ 🙂",
    "trailing space \nline"
  ]

  # Lesson titles, which the front matter holds.
  @titles [
    "two\nlines",
    "ends with blank lines\n\n",
    " indented first\nsecond",
    "1.0.0",
    "---"
  ]

  # Lesson bodies, which the lesson files hold unchanged.
  @bodies [
    "    four spaces first\n\n- list\n\ttab",
    "trailing spaces  \nnext",
    "# heading\n---\n...",
    "{braces} and \"quotes\" and 'apostrophes'",
    "a: b\n- c\n  d: e"
  ]

  defp import_and_publish!(path) do
    {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(path, nil)
    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    {pack_import.payload, Catalog.get_program_by_slug(pack_import.pack_key)}
  end

  # Imports and publishes `source`, writes its program into a directory of
  # `tmp_dir`, checks the output with the validator of task 0008, and
  # imports and publishes the output.
  defp round_trip!(source, tmp_dir) do
    {original, program} = import_and_publish!(source)
    built = Payload.build(program)
    out = Path.join(tmp_dir, "pack")

    assert {:ok, _version} = PackWriter.write(program, out)
    assert {:ok, loaded} = Loader.load(out)
    assert %{errors: [], warnings: [], payload: validated} = Validator.run(loaded)

    assert {:ok, %PackImport{status: :validated} = reimport} = Importer.import(out, nil)
    assert reimport.report == %{"errors" => [], "warnings" => []}
    assert {:ok, %PackImport{status: :published}} = Publisher.publish(reimport)

    %{
      original: original,
      program: program,
      built: built,
      out: out,
      validated: validated,
      reimported: reimport.payload
    }
  end

  defp archived_rows do
    for schema <- @keyed,
        do: {schema, Repo.aggregate(from(r in schema, where: not is_nil(r.archived_at)), :count)}
  end

  # The directory of module `number` in the pack `out`, relative to `out`.
  defp module_dir!(out, number) do
    dir =
      out
      |> Path.join("modules/*/module.yaml")
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(Path.dirname(&1), out))
      |> Enum.find(&(read_yaml!(out, &1 <> "/module.yaml")["number"] == number))

    assert is_binary(dir), "no module #{number} in #{out}"
    dir
  end

  defp find_key(entries, key), do: Enum.find(entries, &(&1["key"] == key))

  defp objective(payload, key) do
    payload["modules"] |> Enum.flat_map(& &1["objectives"]) |> find_key(key)
  end

  defp codes(qualifications), do: Enum.map(qualifications, & &1["code"])

  # Sets `position` on every qualification, counting down from the number of
  # entries, so that the positions reverse the order of the file.
  defp reverse_positions(qualifications) do
    count = length(qualifications)

    qualifications
    |> Enum.with_index()
    |> Enum.map(fn {qualification, index} ->
      Map.put(qualification, "position", count - index)
    end)
  end

  # The original payload, the built payload and the written
  # qualifications.yaml list the qualifications in the order `codes`, the
  # written file holds no `position`, and the re-import of the written pack
  # gives the payload of the original import.
  defp assert_qualification_round_trip(run, codes) do
    assert codes(run.original["qualifications"]) == codes
    assert codes(run.built["qualifications"]) == codes

    written = read_yaml!(run.out, "qualifications.yaml")
    assert codes(written) == codes
    refute Enum.any?(written, &Map.has_key?(&1, "position"))

    assert run.built == run.original
    assert run.validated == run.original
    assert run.reimported == run.original
    assert Payload.build(run.program) == run.original
    assert Enum.all?(archived_rows(), fn {_schema, count} -> count == 0 end)
  end

  describe "write/2" do
    @tag :tmp_dir
    test "round trip: the re-import of the output gives the payload of the program", %{
      tmp_dir: tmp_dir
    } do
      run = round_trip!(demo_path(), tmp_dir)

      assert run.built == run.original
      assert run.validated == run.original
      assert run.reimported == run.built
      assert run.reimported == run.original

      program = Catalog.get_program_by_slug(run.program.slug)
      assert %Program{id: id, status: :published} = program
      assert id == run.program.id
      assert Payload.build(program) == run.original
      assert Enum.all?(archived_rows(), fn {_schema, count} -> count == 0 end)
    end

    @tag :tmp_dir
    test "round trip of the alignment: objectives, areas elsewhere, formats and the setting", %{
      tmp_dir: tmp_dir
    } do
      run = round_trip!(demo_path(), tmp_dir)
      out = run.out

      assert out |> Path.join("modules/*/objectives.yaml") |> Path.wildcard() |> length() == 2
      assert read_yaml!(out, "pack.yaml")["alignment"] == "strict"

      module2 = read_yaml!(out, module_dir!(out, 2) <> "/module.yaml")
      assert module2["areas_elsewhere"] |> Map.keys() |> Enum.sort() == ["self", "social"]

      assert %{"objectives" => @workshop_objectives} =
               find_key(read_yaml!(out, "formats.yaml"), "workshop")

      assert Alignment.check(run.reimported) == {[], []}
      assert Alignment.matrix(run.reimported) == Alignment.matrix(run.original)
      assert Alignment.matrix(run.reimported) == Alignment.matrix(run.program)
      assert length(Alignment.matrix(run.reimported)) == 24
    end

    @tag :tmp_dir
    test "round trip of the optional fields and the order", %{tmp_dir: tmp_dir} do
      pack = copy_pack!(demo_path())
      update_yaml!(pack, "pack.yaml", &Map.put(&1, "alignment", "warn"))

      update_yaml!(pack, "modules/01-basics/objectives.yaml", fn objectives ->
        Enum.map(objectives, fn
          %{"key" => "m1-subject-next-word"} = objective -> Map.delete(objective, "domain")
          objective -> objective
        end)
      end)

      update_yaml!(pack, "formats.yaml", fn formats ->
        Enum.map(formats, fn
          %{"key" => "workshop"} = format ->
            %{format | "objectives" => Enum.reverse(@workshop_objectives)}

          format ->
            format
        end)
      end)

      assert %{"objectives" => ["m1-social-team-transparency", "m1-self-own-responsibility"]} =
               find_key(read_yaml!(pack, "formats.yaml"), "workshop")

      run = round_trip!(pack, tmp_dir)
      out = run.out

      assert read_yaml!(out, "pack.yaml")["alignment"] == "warn"

      written = read_yaml!(out, module_dir!(out, 1) <> "/objectives.yaml")
      refute Map.has_key?(find_key(written, "m1-subject-next-word"), "domain")
      assert find_key(written, "m1-subject-varying-answers")["domain"] == "drafting"

      assert %{"objectives" => @workshop_objectives} =
               find_key(read_yaml!(out, "formats.yaml"), "workshop")

      assert run.reimported == run.built
      assert run.reimported == run.original
      assert run.original["alignment"] == "warn"

      for payload <- [run.original, run.built, run.reimported] do
        assert {:ok, nil} = Map.fetch(objective(payload, "m1-subject-next-word"), "domain")
      end

      assert Payload.build(run.program) == run.original
      assert Enum.all?(archived_rows(), fn {_schema, count} -> count == 0 end)
    end

    # The demo pack lists `basics` before `workshop`, as the code order
    # does. The copies of the next two tests list `workshop` first: one by
    # the order of its file, one by `position` against the order of its file.
    @tag :tmp_dir
    test "round trip of the qualification order of the file", %{tmp_dir: tmp_dir} do
      pack = copy_pack!(demo_path())
      update_yaml!(pack, "qualifications.yaml", &Enum.reverse/1)
      assert codes(read_yaml!(pack, "qualifications.yaml")) == ["workshop", "basics"]

      assert_qualification_round_trip(round_trip!(pack, tmp_dir), ["workshop", "basics"])
    end

    @tag :tmp_dir
    test "round trip of the qualification order by position", %{tmp_dir: tmp_dir} do
      pack = copy_pack!(demo_path())
      update_yaml!(pack, "qualifications.yaml", &reverse_positions/1)

      assert [%{"code" => "basics", "position" => 2}, %{"code" => "workshop", "position" => 1}] =
               read_yaml!(pack, "qualifications.yaml")

      assert_qualification_round_trip(round_trip!(pack, tmp_dir), ["workshop", "basics"])
    end

    @tag :tmp_dir
    test "writes the files of the demo program in the pack layout", %{tmp_dir: tmp_dir} do
      {_payload, program} = import_and_publish!(demo_path())
      assert {:ok, "1.0.0"} = PackWriter.write(program, tmp_dir)

      files =
        tmp_dir
        |> Path.join("**")
        |> Path.wildcard()
        |> Enum.reject(&File.dir?/1)
        |> Enum.map(&Path.relative_to(&1, tmp_dir))
        |> Enum.sort()

      assert files ==
               Enum.sort(
                 ~w(pack.yaml sources.yaml glossary.yaml segments.yaml stations.yaml
                    feedback.yaml qualifications.yaml formats.yaml) ++
                   Enum.map(
                     ~w(module.yaml objectives.yaml rules.yaml items.yaml assessment.yaml
                        lessons/01-first-lesson.md lessons/02-second-lesson.md
                        lessons/03-third-lesson.md),
                     &"#{@module1}/#{&1}"
                   ) ++
                   Enum.map(
                     ~w(module.yaml objectives.yaml rules.yaml items.yaml
                        lessons/01-first-lesson.md lessons/02-second-lesson.md),
                     &"#{@module2}/#{&1}"
                   )
               )

      assert read!(tmp_dir, "#{@module1}/lessons/01-first-lesson.md") == """
             ---
             title: What a language model does
             position: 1
             ---

             :::text{provenance=invented}
             A [[term:llm|language model]] continues text.
             :::

             :::explanation{provenance=sourced collapsed_on=short cite="vendor-guide#Overview"}
             The next word follows from probabilities learned in training.
             :::

             :::placeholder{provenance=placeholder key=input-rules}
             Your organization adds its rules for inputs here.
             :::
             """

      assert read!(tmp_dir, "pack.yaml") == """
             schema: 1
             key: ai-assistant-basics-demo
             title: AI assistant basics (demo)
             locale: en
             license: CC0-1.0
             version: "1.0.0"
             alignment: strict
             """

      sources = read!(tmp_dir, "sources.yaml")
      assert sources =~ ~s(edition_date: "2026-03-01")
      assert sources =~ ~s(retrieved_on: "2026-09-15")

      # The station keeps its own config, and feedback.yaml gets intro and
      # questions back.
      assert tmp_dir |> read_yaml!("stations.yaml") |> List.last() ==
               %{"kind" => "feedback", "title" => "Your feedback", "config" => %{}}

      assert read_yaml!(tmp_dir, "feedback.yaml") == read_yaml!(demo_path(), "feedback.yaml")

      assert %{"requirements" => requirements} =
               tmp_dir
               |> read_yaml!("qualifications.yaml")
               |> Enum.find(&(&1["code"] == "basics"))

      assert %{"kind" => "module_completed", "target" => 1} in requirements
    end

    @tag :tmp_dir
    test "refuses a program that is not published and a directory that is not empty", %{
      tmp_dir: tmp_dir
    } do
      {_payload, program} = import_and_publish!(demo_path())
      out = Path.join(tmp_dir, "pack")

      assert PackWriter.write(%{program | status: :draft}, out) == {:error, :not_published}
      refute File.exists?(out)

      File.write!(Path.join(tmp_dir, "notes.txt"), "kept")
      assert PackWriter.write(program, tmp_dir) == {:error, :not_empty}
      assert File.ls!(tmp_dir) == ["notes.txt"]

      assert PackWriter.write(program, Path.join(tmp_dir, "notes.txt")) ==
               {:error, :not_directory}
    end
  end

  describe "write/2 after two publishes of one pack" do
    # `Payload.build/1` reads `schema`, `license` and `alignment` from the
    # import published last. The publisher gives a later publish of one
    # pack a later `published_at`, also within one second.
    @tag :tmp_dir
    test "writes the alignment of the import published last, also within one second", %{
      tmp_dir: tmp_dir
    } do
      {:ok, first} = Importer.import(demo_path(), nil)
      {:ok, %PackImport{status: :published} = first} = Publisher.publish(first)

      pack = copy_pack!(demo_path())
      update_yaml!(pack, "pack.yaml", &Map.put(&1, "alignment", "warn"))
      {:ok, second} = Importer.import(pack, nil)
      {:ok, %PackImport{status: :published} = second} = Publisher.publish(second)

      assert DateTime.compare(second.published_at, first.published_at) == :gt

      program = Catalog.get_program_by_slug(first.pack_key)
      assert {:ok, "1.0.0"} = PackWriter.write(program, tmp_dir)
      assert read_yaml!(tmp_dir, "pack.yaml")["alignment"] == "warn"
    end

    # `write/2` reads the program again before it builds the payload, so a
    # program read before the second publish gives the version published
    # last.
    @tag :tmp_dir
    test "writes the version published last for a program read before it", %{
      tmp_dir: tmp_dir
    } do
      {_payload, before} = import_and_publish!(demo_path())

      pack = copy_pack!(demo_path())
      update_yaml!(pack, "pack.yaml", &Map.put(&1, "version", "1.1.0"))

      update_yaml!(
        pack,
        "modules/01-basics/module.yaml",
        &Map.put(&1, "title", "Language models, second edition")
      )

      {second, program} = import_and_publish!(pack)
      assert program.id == before.id
      assert before.pack_version == "1.0.0"

      assert {:ok, "1.1.0"} = PackWriter.write(before, tmp_dir)
      assert read_yaml!(tmp_dir, "pack.yaml")["version"] == "1.1.0"

      assert read_yaml!(tmp_dir, module_dir!(tmp_dir, 1) <> "/module.yaml")["title"] ==
               "Language models, second edition"

      assert {:ok, loaded} = Loader.load(tmp_dir)
      assert %{errors: [], payload: ^second} = Validator.run(loaded)
    end

    @tag :tmp_dir
    test "refuses a program that is no longer published when it writes", %{tmp_dir: tmp_dir} do
      {_payload, program} = import_and_publish!(demo_path())
      out = Path.join(tmp_dir, "pack")

      Repo.update_all(from(p in Program, where: p.id == ^program.id), set: [status: :archived])

      assert program.status == :published
      assert PackWriter.write(program, out) == {:error, :not_published}
      refute File.exists?(out)
    end
  end

  describe "write_payload/2" do
    setup do
      {:ok, loaded} = Loader.load(demo_path())
      %{payload: payload} = Validator.run(loaded)
      %{payload: payload}
    end

    @tag :tmp_dir
    test "keeps every string, also those that YAML would retype", %{
      payload: payload,
      tmp_dir: tmp_dir
    } do
      assert length(Enum.uniq(@strings)) == length(@strings)
      payload = with_strings(payload)

      assert :ok = PackWriter.write_payload(payload, tmp_dir)
      assert {:ok, loaded} = Loader.load(tmp_dir)
      assert %{errors: [], warnings: [], payload: read_back} = Validator.run(loaded)
      assert read_back == payload
    end

    @tag :tmp_dir
    test "raises for a block body that a lesson file cannot hold", %{
      payload: payload,
      tmp_dir: tmp_dir
    } do
      [module | modules] = payload["modules"]
      [lesson | lessons] = module["lessons"]
      [block | blocks] = lesson["blocks"]
      block = %{block | "body" => "before\n:::\nafter"}
      lesson = %{lesson | "blocks" => [block | blocks]}
      payload = %{payload | "modules" => [%{module | "lessons" => [lesson | lessons]} | modules]}

      assert_raise ArgumentError, ~r/:::/, fn -> PackWriter.write_payload(payload, tmp_dir) end
    end
  end

  # Puts @strings into the payload: into the `unlocks` of the first
  # qualification, as values and keys of the config of the overview station,
  # and into the feedback of the options in item order as far as they reach.
  # The pack version becomes `1e3`, @titles and @bodies become the titles and
  # the first block bodies of the lessons, and a block and a rule get
  # citations with spaces and a comma.
  defp with_strings(payload) do
    {modules, _rest} =
      Enum.map_reduce(payload["modules"], {@strings, @titles, @bodies}, &module_with_strings/2)

    payload
    |> Map.merge(%{"version" => "1e3", "modules" => modules})
    |> Map.update!("qualifications", fn [first | rest] ->
      [%{first | "unlocks" => @strings} | rest]
    end)
    |> Map.update!("stations", fn stations -> Enum.map(stations, &station_with_strings/1) end)
  end

  # The loader rejects the map key `<<` in any form (a YAML merge key), so a
  # payload holds no such key.
  defp station_with_strings(%{"kind" => "overview", "config" => config} = station) do
    keys = Map.new(@strings -- ["<<"], &{&1, &1})
    %{station | "config" => Map.merge(config, %{"strings" => @strings, "keys" => keys})}
  end

  defp station_with_strings(station), do: station

  defp module_with_strings(module, {strings, titles, bodies}) do
    {items, strings} = Enum.map_reduce(module["items"], strings, &item_with_strings/2)

    {lessons, {titles, bodies}} =
      Enum.map_reduce(module["lessons"], {titles, bodies}, &lesson_with_strings/2)

    rules = Enum.map(module["rules"], &rule_with_cite/1)

    {%{module | "items" => items, "lessons" => lessons, "rules" => rules},
     {strings, titles, bodies}}
  end

  defp item_with_strings(item, strings) do
    {options, strings} =
      Enum.map_reduce(item["options"], strings, fn
        option, [string | rest] -> {%{option | "feedback" => string}, rest}
        option, [] -> {option, []}
      end)

    {%{item | "options" => options}, strings}
  end

  defp lesson_with_strings(lesson, {[title | titles], [body | bodies]}) do
    [first | blocks] = Enum.map(lesson["blocks"], &block_with_cites/1)
    lesson = %{lesson | "title" => title, "blocks" => [%{first | "body" => body} | blocks]}
    {lesson, {titles, bodies}}
  end

  defp block_with_cites(%{"cite" => ["vendor-guide#Overview"]} = block) do
    %{
      block
      | "cite" => ["office-study#Page 3", "vendor-guide#Overview"],
        "collapsed_on" => ["full", "short"]
    }
  end

  defp block_with_cites(block), do: block

  defp rule_with_cite(%{"number" => 2, "cite" => [_ | _]} = rule),
    do: %{rule | "cite" => ["vendor-guide#Limitations, part 2"]}

  defp rule_with_cite(rule), do: rule
end
