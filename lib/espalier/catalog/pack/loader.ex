defmodule Espalier.Catalog.Pack.Loader do
  @moduledoc """
  Reads a content pack directory into the loaded map (task 0008, step 6).

  The loader walks the pack with `File.lstat/1`, the root included, and
  rejects every symbolic link and every entry that is neither a directory nor
  a regular file, also inside directories it does not read. It lists a
  directory with `:file.list_dir_all/1`, which also returns the names that
  are not valid UTF-8, and rejects every such name without reading or
  following the entry; the error names the parent directory (`.` for the
  root) and the name with every byte outside printable ASCII, the backtick
  and the backslash written as `\\xNN`. The walk stops with one error at
  `.`, and the loader then reads no file, when the time budget of the pack
  passes (it starts before the walk), when the pack directory holds more
  than 20,000 entries or when a directory lies deeper than 32 levels. The
  loader reads only the files of the pack format, with `File.read/1` on
  paths built from the root and the listed names, so that no read follows a
  link or leaves the pack:

    * the top-level files `pack.yaml`, `sources.yaml`, `glossary.yaml`,
      `segments.yaml`, `stations.yaml`, `feedback.yaml`,
      `qualifications.yaml` and `formats.yaml`;
    * `modules/<dir>/{module,objectives,rules,items,assessment}.yaml`;
    * `modules/<dir>/lessons/*.md`.

  A file larger than 1 MiB (1,048,576 bytes, the size that `File.lstat/1`
  reports) is rejected before it is read. Every text must be valid UTF-8 and
  must not hold a control character other than tab, line feed and carriage
  return (U+0000 to U+0008, U+000B, U+000C, U+000E to U+001F and U+007F,
  `Espalier.Catalog.Pack.LineIndex.control_character/1`); the error names the
  line and the column of the first one. Each YAML text and each front matter is
  parsed in two passes: `Espalier.Catalog.Pack.LineIndex.build/2` first, and
  only on its success `YamlElixir.read_from_string/2` without `atoms: true`,
  so that the data has string keys and the loader creates no atoms. Both
  passes run in a process of their own within the budget of `parse_budget/0`
  (10 seconds and 256 MiB by default), because yamerl 0.10.0 needs time that
  grows with the square of the length of a flow collection in the position of
  an implicit key, which the size and depth limits do not bound. The parse
  process dies with its caller. Once the time budget of the whole pack has
  passed (60 seconds by default), the loader reads no further file. A lesson
  file starts with a line `---`, then the front matter, then a line `---`,
  and its body goes to `Espalier.Catalog.Pack.Directives.split/2`.

  The loader adds up the size of what it decodes, pack-wide: for each YAML
  file the size of its data and for each lesson file the size of its front
  matter data and its blocks, each measured with `:erlang.external_size/1`,
  which counts a value that a YAML alias repeats as often as it occurs. The
  file at which the sum exceeds `max_pack_bytes/0` (32 MiB) gets the error
  `the pack holds more than 32 MiB of text once decoded`, and the loader
  reads no further file. The per-text bounds of
  `Espalier.Catalog.Pack.LineIndex` let a small text expand through aliases,
  and this bound keeps the sum over many such texts below what the `payload`
  and `report` columns of `Espalier.Catalog.PackImport` hold.

  `pack.yaml` must exist, `modules/` must hold at least one directory, and
  every module directory must hold `module.yaml` and a `lessons/` directory
  with at least one `.md` file whose name without `.md` matches the key
  format. The loader collects the errors of all files, sorts them by file,
  line and message, and passes them through
  `Espalier.Catalog.Pack.Entries.limit/2`: at most 100 errors per file, and
  every message and file name one line of at most 1,000 characters.

  The loaded map:

      %{
        root: String.t(),
        files: %{String.t() => doc},       # the top-level YAML files that exist
        modules: [module_dir]              # sorted by directory name
      }

      doc = %{file: String.t(), data: term(), lines: LineIndex.t()}
      module_dir = %{dir: String.t(), files: %{String.t() => doc}, lessons: [lesson_file]}
      lesson_file = %{key: String.t(), file: String.t(), front: doc, blocks: [Directives.block()]}

  `file` is the path relative to the pack directory, and `data` is `nil` for
  an empty document.
  """

  alias Espalier.Catalog.Pack.{Directives, Entries, LineIndex}
  alias Espalier.Catalog.Pack.Schema.Cast
  alias YamlElixir.ParsingError

  @top_files ~w(pack.yaml sources.yaml glossary.yaml segments.yaml stations.yaml feedback.yaml qualifications.yaml formats.yaml)
  @module_files ~w(module.yaml objectives.yaml rules.yaml items.yaml assessment.yaml)
  @max_file_bytes 1_048_576
  @max_pack_bytes 32 * 1_048_576
  # The walk of the pack directory: entries and levels below the pack
  # directory. The pack format needs four levels and a few hundred entries.
  @max_walk_entries 20_000
  @max_walk_depth 32

  # The budget of one YAML parse. yamerl 0.10.0 needs time that grows with the
  # square of the length of a flow collection in the position of an implicit
  # key (`- [1, 1, ...]`), which the size and depth limits do not bound.
  # A pack stops loading once pack_timeout_ms have passed, so that the time
  # of a load does not grow with the number of files.
  @parse_budget [
    timeout_ms: 10_000,
    max_heap_words: 32 * 1024 * 1024,
    pack_timeout_ms: 60_000
  ]

  @typedoc "An error of the loader."
  @type entry :: %{file: String.t(), line: pos_integer(), message: String.t()}

  @typedoc "A parsed YAML text with its line index."
  @type doc :: %{file: String.t(), data: term(), lines: LineIndex.t()}

  @typedoc "A lesson file."
  @type lesson_file :: %{
          key: String.t(),
          file: String.t(),
          front: doc(),
          blocks: [Directives.block()]
        }

  @typedoc "A module directory."
  @type module_dir :: %{dir: String.t(), files: %{String.t() => doc()}, lessons: [lesson_file()]}

  @typedoc "The loaded map."
  @type loaded :: %{root: String.t(), files: %{String.t() => doc()}, modules: [module_dir()]}

  @doc "The names of the top-level YAML files of the pack format."
  @spec top_files() :: [String.t()]
  def top_files, do: @top_files

  @doc "The names of the YAML files of a module directory."
  @spec module_files() :: [String.t()]
  def module_files, do: @module_files

  @doc "The maximum size in bytes of a file that the loader reads."
  @spec max_file_bytes() :: pos_integer()
  def max_file_bytes, do: @max_file_bytes

  @doc """
  The maximum size in bytes of the decoded data of a whole pack, 32 MiB
  (33,554,432 bytes), measured with `:erlang.external_size/1` as the
  moduledoc describes.
  """
  @spec max_pack_bytes() :: pos_integer()
  def max_pack_bytes, do: @max_pack_bytes

  @doc "The maximum number of entries (files and directories) of a pack directory."
  @spec max_walk_entries() :: pos_integer()
  def max_walk_entries, do: @max_walk_entries

  @doc "The maximum level of a directory below the pack directory."
  @spec max_walk_depth() :: pos_integer()
  def max_walk_depth, do: @max_walk_depth

  @doc """
  The budget of one YAML parse, `timeout_ms` (default 10,000) and
  `max_heap_words` (default 33,554,432 words, 256 MiB on a 64-bit system),
  and the time budget of a whole pack, `pack_timeout_ms` (default 60,000):
  once it has passed, the loader reads no further file. A load therefore
  ends within `pack_timeout_ms` plus the `timeout_ms` of the file that was
  being parsed. `config :espalier, Espalier.Catalog.Pack.Loader,
  parse_budget: [...]` overrides each value.
  """
  @spec parse_budget() :: [
          timeout_ms: pos_integer(),
          max_heap_words: pos_integer(),
          pack_timeout_ms: pos_integer()
        ]
  def parse_budget do
    overrides = :espalier |> Application.get_env(__MODULE__, []) |> Keyword.get(:parse_budget, [])
    for {key, default} <- @parse_budget, do: {key, Keyword.get(overrides, key, default)}
  end

  @doc """
  Loads the pack in the directory `path`. Returns the loaded map, or the
  errors of the walk and of the files, sorted by file, line and message and
  bounded by `Espalier.Catalog.Pack.Entries.limit/2`.
  """
  @spec load(Path.t()) :: {:ok, loaded()} | {:error, [entry()]}
  def load(path) when is_binary(path) do
    root = Path.expand(path)

    case check_root(root) do
      :ok -> load_root(root)
      {:error, errors} -> {:error, finish(errors)}
    end
  end

  defp load_root(root) do
    deadline = System.monotonic_time(:millisecond) + parse_budget()[:pack_timeout_ms]
    tree = walk(root, deadline)

    # A walk that stopped saw only part of the pack, so no file is read.
    if tree.stopped do
      {:error, finish(tree.errors)}
    else
      read_root(root, tree, deadline)
    end
  end

  defp read_root(root, tree, deadline) do
    {files, file_errors, used} = read_top_files(root, tree, %{bytes: 0, deadline: deadline})
    {modules, module_errors, _used} = read_modules(root, tree, used)

    case tree.errors ++ file_errors ++ module_errors do
      [] -> {:ok, %{root: root, files: files, modules: modules}}
      errors -> {:error, finish(errors)}
    end
  end

  @doc """
  Reads only `pack.yaml` of the pack in `path`, with the same safety rules as
  `load/1`, and returns its `key` and `version` when they are strings. The
  importer uses it for a pack that `load/1` rejects.
  """
  @spec pack_meta(Path.t()) :: %{key: String.t() | nil, version: String.t() | nil}
  def pack_meta(path) when is_binary(path) do
    root = Path.expand(path)

    with :ok <- check_root(root),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(Path.join(root, "pack.yaml")),
         {:ok, %{data: %{} = data}} <- read_yaml(root, "pack.yaml") do
      %{key: string_or_nil(data["key"]), version: string_or_nil(data["version"])}
    else
      _ -> %{key: nil, version: nil}
    end
  end

  defp string_or_nil(value) when is_binary(value), do: value
  defp string_or_nil(_value), do: nil

  # The walk

  defp check_root(root) do
    case File.lstat(root) do
      {:ok, %File.Stat{type: :directory}} ->
        :ok

      {:ok, %File.Stat{type: :symlink}} ->
        {:error, [error(".", "the pack directory is a symbolic link")]}

      {:ok, %File.Stat{}} ->
        {:error, [error(".", "the pack path is not a directory")]}

      {:error, _reason} ->
        {:error, [error(".", "the pack directory does not exist")]}
    end
  end

  # The walk stops with one error at the pack directory when the deadline of
  # the pack passes, when the pack holds more than max_walk_entries/0
  # entries, or when a directory lies deeper than max_walk_depth/0 levels.
  defp walk(root, deadline) do
    tree = %{
      files: MapSet.new(),
      dirs: MapSet.new(),
      errors: [],
      deadline: deadline,
      entries: 0,
      stopped: false
    }

    walk_dir(root, "", tree)
  end

  defp walk_dir(root, rel, tree) do
    cond do
      System.monotonic_time(:millisecond) >= tree.deadline ->
        stop_walk(
          tree,
          "the pack takes longer than #{parse_budget()[:pack_timeout_ms]} ms to load"
        )

      depth(rel) > @max_walk_depth ->
        stop_walk(tree, "the pack directory nests deeper than #{@max_walk_depth} levels")

      true ->
        list_dir(root, rel, tree)
    end
  end

  # `:file.list_dir_all/1` returns a name that is valid UTF-8 as a charlist
  # and any other name as a binary of its raw bytes. `File.ls/1` would drop
  # the latter, so that the walk would not see a link with such a name.
  defp list_dir(root, rel, tree) do
    case :file.list_dir_all(Path.join(root, rel)) do
      {:ok, entries} when tree.entries + length(entries) > @max_walk_entries ->
        stop_walk(tree, "the pack directory holds more than 20,000 entries")

      {:ok, entries} ->
        {names, raw_names} = Enum.split_with(entries, &is_list/1)
        tree = %{tree | entries: tree.entries + length(entries)}

        tree =
          raw_names
          |> Enum.sort()
          |> Enum.reduce(tree, fn raw, tree ->
            add_tree_error(
              tree,
              dir_label(rel),
              "the entry name `#{escape(raw)}` is not valid UTF-8"
            )
          end)

        names
        |> Enum.map(&List.to_string/1)
        |> Enum.sort()
        |> Enum.reduce(tree, &walk_entry(root, join(rel, &1), &2))

      {:error, reason} ->
        add_tree_error(
          tree,
          dir_label(rel),
          "cannot list the directory: #{:file.format_error(reason)}"
        )
    end
  end

  defp depth(""), do: 0
  defp depth(rel), do: rel |> String.split("/") |> length()

  defp stop_walk(tree, message),
    do: %{add_tree_error(tree, ".", message) | stopped: true}

  defp dir_label(""), do: "."
  defp dir_label(rel), do: rel

  # Keeps printable ASCII except the backtick and the backslash, and writes
  # every other byte as `\xNN`, so that the report holds valid UTF-8 only.
  defp escape(raw) do
    for <<byte <- raw>>, into: "" do
      if byte in 0x20..0x7E and byte not in [?`, ?\\],
        do: <<byte>>,
        else: "\\x" <> Base.encode16(<<byte>>)
    end
  end

  defp walk_entry(_root, _rel, %{stopped: true} = tree), do: tree

  defp walk_entry(root, rel, tree) do
    case File.lstat(Path.join(root, rel)) do
      {:ok, %File.Stat{type: :directory}} ->
        walk_dir(root, rel, %{tree | dirs: MapSet.put(tree.dirs, rel)})

      {:ok, %File.Stat{type: :regular}} ->
        %{tree | files: MapSet.put(tree.files, rel)}

      {:ok, %File.Stat{type: :symlink}} ->
        add_tree_error(tree, rel, "symbolic links are not allowed in a pack")

      {:ok, %File.Stat{}} ->
        add_tree_error(tree, rel, "only directories and regular files are allowed in a pack")

      {:error, reason} ->
        add_tree_error(
          tree,
          rel,
          "cannot read the file information: #{:file.format_error(reason)}"
        )
    end
  end

  defp add_tree_error(tree, rel, message),
    do: %{tree | errors: [error(rel, message) | tree.errors]}

  defp join("", name), do: name
  defp join(rel, name), do: rel <> "/" <> name

  # Top-level files

  # `used` holds the number of decoded bytes of the files read so far and the
  # deadline of the pack, or is :full once a file has crossed max_pack_bytes/0
  # or the deadline has passed; from then on the loader reads no further file.
  defp read_top_files(root, tree, used) do
    read_files(@top_files, used, fn name, used ->
      read_known_file(root, tree, name, name == "pack.yaml", used)
    end)
  end

  defp read_files(names, used, read) do
    {files, errors, used} =
      Enum.reduce(names, {%{}, [], used}, fn name, {files, errors, used} ->
        case read.(name, used) do
          {:ok, nil, used} -> {files, errors, used}
          {:ok, doc, used} -> {Map.put(files, name, doc), errors, used}
          {:error, file_errors, used} -> {files, [file_errors | errors], used}
        end
      end)

    {files, concat(errors), used}
  end

  defp read_known_file(_root, _tree, _rel, _required?, :full), do: {:ok, nil, :full}

  defp read_known_file(root, tree, rel, required?, used) do
    cond do
      MapSet.member?(tree.files, rel) ->
        within_deadline(rel, used, fn ->
          root |> read_yaml(rel) |> charge(rel, used, & &1.data)
        end)

      MapSet.member?(tree.dirs, rel) ->
        {:error, [error(rel, "expected a file, found a directory")], used}

      required? ->
        {:error, [error(rel, "missing file")], used}

      true ->
        {:ok, nil, used}
    end
  end

  # Adds the decoded size of a file that loaded to `used`. The file at which
  # the sum exceeds the budget gets an error, and `used` becomes :full.
  defp charge({:ok, value}, rel, used, decoded) do
    total = used.bytes + :erlang.external_size(decoded.(value))

    if total > @max_pack_bytes,
      do: {:error, [error(rel, "the pack holds more than 32 MiB of text once decoded")], :full},
      else: {:ok, value, %{used | bytes: total}}
  end

  defp charge({:error, errors}, _rel, used, _decoded), do: {:error, errors, used}

  # Reads the file `rel` with `read` while the deadline of the pack has not
  # passed; otherwise the file gets an error, and the loader stops reading.
  defp within_deadline(rel, used, read) do
    if System.monotonic_time(:millisecond) < used.deadline do
      read.()
    else
      budget = parse_budget()[:pack_timeout_ms]
      {:error, [error(rel, "the pack takes longer than #{budget} ms to load")], :full}
    end
  end

  # Joins lists of errors that a reduce collected in reverse order.
  defp concat(reversed_lists), do: reversed_lists |> Enum.reverse() |> Enum.concat()

  # Modules

  defp read_modules(root, tree, used) do
    dirs = module_dirs(tree)

    cond do
      not MapSet.member?(tree.dirs, "modules") ->
        {[], [error("modules", "missing directory `modules`")], used}

      dirs == [] ->
        {[], [error("modules", "the directory `modules` holds no module directory")], used}

      true ->
        read_module_dirs(root, tree, dirs, used)
    end
  end

  defp read_module_dirs(root, tree, dirs, used) do
    {modules, errors, used} =
      Enum.reduce(dirs, {[], [], used}, fn dir, {modules, errors, used} ->
        case read_module(root, tree, dir, used) do
          {:ok, module, used} -> {[module | modules], errors, used}
          {:error, module_errors, used} -> {modules, [module_errors | errors], used}
        end
      end)

    {Enum.reverse(modules), concat(errors), used}
  end

  defp module_dirs(%{dirs: dirs}) do
    dirs
    |> Enum.flat_map(fn
      "modules/" <> name -> if String.contains?(name, "/"), do: [], else: [name]
      _other -> []
    end)
    |> Enum.sort()
  end

  defp read_module(root, tree, dir, used) do
    base = "modules/" <> dir

    name_errors =
      if Cast.key?(dir),
        do: [],
        else: [error(base, "module directory name `#{dir}` does not match the key format")]

    {files, file_errors, used} = read_module_files(root, tree, base, used)
    {lessons, lesson_errors, used} = read_lessons(root, tree, base, used)

    case name_errors ++ file_errors ++ lesson_errors do
      [] -> {:ok, %{dir: dir, files: files, lessons: lessons}, used}
      errors -> {:error, errors, used}
    end
  end

  defp read_module_files(root, tree, base, used) do
    read_files(@module_files, used, fn name, used ->
      read_known_file(root, tree, base <> "/" <> name, name == "module.yaml", used)
    end)
  end

  defp read_lessons(root, tree, base, used) do
    lessons_dir = base <> "/lessons"

    names =
      tree.files
      |> Enum.flat_map(&lesson_name(&1, lessons_dir <> "/"))
      |> Enum.sort_by(&String.replace_suffix(&1, ".md", ""))

    cond do
      not MapSet.member?(tree.dirs, lessons_dir) ->
        {[], [error(lessons_dir, "missing directory `lessons`")], used}

      names == [] ->
        {[], [error(lessons_dir, "the directory `lessons` holds no `.md` file")], used}

      true ->
        read_lesson_files(root, lessons_dir, names, used)
    end
  end

  defp read_lesson_files(root, lessons_dir, names, used) do
    {lessons, errors, used} =
      Enum.reduce(names, {[], [], used}, fn
        _name, {lessons, errors, :full} ->
          {lessons, errors, :full}

        name, {lessons, errors, used} ->
          case read_lesson(root, lessons_dir, name, used) do
            {:ok, lesson, used} -> {[lesson | lessons], errors, used}
            {:error, more, used} -> {lessons, [more | errors], used}
          end
      end)

    {Enum.reverse(lessons), concat(errors), used}
  end

  defp lesson_name(rel, prefix) do
    with true <- String.starts_with?(rel, prefix),
         name = String.replace_prefix(rel, prefix, ""),
         false <- String.contains?(name, "/"),
         true <- String.ends_with?(name, ".md") do
      [name]
    else
      _ -> []
    end
  end

  defp read_lesson(root, lessons_dir, name, used) do
    rel = lessons_dir <> "/" <> name
    key = String.replace_suffix(name, ".md", "")

    within_deadline(rel, used, fn ->
      result =
        with :ok <- check_lesson_key(rel, key),
             {:ok, text} <- read_text(root, rel),
             {:ok, front_text, body, body_line} <- split_front_matter(rel, text) do
          parse_lesson(rel, key, front_text, body, body_line)
        end

      charge(result, rel, used, &{&1.front.data, &1.blocks})
    end)
  end

  defp check_lesson_key(rel, key) do
    if Cast.key?(key),
      do: :ok,
      else: {:error, [error(rel, "lesson key `#{key}` does not match the key format")]}
  end

  defp parse_lesson(rel, key, front_text, body, body_line) do
    front = parse_yaml(rel, front_text, 2)

    # The errors are shortened here already, because a message can quote a
    # line of the body as long as the file.
    blocks =
      case Directives.split(body, body_line) do
        {:ok, blocks} -> {:ok, blocks}
        {:error, errors} -> {:error, errors |> Enum.map(&Map.put(&1, :file, rel)) |> finish()}
      end

    case {front, blocks} do
      {{:ok, front}, {:ok, blocks}} -> {:ok, %{key: key, file: rel, front: front, blocks: blocks}}
      _ -> {:error, error_list(front) ++ error_list(blocks)}
    end
  end

  defp error_list({:error, errors}), do: errors
  defp error_list({:ok, _value}), do: []

  defp split_front_matter(rel, text) do
    lines = String.split(text, ["\r\n", "\n"])

    with [first | rest] <- lines,
         true <- delimiter?(first),
         index when is_integer(index) <- Enum.find_index(rest, &delimiter?/1) do
      {front, [_close | body]} = Enum.split(rest, index)
      {:ok, Enum.join(front, "\n"), Enum.join(body, "\n"), index + 3}
    else
      nil -> {:error, [error(rel, "the front matter is not closed by a line `---`")]}
      _ -> {:error, [error(rel, "a lesson file starts with a front matter line `---`")]}
    end
  end

  defp delimiter?(line), do: String.trim_trailing(line) == "---"

  # YAML

  defp read_yaml(root, rel) do
    with {:ok, text} <- read_text(root, rel), do: parse_yaml(rel, text, 1)
  end

  # Both passes run in a process of their own with the budget of
  # parse_budget/0, so that a text the size and depth limits let through
  # cannot hold a scheduler or the memory of the caller.
  defp parse_yaml(rel, text, first_line) do
    budget = parse_budget()

    case run_within(budget, fn -> parse_passes(rel, text, first_line) end) do
      {:ok, result} ->
        result

      :timeout ->
        {:error,
         [error(rel, "the YAML text takes longer than #{budget[:timeout_ms]} ms to parse")]}

      :heap ->
        {:error, [error(rel, "the YAML text needs more memory to parse than the loader allows")]}
    end
  end

  defp parse_passes(rel, text, first_line) do
    with {:ok, lines} <- index(rel, text, first_line),
         {:ok, data} <- decode(rel, text, lines, first_line - 1) do
      {:ok, %{file: rel, data: data, lines: lines}}
    end
  end

  # A process killed for its heap size exits with :killed. Any other exit is a
  # defect of the parse and propagates to the caller. The parse process first
  # starts a watchdog that kills it when the caller dies; a link would do the
  # same, but a heap kill would then take the caller down as well.
  defp run_within(budget, fun) do
    parent = self()
    ref = make_ref()
    heap = %{size: budget[:max_heap_words], kill: true, error_logger: false}

    parse = fn ->
      watch_caller(parent, self())
      send(parent, {ref, fun.()})
    end

    {pid, monitor} = :erlang.spawn_opt(parse, [:monitor, {:max_heap_size, heap}])

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        {:ok, result}

      {:DOWN, ^monitor, :process, ^pid, :killed} ->
        :heap

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        exit(reason)
    after
      budget[:timeout_ms] ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])

        receive do
          {^ref, _late} -> :ok
        after
          0 -> :ok
        end

        :timeout
    end
  end

  defp watch_caller(caller, parser) do
    spawn(fn ->
      caller_ref = Process.monitor(caller)
      parser_ref = Process.monitor(parser)

      receive do
        {:DOWN, ^caller_ref, :process, _, _} -> Process.exit(parser, :kill)
        {:DOWN, ^parser_ref, :process, _, _} -> :ok
      end
    end)
  end

  # The index reports up to one error per node, so its errors are bounded
  # here already, inside the process of the parse, and not only by load/1.
  defp index(rel, text, first_line) do
    case LineIndex.build(text, first_line: first_line) do
      {:ok, lines} -> {:ok, lines}
      {:error, errors} -> {:error, errors |> Enum.map(&Map.put(&1, :file, rel)) |> finish()}
    end
  end

  defp decode(_rel, _text, lines, _offset) when not is_map_key(lines, []), do: {:ok, nil}

  defp decode(rel, text, _lines, offset) do
    case YamlElixir.read_from_string(text) do
      {:ok, data} ->
        {:ok, data}

      {:error, %ParsingError{} = parse_error} ->
        {:error, [parse_error |> LineIndex.syntax_error(offset) |> Map.put(:file, rel)]}
    end
  end

  defp read_text(root, rel) do
    path = Path.join(root, rel)

    with :ok <- check_size(path, rel),
         {:ok, text} <- read_file(path, rel),
         :ok <- check_utf8(text, rel),
         :ok <- check_control(text, rel) do
      {:ok, text}
    end
  end

  defp check_size(path, rel) do
    case File.lstat(path) do
      {:ok, %File.Stat{size: size}} when size > @max_file_bytes ->
        {:error, [error(rel, "the file is larger than 1 MiB (1,048,576 bytes)")]}

      {:ok, %File.Stat{}} ->
        :ok

      {:error, reason} ->
        {:error, [error(rel, "cannot read the file: #{:file.format_error(reason)}")]}
    end
  end

  # read_file/2 receives the pack root joined with a name that the loader's own
  # lstat walk listed and found to be a regular file of the pack format;
  # symbolic links are rejected before, so no read leaves the pack.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_file(path, rel) do
    case File.read(path) do
      {:ok, text} ->
        {:ok, text}

      {:error, reason} ->
        {:error, [error(rel, "cannot read the file: #{:file.format_error(reason)}")]}
    end
  end

  defp check_utf8(text, rel) do
    if String.valid?(text),
      do: :ok,
      else: {:error, [error(rel, "the file is not valid UTF-8 text")]}
  end

  defp check_control(text, rel) do
    case LineIndex.control_character(text) do
      nil ->
        :ok

      %{character: character, line: line, column: column} ->
        message =
          "control character #{character} is not allowed at line #{line}, column #{column}"

        {:error, [%{file: rel, line: line, message: message}]}
    end
  end

  defp error(file, message), do: %{file: file, line: 1, message: message}

  defp finish(errors), do: errors |> Entries.sort() |> Entries.limit(:error)
end
