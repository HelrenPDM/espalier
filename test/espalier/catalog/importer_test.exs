defmodule Espalier.Catalog.ImporterTest do
  use Espalier.DataCase, async: false

  import ExUnit.CaptureIO

  import Espalier.PackFixtures,
    only: [
      copy_pack!: 1,
      demo_path: 0,
      line_of!: 3,
      read!: 2,
      read_yaml!: 2,
      replace!: 4,
      update_yaml!: 3,
      write!: 3
    ]

  alias Espalier.Catalog.Pack.{Entries, Importer, Loader, Publisher, Report, Validator}
  alias Espalier.Catalog.PackImport
  alias Espalier.Release
  alias Mix.Tasks.Espalier, as: Tasks

  # The front matter of an extra lesson; its body starts at line 5.
  @front "---\ntitle: Extra\nposition: 9\n---\n"

  @items1 "modules/01-basics/items.yaml"
  @items2 "modules/02-checking/items.yaml"
  @objectives1 "modules/01-basics/objectives.yaml"
  @rules1 "modules/01-basics/rules.yaml"
  @lesson1 "modules/01-basics/lessons/01-first-lesson.md"
  @demo_exam_items ~w(m1-exam-next-word m1-exam-varying-answers m1-exam-check-claims m1-exam-confident-answer)

  describe "import/2" do
    @tag :tmp_dir
    test "a pack that does not load gives a failed import with the loader errors", %{
      tmp_dir: tmp_dir
    } do
      actor_id = Ecto.UUID.generate()
      path = Path.join(tmp_dir, "missing-pack")

      assert {:ok, %PackImport{} = pack_import} = Importer.import(path, actor_id)

      assert pack_import.status == :failed
      assert pack_import.payload == nil
      assert pack_import.pack_key == nil
      assert pack_import.pack_version == nil
      assert pack_import.imported_by_id == actor_id
      assert pack_import.published_at == nil
      assert %{"errors" => [_ | _] = errors, "warnings" => []} = pack_import.report

      for entry <- errors do
        assert %{"file" => file, "line" => line, "message" => message} = entry
        assert is_binary(file) and is_integer(line) and is_binary(message)
        assert Enum.all?(Map.keys(entry), &is_binary/1)
      end

      assert Repo.get!(PackImport, pack_import.id) == pack_import
      assert Publisher.publish(pack_import) == {:error, :not_validated}
    end

    @tag :tmp_dir
    test "an import without an actor stores no actor id", %{tmp_dir: tmp_dir} do
      assert {:ok, pack_import} = Importer.import(Path.join(tmp_dir, "missing-pack"), nil)
      assert pack_import.imported_by_id == nil
      assert Repo.get!(PackImport, pack_import.id).imported_by_id == nil
    end

    test "the changeset of an import takes no actor id, which only the importer sets" do
      actor_id = Ecto.UUID.generate()

      changeset =
        PackImport.changeset(%PackImport{}, %{
          "status" => "failed",
          "report" => %{"errors" => [], "warnings" => []},
          "imported_by_id" => actor_id
        })

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :imported_by_id)

      assert {:ok, pack_import} = Importer.import(demo_path(), actor_id)
      assert Repo.get!(PackImport, pack_import.id).imported_by_id == actor_id
    end
  end

  describe "import/2 of a pack with an orphan exam item" do
    test "fails in strict mode with one check 2 entry in the stored errors" do
      pack = orphan_pack!(:strict)

      assert {:ok, %PackImport{} = pack_import} = Importer.import(pack, nil)
      stored = Repo.get!(PackImport, pack_import.id)

      assert stored.status == :failed
      assert stored.payload == nil
      assert {stored.pack_key, stored.pack_version} == {"minimal-pack", "0.1.0"}
      assert %{"errors" => [entry], "warnings" => []} = stored.report
      assert_orphan_entry(pack, entry)
    end

    test "is validated in warn mode with the same entry in the stored warnings" do
      strict = orphan_pack!(:strict)
      warn = orphan_pack!(:warn)

      assert {:ok, strict_import} = Importer.import(strict, nil)
      assert {:ok, warn_import} = Importer.import(warn, nil)
      assert %{"errors" => [entry]} = Repo.get!(PackImport, strict_import.id).report
      assert_orphan_entry(warn, entry)

      stored = Repo.get!(PackImport, warn_import.id)
      assert stored.status == :validated
      assert stored.report == %{"errors" => [], "warnings" => [entry]}
      assert stored.payload["alignment"] == "warn"

      assert [%{"items" => items} | _] = stored.payload["modules"]

      assert %{"objectives" => [], "lesson" => nil} =
               Enum.find(items, &(&1["key"] == "m1-exam-2"))
    end

    test "each exam item of the demo pack without objectives gives exactly one check 2 error" do
      [exam] = read_yaml!(demo_path(), "modules/01-basics/assessment.yaml")
      assert exam["items"] == @demo_exam_items

      for key <- @demo_exam_items do
        pack = copy_pack!(demo_path())
        drop_objectives!(pack, @items1, key)
        line = line_of!(pack, @items1, "- key: #{key}")

        assert {:ok, pack_import} = Importer.import(pack, nil)
        stored = Repo.get!(PackImport, pack_import.id)

        assert stored.status == :failed, "#{key} without objectives gave a validated import"
        assert %{"errors" => [entry], "warnings" => []} = stored.report

        assert %{
                 "check" => 2,
                 "module" => 1,
                 "key" => ^key,
                 "file" => @items1,
                 "line" => ^line,
                 "message" => message
               } = entry

        assert message =~ "`#{key}`"
      end
    end
  end

  describe "import/2 of the demo pack" do
    test "a validated import stores pack_key, pack_version and the actor id" do
      actor_id = Ecto.UUID.generate()

      assert {:ok, pack_import} = Importer.import(demo_path(), actor_id)
      stored = Repo.get!(PackImport, pack_import.id)

      assert stored.status == :validated
      assert stored.pack_key == "ai-assistant-basics-demo"
      assert stored.pack_version == "1.0.0"
      assert stored.imported_by_id == actor_id
      assert stored.published_at == nil
      assert stored.report == %{"errors" => [], "warnings" => []}
    end

    test "the payload read back from the database equals the payload of the returned import" do
      assert {:ok, loaded} = Loader.load(demo_path())
      assert %{errors: [], warnings: [], payload: %{} = payload} = Validator.run(loaded)

      assert {:ok, pack_import} = Importer.import(demo_path(), nil)
      assert pack_import.payload == payload

      stored = Repo.get!(PackImport, pack_import.id)
      assert stored.payload == pack_import.payload
      assert stored == pack_import
    end

    test "two imports of the unchanged demo pack give equal payloads" do
      first = stored_payload!(demo_path())
      second = stored_payload!(copy_pack!(demo_path()))

      assert %{"key" => "ai-assistant-basics-demo", "modules" => [_, _]} = first
      assert second == first
    end

    test "the payload equals the payload of a copy that lists the sorted lists in reverse order" do
      reversed = copy_pack!(demo_path())
      reverse_sorted_lists!(reversed)

      for rel <- [@items1, @items2, "formats.yaml", "sources.yaml", "glossary.yaml"] do
        assert read_yaml!(reversed, rel) != read_yaml!(demo_path(), rel),
               "the reversed copy lists #{rel} in the same order"
      end

      payload = stored_payload!(demo_path())
      assert stored_payload!(reversed) == payload

      assert [basics, checking] = payload["modules"]

      assert Enum.map(checking["objectives"], &{&1["key"], Map.fetch(&1, "domain")}) == [
               {"m2-subject-prompt-parts", {:ok, nil}},
               {"m2-method-judge-output", {:ok, nil}},
               {"m2-method-release-check", {:ok, nil}}
             ]

      exam_keys =
        for module <- payload["modules"],
            assessment <- module["assessments"],
            assessment["kind"] == "exam",
            key <- assessment["items"],
            do: key

      assert exam_keys == @demo_exam_items

      items = Map.new(basics["items"] ++ checking["items"], &{&1["key"], &1})
      assert map_size(items) == 12

      for key <- exam_keys do
        assert Map.fetch(items[key], "lesson") == {:ok, nil}
      end

      for {key, item} <- items do
        assert item["rules"] == Enum.sort(item["rules"]), "the rules of #{key} are not ascending"
      end

      assert items["m1-fluent-figure"]["rules"] == [1, 3]
      assert items["m2-judge-drafts"]["rules"] == [2, 4]
      assert Enum.map(payload["sources"], & &1["key"]) == ["office-study", "vendor-guide"]

      slugs = Enum.map(payload["glossary"], & &1["slug"])
      assert length(slugs) == 8
      assert slugs == Enum.sort(slugs)

      assert Enum.find(payload["formats"], &(&1["key"] == "workshop"))["objectives"] == [
               "m1-self-own-responsibility",
               "m1-social-team-transparency"
             ]
    end

    test "reveals, objectives, taught_in and cite lists with two entries are sorted in either order" do
      base = copy_pack!(demo_path())

      put_member!(base, @items1, "m1-how-models-write", "reveals", [
        "01-first-lesson",
        "02-second-lesson"
      ])

      put_member!(base, @items1, "m1-exam-confident-answer", "objectives", [
        "m1-method-check-claims",
        "m1-subject-next-word"
      ])

      put_member!(base, @items1, "m1-before-use", "cite", [
        "office-study#Interviews",
        "vendor-guide#Overview"
      ])

      put_member!(base, @objectives1, "m1-method-check-claims", "taught_in", [
        "02-second-lesson",
        "03-third-lesson"
      ])

      update_yaml!(base, @rules1, fn rules ->
        List.update_at(
          rules,
          1,
          &Map.put(&1, "cite", ["office-study#Interviews", "vendor-guide#Limitations"])
        )
      end)

      replace!(
        base,
        @lesson1,
        ~s(cite="vendor-guide#Overview"),
        ~s(cite="office-study#Interviews,vendor-guide#Overview")
      )

      reversed = copy_pack!(base)
      reverse_sorted_lists!(reversed)

      for rel <- [@items1, @objectives1, @rules1, @lesson1] do
        assert read!(reversed, rel) != read!(base, rel),
               "the reversed copy lists #{rel} in the same order"
      end

      payload = stored_payload!(base)
      assert stored_payload!(reversed) == payload

      assert [basics, _checking] = payload["modules"]
      items = Map.new(basics["items"], &{&1["key"], &1})

      assert items["m1-how-models-write"]["reveals"] == ["01-first-lesson", "02-second-lesson"]

      assert items["m1-exam-confident-answer"]["objectives"] == [
               "m1-method-check-claims",
               "m1-subject-next-word"
             ]

      assert items["m1-before-use"]["cite"] == [
               "office-study#Interviews",
               "vendor-guide#Overview"
             ]

      assert Enum.find(basics["objectives"], &(&1["key"] == "m1-method-check-claims"))[
               "taught_in"
             ] == ["02-second-lesson", "03-third-lesson"]

      assert Enum.find(basics["rules"], &(&1["number"] == 2))["cite"] == [
               "office-study#Interviews",
               "vendor-guide#Limitations"
             ]

      [first_lesson | _] = basics["lessons"]
      explanation = Enum.find(first_lesson["blocks"], &(&1["kind"] == "explanation"))
      assert explanation["cite"] == ["office-study#Interviews", "vendor-guide#Overview"]
    end
  end

  describe "import/2 at the bounds of the columns" do
    test "values at the bounds validate, keep pack_key and publish" do
      pack = copy_pack!("minimal")
      key = String.duplicate("k", 255)
      # 127 letters with a combining accent and one plain letter: 255 code points.
      title = String.duplicate("e" <> <<0x0301::utf8>>, 127) <> "e"
      locator = String.duplicate("s", 255)
      replace!(pack, "pack.yaml", "key: minimal-pack", "key: #{key}")
      replace!(pack, "pack.yaml", "title: Minimal pack (test fixture)", "title: #{title}")
      replace!(pack, "modules/02-checking/module.yaml", "number: 2", "number: 2147483647")
      replace!(pack, "stations.yaml", "module: 2", "module: 2147483647")
      replace!(pack, "modules/01-basics/rules.yaml", "Section 1", locator)

      assert {:ok, %PackImport{status: :validated} = draft} = Importer.import(pack, nil)
      assert {draft.pack_key, draft.pack_version} == {key, "0.1.0"}
      assert Repo.get!(PackImport, draft.id) == draft

      assert {:ok, %PackImport{status: :published}} = Publisher.publish(draft)
      assert %{title: ^title} = Espalier.Catalog.get_program_by_slug(key)
    end

    test "a key, a title, a cite locator and a module number past the bounds fail with file and line" do
      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", "key: minimal-pack", "key: #{String.duplicate("k", 256)}")
      replace!(pack, "pack.yaml", "version: 0.1.0", "version: 0.1.#{String.duplicate("1", 252)}")

      replace!(
        pack,
        "pack.yaml",
        "title: Minimal pack (test fixture)",
        "title: #{String.duplicate("t", 256)}"
      )

      replace!(pack, "modules/01-basics/rules.yaml", "Section 1", String.duplicate("s", 256))
      replace!(pack, "modules/02-checking/module.yaml", "number: 2", "number: 2147483648")

      assert {:ok, %PackImport{} = pack_import} = Importer.import(pack, nil)
      assert {pack_import.status, pack_import.payload} == {:failed, nil}
      assert {pack_import.pack_key, pack_import.pack_version} == {nil, nil}

      assert %{"errors" => errors, "warnings" => []} = pack_import.report

      assert Enum.map(errors, &{&1["file"], &1["line"], &1["message"]}) == [
               {"modules/01-basics/rules.yaml", 4,
                "the locator of a `cite` entry must have at most 255 characters"},
               {"modules/02-checking/module.yaml", 1, "`number` must be at most 2147483647"},
               {"pack.yaml", 2, "`key` must have at most 255 characters"},
               {"pack.yaml", 3, "`title` must have at most 255 characters"},
               {"pack.yaml", 6, "`version` must have at most 255 characters"}
             ]

      assert Repo.get!(PackImport, pack_import.id) == pack_import
    end

    test "aliases that multiply a long string and an escape of a lone surrogate give failed imports" do
      long = String.duplicate("x", 100_000)
      aliased = "- slug: &s \"#{long}\"\n" <> String.duplicate("- slug: *s\n", 30)

      for {file, content, message} <- [
            {"glossary.yaml", aliased, "the strings of the YAML text hold more than 2 MiB"},
            {"glossary.yaml", ~S(- slug: "\uDC00") <> "\n",
             "a string holds an escape that names no Unicode character"}
          ] do
        pack = copy_pack!("minimal")
        write!(pack, file, content)

        assert {:ok, %PackImport{status: :failed, payload: nil} = pack_import} =
                 Importer.import(pack, nil)

        assert %{"errors" => [%{"file" => ^file, "line" => 1, "message" => ^message}]} =
                 pack_import.report

        assert Repo.get!(PackImport, pack_import.id) == pack_import
      end
    end

    test "a NUL character in a YAML string or a lesson body gives a failed import" do
      in_yaml = copy_pack!("minimal")

      replace!(
        in_yaml,
        "sources.yaml",
        "title: A fictional guide",
        ~s(title: "A fictional\\0 guide)
      )

      replace!(in_yaml, "sources.yaml", "(invented for tests)", ~s[(invented for tests)"])

      in_body = copy_pack!("minimal")

      replace!(
        in_body,
        "modules/01-basics/lessons/01-intro.md",
        "continues text.",
        "continues\0 text."
      )

      for {pack, file} <- [
            {in_yaml, "sources.yaml"},
            {in_body, "modules/01-basics/lessons/01-intro.md"}
          ] do
        assert {:ok, %PackImport{status: :failed, payload: nil} = pack_import} =
                 Importer.import(pack, nil)

        assert %{"errors" => [entry]} = pack_import.report
        assert %{"file" => ^file, "line" => line, "message" => message} = entry
        assert is_integer(line) and line >= 1
        assert message =~ ~r/NUL|U\+0000/
        assert Repo.get!(PackImport, pack_import.id) == pack_import
      end
    end

    test "lessons of many stray lines and a block kind of 1 MiB give failed imports with a bounded report" do
      stray = copy_pack!("minimal")

      for n <- 1..6 do
        write!(
          stray,
          "modules/02-checking/lessons/9#{n}-x.md",
          @front <> String.duplicate("x\n", 20_000)
        )
      end

      assert {:ok, %PackImport{status: :failed, payload: nil} = stray_import} =
               Importer.import(stray, nil)

      assert %{"errors" => errors, "warnings" => []} = stray_import.report
      assert length(errors) == 6 * 101
      assert Entries.count(errors) == 6 * 20_000

      assert %{"line" => 104, "message" => "and 19,900 further errors in this file"} =
               List.last(errors)

      assert Repo.get!(PackImport, stray_import.id) == stray_import

      long_kind = copy_pack!("minimal")

      write!(
        long_kind,
        "modules/02-checking/lessons/91-x.md",
        @front <> ":::" <> String.duplicate("a", 1_048_000) <> "\nText.\n"
      )

      assert {:ok, %PackImport{status: :failed} = kind_import} = Importer.import(long_kind, nil)
      assert %{"errors" => [unclosed, unknown]} = kind_import.report
      # 997 characters of the message and the marker `[…]`.
      assert unclosed["message"] =~ ~r/\Aunclosed block `a{981}\[…\]\z/u
      assert unknown["message"] =~ ~r/\Aunknown block kind `a{977}\[…\]\z/u
      assert Repo.get!(PackImport, kind_import.id) == kind_import
    end

    test "aliases spread over many small files give a failed import at the pack budget" do
      pack = copy_pack!("minimal")
      stem = String.duplicate("x", 40_000)

      # 16 of these items.yaml files stay below the budget, the 17th crosses it.
      for number <- 3..20 do
        dir = "modules/#{number |> Integer.to_string() |> String.pad_leading(2, "0")}-big"
        write!(pack, dir <> "/module.yaml", "number: #{number}\n")

        write!(pack, dir <> "/items.yaml", [
          "- &s \"",
          stem,
          "\"\n",
          String.duplicate("- *s\n", 49)
        ])

        write!(pack, dir <> "/lessons/01-a.md", @front)
      end

      assert {:ok, %PackImport{status: :failed, payload: nil} = pack_import} =
               Importer.import(pack, nil)

      assert pack_import.report == %{
               "errors" => [
                 %{
                   "file" => "modules/19-big/items.yaml",
                   "line" => 1,
                   "message" => "the pack holds more than 32 MiB of text once decoded"
                 }
               ],
               "warnings" => []
             }

      assert Repo.get!(PackImport, pack_import.id) == pack_import
    end

    test "a station config of strings, integers, booleans, null, lists and maps survives the payload column" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "stations.yaml",
        "    intro: Two short modules.",
        """
            intro: Two short modules.
            weight: 1000
            big: 9007199254740991
            shown: true
            note: null
            steps: [1, "two", {three: 3}]
        """
        |> String.trim_trailing()
      )

      assert {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(pack, nil)
      stored = Repo.get!(PackImport, pack_import.id)
      assert stored.payload === pack_import.payload

      overview = Enum.find(stored.payload["stations"], &(&1["kind"] == "overview"))
      assert overview["config"]["weight"] === 1000
      assert overview["config"]["steps"] == [1, "two", %{"three" => 3}]
    end
  end

  describe "Report" do
    test "format/2 gives the line forms of mix espalier.validate for both key kinds" do
      atom_entry = %{file: "modules/01-basics/items.yaml", line: 12, message: "unknown key `x`"}
      string_entry = %{"file" => "pack.yaml", "line" => 1, "message" => "`schema` must be 1"}

      assert Report.format(atom_entry, :error) ==
               "modules/01-basics/items.yaml:12: unknown key `x`"

      assert Report.format(atom_entry, :warning) ==
               "modules/01-basics/items.yaml:12: warning: unknown key `x`"

      assert Report.format(string_entry, :error) == "pack.yaml:1: `schema` must be 1"
      assert Report.format(string_entry, :warning) == "pack.yaml:1: warning: `schema` must be 1"

      assert Report.lines([string_entry], [atom_entry]) == [
               "pack.yaml:1: `schema` must be 1",
               "modules/01-basics/items.yaml:12: warning: unknown key `x`"
             ]
    end

    test "stored/2 keeps every member with string keys and survives the JSON column" do
      error = %{
        check: 2,
        module: 1,
        key: "m1-exam-one",
        file: "modules/01-basics/items.yaml",
        line: 40,
        message: "item `m1-exam-one` names no objective"
      }

      warning = %{file: "pack.yaml", line: 3, message: "value `a\0b`"}
      report = Report.stored([error], [warning])

      assert report == %{
               "errors" => [
                 %{
                   "check" => 2,
                   "module" => 1,
                   "key" => "m1-exam-one",
                   "file" => "modules/01-basics/items.yaml",
                   "line" => 40,
                   "message" => "item `m1-exam-one` names no objective"
                 }
               ],
               "warnings" => [
                 %{"file" => "pack.yaml", "line" => 3, "message" => "value `a\\x00b`"}
               ]
             }

      stored = Repo.insert!(%PackImport{status: :failed, report: report})
      assert Repo.get!(PackImport, stored.id).report == report

      assert Report.report_lines(report) == [
               "modules/01-basics/items.yaml:40: item `m1-exam-one` names no objective",
               "pack.yaml:3: warning: value `a\\x00b`"
             ]
    end

    test "matrix_text/1 joins lists with commas and marks empty fields with a dash" do
      assert Report.matrix_text(rows()) == [
               "module\tarea\tdepth\tobjectives\tlessons\tevidence\telsewhere",
               "1\tsubject\tknow\tm1-a,m1-b\t01-first-lesson\titem:m1-x,format:workshop\t-",
               "2\tsocial\tjudge\t-\t-\t-\tformat:workshop"
             ]
    end

    test "matrix_csv/1 writes RFC 4180 records and quotes fields that need it" do
      assert Report.matrix_csv(rows()) ==
               "module,area,depth,objectives,lessons,evidence,elsewhere\r\n" <>
                 "1,subject,know,m1-a m1-b,01-first-lesson,item:m1-x format:workshop,\r\n" <>
                 "2,social,judge,,,,format:workshop\r\n"

      odd = %{
        hd(rows())
        | objectives: ["a,b", "c\"d"],
          lessons: ["line\nbreak"],
          elsewhere: "plain"
      }

      assert Report.matrix_csv([odd]) ==
               "module,area,depth,objectives,lessons,evidence,elsewhere\r\n" <>
                 ~s(1,subject,know,"a,b c""d","line\nbreak",item:m1-x format:workshop,plain\r\n)
    end

    test "matrix_json/3 encodes the matrix and the findings in one object" do
      error = %{file: "pack.yaml", line: 1, message: "broken"}
      decoded = JSON.decode!(Report.matrix_json(rows(), [error], []))

      assert decoded["errors"] == [%{"file" => "pack.yaml", "line" => 1, "message" => "broken"}]
      assert decoded["warnings"] == []
      assert [first, %{"elsewhere" => "format:workshop", "objectives" => []}] = decoded["matrix"]
      assert first["module"] == 1 and first["elsewhere"] == nil
    end

    @tag :tmp_dir
    test "run_import/2 prints the report of a failed import", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "missing-pack")

      {result, output} = with_io(fn -> Report.run_import(path) end)
      assert {:error, %PackImport{status: :failed} = failed} = result

      for line <- Report.report_lines(failed.report) do
        assert output =~ line
      end

      assert output =~ "Import #{failed.id} failed"
    end

    test "run_import/2 prints the closing entries and counts the errors they stand for" do
      pack = copy_pack!("minimal")
      file = "modules/02-checking/lessons/09-stray.md"
      write!(pack, file, @front <> String.duplicate("x\n", 2_500))

      {result, output} = with_io(fn -> Report.run_import(pack) end)
      assert {:error, %PackImport{status: :failed} = failed} = result

      lines = String.split(output, "\n", trim: true)
      assert length(lines) == 102
      assert hd(lines) == "#{file}:5: text outside a block"
      assert Enum.at(lines, 100) == "#{file}:104: and 2,400 further errors in this file"
      assert List.last(lines) == "Import #{failed.id} failed with 2,500 errors"
    end
  end

  describe "Release.import_pack/2" do
    @tag :tmp_dir
    test "imports inside with_repo and returns the failed import", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "missing-pack")

      output =
        capture_io(fn ->
          assert {:error, %PackImport{status: :failed}} = Release.import_pack(path)
          assert {:error, %PackImport{status: :failed}} = Release.import_pack(path, draft: true)
        end)

      assert output =~ "failed"
    end
  end

  describe "mix tasks" do
    @tag :tmp_dir
    test "espalier.validate prints the loader errors and exits with status 1", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "missing-pack")

      output =
        capture_io(fn ->
          assert catch_exit(Tasks.Validate.run([path])) == {:shutdown, 1}
        end)

      assert output =~ ~r/^[^:\n]+:\d+: /
    end

    @tag :tmp_dir
    test "espalier.import exits with status 1 for a failed import", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "missing-pack")

      output =
        capture_io(fn ->
          assert catch_exit(Tasks.Import.run([path, "--draft"])) == {:shutdown, 1}
        end)

      assert output =~ "failed"
    end

    test "invalid arguments and an unknown format exit with status 1" do
      capture_io(:stderr, fn ->
        assert catch_exit(Tasks.Alignment.run(["content/demo", "--format", "xml"])) ==
                 {:shutdown, 1}

        assert catch_exit(Tasks.Alignment.run(["content/demo", "--colour"])) == {:shutdown, 1}
        assert catch_exit(Tasks.Alignment.run([])) == {:shutdown, 1}
        assert catch_exit(Tasks.Validate.run(["a", "b"])) == {:shutdown, 1}
        assert catch_exit(Tasks.Import.run(["a", "--force"])) == {:shutdown, 1}
      end)
    end
  end

  defp rows do
    [
      %{
        module: 1,
        area: "subject",
        depth: "know",
        objectives: ["m1-a", "m1-b"],
        lessons: ["01-first-lesson"],
        evidence: ["item:m1-x", "format:workshop"],
        elsewhere: nil
      },
      %{
        module: 2,
        area: "social",
        depth: "judge",
        objectives: [],
        lessons: [],
        evidence: [],
        elsewhere: "format:workshop"
      }
    ]
  end

  # A copy of the minimal pack whose exam item `m1-exam-2` names no objective.
  defp orphan_pack!(mode) do
    pack = copy_pack!("minimal")
    drop_objectives!(pack, @items1, "m1-exam-2")

    if mode == :warn,
      do: replace!(pack, "pack.yaml", "version: 0.1.0", "version: 0.1.0\nalignment: warn")

    pack
  end

  defp assert_orphan_entry(pack, entry) do
    line = line_of!(pack, @items1, "- key: m1-exam-2")

    assert %{
             "check" => 2,
             "module" => 1,
             "key" => "m1-exam-2",
             "file" => "modules/01-basics/items.yaml",
             "line" => ^line,
             "message" => message
           } = entry

    assert map_size(entry) == 6
    assert message =~ "`m1-exam-2`"
  end

  # Removes the `objectives` line of the item `key` from a hand-written
  # items.yaml and leaves every other line as it is.
  defp drop_objectives!(pack, rel, key) do
    lines = pack |> read!(rel) |> String.split("\n")
    start = Enum.find_index(lines, &(&1 == "- key: #{key}"))
    assert is_integer(start), "no entry #{key} in #{rel}"

    offset =
      lines
      |> Enum.drop(start + 1)
      |> Enum.take_while(&(not String.starts_with?(&1, "- ")))
      |> Enum.find_index(&String.starts_with?(&1, "  objectives:"))

    assert is_integer(offset), "the entry #{key} in #{rel} has no objectives line"
    write!(pack, rel, lines |> List.delete_at(start + 1 + offset) |> Enum.join("\n"))
  end

  # Imports `pack` and returns the payload of the import read back from the
  # database, asserting that the import is validated without findings.
  defp stored_payload!(pack) do
    assert {:ok, pack_import} = Importer.import(pack, nil)
    stored = Repo.get!(PackImport, pack_import.id)
    assert stored.status == :validated
    assert stored.report == %{"errors" => [], "warnings" => []}
    stored.payload
  end

  defp put_member!(pack, rel, key, field, value) do
    update_yaml!(pack, rel, fn entries ->
      Enum.map(entries, fn
        %{"key" => ^key} = entry -> Map.put(entry, field, value)
        entry -> entry
      end)
    end)
  end

  # Reverses the lists that the payload sorts: the rules, reveals, objectives
  # and cite lists of items, the taught_in lists of objectives, the cite
  # lists of rules and blocks, the objectives of formats, the sources and
  # the glossary terms.
  defp reverse_sorted_lists!(pack) do
    for dir <- File.ls!(Path.join(pack, "modules")) do
      module = "modules/#{dir}"
      reverse_members!(pack, "#{module}/items.yaml", ~w(rules reveals objectives cite))
      reverse_members!(pack, "#{module}/objectives.yaml", ~w(taught_in))
      reverse_members!(pack, "#{module}/rules.yaml", ~w(cite))

      for lesson <- File.ls!(Path.join(pack, "#{module}/lessons")) do
        reverse_cite_attributes!(pack, "#{module}/lessons/#{lesson}")
      end
    end

    reverse_members!(pack, "formats.yaml", ~w(objectives))
    update_yaml!(pack, "sources.yaml", &Enum.reverse/1)
    update_yaml!(pack, "glossary.yaml", &Enum.reverse/1)
  end

  defp reverse_members!(pack, rel, fields) do
    update_yaml!(pack, rel, fn entries ->
      Enum.map(entries, &reverse_fields(&1, fields))
    end)
  end

  defp reverse_fields(entry, fields) do
    Enum.reduce(fields, entry, fn field, acc ->
      Map.replace_lazy(acc, field, &Enum.reverse/1)
    end)
  end

  defp reverse_cite_attributes!(pack, rel) do
    content =
      Regex.replace(~r/cite="([^"]*)"/, read!(pack, rel), fn _attribute, cites ->
        reversed = cites |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reverse()
        ~s(cite="#{Enum.join(reversed, ",")}")
      end)

    write!(pack, rel, content)
  end
end
