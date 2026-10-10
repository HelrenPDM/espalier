defmodule Espalier.Catalog.LoaderTest do
  use ExUnit.Case, async: true

  import Espalier.PackFixtures

  alias Espalier.Catalog.Pack.{LineIndex, Loader, Validator}

  # The front matter of an extra lesson; its body starts at line 5.
  @front "---\ntitle: Extra\nposition: 9\n---\n"

  defp load_errors(pack) do
    assert {:error, errors} = Loader.load(pack)
    Enum.map(errors, &{&1.file, &1.line, &1.message})
  end

  describe "load/1" do
    test "reads the minimal pack" do
      pack = copy_pack!("minimal")
      assert {:ok, loaded} = Loader.load(pack)

      assert loaded.root == Path.expand(pack)

      assert Map.keys(loaded.files) |> Enum.sort() ==
               ~w(feedback.yaml formats.yaml glossary.yaml pack.yaml qualifications.yaml segments.yaml sources.yaml stations.yaml)

      assert %{file: "pack.yaml", data: %{"schema" => 1, "key" => "minimal-pack"}} =
               loaded.files["pack.yaml"]

      assert [%{dir: "01-basics"} = basics, %{dir: "02-checking"} = checking] = loaded.modules

      assert Map.keys(basics.files) |> Enum.sort() ==
               ~w(assessment.yaml items.yaml module.yaml objectives.yaml rules.yaml)

      refute Map.has_key?(checking.files, "assessment.yaml")
      assert basics.files["items.yaml"].file == "modules/01-basics/items.yaml"

      assert [%{key: "01-intro"} = intro, %{key: "02-practice"}] = basics.lessons
      assert intro.file == "modules/01-basics/lessons/01-intro.md"
      assert intro.front.data == %{"title" => "What an assistant does", "position" => 1}
      assert intro.front.lines[["position"]] == 3

      assert Enum.map(intro.blocks, &{&1.kind, &1.line}) == [
               {"text", 6},
               {"explanation", 10},
               {"quote", 14},
               {"placeholder", 18}
             ]
    end

    test "sorts the lessons of a module by key" do
      pack = copy_pack!("minimal")
      lesson = "---\ntitle: Extra\nposition: 9\n---\n\n:::text{provenance=invented}\nText.\n:::\n"
      write!(pack, "modules/02-checking/lessons/0-a-b.md", lesson)
      write!(pack, "modules/02-checking/lessons/0-a.md", lesson)

      assert {:ok, %{modules: [_basics, checking]}} = Loader.load(pack)
      assert Enum.map(checking.lessons, & &1.key) == ["0-a", "0-a-b", "01-check"]
    end

    test "maps every node to its line" do
      pack = copy_pack!("minimal")
      assert {:ok, loaded} = Loader.load(pack)
      items = hd(loaded.modules).files["items.yaml"]

      assert items.lines[[1]] == line_of!(pack, "modules/01-basics/items.yaml", "key: m1-multi")

      assert items.lines[[0, "options", 1]] ==
               line_of!(pack, "modules/01-basics/items.yaml", "- key: b")

      assert LineIndex.line(items.lines, [1, "missing"]) == items.lines[[1]]
    end

    test "rejects a symbolic link that points inside the pack" do
      pack = copy_pack!("minimal")
      File.ln_s!(path(pack, "sources.yaml"), path(pack, "modules/01-basics/notes.yaml"))

      assert [{"modules/01-basics/notes.yaml", 1, "symbolic links are not allowed in a pack"}] =
               load_errors(pack)
    end

    test "rejects a symbolic link that points outside the pack" do
      pack = copy_pack!("minimal")
      outside = copy_pack!("minimal")
      remove!(pack, "glossary.yaml")
      File.ln_s!(path(outside, "glossary.yaml"), path(pack, "glossary.yaml"))

      assert [{"glossary.yaml", 1, "symbolic links are not allowed in a pack"}] =
               load_errors(pack)
    end

    test "rejects a symbolic link to a directory and a link inside a directory that it does not read" do
      pack = copy_pack!("minimal")
      write!(pack, "drafts/notes.txt", "not part of the pack")
      File.ln_s!("/etc", path(pack, "drafts/etc"))
      File.ln_s!(path(pack, "modules/01-basics"), path(pack, "modules/03-copy"))

      assert [
               {"drafts/etc", 1, "symbolic links are not allowed in a pack"},
               {"modules/03-copy", 1, "symbolic links are not allowed in a pack"}
             ] = load_errors(pack)
    end

    test "rejects entry names that are not valid UTF-8, symbolic links among them" do
      pack = copy_pack!("minimal")
      write!(pack, "drafts/notes.txt", "not part of the pack")

      # Raw binary names; Linux file systems accept any byte except "/" and NUL.
      :ok = :file.make_symlink("/etc", <<pack::binary, "/top", 0xFF>>)
      :ok = :file.make_symlink("/etc/passwd", <<path(pack, "drafts")::binary, "/link", 0xFF>>)

      :ok =
        :file.write_file(
          <<path(pack, "modules/01-basics/lessons")::binary, "/bad`\\", 0xC3, 0x28, ".md">>,
          "---\ntitle: Bad\nposition: 3\n---\n"
        )

      assert load_errors(pack) == [
               {".", 1, "the entry name `top\\xFF` is not valid UTF-8"},
               {"drafts", 1, "the entry name `link\\xFF` is not valid UTF-8"},
               {"modules/01-basics/lessons", 1,
                "the entry name `bad\\x60\\x5C\\xC3(.md` is not valid UTF-8"}
             ]
    end

    test "rejects a pack directory that is a symbolic link" do
      pack = copy_pack!("minimal")
      link = pack <> "-link"
      File.ln_s!(pack, link)
      on_exit(fn -> File.rm(link) end)

      assert {:error, [%{file: ".", line: 1, message: "the pack directory is a symbolic link"}]} =
               Loader.load(link)

      assert Loader.pack_meta(link) == %{key: nil, version: nil}
    end

    test "rejects an entry that is neither a directory nor a regular file" do
      pack = copy_pack!("minimal")
      {_, 0} = System.cmd("mkfifo", [path(pack, "modules/01-basics/lessons/pipe.md")])

      assert [
               {"modules/01-basics/lessons/pipe.md", 1,
                "only directories and regular files are allowed in a pack"}
             ] = load_errors(pack)
    end

    test "reads only the files of the pack format" do
      pack = copy_pack!("minimal")
      write!(pack, "notes.yaml", "key: [unclosed")
      write!(pack, "modules/01-basics/extra.yaml", "key: [unclosed")
      write!(pack, "modules/01-basics/lessons/readme.txt", "---\nnot: [closed\n")
      write!(pack, "modules/README.md", "Not a module.")

      assert {:ok, loaded} = Loader.load(pack)
      refute Map.has_key?(loaded.files, "notes.yaml")
      refute Map.has_key?(hd(loaded.modules).files, "extra.yaml")
      assert Enum.map(hd(loaded.modules).lessons, & &1.key) == ["01-intro", "02-practice"]
    end

    test "reports a YAML syntax error with file, line and column" do
      pack = copy_pack!("minimal")
      replace!(pack, "formats.yaml", "phases: [anchor]", "phases: [anchor")

      assert [{"formats.yaml", line, message}] = load_errors(pack)
      assert line in 5..7
      assert message =~ ~r/^YAML syntax error: .+ at line #{line}, column \d+$/
    end

    test "reports the exact line and column of a YAML syntax error in a top-level and a module file" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "pack.yaml",
        "title: Minimal pack (test fixture)",
        "title: Minimal\n  extra: value"
      )

      replace!(
        pack,
        "modules/01-basics/module.yaml",
        "title: Basics",
        "title: Basics\n  extra: value"
      )

      assert load_errors(pack) == [
               {"modules/01-basics/module.yaml", 3,
                "YAML syntax error: Block mapping value not allowed here at line 3, column 8"},
               {"pack.yaml", 4,
                "YAML syntax error: Block mapping value not allowed here at line 4, column 8"}
             ]
    end

    test "reports the exact line and column of a syntax error in a front matter" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "modules/01-basics/lessons/02-practice.md",
        "title: Practice",
        "title: Practice\n  extra: value"
      )

      assert load_errors(pack) == [
               {"modules/01-basics/lessons/02-practice.md", 3,
                "YAML syntax error: Block mapping value not allowed here at line 3, column 8"}
             ]
    end

    test "reports a syntax error in a front matter with the line in the Markdown file" do
      pack = copy_pack!("minimal")
      replace!(pack, "modules/01-basics/lessons/02-practice.md", "position: 2", "position: [2")

      assert [{"modules/01-basics/lessons/02-practice.md", line, message}] = load_errors(pack)
      assert line in 3..4
      assert message =~ "at line #{line}, column"
    end

    test "keeps a key written as :name a string and creates no atom" do
      pack = copy_pack!("minimal")

      write!(
        pack,
        "pack.yaml",
        read!(pack, "pack.yaml") <> ":espalier_pack_probe_key: :espalier_pack_probe_value\n"
      )

      assert {:ok, loaded} = Loader.load(pack)
      data = loaded.files["pack.yaml"].data
      assert data[":espalier_pack_probe_key"] == ":espalier_pack_probe_value"
      assert_raise ArgumentError, fn -> String.to_existing_atom("espalier_pack_probe_key") end
      assert_raise ArgumentError, fn -> String.to_existing_atom("espalier_pack_probe_value") end
    end

    test "rejects a document above the node limit" do
      pack = copy_pack!("minimal")
      write!(pack, "glossary.yaml", String.duplicate("- x\n", LineIndex.max_nodes()))

      assert [{"glossary.yaml", 50_000, "the YAML text holds more than 50,000 nodes"}] =
               load_errors(pack)
    end

    test "accepts a document at the node limit" do
      assert {:ok, _lines} = LineIndex.build(String.duplicate("- x\n", LineIndex.max_nodes() - 1))
    end

    test "stops the expansion of aliases at the node limit" do
      pack = copy_pack!("minimal")

      levels =
        for level <- 1..4 do
          ["l#{level}: &l#{level}\n", String.duplicate("  - *l#{level - 1}\n", 10)]
        end

      text = [
        "l0: &l0\n",
        String.duplicate("  - x\n", 10),
        levels,
        "l5:\n",
        String.duplicate("  - *l4\n", 10)
      ]

      write!(pack, "sources.yaml", text)

      {micros, result} = :timer.tc(fn -> Loader.load(pack) end)

      assert {:error,
              [%{file: "sources.yaml", message: "the YAML text holds more than 50,000 nodes"}]} =
               result

      assert micros < 5_000_000
    end

    test "rejects a block nesting and a flow nesting deeper than 32 levels" do
      pack = copy_pack!("minimal")
      write!(pack, "glossary.yaml", String.duplicate("- ", 1_000) <> "x")

      write!(
        pack,
        "modules/01-basics/rules.yaml",
        "- number: 1\n  statement: " <>
          String.duplicate("[", 1_000) <> String.duplicate("]", 1_000) <> "\n"
      )

      assert load_errors(pack) == [
               {"glossary.yaml", 1, "the YAML text nests deeper than 32 levels"},
               {"modules/01-basics/rules.yaml", 2, "the YAML text nests deeper than 32 levels"}
             ]
    end

    test "rejects a file larger than 1 MiB before reading it and reads a file of 1 MiB" do
      pack = copy_pack!("minimal")
      assert Loader.max_file_bytes() == 1_048_576

      write!(pack, "glossary.yaml", String.duplicate("#", Loader.max_file_bytes()) <> "\n")

      write!(
        pack,
        "modules/01-basics/lessons/02-practice.md",
        read!(pack, "modules/01-basics/lessons/02-practice.md") <>
          String.duplicate("\n", Loader.max_file_bytes())
      )

      assert load_errors(pack) == [
               {"glossary.yaml", 1, "the file is larger than 1 MiB (1,048,576 bytes)"},
               {"modules/01-basics/lessons/02-practice.md", 1,
                "the file is larger than 1 MiB (1,048,576 bytes)"}
             ]

      remove!(pack, "modules/01-basics/lessons/02-practice.md")
      write!(pack, "glossary.yaml", String.duplicate("#", Loader.max_file_bytes() - 1) <> "\n")

      assert {:ok, loaded} = Loader.load(pack)
      assert loaded.files["glossary.yaml"].data == nil
    end

    test "rejects a control character in a lesson body and in a YAML file with its line and column" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "modules/01-basics/lessons/01-intro.md",
        "continues text.",
        "continues" <> <<0>> <> " text."
      )

      replace!(pack, "formats.yaml", "title: Handbook", "title: Hand\u0001book")
      replace!(pack, "pack.yaml", "title: Minimal", "title: Minimal\u007F")

      assert load_errors(pack) == [
               {"formats.yaml", 8,
                "control character U+0001 is not allowed at line 8, column 14"},
               {"modules/01-basics/lessons/01-intro.md", 7,
                "control character U+0000 is not allowed at line 7, column 49"},
               {"pack.yaml", 3, "control character U+007F is not allowed at line 3, column 15"}
             ]
    end

    test "rejects a control character that a YAML escape produces, also in a front matter" do
      pack = copy_pack!("minimal")
      replace!(pack, "glossary.yaml", "label: Writing assistant", ~S(label: "Writing\0assistant"))

      replace!(
        pack,
        "modules/01-basics/lessons/02-practice.md",
        "title: Practice",
        ~S(title: "Practice\x01")
      )

      assert load_errors(pack) == [
               {"glossary.yaml", 2, "control character U+0000 is not allowed in a string"},
               {"modules/01-basics/lessons/02-practice.md", 2,
                "control character U+0001 is not allowed in a string"}
             ]
    end

    test "rejects an anchor on a flow collection and keeps anchors on block collections" do
      pack = copy_pack!("minimal")
      file = "modules/01-basics/items.yaml"
      replace!(pack, file, "rules: [1]", "rules: &r [1]")
      replace!(pack, file, "rules: [1]", "rules: *r")

      # yamerl 0.10.0 would give the second item `rules: 1`.
      assert load_errors(pack) == [
               {file, 9,
                "an anchor on an empty value or a flow collection is not supported at line 9, " <>
                  "column 10; write `~` for an empty value and the collection in block style"}
             ]

      replace!(pack, file, "rules: &r [1]", "rules: &r\n    - 1")
      assert {:ok, loaded} = Loader.load(pack)

      assert [%{"rules" => [1]}, %{"rules" => [1]} | _] =
               hd(loaded.modules).files["items.yaml"].data
    end

    test "rejects duplicate keys, non-string keys, merge keys, binary values and a second document" do
      pack = copy_pack!("minimal")
      write!(pack, "pack.yaml", read!(pack, "pack.yaml") <> "title: Again\n")
      write!(pack, "glossary.yaml", "- slug: a\n  1: x\n")
      write!(pack, "segments.yaml", "- <<: {key: a}\n")
      write!(pack, "sources.yaml", "- key: a\n  title: !!binary aGVsbG8=\n")
      write!(pack, "formats.yaml", "- key: a\n---\n- key: b\n")

      assert [
               {"formats.yaml", 3, "a file holds one YAML document only"},
               {"glossary.yaml", 2, "a map key must be a string"},
               {"pack.yaml", 7, "duplicate key `title`"},
               {"segments.yaml", 1, "merge keys `<<` are not supported"},
               {"sources.yaml", 2, "unsupported YAML value type"}
             ] = load_errors(pack)
    end

    test "rejects a file that is not valid UTF-8" do
      pack = copy_pack!("minimal")
      write!(pack, "glossary.yaml", <<"- slug: ", 255, 254, "\n">>)

      assert [{"glossary.yaml", 1, "the file is not valid UTF-8 text"}] = load_errors(pack)
    end

    test "gives an empty document the data nil" do
      pack = copy_pack!("minimal")
      write!(pack, "sources.yaml", "# no sources yet\n")

      assert {:ok, loaded} = Loader.load(pack)
      assert loaded.files["sources.yaml"].data == nil
    end

    test "requires pack.yaml, modules and module.yaml and lessons in every module" do
      pack = copy_pack!("minimal")
      remove!(pack, "pack.yaml")
      remove!(pack, "modules/01-basics/module.yaml")
      remove!(pack, "modules/02-checking/lessons")

      assert [
               {"modules/01-basics/module.yaml", 1, "missing file"},
               {"modules/02-checking/lessons", 1, "missing directory `lessons`"},
               {"pack.yaml", 1, "missing file"}
             ] = load_errors(pack)

      remove!(pack, "modules")
      assert {"modules", 1, "missing directory `modules`"} in load_errors(pack)
    end

    test "requires a module directory and a lesson file" do
      pack = copy_pack!("minimal")
      remove!(pack, "modules/02-checking/lessons/01-check.md")
      write!(pack, "modules/02-checking/lessons/notes.txt", "not a lesson")

      assert [{"modules/02-checking/lessons", 1, "the directory `lessons` holds no `.md` file"}] =
               load_errors(pack)

      remove!(pack, "modules/01-basics")
      remove!(pack, "modules/02-checking")

      assert [{"modules", 1, "the directory `modules` holds no module directory"}] =
               load_errors(pack)
    end

    test "rejects lesson keys and module directory names outside the key format" do
      pack = copy_pack!("minimal")
      File.rename!(path(pack, "modules/02-checking"), path(pack, "modules/02 Checking"))

      File.rename!(
        path(pack, "modules/01-basics/lessons/02-practice.md"),
        path(pack, "modules/01-basics/lessons/Practice.md")
      )

      assert [
               {"modules/01-basics/lessons/Practice.md", 1,
                "lesson key `Practice` does not match the key format"},
               {"modules/02 Checking", 1,
                "module directory name `02 Checking` does not match the key format"}
             ] = load_errors(pack)
    end

    test "requires the front matter delimiters of a lesson file" do
      pack = copy_pack!("minimal")
      write!(pack, "modules/01-basics/lessons/02-practice.md", "title: Practice\n")

      write!(
        pack,
        "modules/02-checking/lessons/01-check.md",
        "---\ntitle: Checking\nposition: 1\n"
      )

      assert [
               {"modules/01-basics/lessons/02-practice.md", 1,
                "a lesson file starts with a front matter line `---`"},
               {"modules/02-checking/lessons/01-check.md", 1,
                "the front matter is not closed by a line `---`"}
             ] = load_errors(pack)
    end

    test "reports directive errors with the file and the line in the Markdown file" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "modules/01-basics/lessons/02-practice.md",
        ":::example{provenance=invented}",
        ":::video{provenance=invented}"
      )

      assert [{"modules/01-basics/lessons/02-practice.md", 6, "unknown block kind `video`"}] =
               load_errors(pack)
    end

    test "reports each directive error of step 7 with the file and its line in the Markdown file" do
      pack = copy_pack!("minimal")
      file = "modules/02-checking/lessons/02-errors.md"

      write!(pack, file, """
      ---
      title: Errors
      position: 2
      ---

      Stray text.
      :::video{provenance=invented}
      Text.
      :::
      :::text{provenance=invented colour=red}
      Text.
      :::
      :::example{cite="fictional-guide#Section 1"}
      Text.
      :::
      :::text{provenance=invented}
      :::example{provenance=invented}
      :::
      :::callout{provenance=invented}
      Never closed.
      """)

      # The body starts at line 5, after the four lines of the front matter.
      assert load_errors(pack) == [
               {file, 6, "text outside a block"},
               {file, 7, "unknown block kind `video`"},
               {file, 10, "unknown attribute `colour`"},
               {file, 13, "missing attribute `provenance`"},
               {file, 17, "a block cannot open inside the block opened at line 16"},
               {file, 19, "unclosed block `callout`"}
             ]
    end

    test "rejects a lesson file that is a relative symbolic link to another lesson of the module" do
      pack = copy_pack!("minimal")
      File.ln_s!("02-practice.md", path(pack, "modules/01-basics/lessons/03-copy.md"))

      assert load_errors(pack) == [
               {"modules/01-basics/lessons/03-copy.md", 1,
                "symbolic links are not allowed in a pack"}
             ]
    end

    test "rejects a lessons directory that is a symbolic link to a directory outside the pack" do
      pack = copy_pack!("minimal")
      outside = copy_pack!("minimal")
      remove!(pack, "modules/02-checking/lessons")

      File.ln_s!(
        path(outside, "modules/02-checking/lessons"),
        path(pack, "modules/02-checking/lessons")
      )

      errors = load_errors(pack)

      assert {"modules/02-checking/lessons", 1, "symbolic links are not allowed in a pack"} in errors

      refute Enum.any?(errors, fn {file, _line, _message} ->
               String.starts_with?(file, "modules/02-checking/lessons/")
             end)
    end

    test "loads a module without objectives.yaml with an empty list of objectives" do
      pack = copy_pack!("minimal")
      remove!(pack, "modules/02-checking/objectives.yaml")

      update_yaml!(pack, "modules/02-checking/items.yaml", fn items ->
        Enum.map(items, &Map.delete(&1, "objectives"))
      end)

      assert {:ok, loaded} = Loader.load(pack)
      refute Map.has_key?(Enum.at(loaded.modules, 1).files, "objectives.yaml")

      assert %{payload: %{"modules" => [_basics, checking]}} = Validator.run(loaded)
      assert checking["objectives"] == []
    end
  end

  describe "load/1 report bounds" do
    test "keeps the first 100 errors of a lesson of many stray lines and closes them" do
      pack = copy_pack!("minimal")
      file = "modules/02-checking/lessons/09-stray.md"
      write!(pack, file, @front <> String.duplicate("x\n", 20_000))

      assert {:error, errors} = Loader.load(pack)
      assert length(errors) == 101

      assert Enum.take(errors, 100) ==
               Enum.map(5..104, &%{file: file, line: &1, message: "text outside a block"})

      assert List.last(errors) == %{
               file: file,
               line: 104,
               message: "and 19,900 further errors in this file",
               omitted: 19_900
             }
    end

    test "shortens the messages that quote a block kind of 1 MiB to 1,000 characters" do
      pack = copy_pack!("minimal")
      file = "modules/02-checking/lessons/09-kind.md"
      write!(pack, file, @front <> ":::" <> String.duplicate("a", 1_048_000) <> "\nText.\n")

      assert {:error, [unclosed, unknown]} = Loader.load(pack)
      assert %{file: ^file, line: 5, message: "unclosed block `aaaa" <> _} = unclosed
      assert %{file: ^file, line: 5, message: "unknown block kind `aaaa" <> _} = unknown

      for %{message: message} <- [unclosed, unknown] do
        assert String.length(message) == 1_000
        assert String.ends_with?(message, "aaa[…]")
      end
    end

    test "writes a control character in a file name as \\xNN" do
      pack = copy_pack!("minimal")
      write!(pack, "modules/02-checking/lessons/09-x\e[31mRED\e[0my.md", @front)

      assert load_errors(pack) == [
               {"modules/02-checking/lessons/09-x\\x1B[31mRED\\x1B[0my.md", 1,
                "lesson key `09-x\\x1B[31mRED\\x1B[0my` does not match the key format"}
             ]
    end
  end

  describe "load/1 pack budget" do
    test "stops at the file whose decoded data takes the pack beyond 32 MiB" do
      assert Loader.max_pack_bytes() == 33_554_432
      pack = copy_pack!("minimal")

      # Each items.yaml has about 40 KB of text and 2,000,000 bytes of strings
      # once its aliases are expanded, within the bound of one text. The
      # decoded data of 16 of them stays below the budget, the 17th crosses it.
      for number <- 3..20, do: big_module!(pack, number)

      assert load_errors(pack) == [
               {"modules/19-big/items.yaml", 1,
                "the pack holds more than 32 MiB of text once decoded"}
             ]
    end

    test "counts the decoded data of lesson files" do
      pack = copy_pack!("minimal")
      body = ":::text{provenance=invented}\n" <> String.duplicate("x", 1_000_000) <> "\n:::\n"

      # 33 lessons with a body of 1,000,000 bytes stay below the budget, the
      # 34th crosses it, and the loader reads no lesson after it.
      for number <- 1..36 do
        name = number |> Integer.to_string() |> String.pad_leading(2, "0")
        write!(pack, "modules/02-checking/lessons/5#{name}-long.md", @front <> body)
      end

      assert load_errors(pack) == [
               {"modules/02-checking/lessons/534-long.md", 1,
                "the pack holds more than 32 MiB of text once decoded"}
             ]
    end
  end

  # A module directory `NN-big` whose items.yaml anchors a string of 40,000
  # characters and repeats it 49 times through aliases.
  defp big_module!(pack, number) do
    dir = "modules/#{number |> Integer.to_string() |> String.pad_leading(2, "0")}-big"
    stem = String.duplicate("x", 40_000)

    write!(pack, dir <> "/module.yaml", "number: #{number}\n")
    write!(pack, dir <> "/items.yaml", ["- &s \"", stem, "\"\n", String.duplicate("- *s\n", 49)])
    write!(pack, dir <> "/lessons/01-a.md", @front)
  end

  describe "load/1 walk limits" do
    test "stops the walk with one error when the pack directory holds more than 20,000 entries" do
      pack = copy_pack!("minimal")
      extra = path(pack, "extra")
      File.mkdir_p!(extra)
      for index <- 1..Loader.max_walk_entries(), do: File.touch!(Path.join(extra, "f#{index}"))

      assert {:error, [%{file: ".", line: 1, message: message}]} = Loader.load(pack)
      assert message == "the pack directory holds more than 20,000 entries"
    end

    test "stops the walk with one error at a directory deeper than 32 levels" do
      pack = copy_pack!("minimal")
      deep = Enum.map_join(1..(Loader.max_walk_depth() + 1), "/", &"d#{&1}")
      File.mkdir_p!(path(pack, deep))

      assert {:error, [%{file: ".", line: 1, message: message}]} = Loader.load(pack)
      assert message == "the pack directory nests deeper than 32 levels"

      pack = copy_pack!("minimal")
      File.mkdir_p!(path(pack, Enum.map_join(1..Loader.max_walk_depth(), "/", &"d#{&1}")))
      assert {:ok, _loaded} = Loader.load(pack)
    end
  end

  describe "pack_meta/1" do
    test "returns key and version of pack.yaml" do
      assert Loader.pack_meta(fixture_path("minimal")) == %{key: "minimal-pack", version: "0.1.0"}
    end

    test "returns key and version when the rest of the pack fails to load" do
      pack = copy_pack!("minimal")
      remove!(pack, "modules")
      assert {:error, _errors} = Loader.load(pack)
      assert Loader.pack_meta(pack) == %{key: "minimal-pack", version: "0.1.0"}
    end

    test "returns nil for values that are not strings and for an unreadable pack.yaml" do
      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", "version: 0.1.0", "version: 1")
      assert Loader.pack_meta(pack) == %{key: "minimal-pack", version: nil}

      write!(pack, "pack.yaml", "key: [unclosed")
      assert Loader.pack_meta(pack) == %{key: nil, version: nil}

      remove!(pack, "pack.yaml")
      File.ln_s!(fixture_path("minimal/pack.yaml"), path(pack, "pack.yaml"))
      assert Loader.pack_meta(pack) == %{key: nil, version: nil}

      assert Loader.pack_meta(pack <> "-missing") == %{key: nil, version: nil}
    end
  end
end

defmodule Espalier.Catalog.LoaderAtomsTest do
  # Synchronous, so that no other test creates atoms while this one counts them.
  use ExUnit.Case, async: false

  import Espalier.PackFixtures

  alias Espalier.Catalog.Pack.{Entries, Loader, Validator}

  @keys 2_000

  # A copy of the minimal pack whose pack.yaml holds @keys members of the form
  # `:<prefix>_key_<n>: :<prefix>_value_<n>`, names that no atom has yet.
  defp probe_pack(prefix) do
    pack = copy_pack!("minimal")
    members = for n <- 1..@keys, do: ":#{prefix}_key_#{n}: :#{prefix}_value_#{n}\n"
    write!(pack, "pack.yaml", [read!(pack, "pack.yaml") | members])
    pack
  end

  defp load_and_validate!(pack) do
    assert {:ok, loaded} = Loader.load(pack)
    {loaded, Validator.run(loaded)}
  end

  test "loading and validating a pack with many new :name keys creates no atom" do
    prefix = "espalier_atom_probe_#{System.unique_integer([:positive])}"

    # The first run loads the code of loader, parser and validator, which
    # creates the atoms of their modules.
    load_and_validate!(probe_pack(prefix <> "_warm"))

    pack = probe_pack(prefix)
    atoms_before = :erlang.system_info(:atom_count)
    {loaded, result} = load_and_validate!(pack)
    atoms_after = :erlang.system_info(:atom_count)

    # A loader that turned the keys and values into atoms would add 2 * @keys.
    assert atoms_after - atoms_before < @keys

    data = loaded.files["pack.yaml"].data
    assert map_size(data) == 6 + @keys

    for n <- 1..@keys do
      assert data[":#{prefix}_key_#{n}"] == ":#{prefix}_value_#{n}"
      assert_raise ArgumentError, fn -> String.to_existing_atom("#{prefix}_key_#{n}") end
      assert_raise ArgumentError, fn -> String.to_existing_atom("#{prefix}_value_#{n}") end
    end

    # The report keeps the first 100 errors of pack.yaml and one closing entry
    # that stands for the others.
    assert Entries.count(result.errors) == @keys
    assert length(result.errors) == Entries.max_per_file() + 1

    assert %{file: "pack.yaml", line: 7, message: "unknown field `:#{prefix}_key_1`"} in result.errors

    assert %{file: "pack.yaml", message: "and 1,900 further errors in this file", omitted: 1_900} =
             List.last(result.errors)
  end
end

defmodule Espalier.Catalog.LoaderBudgetTest do
  # The parse budget lives in the application environment, so these tests
  # run on their own.
  use ExUnit.Case, async: false

  import Espalier.PackFixtures

  alias Espalier.Catalog.Pack.Loader

  setup do
    on_exit(fn -> Application.delete_env(:espalier, Loader) end)
  end

  defp put_budget(budget), do: Application.put_env(:espalier, Loader, parse_budget: budget)

  test "the default budget is 10 seconds and 33,554,432 heap words per file and 60 seconds per pack" do
    assert Loader.parse_budget() == [
             timeout_ms: 10_000,
             max_heap_words: 33_554_432,
             pack_timeout_ms: 60_000
           ]

    put_budget(timeout_ms: 50, unknown: 1)

    assert Loader.parse_budget() == [
             timeout_ms: 50,
             max_heap_words: 33_554_432,
             pack_timeout_ms: 60_000
           ]
  end

  test "a pack whose time budget runs out during the walk gets one error and no file is read" do
    pack = copy_pack!("minimal")
    put_budget(pack_timeout_ms: 0)

    assert Loader.load(pack) ==
             {:error, [%{file: ".", line: 1, message: "the pack takes longer than 0 ms to load"}]}
  end

  test "a pack stops loading once its time budget has passed" do
    pack = copy_pack!("minimal")
    flow = "- [" <> Enum.map_join(1..5_000, ",", fn _ -> "1" end) <> "]\n"

    # Three slow files that each stay within the budget of a file; the pack
    # budget runs out after the first of them.
    for file <- ["glossary.yaml", "segments.yaml", "sources.yaml"], do: write!(pack, file, flow)
    put_budget(timeout_ms: 2_000, pack_timeout_ms: 1)

    {microseconds, {:error, errors}} = :timer.tc(fn -> Loader.load(pack) end)

    assert microseconds < 6_000_000

    assert [%{file: file, line: 1, message: "the pack takes longer than 1 ms to load"}] =
             Enum.filter(errors, &(&1.message =~ "takes longer"))

    assert file in Loader.top_files()
    refute Enum.any?(errors, &(&1.file =~ "modules/"))
  end

  test "the parse process ends when its caller dies" do
    pack = copy_pack!("minimal")
    flow = "- [" <> Enum.map_join(1..20_000, ",", fn _ -> "1" end) <> "]\n"
    write!(pack, "glossary.yaml", flow)
    put_budget(timeout_ms: 60_000)

    before = MapSet.new(Process.list())
    caller = spawn(fn -> Loader.load(pack) end)
    started = wait_for_new_processes(before, 200)
    assert started != []

    ref = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, ^caller, :killed}

    for pid <- started do
      parse_ref = Process.monitor(pid)
      assert_receive {:DOWN, ^parse_ref, :process, ^pid, _reason}, 2_000
    end
  end

  # Returns the processes that appeared since `before` once the caller, the
  # parse process and its watchdog exist, checking every 10 ms.
  defp wait_for_new_processes(before, attempts) do
    new = Enum.reject(Process.list(), &MapSet.member?(before, &1))

    if length(new) >= 3 or attempts == 0 do
      new
    else
      receive do
      after
        10 -> wait_for_new_processes(before, attempts - 1)
      end
    end
  end

  test "a YAML text that takes longer than the budget is rejected" do
    pack = copy_pack!("minimal")
    # yamerl needs time that grows with the square of the length of a flow
    # collection in the position of an implicit key.
    flow = "- [" <> Enum.map_join(1..5_000, ",", fn _ -> "1" end) <> "]\n"
    write!(pack, "modules/01-basics/rules.yaml", flow)
    put_budget(timeout_ms: 50)

    assert {:error, errors} = Loader.load(pack)

    assert %{file: "modules/01-basics/rules.yaml", line: 1, message: message} =
             Enum.find(errors, &(&1.file == "modules/01-basics/rules.yaml"))

    assert message == "the YAML text takes longer than 50 ms to parse"
  end

  test "a YAML text that needs more heap than the budget is rejected" do
    pack = copy_pack!(demo_path())
    put_budget(max_heap_words: 20_000)

    assert {:error, errors} = Loader.load(pack)

    assert %{line: 1, message: "the YAML text needs more memory to parse than the loader allows"} =
             Enum.find(errors, &(&1.file == "modules/01-basics/items.yaml"))
  end

  test "the demo pack loads within the default budget" do
    assert {:ok, _loaded} = Loader.load(demo_path())
  end
end
