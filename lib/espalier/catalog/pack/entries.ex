defmodule Espalier.Catalog.Pack.Entries do
  @moduledoc """
  Bounds the report entries of a content pack (task 0008, steps 8, 9 and 11),
  so that a pack of any size gives a report of bounded size that prints one
  line per entry.

  Every list of entries passes through `limit/2` before it leaves
  `Espalier.Catalog.Pack.Loader.load/1` and
  `Espalier.Catalog.Pack.Validator.run/1`:

    * a file keeps at most 100 entries, the first ones in the order of the
      list, and the further entries of the file become one closing entry at
      the line of its last kept entry, for example
      `and 2,341 further errors in this file`;
    * every string member of an entry (`file`, `message` and the `key` of an
      alignment entry) holds at most 1,000 characters (code points); a longer
      one keeps its first 997 characters and ends with the marker `[…]`;
    * every control character of a string member (U+0000 to U+001F and
      U+007F to U+009F, line feed, carriage return and tab among them) and
      the line and paragraph separators U+2028 and U+2029 are written as
      `\\xNN` per byte of their UTF-8 form, the form that the loader uses for
      entry names that are not valid UTF-8. A byte that is not part of valid
      UTF-8 is written the same way. The escape counts towards the 1,000
      characters, and the marker never splits it.

  `Espalier.Catalog.Pack.Report.stored/2` passes each list through `cap/2` in
  addition, which keeps at most 1,000 entries and closes the list with one
  entry `and N further errors` at file `.` and line 1.

  A closing entry has `file`, `line` and `message`, and `omitted`, the number
  of entries it stands for; `count/1` adds them up, so the total stays known.
  `limit/2` and `cap/2` fold the closing entries of their input into their
  own, so that applying them again changes nothing. An entry with atom keys
  gets a closing entry with atom keys, and one with string keys a closing
  entry with string keys.
  """

  @max_per_file 100
  @max_entries 1_000
  @max_chars 1_000
  @marker "[…]"
  @marker_chars 3

  @typedoc "An entry with atom keys or with string keys."
  @type entry :: %{optional(atom() | String.t()) => term()}

  @typedoc "The kind of the entries of a list."
  @type kind :: :error | :warning

  @doc "The largest number of entries that `limit/2` keeps for one file."
  @spec max_per_file() :: pos_integer()
  def max_per_file, do: @max_per_file

  @doc "The largest number of entries that `cap/2` keeps."
  @spec max_entries() :: pos_integer()
  def max_entries, do: @max_entries

  @doc "The largest number of characters of a string member, the marker `[…]` included."
  @spec max_chars() :: pos_integer()
  def max_chars, do: @max_chars

  @doc """
  Keeps at most 100 entries per file and makes every string member one line
  of at most 1,000 characters, as the moduledoc describes. The files keep the
  order of their first entry, and the entries of a file keep their order.
  """
  @spec limit([entry()], kind()) :: [entry()]
  def limit(entries, kind \\ :error) when is_list(entries) and kind in [:error, :warning] do
    {order, groups} = Enum.reduce(entries, {[], %{}}, &group/2)

    order
    |> Enum.reverse()
    |> Enum.flat_map(fn file -> groups |> Map.fetch!(file) |> close_file(file, kind) end)
  end

  @doc """
  Keeps the first 1,000 entries of `entries` and closes the list with one
  entry `and N further errors` (or `warnings`) at file `.` and line 1, where
  `N` counts the entries left out with `count/1`.
  """
  @spec cap([entry()], kind()) :: [entry()]
  def cap(entries, kind \\ :error) when is_list(entries) and kind in [:error, :warning] do
    {kept, rest} = Enum.split(entries, @max_entries)

    case count(rest) do
      0 -> kept
      omitted -> kept ++ [closing_entry(hd(rest), ".", 1, omitted, further(omitted, kind))]
    end
  end

  @doc """
  The number of entries that `entries` stands for: one for each entry, and
  `omitted` for each closing entry.
  """
  @spec count([entry()]) :: non_neg_integer()
  def count(entries) when is_list(entries),
    do: Enum.reduce(entries, 0, fn entry, total -> total + (omitted(entry) || 1) end)

  @doc """
  A closing entry without `file` for `omitted` entries of one file, at
  `line`. `Espalier.Catalog.Pack.Directives.split/2` uses it, which does not
  know the file of the body it splits.
  """
  @spec closing(pos_integer(), pos_integer(), kind()) :: %{
          line: pos_integer(),
          message: String.t(),
          omitted: pos_integer()
        }
  def closing(line, omitted, kind \\ :error) when is_integer(omitted) and omitted > 0,
    do: %{line: line, message: further(omitted, kind) <> " in this file", omitted: omitted}

  @doc "Returns true when `entry` is a closing entry."
  @spec closing?(entry()) :: boolean()
  def closing?(entry), do: is_integer(omitted(entry))

  @doc """
  Sorts entries by file, line and message and drops the second of two equal
  entries. Closing entries all stay, because each stands for its own entries.
  """
  @spec sort([entry()]) :: [entry()]
  def sort(entries) when is_list(entries) do
    {closing, plain} = Enum.split_with(entries, &closing?/1)

    (Enum.uniq(plain) ++ closing)
    |> Enum.sort_by(&{member(&1, :file), member(&1, :line), member(&1, :message)})
  end

  @doc """
  Makes `text` one line of at most 1,000 characters: control characters,
  U+2028, U+2029 and bytes outside valid UTF-8 become `\\xNN`, and a longer
  text keeps its first 997 characters and the marker `[…]`.
  """
  @spec clean(binary()) :: String.t()
  def clean(text) when is_binary(text) do
    case units(text, [], 0) do
      {:all, units} -> join(units)
      {:more, units, length} -> join(shorten(units, length)) <> @marker
    end
  end

  @doc "Writes a non-negative integer with commas between groups of three digits, as `2,341`."
  @spec number(non_neg_integer()) :: String.t()
  def number(value) when is_integer(value) and value >= 0 do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  # limit/2

  defp group(entry, {order, groups}) do
    file = member(entry, :file)

    case Map.fetch(groups, file) do
      {:ok, group} ->
        {order, Map.put(groups, file, add(group, entry))}

      :error ->
        group = %{kept: [], count: 0, omitted: 0, line: nil, template: entry}
        {[file | order], Map.put(groups, file, add(group, entry))}
    end
  end

  defp add(group, entry) do
    case omitted(entry) do
      omitted when is_integer(omitted) ->
        %{group | omitted: group.omitted + omitted, line: group.line || member(entry, :line)}

      nil when group.count < @max_per_file ->
        %{group | kept: [entry | group.kept], count: group.count + 1, line: member(entry, :line)}

      nil ->
        %{group | omitted: group.omitted + 1}
    end
  end

  defp close_file(group, file, kind) do
    kept = group.kept |> Enum.reverse() |> Enum.map(&clean_entry/1)

    if group.omitted == 0,
      do: kept,
      else:
        kept ++
          [
            closing_entry(
              group.template,
              file,
              group.line || 1,
              group.omitted,
              further(group.omitted, kind) <> " in this file"
            )
          ]
  end

  defp closing_entry(template, file, line, omitted, message) do
    entry = %{file: file, line: line, message: message, omitted: omitted}

    if is_map_key(template, "file") or is_map_key(template, "message"),
      do: entry |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end) |> clean_entry(),
      else: clean_entry(entry)
  end

  defp further(1, :error), do: "and 1 further error"
  defp further(1, :warning), do: "and 1 further warning"
  defp further(omitted, :error), do: "and #{number(omitted)} further errors"
  defp further(omitted, :warning), do: "and #{number(omitted)} further warnings"

  defp clean_entry(entry) do
    Map.new(entry, fn
      {key, value} when is_binary(value) -> {key, clean(value)}
      pair -> pair
    end)
  end

  defp omitted(entry) do
    case member(entry, :omitted) do
      omitted when is_integer(omitted) -> omitted
      _ -> nil
    end
  end

  defp member(entry, key), do: Map.get(entry, key, Map.get(entry, Atom.to_string(key)))

  # clean/1. A unit is one character of the result, or the escape of one
  # character or byte, with its length in characters. The walk stops once the
  # units exceed the limit, so a long text costs no more than a short one.

  defp units(_text, units, length) when length > @max_chars, do: {:more, units, length}
  defp units(<<>>, units, _length), do: {:all, units}

  defp units(<<char::utf8, rest::binary>>, units, length) do
    if escaped?(char) do
      unit = escape(<<char::utf8>>)
      units(rest, [{unit, byte_size(unit)} | units], length + byte_size(unit))
    else
      units(rest, [{<<char::utf8>>, 1} | units], length + 1)
    end
  end

  defp units(<<byte, rest::binary>>, units, length) do
    unit = escape(<<byte>>)
    units(rest, [{unit, byte_size(unit)} | units], length + byte_size(unit))
  end

  defp escaped?(char),
    do: char in 0x00..0x1F or char in 0x7F..0x9F or char in [0x2028, 0x2029]

  defp escape(bytes), do: for(<<byte <- bytes>>, into: "", do: "\\x" <> Base.encode16(<<byte>>))

  defp shorten([{_unit, size} | rest], length) when length > @max_chars - @marker_chars,
    do: shorten(rest, length - size)

  defp shorten(units, _length), do: units

  defp join(units), do: units |> Enum.reverse() |> Enum.map(&elem(&1, 0)) |> IO.iodata_to_binary()
end
