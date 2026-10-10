defmodule Espalier.Catalog.ReportTest do
  use ExUnit.Case, async: true

  alias Espalier.Catalog.Pack.{Entries, Report}

  # Every C0 control character, DEL, the C1 control characters and the line
  # and paragraph separators.
  @control_regex ~r/[\x{0}-\x{1f}\x{7f}-\x{9f}\x{2028}\x{2029}]/u

  # `count` entries of `file` at the lines 1 to `count`, with atom keys or
  # with string keys.
  defp entries(file, count, keys \\ :atom) do
    for n <- 1..count,
        do:
          keyed(
            %{file: file, line: n, message: "message #{String.pad_leading("#{n}", 5, "0")}"},
            keys
          )
  end

  defp keyed(entry, :atom), do: entry

  defp keyed(entry, :string),
    do: Map.new(entry, fn {key, value} -> {Atom.to_string(key), value} end)

  defp one_line?(text), do: not Regex.match?(@control_regex, text)

  describe "Entries.limit/2" do
    test "keeps the first 100 entries of each file and closes the file at the line of its last kept entry" do
      list = entries("a.yaml", 150) ++ entries("b.yaml", 3) ++ entries("c.yaml", 101)
      limited = Entries.limit(list)

      assert Enum.take(limited, 100) == Enum.take(list, 100)

      assert Enum.at(limited, 100) == %{
               file: "a.yaml",
               line: 100,
               message: "and 50 further errors in this file",
               omitted: 50
             }

      assert Enum.slice(limited, 101, 3) == entries("b.yaml", 3)
      assert Enum.slice(limited, 104, 100) == entries("c.yaml", 100)

      assert List.last(limited) == %{
               file: "c.yaml",
               line: 100,
               message: "and 1 further error in this file",
               omitted: 1
             }

      assert length(limited) == 101 + 3 + 101
      assert Entries.count(limited) == length(list)
    end

    test "names warnings, writes large numbers with commas and keeps string keys" do
      limited = Entries.limit(entries("a.yaml", 2_441, :string), :warning)

      assert List.last(limited) == %{
               "file" => "a.yaml",
               "line" => 100,
               "message" => "and 2,341 further warnings in this file",
               "omitted" => 2_341
             }

      assert [%{message: "and 1 further warning in this file"}] =
               Enum.take(Entries.limit(entries("a.yaml", 101), :warning), -1)
    end

    test "leaves a list within the bounds unchanged" do
      list = entries("a.yaml", 100) ++ entries("b.yaml", 1)
      assert Entries.limit(list) == list
      assert Entries.limit([]) == []
    end

    test "folds closing entries of its input into one, so that a second pass changes nothing" do
      list = entries("a.yaml", 230)
      once = Entries.limit(list)
      assert Entries.limit(once) == once

      # A closing entry of the directive splitter, sorted among the entries.
      directive = Map.put(Entries.closing(40, 7), :file, "a.yaml")
      limited = Entries.limit(Enum.take(list, 105) ++ [directive])

      assert length(limited) == 101

      assert List.last(limited) == %{
               file: "a.yaml",
               line: 100,
               message: "and 12 further errors in this file",
               omitted: 12
             }
    end

    test "shortens long messages and file names to 1,000 characters and keeps the other members" do
      long = String.duplicate("é", 5_000)

      entry = %{
        file: "modules/01-basics/" <> long,
        line: 4,
        message: "unknown block kind `#{long}`",
        check: 2,
        module: 1,
        key: "m1-exam-one"
      }

      assert [limited] = Entries.limit([entry], :warning)
      assert %{check: 2, module: 1, key: "m1-exam-one", line: 4} = limited

      for member <- [:file, :message] do
        assert String.length(limited[member]) == Entries.max_chars()
        assert String.ends_with?(limited[member], "é[…]")
        assert String.starts_with?(entry[member], String.trim_trailing(limited[member], "[…]"))
      end

      exact = String.duplicate("x", 1_000)
      assert [%{message: ^exact}] = Entries.limit([%{file: "a", line: 1, message: exact}])
    end

    test "writes every control character, U+2028, U+2029 and a stray byte as \\xNN" do
      raw =
        "a\nb\rc\td\e[31me\0f\x7Fg\u0085h" <>
          <<0x2028::utf8>> <> "i" <> <<0x2029::utf8>> <> "j" <> <<0xFF>> <> "k"

      assert [limited] = Entries.limit([%{file: "x\ny.md", line: 1, message: raw}])

      assert limited.message ==
               "a\\x0Ab\\x0Dc\\x09d\\x1B[31me\\x00f\\x7Fg\\xC2\\x85h\\xE2\\x80\\xA8i\\xE2\\x80\\xA9j\\xFFk"

      assert limited.file == "x\\x0Ay.md"
      assert String.valid?(limited.message)
      assert one_line?(limited.message) and one_line?(limited.file)
    end

    test "never cuts an escape when it shortens a text" do
      text = String.duplicate("x", 995) <> String.duplicate("\n", 10)
      cleaned = Entries.clean(text)

      assert cleaned == String.duplicate("x", 995) <> "[…]"
      assert String.length(Entries.clean(String.duplicate("\n", 5_000))) <= 1_000
      assert Entries.clean(String.duplicate("\n", 5_000)) =~ ~r/\A(\\x0A)+\[…\]\z/
    end
  end

  describe "Entries.cap/2 and Entries.count/1" do
    test "keeps 1,000 entries and closes the list with the number left out at file . and line 1" do
      list = Enum.flat_map(1..30, &Entries.limit(entries("f#{&1}.yaml", 120)))
      assert Entries.count(list) == 3_600

      capped = Entries.cap(list)
      assert length(capped) == Entries.max_entries() + 1
      assert Enum.take(capped, 1_000) == Enum.take(list, 1_000)
      assert %{file: ".", line: 1, message: message, omitted: omitted} = List.last(capped)
      assert message == "and #{Entries.number(omitted)} further errors"
      assert Entries.count(capped) == 3_600
      assert Entries.cap(capped) == capped
    end

    test "leaves a list of at most 1,000 entries unchanged and names warnings" do
      list = entries("a.yaml", 1_000)
      assert Entries.cap(list) == list

      assert %{message: "and 1 further warning", omitted: 1} =
               List.last(Entries.cap(entries("a.yaml", 1_001), :warning))
    end

    test "number/1 groups digits by three" do
      assert Enum.map([0, 7, 999, 1_000, 2_341, 1_234_567], &Entries.number/1) ==
               ["0", "7", "999", "1,000", "2,341", "1,234,567"]
    end
  end

  describe "Report" do
    test "format/2 prints every entry on one line, also one that did not pass the loader" do
      entry = %{
        "file" => "modules/01-basics/lessons/09-x\e[31mRED\e[0my.md",
        "line" => 1,
        "message" => "x`\nmodules/01-basics/items.yaml:3: warning: checked"
      }

      for kind <- [:error, :warning] do
        line = Report.format(entry, kind)
        assert one_line?(line)
        assert line =~ "09-x\\x1B[31mRED\\x1B[0my.md:1: "
        assert line =~ "x`\\x0Amodules/01-basics/items.yaml:3: warning: checked"
      end
    end

    test "stored/2 bounds the number of entries and the length of every member" do
      errors =
        Enum.flat_map(1..30, fn n ->
          for line <- 1..120,
              do: %{file: "f#{n}.yaml", line: line, message: String.duplicate("m", 3_000)}
        end)

      warnings = entries("w.yaml", 150)
      report = Report.stored(errors, warnings)

      assert length(report["errors"]) == 1_001
      assert Entries.count(report["errors"]) == 3_600
      assert %{"file" => ".", "line" => 1} = List.last(report["errors"])
      assert length(report["warnings"]) == 101
      assert Entries.count(report["warnings"]) == 150

      for entry <- report["errors"] ++ report["warnings"] do
        assert Enum.all?(Map.keys(entry), &is_binary/1)
        assert String.length(entry["message"]) <= 1_000
      end

      assert byte_size(JSON.encode!(report)) < 2_000_000
    end
  end
end
