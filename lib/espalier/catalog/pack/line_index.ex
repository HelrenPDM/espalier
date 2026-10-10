defmodule Espalier.Catalog.Pack.LineIndex do
  @moduledoc """
  The line index of a YAML text of a content pack (task 0008, step 6).

  `build/2` parses the raw text with `yamerl` (`detailed_constr: true`,
  `str_node_as_binary: true`, `keep_duplicate_keys: true`) and maps the path
  of every node to its line. A path is the list of map keys (strings) and
  list indexes (0-based integers) from the document root, for example
  `[2, "options", 0]`. A map member maps to the line of its key node, a list
  element to the line of the element node, and the root `[]` to the line of
  the root node. A document that is empty or holds only `null` has no entry
  for `[]`. A node that an alias expands keeps the position of the anchored
  node, so its line is a line of the anchored node.

  The index is the first of the two passes over a YAML text, and it reads the
  text for line numbers and for these structural checks only:

    * before yamerl constructs the nodes, a pass over the tokens of the
      parser stops with an error at the first node that lies deeper than 32
      levels (the root lies at level 0), and at an anchor on a flow
      collection (`&a [1, 2]` or `&a {x: 1}`) or on an empty value
      (`a: &x` followed by the next key), which yamerl 0.10.0 attaches to
      the next node instead of the anchored one, even when no alias uses
      the anchor; `a: &x ~` anchors a null correctly;
    * the walk over the nodes stops with an error after 50,000 nodes, which
      bounds the expansion of YAML aliases before any other code walks the
      data, at a node deeper than 32 levels, which an alias can build from
      shallow text, and once its strings (map keys and values) hold more
      than 2 MiB, so that an alias cannot multiply a long string either; a
      text without aliases of at most 1 MiB never reaches that bound,
      because no YAML escape decodes to more than twice its length. The
      bound holds for one text; `Espalier.Catalog.Pack.Loader` bounds the
      decoded data of the whole pack (`max_pack_bytes/0` there), so that
      aliases spread over many texts stay bounded too;
    * a duplicate map key, a map key that is not a string, a merge key `<<`,
      a value of a type outside the YAML core schema (for example `!!binary`),
      a second document in the text and a string (map key or value) that
      holds a control character are errors. The string check covers the
      control characters that a YAML escape such as `"\\0"` or `"\\x01"`
      produces. An escape that names no Unicode scalar value (a lone
      surrogate such as `"\\uDC00"`, or `"\\U00110000"`) is an error too.

  The control characters are U+0000 to U+0008, U+000B, U+000C, U+000E to
  U+001F and U+007F: every C0 control character except tab, line feed and
  carriage return, and DEL. `control_character/1` finds the first of them
  in a raw text.

  The walk creates no atoms.
  """

  alias YamlElixir.ParsingError

  @max_nodes 50_000
  @max_depth 32
  @max_string_bytes 2 * 1_048_576

  @scalars [:yamerl_str, :yamerl_null, :yamerl_bool, :yamerl_int, :yamerl_float]

  # Each control character is a single byte in UTF-8, and no byte of a
  # multi-byte sequence lies in this range, so a byte search finds them.
  @control_bytes Enum.to_list(0x00..0x08) ++
                   [0x0B, 0x0C] ++ Enum.to_list(0x0E..0x1F) ++ [0x7F]
  @control_patterns Enum.map(@control_bytes, &<<&1>>)

  @typedoc "The path of a node: map keys and list indexes from the root."
  @type path :: [String.t() | non_neg_integer()]

  @typedoc "Maps the path of every node to its line."
  @type t :: %{optional(path()) => pos_integer()}

  @typedoc "An error of the index with its line."
  @type error :: %{line: pos_integer(), message: String.t()}

  @typedoc "A control character with its 1-based line and column (in code points)."
  @type control :: %{character: String.t(), line: pos_integer(), column: pos_integer()}

  @doc "The maximum number of YAML nodes in one text."
  @spec max_nodes() :: pos_integer()
  def max_nodes, do: @max_nodes

  @doc "The maximum level of a YAML node in one text; the root lies at level 0."
  @spec max_depth() :: pos_integer()
  def max_depth, do: @max_depth

  @doc "The maximum number of bytes of all strings (map keys and values) of one text."
  @spec max_string_bytes() :: pos_integer()
  def max_string_bytes, do: @max_string_bytes

  @doc """
  Builds the line index of `text`.

  The option `first_line` gives the line number of the first line of `text`
  in its file (default 1), so that the index of a front matter holds line
  numbers of the Markdown file.
  """
  @spec build(String.t(), keyword()) :: {:ok, t()} | {:error, [error()]}
  def build(text, opts \\ []) when is_binary(text) do
    offset = Keyword.get(opts, :first_line, 1) - 1

    case parse(text) do
      {:ok, documents} -> index_documents(documents, offset)
      {:error, %ParsingError{} = error} -> {:error, [syntax_error(error, offset)]}
      {:error, token_error} -> {:error, [token_error(token_error, offset)]}
    end
  end

  @doc """
  Returns the line of the longest prefix of `path` that has an entry in
  `lines`, or 1 when no prefix has one. A missing field at `[3, "core"]`
  therefore reports the line of the entry `[3]`.
  """
  @spec line(t(), path()) :: pos_integer()
  def line(lines, path) when is_map(lines) and is_list(path) do
    case Map.fetch(lines, path) do
      {:ok, line} -> line
      :error when path == [] -> 1
      :error -> line(lines, Enum.drop(path, -1))
    end
  end

  @doc """
  Formats a YAML syntax error as an index error: the line, and a message that
  names the line and the column. `offset` is the number of file lines before
  the parsed text. An error without a line gets the first line of the text,
  and its message names no location.
  """
  @spec syntax_error(ParsingError.t(), non_neg_integer()) :: error()
  def syntax_error(%ParsingError{} = error, offset \\ 0) do
    {line, location} =
      cond do
        not (is_integer(error.line) and error.line > 0) ->
          {1 + offset, ""}

        is_integer(error.column) ->
          {error.line + offset, " at line #{error.line + offset}, column #{error.column}"}

        true ->
          {error.line + offset, " at line #{error.line + offset}"}
      end

    %{line: line, message: "YAML syntax error: " <> error.message <> location}
  end

  @doc """
  Returns the first control character of `text` with its line and column, or
  `nil` when the text holds none. The character is named as `U+XXXX`, lines
  are counted at line feeds, and the column counts code points from 1.
  """
  @spec control_character(binary()) :: control() | nil
  def control_character(text) when is_binary(text) do
    case :binary.match(text, @control_patterns) do
      :nomatch ->
        nil

      {position, 1} ->
        before = binary_part(text, 0, position)
        newlines = :binary.matches(before, "\n")

        line_start =
          case List.last(newlines) do
            nil -> 0
            {newline, 1} -> newline + 1
          end

        column =
          before
          |> binary_part(line_start, position - line_start)
          |> String.codepoints()
          |> length()

        %{
          character: character_name(:binary.at(text, position)),
          line: length(newlines) + 1,
          column: column + 1
        }
    end
  end

  defp character_name(code_point),
    do: "U+" <> (code_point |> Integer.to_string(16) |> String.pad_leading(4, "0"))

  defp parse(text) do
    {:ok, _} = Application.ensure_all_started(:yamerl)

    # The token pass runs first, so that yamerl constructs no node of a text
    # that nests too deep or holds a misplaced anchor.
    :yamerl_parser.string(text, token_fun: token_fun(%{open: 0, last: {0, 0}}))

    {:ok,
     :yamerl_constr.string(text,
       detailed_constr: true,
       str_node_as_binary: true,
       keep_duplicate_keys: true
     )}
  catch
    {:yamerl_exception, [first | _] = errors} ->
      error =
        Enum.find(errors, first, &match?({:yamerl_parsing_error, :error, _, _, _, _, _, _}, &1))

      {:error, ParsingError.from_yamerl(error)}

    {:depth_limit, _line} = token_error ->
      {:error, token_error}

    {:misplaced_anchor, _line, _column} = token_error ->
      {:error, token_error}

    :error, _reason ->
      # yamerl 0.10.0 fails with a function clause error on a control
      # character in a scalar, so the error names the character instead.
      case control_character(text) do
        %{character: character, line: line, column: column} ->
          {:error,
           %ParsingError{
             message: "control character #{character} is not allowed",
             line: line,
             column: column
           }}

        nil ->
          {:error, %ParsingError{message: "malformed YAML"}}
      end
  end

  defp token_error({:depth_limit, line}, offset),
    do: %{line: line + offset, message: depth_message()}

  defp token_error({:misplaced_anchor, line, column}, offset) do
    %{
      line: line + offset,
      message:
        "an anchor on an empty value or a flow collection is not supported at line " <>
          "#{line + offset}, column #{column}; write `~` for an empty value and the " <>
          "collection in block style"
    }
  end

  defp depth_message, do: "the YAML text nests deeper than #{@max_depth} levels"

  # The token pass. `open` counts the open collections, which is the level of
  # the next node. `last` is the position of the last token other than an
  # anchor. yamerl emits the anchor of a flow collection after the start of
  # the collection and its first entry, and the anchor of an empty value after
  # the tokens that follow it, and then attaches it to the wrong node. An
  # anchor in its place comes after the token before it, so an anchor whose
  # position lies before the last token is misplaced.
  defp token_fun(state), do: fn token -> {:ok, token_fun(check_token(token, state))} end

  defp check_token({:yamerl_collection_start, line, column, _tag, _style, _kind}, state) do
    check_depth(state, line)
    %{state | open: state.open + 1, last: {line, column}}
  end

  defp check_token({:yamerl_collection_end, line, column, _style, _kind}, state),
    do: %{state | open: state.open - 1, last: {line, column}}

  defp check_token({:yamerl_anchor, line, column, _name}, state) do
    if {line, column} < state.last, do: throw({:misplaced_anchor, line, column})
    state
  end

  defp check_token(token, state) when elem(token, 0) in [:yamerl_scalar, :yamerl_alias] do
    check_depth(state, elem(token, 1))
    %{state | last: {elem(token, 1), elem(token, 2)}}
  end

  defp check_token(token, state) when is_integer(elem(token, 1)) and is_integer(elem(token, 2)),
    do: %{state | last: {elem(token, 1), elem(token, 2)}}

  defp check_token(_token, state), do: state

  defp check_depth(%{open: open}, line) when open > @max_depth, do: throw({:depth_limit, line})
  defp check_depth(_state, _line), do: :ok

  defp index_documents([], _offset), do: {:ok, %{}}

  defp index_documents([{:yamerl_doc, root}], offset) do
    walk_root(root, offset)
  end

  defp index_documents([_first, {:yamerl_doc, second} | _], offset) do
    {:error,
     [%{line: node_line(second) + offset, message: "a file holds one YAML document only"}]}
  end

  defp walk_root({:yamerl_null, _, _, _}, _offset), do: {:ok, %{}}

  defp walk_root(root, offset) do
    acc = %{
      lines: %{[] => node_line(root) + offset},
      count: 0,
      bytes: 0,
      errors: [],
      offset: offset
    }

    case walk(root, [], 0, acc) do
      %{errors: []} = acc -> {:ok, acc.lines}
      %{errors: errors} -> {:error, errors |> Enum.uniq() |> Enum.sort_by(& &1.line)}
    end
  catch
    {:node_limit, line} ->
      {:error, [%{line: line, message: "the YAML text holds more than 50,000 nodes"}]}

    {:depth_limit, line} ->
      {:error, [%{line: line, message: depth_message()}]}

    {:byte_limit, line} ->
      {:error, [%{line: line, message: "the strings of the YAML text hold more than 2 MiB"}]}
  end

  # `depth` is the level of `node`; the root lies at level 0.
  defp walk(node, path, depth, acc) do
    if depth > @max_depth, do: throw({:depth_limit, node_line(node) + acc.offset})

    acc = count(acc, node)

    case node do
      {:yamerl_seq, _mod, _tag, _pres, entries, _count} -> walk_seq(entries, path, depth + 1, acc)
      {:yamerl_map, _mod, _tag, _pres, pairs} -> walk_map(pairs, path, depth + 1, acc)
      {:yamerl_str, _mod, _tag, _pres, text} when is_binary(text) -> walk_string(acc, node, text)
      {:yamerl_str, _mod, _tag, _pres, _invalid} -> invalid_escape(acc, node, "a string")
      _scalar when elem(node, 0) in @scalars -> acc
      _other -> add_error(acc, node_line(node), "unsupported YAML value type")
    end
  end

  defp walk_seq(entries, path, depth, acc) do
    entries
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {entry, index}, acc ->
      entry_path = path ++ [index]
      acc = put_line(acc, entry_path, node_line(entry))
      walk(entry, entry_path, depth, acc)
    end)
  end

  defp walk_map(pairs, path, depth, acc) do
    {acc, _seen} =
      Enum.reduce(pairs, {acc, MapSet.new()}, fn {key, value}, {acc, seen} ->
        acc = count(acc, key)
        walk_pair(key, value, {path, depth}, acc, seen)
      end)

    acc
  end

  defp walk_pair({:yamerl_str, _mod, _tag, _pres, "<<"} = key, _value, _at, acc, seen) do
    {add_error(acc, node_line(key), "merge keys `<<` are not supported"), seen}
  end

  # yamerl stores the error tuple of :unicode.characters_to_binary/1 for an
  # escape that names no Unicode scalar value.
  defp walk_pair({:yamerl_str, _mod, _tag, _pres, name} = key, _value, _at, acc, seen)
       when not is_binary(name) do
    {invalid_escape(acc, key, "a map key"), seen}
  end

  defp walk_pair({:yamerl_str, _mod, _tag, _pres, name} = key, value, {path, depth}, acc, seen) do
    acc = count_bytes(acc, key, name)

    cond do
      control?(name) ->
        {check_string(acc, key, name, "a map key"), seen}

      MapSet.member?(seen, name) ->
        {add_error(acc, node_line(key), "duplicate key `#{name}`"), seen}

      true ->
        member_path = path ++ [name]
        acc = put_line(acc, member_path, node_line(key))
        {walk(value, member_path, depth, acc), MapSet.put(seen, name)}
    end
  end

  defp walk_pair(key, _value, _at, acc, seen) do
    {add_error(acc, node_line(key), "a map key must be a string"), seen}
  end

  defp control?(text), do: :binary.match(text, @control_patterns) != :nomatch

  defp walk_string(acc, node, text) do
    acc
    |> count_bytes(node, text)
    |> check_string(node, text, "a string")
  end

  defp invalid_escape(acc, node, what),
    do: add_error(acc, node_line(node), "#{what} holds an escape that names no Unicode character")

  defp count_bytes(%{bytes: bytes} = acc, node, text) do
    bytes = bytes + byte_size(text)
    if bytes > @max_string_bytes, do: throw({:byte_limit, node_line(node) + acc.offset})
    %{acc | bytes: bytes}
  end

  defp check_string(acc, node, text, what) do
    case :binary.match(text, @control_patterns) do
      :nomatch ->
        acc

      {position, 1} ->
        character = character_name(:binary.at(text, position))

        add_error(
          acc,
          node_line(node),
          "control character #{character} is not allowed in #{what}"
        )
    end
  end

  defp count(%{count: count} = acc, node) do
    if count >= @max_nodes, do: throw({:node_limit, node_line(node) + acc.offset})
    %{acc | count: count + 1}
  end

  defp put_line(acc, path, line), do: %{acc | lines: Map.put(acc.lines, path, line + acc.offset)}

  defp add_error(acc, line, message),
    do: %{acc | errors: [%{line: line + acc.offset, message: message} | acc.errors]}

  defp node_line(node) when is_tuple(node) and tuple_size(node) >= 4 do
    case node |> elem(3) |> pres_line() do
      line when is_integer(line) and line > 0 -> line
      _ -> 1
    end
  end

  defp node_line(_node), do: 1

  defp pres_line(pres) when is_list(pres), do: Keyword.get(pres, :line)
  defp pres_line(_pres), do: nil
end
