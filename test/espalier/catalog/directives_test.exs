defmodule Espalier.Catalog.DirectivesTest do
  use ExUnit.Case, async: true

  alias Espalier.Catalog.Pack.Directives

  defp split(lines, first_line \\ 1), do: lines |> Enum.join("\n") |> Directives.split(first_line)

  defp errors(lines, first_line \\ 1) do
    assert {:error, errors} = split(lines, first_line)
    Enum.map(errors, &{&1.line, &1.message})
  end

  describe "attributes" do
    test "reads quoted and unquoted attributes" do
      assert {:ok, [block]} =
               split([
                 ~s(:::explanation{provenance=sourced cite="vendor-guide#Overview page"}),
                 "Text.",
                 ":::"
               ])

      assert block.kind == "explanation"
      assert block.provenance == "sourced"
      assert block.cite == ["vendor-guide#Overview page"]
      assert block.collapsed_on == []
      assert block.placeholder_key == nil
    end

    test "splits collapsed_on with two paths and cite with two citations at commas" do
      assert {:ok, [block]} =
               split([
                 ~s(:::callout{collapsed_on="short, full" provenance=invented cite="a#1,b#Section 2"}),
                 "Text.",
                 ":::"
               ])

      assert block.collapsed_on == ["short", "full"]
      assert block.cite == ["a#1", "b#Section 2"]
    end

    test "gives a placeholder block the provenance placeholder and its key" do
      assert {:ok, [block]} = split([":::placeholder{key=input-rules}", "Your rules.", ":::"])
      assert block.kind == "placeholder"
      assert block.provenance == "placeholder"
      assert block.placeholder_key == "input-rules"
    end

    test "accepts the explicit provenance placeholder on a placeholder block" do
      assert {:ok, [block]} =
               split([":::placeholder{provenance=placeholder key=input-rules}", "Text.", ":::"])

      assert block.provenance == "placeholder"
    end

    test "splits unquoted collapsed_on and cite values with two entries at commas" do
      assert {:ok, [block]} =
               split([
                 ":::example{provenance=invented collapsed_on=short,full cite=a#1,b#2}",
                 "Text.",
                 ":::"
               ])

      assert block.provenance == "invented"
      assert block.collapsed_on == ["short", "full"]
      assert block.cite == ["a#1", "b#2"]
    end

    test "reads a quoted placeholder key and a quoted provenance like unquoted ones" do
      assert {:ok, [quoted, unquoted]} =
               split([
                 ~s(:::placeholder{key="input-rules"}),
                 "Your rules.",
                 ":::",
                 ~s(:::text{provenance="vendor_statement"}),
                 "Text.",
                 ":::"
               ])

      assert {quoted.provenance, quoted.placeholder_key} == {"placeholder", "input-rules"}
      assert {unquoted.provenance, unquoted.placeholder_key} == {"vendor_statement", nil}
    end

    test "keeps the provenance of a non-placeholder block as written" do
      for provenance <- ~w(invented sourced vendor_statement assumption) do
        assert {:ok, [block]} =
                 split([":::callout{provenance=#{provenance}}", "Text.", ":::"])

        assert block.provenance == provenance
      end
    end

    test "accepts an opening line without attributes on a placeholder block only" do
      assert [{1, "missing attribute `key` on a `placeholder` block"}] =
               errors([":::placeholder", "Text.", ":::"])

      assert [{1, "missing attribute `provenance`"}] = errors([":::text", "Text.", ":::"])
    end
  end

  describe "blocks" do
    test "keeps the file order, the opening line and the body without surrounding blank lines" do
      assert {:ok, [first, second]} =
               split(
                 [
                   "",
                   ":::text{provenance=invented}",
                   "",
                   "First line.",
                   "",
                   "Second line.",
                   "  ",
                   ":::",
                   "",
                   ":::quote{provenance=sourced cite=a#1}",
                   "Quoted.",
                   ":::  "
                 ],
                 5
               )

      assert {first.kind, first.line, first.body} == {"text", 6, "First line.\n\nSecond line."}
      assert {second.kind, second.line, second.body} == {"quote", 14, "Quoted."}
    end

    test "reads Windows line endings" do
      assert {:ok, [block]} =
               Directives.split(":::text{provenance=invented}\r\nText.\r\n:::\r\n", 1)

      assert block.body == "Text."
    end

    test "returns no block for an empty body" do
      assert {:ok, []} = Directives.split("\n\n", 1)
    end
  end

  describe "errors with their line numbers" do
    test "an unknown kind" do
      assert [{3, "unknown block kind `video`"}] =
               errors([
                 ":::text{provenance=invented}",
                 ":::",
                 ":::video{provenance=invented}",
                 "Text.",
                 ":::"
               ])
    end

    test "an unknown attribute" do
      assert [{2, "unknown attribute `colour`"}] =
               errors(["", ":::text{provenance=invented colour=red}", "Text.", ":::"])
    end

    test "the attribute key on a block other than placeholder" do
      assert [{1, "attribute `key` is allowed on `placeholder` blocks only"}] =
               errors([":::text{provenance=invented key=x}", "Text.", ":::"])
    end

    test "a missing provenance" do
      assert [{4, "missing attribute `provenance`"}] =
               errors([
                 ":::text{provenance=invented}",
                 "Text.",
                 ":::",
                 ":::example{cite=a#1}",
                 "Text.",
                 ":::"
               ])
    end

    test "an opening line inside an open block" do
      assert [{3, "a block cannot open inside the block opened at line 1"}] =
               errors([
                 ":::text{provenance=invented}",
                 "Text.",
                 ":::example{provenance=invented}",
                 "More.",
                 ":::"
               ])
    end

    test "an unclosed block" do
      assert [{3, "unclosed block `example`"}] =
               errors([
                 ":::text{provenance=invented}",
                 ":::",
                 ":::example{provenance=invented}",
                 "Text."
               ])
    end

    test "non-blank text outside a block" do
      assert [{13, "text outside a block"}] =
               errors([":::text{provenance=invented}", "Text.", ":::", "Stray."], 10)
    end

    test "a closing line outside a block" do
      assert [{1, "closing line `:::` outside a block"}] = errors([":::"])
    end

    test "a line that starts with ::: and neither opens nor closes a block" do
      assert [{1, "malformed directive line"}] =
               errors([":::text {provenance=invented}", "Text.", ":::"])

      assert [{2, "malformed directive line"}] =
               errors([":::text{provenance=invented}", ":::Note", ":::"])
    end

    test "a placeholder block with another provenance" do
      assert [{1, "a `placeholder` block takes the provenance `placeholder` only"}] =
               errors([":::placeholder{provenance=invented key=input-rules}", "Text.", ":::"])
    end

    test "a placeholder block without key" do
      assert [{1, "missing attribute `key` on a `placeholder` block"}] =
               errors([":::placeholder{provenance=placeholder}", "Text.", ":::"])
    end

    test "a duplicate attribute" do
      assert [{1, "duplicate attribute `cite`"}] =
               errors([":::text{provenance=invented cite=a#1 cite=b#2}", "Text.", ":::"])
    end

    test "a malformed attribute list" do
      assert [{1, "malformed attribute list `{provenance=\"invented}`"}] =
               errors([~s(:::text{provenance="invented}), "Text.", ":::"])

      assert [{1, "malformed attribute list `{provenance invented}`"}] =
               errors([":::text{provenance invented}", "Text.", ":::"])
    end

    test "reports each error of step 7 at its line in the file when the body starts later" do
      assert errors(
               [
                 "Stray.",
                 ":::video{provenance=invented}",
                 "Text.",
                 ":::",
                 ":::text{provenance=invented colour=red}",
                 ":::",
                 ":::example{cite=a#1}",
                 ":::",
                 ":::text{provenance=invented}",
                 ":::example{provenance=invented}",
                 ":::",
                 ":::callout{provenance=invented}",
                 "Text."
               ],
               20
             ) == [
               {20, "text outside a block"},
               {21, "unknown block kind `video`"},
               {24, "unknown attribute `colour`"},
               {26, "missing attribute `provenance`"},
               {29, "a block cannot open inside the block opened at line 28"},
               {31, "unclosed block `callout`"}
             ]
    end

    test "reports an unclosed block at its opening line, not at the end of the body" do
      assert errors([":::text{provenance=invented}", "One.", "", "Two.", ""], 7) == [
               {7, "unclosed block `text`"}
             ]
    end

    test "reports every error of a body, sorted by line" do
      assert [
               {1, "text outside a block"},
               {2, "unknown block kind `video`"},
               {5, "unclosed block `text`"}
             ] =
               errors([
                 "Stray.",
                 ":::video{provenance=invented}",
                 "Text.",
                 ":::",
                 ":::text{provenance=invented}"
               ])
    end
  end

  describe "the error bound" do
    test "keeps the first 100 errors of a body and closes them with the number left out" do
      lines = List.duplicate("Stray.", 350)

      assert {:error, errors} = split(lines, 5)
      assert length(errors) == Directives.max_errors() + 1

      assert Enum.take(errors, 100) ==
               Enum.map(5..104, &%{line: &1, message: "text outside a block"})

      assert List.last(errors) == %{
               line: 104,
               message: "and 250 further errors in this file",
               omitted: 250
             }
    end

    test "adds no closing entry for exactly 100 errors" do
      assert {:error, errors} = split(List.duplicate("Stray.", 100))
      assert length(errors) == 100
      refute Enum.any?(errors, &Map.has_key?(&1, :omitted))
    end

    test "counts an unclosed block after the bound among the errors left out" do
      lines = List.duplicate("Stray.", 100) ++ [":::text{provenance=invented}", "Text."]

      assert {:error, errors} = split(lines)
      assert length(errors) == 101

      assert List.last(errors) == %{
               line: 100,
               message: "and 1 further error in this file",
               omitted: 1
             }
    end

    test "quotes a block kind of 1 MiB in full and leaves the shortening to the report" do
      kind = String.duplicate("a", 1_048_000)

      assert {:error, [unknown, unclosed]} = split([":::" <> kind, "Text."])
      assert unknown == %{line: 1, message: "unknown block kind `#{kind}`"}
      assert unclosed == %{line: 1, message: "unclosed block `#{kind}`"}
    end
  end
end
