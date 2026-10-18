defmodule Espalier.Catalog.Pack.Directives do
  @moduledoc """
  Splits the body of a lesson file into blocks and reports the syntax errors of the `:::` directives.

  The body of a lesson file follows its front matter (see
  `Espalier.Catalog.Pack.Schema.Lesson`). It consists of container directives,
  and each directive becomes one block. The order of the directives gives the
  order of the blocks. `Espalier.Catalog.Pack.Loader` calls `split/2` for every
  lesson file. The splitter checks the syntax only. The validator casts the
  values of the attributes with `Espalier.Catalog.Pack.Schema.Block`.

  ## Syntax

  A block has three parts:

  ```markdown
  :::explanation{collapsed_on=short provenance=sourced cite="vendor-guide#Overview"}
  The next word follows from probabilities learned in training.
  :::
  ```

  * The opening line starts in the first column with `:::`, followed by the
    kind and optionally by the attributes in braces. It matches
    `^:::([a-z_]+)(\\{.*\\})?\\s*$`. No space stands between the kind and the
    brace, and only whitespace may follow the closing brace.
  * The lines between the opening and the closing line are the Markdown text
    of the block. They become its `body` without leading and trailing blank
    lines. The splitter does not interpret the Markdown.
  * The closing line matches `^:::\\s*$`.

  Blank lines between blocks are ignored. Every other line outside a block is
  an error. A block does not nest, and a line inside a block that starts with
  `:::` is either its closing line or an error, so a body holds no such line.
  Lines end with a line feed or a carriage return and a line feed.

  ## Block kinds

  The kind is one of `text`, `explanation`, `example`, `case_comparison`,
  `quote`, `callout`, `placeholder`, `figure` and `video`, as `kinds/0`
  returns them. A `figure` block shows an image and a `video` block a video;
  their text is the caption and the transcript. A kind has
  lower-case letters and underscores only; any other character in the name
  makes the line a malformed directive line. The content of each kind is in
  `Espalier.Catalog.Pack.Schema.Block`.

  ## Attributes

  Attributes are `name=value` pairs, separated by spaces. A value without
  spaces and double quotes is written as it is, and any other value is
  enclosed in double quotes, which cannot appear inside the value. Names have
  lower-case letters and underscores only.

  | Attribute | Kinds | Value | Block field |
  |---|---|---|---|
  | `provenance` | every kind | One of the provenance values. Required on every kind except `placeholder`, whose provenance is `placeholder`. | `provenance` |
  | `collapsed_on` | every kind | Paths, separated by commas, for example `short,full` | `collapsed_on` |
  | `cite` | every kind | `source-key#locator`, several separated by commas | `cite` |
  | `key` | `placeholder` | Required there | `placeholder_key` |
  | `src`, `alt`, `decorative`, `size` | `figure` | The image and its text alternative | `media` |
  | `src`, `embed`, `title`, `poster`, `captions` | `video` | The video, its player, title, poster and captions | `media` |

  The splitter cuts the value of `collapsed_on` and `cite` at every comma and
  trims the parts. A locator therefore holds no comma. An attribute that the
  line does not set gives an empty list for `collapsed_on` and `cite` and
  `nil` for `key`.

  The attributes of a `figure` or a `video` block other than `provenance`,
  `collapsed_on` and `cite` go into `media`, a map from the attribute name to
  its raw value that holds the attributes the line sets. The splitter does
  not check these values; `Espalier.Catalog.Pack.Schema.FigureMedia` and
  `Espalier.Catalog.Pack.Schema.VideoMedia` do. `media` is `nil` for every
  other kind. The body of a `figure` or a `video` block may be empty.

  ## Example

  This body gives three blocks, and `split/2` called with the line number 1
  for its first line returns them with the lines 1, 5 and 9:

  ```markdown
  :::text{provenance=invented}
  A [[term:llm|language model]] continues text.
  :::

  :::quote{provenance=sourced cite="vendor-guide#Overview, assistant-manual#Chapter 5"}
  Mark every shared document that the assistant helped to draft.
  :::

  :::placeholder{key=input-rules}
  Your organization adds its rules for inputs here.
  :::
  ```

  `split/2` returns the blocks as maps. The second block is:

  ```elixir
  %{
    kind: "quote",
    provenance: "sourced",
    collapsed_on: [],
    cite: ["vendor-guide#Overview", "assistant-manual#Chapter 5"],
    placeholder_key: nil,
    media: nil,
    body: "Mark every shared document that the assistant helped to draft.",
    line: 5
  }
  ```

  A `figure` block puts its attributes into `media`. This body gives one block:

  ```markdown
  :::figure{provenance=invented src=media/next-word.svg alt="Three candidates for the next word" size=medium}
  The candidates with their probabilities.
  :::
  ```

  `split/2` returns it as:

  ```elixir
  %{
    kind: "figure",
    provenance: "invented",
    collapsed_on: [],
    cite: [],
    placeholder_key: nil,
    media: %{
      "src" => "media/next-word.svg",
      "alt" => "Three candidates for the next word",
      "size" => "medium"
    },
    body: "The candidates with their probabilities.",
    line: 1
  }
  ```

  ## Errors

  Every error carries the line number in the file. An error of an opening line
  names that line, and an unclosed block names its opening line. The messages
  are:

  | Message | Cause |
  |---|---|
  | ``unknown block kind `<kind>` `` | The kind is not one of the nine kinds. |
  | ``unknown attribute `<name>` `` | The attribute is none of those in the table above. |
  | ``duplicate attribute `<name>` `` | The line sets an attribute twice. |
  | ``malformed attribute list `<list>` `` | The braces hold something other than `name=value` pairs. |
  | `malformed directive line` | A line that starts with `:::` neither opens nor closes a block, for example `:::Text{provenance=invented}` or `:::text {provenance=invented}`. |
  | ``missing attribute `provenance` `` | A block of a kind other than `placeholder` sets no provenance. |
  | ``a `placeholder` block takes the provenance `placeholder` only`` | A `placeholder` block sets another provenance. |
  | ``missing attribute `key` on a `placeholder` block`` | A `placeholder` block sets no key. |
  | ``attribute `<name>` is allowed on <kinds> blocks only`` | A kind sets an attribute that only other kinds admit. The message names those kinds, as in ``attribute `key` is allowed on `placeholder` blocks only`` for `key` on another kind, and in ``attribute `src` is allowed on `figure` and `video` blocks only`` for `src` on any kind but those two. |
  | `a block cannot open inside the block opened at line <n>` | An opening line appears before the closing line. |
  | ``closing line `:::` outside a block`` | A closing line appears without an open block. |
  | `text outside a block` | A line that is not blank appears outside a block. |
  | ``unclosed block `<kind>` `` | The body ends before the closing line. |

  A block with an error in its opening line is not part of the result. Its
  body and its closing line raise no further error.

  The splitter keeps the first 100 errors of a body and counts the further
  ones, so that a body of many faulty lines holds no more memory than one of
  100. When errors were left out, the sorted errors end with one closing
  entry of `Espalier.Catalog.Pack.Entries.closing/3` at the line of the last
  kept error, for example `and 2,341 further errors in this file`, whose
  `omitted` gives their number.

  ## Renaming media paths

  `rename_media/2` rewrites the media paths in the opening lines of a lesson
  file. The pack workbench calls it when it stores the media of an archive
  under their delivery paths. It changes the values of `src` and `poster`
  and the path of each entry of `captions`, and leaves every other line and
  attribute as it is.

  ## See also

    * [Content packs](content-packs.md), section "Lesson directives"
    * `Espalier.Catalog.Pack.Schema.Lesson` for the front matter and the file layout
    * `Espalier.Catalog.Pack.Schema.Block` for the values of the attributes
    * `Espalier.Catalog.Pack.Loader.load/1`, which reads the lesson files
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

  @typedoc """
  A block of a lesson body as a map. `kind` and `provenance` are the strings
  of the opening line, `collapsed_on` and `cite` the lists of their
  attributes, `placeholder_key` the value of `key` or `nil`, `media` the map
  from the attribute name to its raw value for a `figure` or a `video` block
  and `nil` for every other kind, `body` the text between the opening and
  the closing line, and `line` the line number of the opening line in the
  lesson file.
  """
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

  @doc "Returns the nine block kinds as strings: `text`, `explanation`, `example`, `case_comparison`, `quote`, `callout`, `placeholder`, `figure` and `video`."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc """
  Returns the attributes that a block of `kind` admits, as strings.

  Every kind admits `provenance`, `collapsed_on` and `cite`. `placeholder`
  adds `key`, `figure` adds `src`, `alt`, `decorative` and `size`, and
  `video` adds `src`, `embed`, `title`, `poster` and `captions`. An unknown
  kind admits the common three only.
  """
  @spec attributes(String.t()) :: [String.t()]
  def attributes(kind), do: @common ++ Map.get(@own, kind, [])

  @doc "Returns 100, the largest number of errors that `split/2` keeps for one body."
  @spec max_errors() :: pos_integer()
  def max_errors, do: @max_errors

  @doc """
  Splits `markdown`, the body of a lesson file, into blocks.

  `first_line` is the line number of the first line of `markdown` in its file;
  every block and every error carries the line number in the file. Returns
  `{:ok, blocks}` in the order of the file when the body has no error, and
  `{:error, errors}` otherwise, with the errors sorted by line.
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
