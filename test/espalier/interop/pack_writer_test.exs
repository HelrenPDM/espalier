defmodule Espalier.Interop.PackWriterTest do
  # The re-import of a written pack runs the real ingest of its media, whose
  # advisory lock the SQL sandbox holds until the test ends (task 0018).
  use Espalier.DataCase, async: false

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
  alias Espalier.Media.{Asset, Store}
  alias Espalier.MediaFixtures

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

  # The lesson of the demo pack that gains a figure in the media tests.
  @demo_lesson "modules/02-checking/lessons/02-second-lesson.md"

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
    {:ok, %PackImport{status: :validated} = pack_import} =
      Importer.import(path, nil, media: MediaFixtures.media_for(path))

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
    assert run.validated == Map.delete(run.original, "media")
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
      assert run.validated == Map.delete(run.original, "media")
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
                   ) ++
                   ~w(media/assistant-demo-en.vtt media/assistant-demo.webm
                      media/release-checks.svg)
               )

      # The media files hold the bytes of their delivery files.
      for rel <- MediaFixtures.demo_media_paths() do
        assert read!(tmp_dir, rel) == read!(demo_path(), rel), rel
      end

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

             :::video{provenance=invented src="media/assistant-demo.webm" title="A test pattern with a tone" captions="media/assistant-demo-en.vtt:en"}
             The video shows a moving test pattern with colour bars and a counter while a steady tone plays. It holds no speech.
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
      {:ok, first} =
        Importer.import(demo_path(), nil, media: MediaFixtures.media_for(demo_path()))

      {:ok, %PackImport{status: :published} = first} = Publisher.publish(first)

      pack = copy_pack!(demo_path())
      update_yaml!(pack, "pack.yaml", &Map.put(&1, "alignment", "warn"))
      {:ok, second} = Importer.import(pack, nil, media: MediaFixtures.media_for(pack))
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
      assert %{errors: [], payload: validated} = Validator.run(loaded)
      assert validated == Map.delete(second, "media")
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
    # The payload of an import with the media of MediaFixtures, so that the
    # writer copies the demo files from the store.
    setup do
      {:ok, %PackImport{status: :validated, payload: payload}} =
        Importer.import(demo_path(), nil, media: MediaFixtures.demo_media!())

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
      assert read_back == Map.delete(payload, "media")

      # The media files come from the store.
      for rel <- MediaFixtures.demo_media_paths() do
        assert read!(tmp_dir, rel) == read!(demo_path(), rel), rel
      end
    end

    @tag :tmp_dir
    test "answers the error of a missing file for a media path whose asset is gone", %{
      payload: payload,
      tmp_dir: tmp_dir
    } do
      gone = %{"path" => "media/gone.png", "asset_id" => Ecto.UUID.generate(), "kind" => "image"}
      payload = Map.update!(payload, "media", &[gone | &1])

      assert PackWriter.write_payload(payload, tmp_dir) ==
               {:error, {:file, "media/gone.webp", :enoent}}
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

  describe "media_files/1 and captions_files/1" do
    test "list the delivery paths with their assets by path, the captions apart" do
      media = MediaFixtures.demo_media!()

      {:ok, %PackImport{status: :validated, payload: payload}} =
        Importer.import(demo_path(), nil, media: media)

      assert ids(PackWriter.media_files(payload)) == [
               {"media/assistant-demo.webm", media["media/assistant-demo.webm"]},
               {"media/release-checks.svg", media["media/release-checks.svg"]}
             ]

      assert ids(PackWriter.captions_files(payload)) == [
               {"media/assistant-demo-en.vtt", media["media/assistant-demo-en.vtt"]}
             ]

      assert [{_path, %Asset{kind: :video, status: :ready, ext: "webm"}}, _svg] =
               PackWriter.media_files(payload)
    end

    test "give an image its delivery path and leave out a path whose asset is gone" do
      file = Path.join(demo_path(), "media/release-checks.svg")
      image = MediaFixtures.stored_asset!(file, :image, "webp", %{width: 720, height: 200})

      payload = %{
        "media" => [
          %{"path" => "media/photos/photo.jpg", "asset_id" => image.id, "kind" => "image"},
          %{"path" => "media/gone.png", "asset_id" => Ecto.UUID.generate(), "kind" => "image"}
        ]
      }

      assert ids(PackWriter.media_files(payload)) == [{"media/photos/photo.webp", image.id}]
      assert PackWriter.captions_files(payload) == []
    end

    test "give a payload without media no files" do
      assert PackWriter.media_files(%{}) == []
      assert PackWriter.captions_files(%{}) == []
      assert PackWriter.media_files(%{"media" => []}) == []
    end
  end

  describe "write/2 with converted media" do
    # The real ingest converts the generated inputs with ffmpeg of the
    # shell; the demo media come from MediaFixtures.

    @tag :tmp_dir
    test "round trip of an animated figure on the same installation and on another",
         %{tmp_dir: tmp_dir} do
      pack = copy_pack!(demo_path())

      ffmpeg!([
        "-f",
        "lavfi",
        "-i",
        "testsrc2=size=96x64:rate=4:duration=1",
        "-f",
        "gif",
        Path.join(pack, "media/animation.gif")
      ])

      append_block!(
        pack,
        @demo_lesson,
        ~s(:::figure{src=media/animation.gif alt="A moving test pattern." provenance=invented}\n:::\n)
      )

      original = import_processed!(pack, MediaFixtures.media_for(pack))
      animation = asset!(original.payload, "media/animation.gif")

      assert %Asset{kind: :image, status: :ready, ext: "webp", animated: true} = animation
      assert is_binary(animation.poster_sha256)

      program = Catalog.get_program_by_slug(original.pack_key)
      out = Path.join(tmp_dir, "pack")
      assert {:ok, "1.0.0"} = PackWriter.write(program, out)

      # The written pack holds the delivery file and references it.
      refute File.exists?(Path.join(out, "media/animation.gif"))

      assert read!(out, "media/animation.webp") ==
               File.read!(Store.path(animation.sha256, "webp"))

      assert read!(out, "#{@module2}/lessons/02-second-lesson.md") =~
               ~s(:::figure{provenance=invented src="media/animation.webp" alt="A moving test pattern." size=full})

      # The same installation: the delivery digests find the assets, so the
      # import queues nothing and links the same asset ids.
      expected = rename_media(original.payload, "media/animation.gif", "media/animation.webp")
      assert {:ok, %PackImport{status: :validated} = same} = Importer.import(out, nil)
      assert MediaFixtures.process_queued!(same) == []
      assert same.payload == expected
      assert Enum.sort(same.media_asset_ids) == Enum.sort(original.media_asset_ids)
      assert {:ok, %PackImport{status: :published}} = Publisher.publish(same)
      assert Payload.build(program) == expected

      # An installation without the program and its assets: the import
      # ingests every file again, and the structural path of animated WebP
      # inputs accepts the animation, which keeps its bytes and its poster.
      Repo.query!("TRUNCATE programs, media_assets CASCADE")

      fresh = import_processed!(out, %{})
      again = asset!(fresh.payload, "media/animation.webp")

      assert %Asset{kind: :image, status: :ready, ext: "webp", animated: true} = again
      assert {again.sha256, again.poster_sha256} == {animation.sha256, animation.poster_sha256}

      assert Enum.map(fresh.payload["media"], &Map.delete(&1, "asset_id")) ==
               Enum.map(expected["media"], &Map.delete(&1, "asset_id"))

      assert MapSet.disjoint?(MapSet.new(fresh.media_asset_ids), MapSet.new(same.media_asset_ids))
      assert Map.delete(fresh.payload, "media") == Map.delete(expected, "media")

      republished = Catalog.get_program_by_slug(fresh.pack_key)
      assert Payload.build(republished) == fresh.payload
    end

    @tag :tmp_dir
    test "a JPEG photo is written as WebP and round-trips from its first export on",
         %{tmp_dir: tmp_dir} do
      pack = copy_pack!(demo_path())

      ffmpeg!([
        "-f",
        "lavfi",
        "-i",
        "testsrc2=size=96x64",
        "-frames:v",
        "1",
        "-c:v",
        "mjpeg",
        "-f",
        "mjpeg",
        Path.join(pack, "media/photo.jpg")
      ])

      append_block!(
        pack,
        @demo_lesson,
        ~s(:::figure{src=media/photo.jpg alt="A test pattern." size=medium provenance=invented}\n:::\n)
      )

      first = import_processed!(pack, MediaFixtures.media_for(pack))
      photo = asset!(first.payload, "media/photo.jpg")
      assert %Asset{kind: :image, status: :ready, ext: "webp", animated: false} = photo

      program = Catalog.get_program_by_slug(first.pack_key)
      out1 = Path.join(tmp_dir, "first")
      assert {:ok, _version} = PackWriter.write(program, out1)

      files = contents(out1)
      refute Map.has_key?(files, "media/photo.jpg")
      assert files["media/photo.webp"] == File.read!(Store.path(photo.sha256, "webp"))

      assert files["#{@module2}/lessons/02-second-lesson.md"] =~
               ~s(:::figure{provenance=invented src="media/photo.webp" alt="A test pattern." size=medium})

      # From the first export on the pack round-trips: its import links the
      # same asset, and its export writes the same files.
      assert {:ok, %PackImport{status: :validated} = second} = Importer.import(out1, nil)
      assert MediaFixtures.process_queued!(second) == []
      assert second.payload == rename_media(first.payload, "media/photo.jpg", "media/photo.webp")
      assert {:ok, %PackImport{status: :published}} = Publisher.publish(second)

      out2 = Path.join(tmp_dir, "second")
      assert {:ok, _version} = PackWriter.write(program, out2)
      assert contents(out2) == files

      assert {:ok, %PackImport{status: :validated} = third} = Importer.import(out2, nil)
      assert third.payload == second.payload
    end
  end

  defp ids(entries), do: Enum.map(entries, fn {path, asset} -> {path, asset.id} end)

  # Runs ffmpeg of the shell with `args` after the fixed options.
  defp ffmpeg!(args) do
    executable = System.find_executable("ffmpeg") || flunk("ffmpeg is not on the PATH")

    {output, status} =
      System.cmd(executable, ["-nostdin", "-hide_banner", "-loglevel", "error", "-y" | args],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp append_block!(pack, rel, block),
    do: File.write!(Path.join(pack, rel), "\n" <> block, [:append])

  # Imports `pack` with the mapping `media`, processes every asset that the
  # import queued in this process, and publishes the import.
  defp import_processed!(pack, media) do
    assert {:ok, %PackImport{status: :validated} = pack_import} =
             Importer.import(pack, nil, media: media)

    for asset <- MediaFixtures.process_queued!(pack_import) do
      assert asset.status == :ready,
             "#{asset.source_name}: #{asset.failure} #{asset.failure_detail}"
    end

    assert {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    pack_import
  end

  defp asset!(payload, path) do
    %{"asset_id" => id} = Enum.find(payload["media"], &(&1["path"] == path))
    Repo.get!(Asset, id)
  end

  # The payload with the media path `from` renamed to `to` in the media
  # list and in the blocks, as an export writes it.
  defp rename_media(payload, from, to) do
    rename = fn
      ^from -> to
      other -> other
    end

    modules = Enum.map(payload["modules"], &rename_in_module(&1, rename))

    media =
      payload["media"]
      |> Enum.map(&Map.update!(&1, "path", rename))
      |> Enum.sort_by(& &1["path"])

    %{payload | "modules" => modules, "media" => media}
  end

  defp rename_in_module(module, rename),
    do:
      Map.update!(module, "lessons", fn lessons ->
        Enum.map(lessons, &rename_in_lesson(&1, rename))
      end)

  defp rename_in_lesson(lesson, rename),
    do:
      Map.update!(lesson, "blocks", fn blocks ->
        Enum.map(blocks, &rename_in_block(&1, rename))
      end)

  defp rename_in_block(%{"media" => %{} = media} = block, rename),
    do: %{block | "media" => %{media | "src" => rename.(media["src"])}}

  defp rename_in_block(block, _rename), do: block

  # The files below `dir` with their contents, keyed by relative path.
  defp contents(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.reject(&File.dir?/1)
    |> Map.new(&{Path.relative_to(&1, dir), File.read!(&1)})
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
