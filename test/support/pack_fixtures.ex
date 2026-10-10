defmodule Espalier.PackFixtures do
  @moduledoc """
  Helpers for tests on content packs (task 0008, step 15).

  `copy_pack!/1` copies a fixture pack, or the demo pack, into a fresh
  directory under `System.tmp_dir!/0` and removes it when the test exits.
  The other helpers change a file inside the copy: replace a string, write
  text, rewrite a YAML file from Elixir data, or remove a file. `line_of!/4`
  finds the line of a text, so that a test can assert the line of a report
  entry without counting lines by hand.

      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", "schema: 1", "schema: 2")
      update_yaml!(pack, "formats.yaml", fn [first | rest] -> [Map.delete(first, "phases") | rest] end)
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @fixtures Path.expand("../espalier/catalog/fixtures", __DIR__)
  @demo Path.expand("../../content/demo", __DIR__)

  @doc "The path of the fixture pack `name` under `test/espalier/catalog/fixtures/`."
  @spec fixture_path(String.t()) :: String.t()
  def fixture_path(name), do: Path.join(@fixtures, name)

  @doc "The path of the demo pack `content/demo`."
  @spec demo_path() :: String.t()
  def demo_path, do: @demo

  @doc """
  Copies a pack into a fresh temporary directory and returns its path. The
  argument is the name of a fixture pack or an absolute path, for example
  `demo_path/0`. The copy is removed when the test exits.
  """
  @spec copy_pack!(String.t()) :: String.t()
  def copy_pack!(name_or_path) do
    source =
      if Path.type(name_or_path) == :absolute, do: name_or_path, else: fixture_path(name_or_path)

    target =
      Path.join(
        System.tmp_dir!(),
        "espalier-pack-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(target)
    on_exit(fn -> File.rm_rf!(target) end)
    File.cp_r!(source, target)
    target
  end

  @doc "The absolute path of the file `rel` inside `pack`."
  @spec path(String.t(), String.t()) :: String.t()
  def path(pack, rel), do: Path.join(pack, rel)

  @doc "Reads the file `rel` inside `pack`."
  @spec read!(String.t(), String.t()) :: String.t()
  def read!(pack, rel), do: pack |> path(rel) |> File.read!()

  @doc "Writes `content` to the file `rel` inside `pack`, creating its directory."
  @spec write!(String.t(), String.t(), iodata()) :: :ok
  def write!(pack, rel, content) do
    file = path(pack, rel)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, content)
  end

  @doc "Removes the file or directory `rel` inside `pack`."
  @spec remove!(String.t(), String.t()) :: :ok
  def remove!(pack, rel) do
    File.rm_rf!(path(pack, rel))
    :ok
  end

  @doc """
  Replaces the first occurrence of `from` with `to` in the file `rel`, or
  every occurrence with `global: true`. Raises when `from` does not occur, so
  that a test cannot pass on an edit that changed nothing.
  """
  @spec replace!(String.t(), String.t(), String.t(), String.t(), keyword()) :: :ok
  def replace!(pack, rel, from, to, opts \\ []) do
    content = read!(pack, rel)

    unless String.contains?(content, from) do
      raise ArgumentError, "#{inspect(from)} does not occur in #{rel}"
    end

    write!(
      pack,
      rel,
      String.replace(content, from, to, global: Keyword.get(opts, :global, false))
    )
  end

  @doc "Reads the YAML file `rel` inside `pack` into Elixir data with string keys."
  @spec read_yaml!(String.t(), String.t()) :: term()
  def read_yaml!(pack, rel), do: pack |> read!(rel) |> YamlElixir.read_from_string!()

  @doc """
  Writes Elixir data as a YAML file `rel` inside `pack`: maps and lists in
  block style, map keys sorted, strings double-quoted.
  """
  @spec write_yaml!(String.t(), String.t(), term()) :: :ok
  def write_yaml!(pack, rel, data), do: write!(pack, rel, to_yaml(data))

  @doc "Reads the YAML file `rel`, applies `fun` to its data and writes the result back."
  @spec update_yaml!(String.t(), String.t(), (term() -> term())) :: :ok
  def update_yaml!(pack, rel, fun), do: write_yaml!(pack, rel, fun.(read_yaml!(pack, rel)))

  @doc """
  Returns the 1-based number of the first line of the file `rel` that
  contains `needle`. With `after: anchor`, the search starts after the first
  line that contains `anchor`. Raises when no line matches.
  """
  @spec line_of!(String.t(), String.t(), String.t(), keyword()) :: pos_integer()
  def line_of!(pack, rel, needle, opts \\ []) do
    lines = pack |> read!(rel) |> String.split("\n") |> Enum.with_index(1)

    start =
      case Keyword.fetch(opts, :after) do
        {:ok, anchor} -> find_line!(lines, anchor, 0, rel)
        :error -> 0
      end

    find_line!(lines, needle, start, rel)
  end

  defp find_line!(lines, needle, start, rel) do
    case Enum.find(lines, fn {text, number} ->
           number > start and String.contains?(text, needle)
         end) do
      {_text, number} ->
        number

      nil ->
        raise ArgumentError, "no line of #{rel} after line #{start} contains #{inspect(needle)}"
    end
  end

  @doc "Renders Elixir data as YAML text in block style."
  @spec to_yaml(term()) :: String.t()
  def to_yaml(data), do: data |> emit(0) |> IO.iodata_to_binary()

  defp emit(map, indent) when is_map(map) and map_size(map) > 0 do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> [pad(indent), scalar(key), ":", member(value, indent)] end)
  end

  defp emit(list, indent) when is_list(list) and list != [] do
    Enum.map(list, fn value -> [pad(indent), "-", element(value, indent)] end)
  end

  defp emit(value, _indent), do: [scalar(value), "\n"]

  defp member(value, indent)
       when (is_map(value) and map_size(value) > 0) or (is_list(value) and value != []),
       do: ["\n", emit(value, indent + 2)]

  defp member(value, _indent), do: [" ", scalar(value), "\n"]

  defp element(value, indent) when is_map(value) and map_size(value) > 0 do
    rendered = value |> emit(indent + 2) |> IO.iodata_to_binary()
    [" ", String.replace_prefix(rendered, pad(indent + 2), "")]
  end

  defp element(value, indent) when is_list(value) and value != [],
    do: ["\n", emit(value, indent + 2)]

  defp element(value, _indent), do: [" ", scalar(value), "\n"]

  defp scalar(nil), do: "null"
  defp scalar(value) when is_boolean(value), do: to_string(value)
  defp scalar(value) when is_number(value), do: to_string(value)
  defp scalar([]), do: "[]"
  defp scalar(map) when map == %{}, do: "{}"
  defp scalar(value) when is_binary(value), do: JSON.encode!(value)
  defp scalar(value) when is_atom(value), do: JSON.encode!(Atom.to_string(value))

  defp pad(indent), do: String.duplicate(" ", indent)
end
