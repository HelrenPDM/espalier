defmodule Espalier.Workbench.DraftDir do
  @moduledoc """
  The file system side of the pack workbench (task 0016a, steps 5 and 6;
  ASVS 5.2.2, 5.3.2 and 15.2.2).

  `with_dir/2` writes the files of a draft into a new directory below
  `System.tmp_dir!/0`, so that the loader and the importer of task 0008 read
  them as they read a pack directory, and removes the directory in an
  `after` block. Each path passes `Espalier.Workbench.Paths.check/1` again
  before it is joined with the directory, so every write stays inside it
  also for a row that reached the table by another way than the context.

  `read_pack/1` reads the pack of an extracted archive into a list of files:
  it keeps every regular file whose path relative to the root passes the
  path rules, and lists every other file as skipped.
  """

  alias Espalier.Workbench.Paths

  @max_skipped 100

  @typedoc "A report entry in the shape of the archive report."
  @type entry :: %{String.t() => String.t() | nil}

  @typedoc "The skipped paths, sorted: at most #{@max_skipped}, and the number left out."
  @type skipped :: %{paths: [String.t()], omitted: non_neg_integer()}

  @doc "The largest number of skipped paths that `read_pack/1` lists."
  @spec max_skipped() :: pos_integer()
  def max_skipped, do: @max_skipped

  @doc """
  Writes `files`, a list of `{path, content}`, into a new directory
  `espalier-draft-<random>` below `System.tmp_dir!/0`, runs `fun` on it and
  removes it in an `after` block, also when `fun` raises. A path that fails
  the path rules answers `{:error, :invalid_path}` before `fun` runs.
  """
  @spec with_dir([{String.t(), String.t()}], (Path.t() -> result)) ::
          result | {:error, :invalid_path}
        when result: term()
  # The directory is a new directory below System.tmp_dir!/0 with a random
  # name; no input reaches its path.
  # sobelow_skip ["Traversal.FileModule"]
  def with_dir(files, fun) when is_list(files) and is_function(fun, 1) do
    dir = Path.join(System.tmp_dir!(), "espalier-draft-" <> random_name())
    File.mkdir_p!(dir)

    try do
      with :ok <- write_files(dir, files), do: fun.(dir)
    after
      File.rm_rf(dir)
    end
  end

  defp write_files(dir, files) do
    Enum.reduce_while(files, :ok, fn {path, content}, :ok ->
      case Paths.check(path) do
        :ok ->
          write_file(dir, path, content)
          {:cont, :ok}

        {:error, :invalid_path} = error ->
          {:halt, error}
      end
    end)
  end

  # The path has passed the path rules just before: a relative path of the
  # pack layout without an empty, `.` or `..` component, so the joined path
  # stays inside the new directory.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_file(dir, path, content) do
    file = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, content)
  end

  @doc """
  Reads the pack below `root`, a directory of an archive that
  `Espalier.Catalog.Pack.Archive` has extracted. It walks the root with
  `File.lstat/1` and keeps every regular file whose path relative to the
  root passes the path rules; every other file is skipped.

  Returns `{:ok, files, skipped}` with the files as `{path, content}` sorted
  by path, or `{:error, entries}` with one report entry per kept file above
  `Espalier.Workbench.max_file_bytes/0`, with content that is no valid UTF-8
  or with U+0000, and one entry at `.` when no file passes the path rules.
  """
  @spec read_pack(Path.t()) ::
          {:ok, [{String.t(), String.t()}], skipped()} | {:error, [entry()]}
  def read_pack(root) when is_binary(root) do
    {kept, skipped} = root |> walk("") |> Enum.split_with(&kept?/1)

    entries = kept |> Enum.map(&read_kept(root, &1)) |> Enum.sort_by(&elem(&1, 1))

    case {for({:error, _path, entry} <- entries, do: entry), kept} do
      {[], []} ->
        {:error, [entry(".", "the archive holds no file of the pack layout")]}

      {[], _kept} ->
        files = for {:ok, path, content} <- entries, do: {path, content}
        {:ok, files, skipped(skipped)}

      {errors, _kept} ->
        {:error, errors}
    end
  end

  # Every entry below the root as {relative path, type}. The archive holds at
  # most 2,000 entries and no symbolic link (task 0015, step 7).
  # sobelow_skip ["Traversal.FileModule"]
  defp walk(root, rel) do
    case :file.list_dir_all(Path.join(root, rel)) do
      {:ok, names} ->
        Enum.flat_map(names, &walk_entry(root, join(rel, name_binary(&1))))

      {:error, _reason} ->
        []
    end
  end

  # The names come from the listing of a directory below the root.
  # sobelow_skip ["Traversal.FileModule"]
  defp walk_entry(root, child) do
    case File.lstat(Path.join(root, child)) do
      {:ok, %File.Stat{type: :directory}} -> walk(root, child)
      {:ok, %File.Stat{type: type}} -> [{child, type}]
      {:error, _reason} -> [{child, :unreadable}]
    end
  end

  # list_dir_all/1 returns a name as a list of code points when it decodes
  # and as raw bytes otherwise.
  defp name_binary(name) when is_binary(name), do: name
  defp name_binary(name) when is_list(name), do: List.to_string(name)

  defp join("", name), do: name
  defp join(rel, name), do: rel <> "/" <> name

  defp kept?({path, :regular}), do: Paths.check(path) == :ok
  defp kept?(_entry), do: false

  # The path passed the path rules, and the walk found a regular file there.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_kept(root, {path, :regular}) do
    file = Path.join(root, path)
    max = Espalier.Workbench.max_file_bytes()

    with {:ok, %File.Stat{size: size}} when size <= max <- File.lstat(file),
         {:ok, content} <- File.read(file),
         :ok <- check_text(content) do
      {:ok, path, content}
    else
      {:ok, %File.Stat{}} ->
        {:error, path, entry(path, "the file is larger than 1 MiB (1,048,576 bytes)")}

      {:error, message} when is_binary(message) ->
        {:error, path, entry(path, message)}

      {:error, _reason} ->
        {:error, path, entry(path, "the file cannot be read")}
    end
  end

  defp check_text(content) do
    cond do
      not String.valid?(content) -> {:error, "the file is not valid UTF-8 text"}
      String.contains?(content, <<0>>) -> {:error, "the file holds the character U+0000"}
      true -> :ok
    end
  end

  defp skipped(entries) do
    paths = entries |> Enum.map(fn {path, _type} -> printable(path) end) |> Enum.sort()
    %{paths: Enum.take(paths, @max_skipped), omitted: max(length(paths) - @max_skipped, 0)}
  end

  defp entry(file, message), do: %{"file" => printable(file), "line" => nil, "message" => message}

  # A path goes into an answer as one printable line, as the archive report
  # writes the names of its entries.
  defp printable(path) do
    path
    |> String.replace_invalid()
    |> String.replace(~r/[\x00-\x1f\x7f]/u, "?")
    |> String.slice(0, 1_000)
  end

  defp random_name, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
