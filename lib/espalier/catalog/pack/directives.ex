defmodule Espalier.Catalog.Pack.Directives do
  @moduledoc """
  Splits the body of a lesson file into blocks (task 0008, step 7).

  A line matching `^:::([a-z_]+)(\\{.*\\})?\\s*$` opens a block, and a line
  matching `^:::\\s*$` closes it. The lines between become the `body` of the
  block, without leading and trailing blank lines, and the order of the
  blocks becomes their position.

  Attributes are `key=value` or `key="value with spaces"`, separated by
  spaces:

  | Attribute | Kinds | Value |
  |---|---|---|
  | `provenance` | every kind | required, except on `placeholder`, whose provenance is `placeholder` |
  | `collapsed_on` | every kind | paths, separated by commas |
  | `cite` | every kind | `source-key#locator`, several separated by commas |
  | `key` | `placeholder` | becomes `placeholder_key` and is required there |
  | `src`, `alt`, `decorative`, `size` | `figure` | the image and its text alternative (task 0018) |
  | `src`, `embed`, `title`, `poster`, `captions` | `video` | the video, its title, poster and captions (task 0018) |

  The attributes of a `figure` or a `video` block other than `provenance`,
  `collapsed_on` and `cite` go into `media`, a map from the attribute name
  to its raw value; `media` is `nil` for the other kinds. A `figure` or a
  `video` block may have an empty body, the caption or the transcript.

  Each of the following is an error with its line number: an unknown kind,
  an unknown attribute, an attribute on a kind that does not admit it
  (`attribute <name> is allowed on <kinds> blocks only`), a duplicate
  attribute, a malformed attribute list, a missing `provenance`, a
  `placeholder` block with another provenance or without `key`, an opening
  line inside an open block, a line that starts with `:::` but neither
  opens nor closes a block, an unclosed block, and non-blank text outside a
  block.

  The splitter keeps the first 100 errors of a body and counts the further
  ones, so that a body of many faulty lines holds no more memory than one of
  100. When errors were left out, the sorted errors end with one closing
  entry of `Espalier.Catalog.Pack.Entries.closing/3` at the line of the last
  kept error, for example `and 2,341 further errors in this file`, whose
  `omitted` gives their number.

  The splitter checks the syntax only. The validator checks the values of
  the attributes (`Espalier.Catalog.Pack.Schema.Block`).

  `rename_media/2` rewrites the media paths in the opening lines of a
  lesson file, which the pack workbench needs when it stores the media of
  an archive under their delivery paths (task 0018, step 16).
  """

  alias Espalier.Catalog.Pack.Entries

  @kinds ~w(text explanation example case_comparison quote callout placeholder figure video)

  # The attributes of every kind, and those that a kind admits on top.
  @common ~w(provenance collapsed_on cite)
  @own %{
    "placeholder" => ~w(key),
    "figure" => ~w(src alt decorative size),
    "video" => ~w(src embed title poster captions)
  }
  @attributes @common ++ (@own |> Map.values() |> List.flatten() |> Enum.uniq())
  @media_kinds ~w(figure video)

  # The attributes whose values name media paths, for rename_media/2.
  @path_attributes ~w(src poster)

  @open_regex ~r/^:::([a-z_]+)(\{.*\})?\s*$/
  @close_regex ~r/^:::\s*$/
  @attribute_regex ~r/\A([a-z_]+)=(?:"([^"]*)"|([^\s"]+))(?:\s+|\z)/

  @max_errors 100

  @typedoc "A block of a lesson body."
  @type block :: %{
          kind: String.t(),
          provenance: String.t(),
          collapsed_on: [String.t()],
          cite: [String.t()],
          placeholder_key: String.t() | nil,
          media: %{String.t() => String.t()} | nil,
          body: String.t(),
          line: pos_integer()
        }

  @typedoc """
  An error of the splitter with its line. The closing entry also holds
  `omitted`, the number of errors left out.
  """
  @type error :: %{
          required(:line) => pos_integer(),
          required(:message) => String.t(),
          optional(:omitted) => pos_integer()
        }

  @doc "The nine block kinds."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "The attributes that a block of `kind` admits."
  @spec attributes(String.t()) :: [String.t()]
  def attributes(kind), do: @common ++ Map.get(@own, kind, [])

  @doc "The largest number of errors that `split/2` keeps for one body."
  @spec max_errors() :: pos_integer()
  def max_errors, do: @max_errors

  @doc """
  Splits `markdown` into blocks. `first_line` is the line number of the first
  line of `markdown` in its file; every block and every error carries the
  line number in the file.
  """
  @spec split(String.t(), pos_integer()) :: {:ok, [block()]} | {:error, [error()]}
  def split(markdown, first_line) when is_binary(markdown) and is_integer(first_line) do
    state =
      markdown
      |> String.split(["\r\n", "\n"])
      |> Enum.with_index(first_line)
      |> Enum.reduce(%{open: nil, blocks: [], errors: [], error_count: 0}, &step/2)
      |> close_at_end()

    case state.errors do
      [] -> {:ok, Enum.reverse(state.blocks)}
      errors -> {:error, errors |> Enum.reverse() |> Enum.sort_by(& &1.line) |> close(state)}
    end
  end

  @doc """
  Rewrites the media paths in the opening lines of `text`, a lesson file or
  a lesson body, with `mapping` from old to new paths: the values of `src`
  and `poster`, and the path of each entry `<path>:<language>` of
  `captions`. Only lines that match the opening pattern change; every other
  line, every other attribute and the quoting and spacing of a changed line
  stay as they are. An opening line whose attribute list is malformed stays
  unchanged, and so does a value that a new path cannot replace without a
  double quote inside it.
  """
  @spec rename_media(String.t(), %{String.t() => String.t()}) :: String.t()
  def rename_media(text, mapping) when is_binary(text) and is_map(mapping) do
    if map_size(mapping) == 0 do
      text
    else
      text
      |> String.split(~r/\r?\n/, include_captures: true)
      |> Enum.map_join(&rename_line(&1, mapping))
    end
  end

  defp rename_line(line, mapping) do
    with [_line, _kind, {start, length}] when length > 0 <-
           Regex.run(@open_regex, line, return: :index),
         {:ok, braces} <- rename_braces(binary_part(line, start, length), mapping) do
      binary_part(line, 0, start) <>
        braces <> binary_part(line, start + length, byte_size(line) - start - length)
    else
      _ -> line
    end
  end

  defp rename_braces(braces, mapping) do
    inner = binary_part(braces, 1, byte_size(braces) - 2)
    trimmed = String.trim_leading(inner)
    lead = binary_part(inner, 0, byte_size(inner) - byte_size(trimmed))

    case rename_attributes(trimmed, mapping, []) do
      {:ok, renamed} -> {:ok, IO.iodata_to_binary(["{", lead, renamed, "}"])}
      :error -> :error
    end
  end

  defp rename_attributes("", _mapping, acc), do: {:ok, Enum.reverse(acc)}

  defp rename_attributes(text, mapping, acc) do
    case Regex.run(@attribute_regex, text) do
      [match, name, quoted] ->
        part = rename_attribute(match, name, quoted, true, mapping)
        rename_attributes(rest(text, match), mapping, [part | acc])

      [match, name, "", plain] ->
        part = rename_attribute(match, name, plain, false, mapping)
        rename_attributes(rest(text, match), mapping, [part | acc])

      nil ->
        :error
    end
  end

  defp rename_attribute(match, name, value, quoted?, mapping) do
    renamed = renamed_value(name, value, mapping)

    if renamed == value do
      match
    else
      raw = if quoted?, do: ~s("#{value}"), else: value
      prefix_bytes = byte_size(name) + 1 + byte_size(raw)
      spacing = binary_part(match, prefix_bytes, byte_size(match) - prefix_bytes)
      name <> "=" <> written_value(renamed, raw, quoted?) <> spacing
    end
  end

  defp renamed_value(name, value, mapping) when name in @path_attributes,
    do: Map.get(mapping, value, value)

  defp renamed_value("captions", value, mapping) do
    value
    |> String.split(",")
    |> Enum.map_join(",", &rename_caption(&1, mapping))
  end

  defp renamed_value(_name, value, _mapping), do: value

  # One entry `<path>:<language>` of `captions` with its spacing.
  defp rename_caption(entry, mapping) do
    with [_entry, lead, path, lang, trail] <-
           Regex.run(~r/\A(\s*)(.*):([^:]*?)(\s*)\z/s, entry),
         {:ok, renamed} <- Map.fetch(mapping, path) do
      lead <> renamed <> ":" <> lang <> trail
    else
      _ -> entry
    end
  end

  defp written_value(value, raw, quoted?) do
    cond do
      String.contains?(value, "\"") -> raw
      not quoted? and Regex.match?(~r/\A[^\s"]+\z/, value) -> value
      true -> ~s("#{value}")
    end
  end

  defp close(errors, %{error_count: count}) when count > @max_errors,
    do: errors ++ [Entries.closing(List.last(errors).line, count - @max_errors)]

  defp close(errors, _state), do: errors

  defp step({text, line}, %{open: nil} = state) do
    cond do
      Regex.match?(@close_regex, text) ->
        add_error(state, line, "closing line `:::` outside a block")

      directive?(text) ->
        open_block(state, text, line)

      String.trim(text) == "" ->
        state

      true ->
        add_error(state, line, "text outside a block")
    end
  end

  defp step({text, line}, %{open: open} = state) do
    cond do
      Regex.match?(@close_regex, text) ->
        close_block(state)

      Regex.match?(@open_regex, text) ->
        add_error(state, line, "a block cannot open inside the block opened at line #{open.line}")

      directive?(text) ->
        add_error(state, line, "malformed directive line")

      true ->
        %{state | open: %{open | lines: [text | open.lines]}}
    end
  end

  defp directive?(text), do: String.starts_with?(text, ":::")

  defp open_block(state, text, line) do
    case Regex.run(@open_regex, text) do
      [_, kind | rest] ->
        open_kind(state, kind, List.first(rest, ""), line)

      nil ->
        # A malformed opening line still opens a block, so that its body and
        # its closing line do not count as text outside a block.
        [_, word] = Regex.run(~r/^:::([^\s{]*)/, text)
        state = add_error(state, line, "malformed directive line")
        %{state | open: %{header: %{kind: word}, line: line, lines: [], valid?: false}}
    end
  end

  defp open_kind(state, kind, attributes, line) do
    {header, errors} = header(kind, attributes)
    state = Enum.reduce(errors, state, &add_error(&2, line, &1))
    %{state | open: %{header: header, line: line, lines: [], valid?: errors == []}}
  end

  defp close_block(%{open: %{valid?: false}} = state), do: %{state | open: nil}

  defp close_block(%{open: open} = state) do
    block =
      Map.merge(open.header, %{
        body: open.lines |> Enum.reverse() |> trim_blank_lines(),
        line: open.line
      })

    %{state | open: nil, blocks: [block | state.blocks]}
  end

  defp close_at_end(%{open: nil} = state), do: state

  defp close_at_end(%{open: open} = state) do
    kind = Map.get(open.header, :kind, "")
    add_error(%{state | open: nil}, open.line, "unclosed block `#{kind}`")
  end

  defp header(kind, attributes) do
    case parse_attributes(attributes) do
      {:ok, pairs} -> build_header(kind, pairs)
      :error -> {%{kind: kind}, ["malformed attribute list `#{attributes}`"]}
    end
  end

  defp build_header(kind, pairs) do
    errors =
      kind_errors(kind) ++
        duplicate_errors(pairs) ++ attribute_errors(kind, pairs) ++ provenance_errors(kind, pairs)

    attrs = Map.new(pairs)

    header = %{
      kind: kind,
      provenance: Map.get(attrs, "provenance", if(kind == "placeholder", do: "placeholder")),
      collapsed_on: list_value(attrs, "collapsed_on"),
      cite: list_value(attrs, "cite"),
      placeholder_key: Map.get(attrs, "key"),
      media: media(kind, attrs)
    }

    {header, errors}
  end

  defp media(kind, attrs) when kind in @media_kinds, do: Map.take(attrs, Map.fetch!(@own, kind))
  defp media(_kind, _attrs), do: nil

  defp kind_errors(kind) when kind in @kinds, do: []
  defp kind_errors(kind), do: ["unknown block kind `#{kind}`"]

  defp duplicate_errors(pairs) do
    pairs
    |> Enum.map(&elem(&1, 0))
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> "duplicate attribute `#{name}`" end)
    |> Enum.sort()
  end

  defp attribute_errors(kind, pairs) do
    allowed = attributes(kind)

    Enum.flat_map(pairs, fn {name, _value} ->
      cond do
        name in allowed -> []
        name in @attributes -> ["attribute `#{name}` is allowed on #{owners(name)} blocks only"]
        true -> ["unknown attribute `#{name}`"]
      end
    end)
  end

  # The kinds that admit the attribute `name` beyond the common ones, such as
  # "`figure` and `video`".
  defp owners(name) do
    @own
    |> Enum.filter(fn {_kind, names} -> name in names end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort_by(&Enum.find_index(@kinds, fn kind -> kind == &1 end))
    |> Enum.map(&"`#{&1}`")
    |> join_and()
  end

  defp join_and([one]), do: one
  defp join_and(names), do: Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names)

  defp provenance_errors("placeholder", pairs) do
    provenance =
      case List.keyfind(pairs, "provenance", 0) do
        {_, value} when value != "placeholder" ->
          ["a `placeholder` block takes the provenance `placeholder` only"]

        _ ->
          []
      end

    key =
      if List.keymember?(pairs, "key", 0),
        do: [],
        else: ["missing attribute `key` on a `placeholder` block"]

    provenance ++ key
  end

  defp provenance_errors(kind, pairs) when kind in @kinds do
    if List.keymember?(pairs, "provenance", 0), do: [], else: ["missing attribute `provenance`"]
  end

  defp provenance_errors(_kind, _pairs), do: []

  defp list_value(attrs, name) do
    case Map.fetch(attrs, name) do
      {:ok, value} -> value |> String.split(",") |> Enum.map(&String.trim/1)
      :error -> []
    end
  end

  defp parse_attributes(""), do: {:ok, []}

  defp parse_attributes("{" <> _ = braces) do
    braces
    |> String.slice(1..-2//1)
    |> String.trim_leading()
    |> scan_attributes([])
  end

  defp scan_attributes("", acc), do: {:ok, Enum.reverse(acc)}

  defp scan_attributes(text, acc) do
    case Regex.run(@attribute_regex, text) do
      [match, name, quoted] -> scan_attributes(rest(text, match), [{name, quoted} | acc])
      [match, name, "", plain] -> scan_attributes(rest(text, match), [{name, plain} | acc])
      nil -> :error
    end
  end

  defp rest(text, match),
    do: binary_part(text, byte_size(match), byte_size(text) - byte_size(match))

  defp trim_blank_lines(lines) do
    lines
    |> Enum.drop_while(&blank?/1)
    |> Enum.reverse()
    |> Enum.drop_while(&blank?/1)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp blank?(line), do: String.trim(line) == ""

  # After @max_errors errors, the splitter counts further errors only.
  defp add_error(%{error_count: count} = state, _line, _message) when count >= @max_errors,
    do: %{state | error_count: count + 1}

  defp add_error(%{error_count: count} = state, line, message),
    do: %{
      state
      | errors: [%{line: line, message: message} | state.errors],
        error_count: count + 1
    }
end
