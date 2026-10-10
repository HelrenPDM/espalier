defmodule Espalier.Catalog.LineIndexTest do
  use ExUnit.Case, async: true

  alias Espalier.Catalog.Pack.LineIndex
  alias YamlElixir.ParsingError

  @depth_message "the YAML text nests deeper than 32 levels"

  defp flow_anchor_message(line, column),
    do:
      "an anchor on an empty value or a flow collection is not supported at line #{line}, " <>
        "column #{column}; write `~` for an empty value and the collection in block style"

  describe "build/2 depth limit" do
    test "accepts a block nesting of 32 levels and rejects one of 33 levels" do
      assert LineIndex.max_depth() == 32
      assert {:ok, lines} = LineIndex.build(String.duplicate("- ", 32) <> "x\n")
      assert lines[List.duplicate(0, 32)] == 1

      assert LineIndex.build(String.duplicate("- ", 33) <> "x\n") ==
               {:error, [%{line: 1, message: @depth_message}]}
    end

    test "accepts a flow nesting of 32 levels and rejects one of 33 levels" do
      flow = fn levels ->
        String.duplicate("[", levels) <> "x" <> String.duplicate("]", levels)
      end

      assert {:ok, _lines} = LineIndex.build(flow.(32))
      assert LineIndex.build(flow.(33)) == {:error, [%{line: 1, message: @depth_message}]}
    end

    test "rejects a deep block nesting and a deep flow nesting before yamerl builds the nodes" do
      block = String.duplicate("- ", 1_000) <> "x"
      flow = String.duplicate("[", 1_000) <> String.duplicate("]", 1_000)

      assert LineIndex.build(block) == {:error, [%{line: 1, message: @depth_message}]}
      assert LineIndex.build(flow) == {:error, [%{line: 1, message: @depth_message}]}
    end

    test "reports the line of the first node below the limit and the line in the file" do
      text = "a: 1\nb:\n" <> String.duplicate("- ", 40) <> "x\n"

      assert LineIndex.build(text) == {:error, [%{line: 3, message: @depth_message}]}

      assert LineIndex.build(text, first_line: 2) ==
               {:error, [%{line: 4, message: @depth_message}]}
    end

    test "stops a nesting that aliases build from shallow text" do
      # Every level is a block sequence that holds the level before it, so the
      # text nests two levels deep and the expanded data 42 levels deep. An
      # expanded node keeps the position of the anchored node: the first node
      # below the limit is the `x` of `l0` on line 2.
      levels = for level <- 1..40, do: "l#{level}: &l#{level}\n  - *l#{level - 1}\n"
      text = IO.iodata_to_binary(["l0: &l0\n  - x\n" | levels])

      assert LineIndex.build(text) == {:error, [%{line: 2, message: @depth_message}]}
    end
  end

  describe "build/2 anchors" do
    test "rejects an anchor on an empty value, also without an alias" do
      for {yaml, line, column} <- [
            {"a: &x\nb: foo\nc: *x\n", 1, 4},
            {"- &a\n- [1]\n- *a\n", 1, 3},
            {"a:\n  b: &x\nc: *x\n", 2, 6},
            {"a: &x\nb: foo\n", 1, 4},
            {"{a: &x , b: 1, c: *x}", 1, 5},
            {"a: !!null &x\nb: c\n", 1, 11}
          ] do
        assert LineIndex.build(yaml) ==
                 {:error, [%{line: line, message: flow_anchor_message(line, column)}]},
               inspect(yaml)
      end
    end

    test "accepts an anchor on a written null and on an implicit key" do
      assert {:ok, _} = LineIndex.build("a: &x ~\nb: *x\n")
      assert {:ok, _} = LineIndex.build("[&x , 1, *x]")
      assert {:ok, _} = LineIndex.build("- &x a: 1\n  b: 2\n- *x\n")
      assert {:ok, %{["b"] => 2}} = LineIndex.build("a: &x ~\nb: *x\n")
    end

    test "rejects an anchor on a flow sequence, a flow mapping and an empty flow collection" do
      assert LineIndex.build("a: &s [1, 2]\nb: *s\n") ==
               {:error, [%{line: 1, message: flow_anchor_message(1, 4)}]}

      assert LineIndex.build("a: &m {x: 1}\nb: *m\n") ==
               {:error, [%{line: 1, message: flow_anchor_message(1, 4)}]}

      assert LineIndex.build("a: &e []\nb: *e\n") ==
               {:error, [%{line: 1, message: flow_anchor_message(1, 4)}]}

      assert LineIndex.build("a: &e {}\nb: *e\n") ==
               {:error, [%{line: 1, message: flow_anchor_message(1, 4)}]}
    end

    test "rejects an anchor on a flow collection at the root, in a list and inside a flow collection" do
      assert LineIndex.build("&r [1, 2]\n") ==
               {:error, [%{line: 1, message: flow_anchor_message(1, 1)}]}

      assert LineIndex.build("- a\n- &e {x: 1}\n") ==
               {:error, [%{line: 2, message: flow_anchor_message(2, 3)}]}

      assert LineIndex.build("a: [1, &i [2], 3]\n") ==
               {:error, [%{line: 1, message: flow_anchor_message(1, 8)}]}
    end

    test "reports an anchor on a flow collection with the line in the file" do
      assert LineIndex.build("title: x\nrules: &r [1]\n", first_line: 2) ==
               {:error, [%{line: 3, message: flow_anchor_message(3, 8)}]}
    end

    test "accepts anchors on block collections and on scalars" do
      text = "a: &s\n  - [1, 2]\nb: *s\nc: &k key\nd: [&v x, *v, *k]\n"

      assert {:ok, lines} = LineIndex.build(text)
      assert lines[["b"]] == 3

      assert YamlElixir.read_from_string(text) ==
               {:ok,
                %{
                  "a" => [[1, 2]],
                  "b" => [[1, 2]],
                  "c" => "key",
                  "d" => ["x", "x", "key"]
                }}
    end
  end

  describe "build/2 control characters" do
    test "rejects a string value that holds a control character from an escape" do
      assert LineIndex.build("a: 1\nlabel: \"x\\0y\"\n") ==
               {:error,
                [%{line: 2, message: "control character U+0000 is not allowed in a string"}]}

      yaml = ~S"""
      - "x\x01y"
      - 'ok'
      - "z\x7F"
      """

      assert LineIndex.build(yaml) ==
               {:error,
                [
                  %{line: 1, message: "control character U+0001 is not allowed in a string"},
                  %{line: 3, message: "control character U+007F is not allowed in a string"}
                ]}
    end

    test "rejects a map key that holds a control character from an escape" do
      assert LineIndex.build("a: 1\n\"k\\e\": v\n", first_line: 3) ==
               {:error,
                [%{line: 4, message: "control character U+001B is not allowed in a map key"}]}
    end

    test "accepts the escapes of tab, line feed and carriage return" do
      assert {:ok, _lines} = LineIndex.build("a: \"x\\ty\\nz\\r\"\n")
    end

    test "reports a raw control character that yamerl cannot parse with its line and column" do
      text = "a: 1\nb: 2\nc: 3\nd: 4\ne: x" <> <<0>> <> "y\n"

      assert LineIndex.build(text) ==
               {:error,
                [
                  %{
                    line: 5,
                    message:
                      "YAML syntax error: control character U+0000 is not allowed at line 5, column 5"
                  }
                ]}

      assert LineIndex.build("title: x\nb: ä\u0001\n", first_line: 2) ==
               {:error,
                [
                  %{
                    line: 3,
                    message:
                      "YAML syntax error: control character U+0001 is not allowed at line 3, column 5"
                  }
                ]}
    end
  end

  describe "build/2 escapes that name no Unicode character" do
    test "rejects a lone surrogate and a code point above U+10FFFF in values and keys" do
      yaml = ~S"""
      a: "x\uDC00y"
      b: "\U00110000"
      "\uDFFF": v
      """

      assert LineIndex.build(yaml, first_line: 2) ==
               {:error,
                [
                  %{line: 2, message: "a string holds an escape that names no Unicode character"},
                  %{line: 3, message: "a string holds an escape that names no Unicode character"},
                  %{line: 4, message: "a map key holds an escape that names no Unicode character"}
                ]}
    end
  end

  describe "build/2 string budget" do
    test "stops aliases that multiply a long string beyond 2 MiB" do
      long = String.duplicate("x", 100_000)
      aliases = Enum.map_join(1..30, "", &"k#{&1}: *s\n")
      yaml = "pad: &s \"#{long}\"\n" <> aliases

      assert byte_size(yaml) < 120_000

      assert LineIndex.build(yaml) ==
               {:error,
                [%{line: 1, message: "the strings of the YAML text hold more than 2 MiB"}]}
    end

    test "counts the map keys that an alias repeats" do
      key = String.duplicate("k", 100_000)
      yaml = "base: &m\n  #{key}: 1\n" <> Enum.map_join(1..25, "", &"c#{&1}: *m\n")

      assert {:error, [%{message: "the strings of the YAML text hold more than 2 MiB"}]} =
               LineIndex.build(yaml)
    end

    test "accepts a text without aliases whose strings fill 1 MiB" do
      yaml = "a: \"" <> String.duplicate("y", 1_048_000) <> "\"\n"
      assert {:ok, %{["a"] => 1}} = LineIndex.build(yaml)
      assert LineIndex.max_string_bytes() == 2 * 1_048_576
    end
  end

  describe "control_character/1" do
    test "returns the first control character with its line and its column in code points" do
      assert LineIndex.control_character("a: 1\r\nb: ää\u0001\u0002\n") ==
               %{character: "U+0001", line: 2, column: 6}

      assert LineIndex.control_character(<<0, "x">>) == %{character: "U+0000", line: 1, column: 1}

      assert LineIndex.control_character("x\n\n  \u007F") == %{
               character: "U+007F",
               line: 3,
               column: 3
             }
    end

    test "finds every control character except tab, line feed and carriage return" do
      for code_point <- Enum.to_list(0x00..0x1F) ++ [0x7F] do
        found = LineIndex.control_character(<<"ab", code_point>>)

        if code_point in [?\t, ?\n, ?\r] do
          assert found == nil
        else
          assert %{line: 1, column: 3} = found

          assert found.character ==
                   "U+" <> String.pad_leading(Integer.to_string(code_point, 16), 4, "0")
        end
      end
    end

    test "returns nil for text without a control character" do
      assert LineIndex.control_character("a: \u0085\u00A0\u2028 x\t\r\n") == nil
    end
  end

  describe "syntax_error/2" do
    test "names no location when the parser gives no line" do
      assert LineIndex.syntax_error(%ParsingError{message: "malformed YAML"}, 2) ==
               %{line: 3, message: "YAML syntax error: malformed YAML"}

      assert LineIndex.syntax_error(%ParsingError{message: "bad", line: 4, column: 7}, 2) ==
               %{line: 6, message: "YAML syntax error: bad at line 6, column 7"}
    end
  end
end
