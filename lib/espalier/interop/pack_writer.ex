defmodule Espalier.Interop.PackWriter do
  @moduledoc """
  Writes a published program back to disk as a content pack (task 0016,
  step 12) in the format of README section 11 and task 0008, step 5.

  `write/2` writes `Espalier.Interop.Payload.build/1` of a published
  program, and `write_payload/2` writes any payload in the shape of the
  normalized map of `Espalier.Catalog.Pack.Normalizer`. The loader, the
  directive splitter and the validator of task 0008 read the written pack
  back to a normalized map that equals the payload, so that an import of the
  written pack gives the payload of the program again and its publish
  archives no row. The target directory must be empty or missing; a missing
  directory is created.

  ## Files

    * `pack.yaml` with `schema`, `key`, `title`, `locale`, `license`,
      `version` and `alignment`. The payload holds `alignment` with the
      default `strict` filled in, so the file always names it.
    * `sources.yaml`, `glossary.yaml`, `segments.yaml`, `stations.yaml`,
      `qualifications.yaml` and `formats.yaml`, each when its list is not
      empty, and `feedback.yaml` when the program has a `feedback` station.
      The normalizer merges `intro` and `questions` of `feedback.yaml` into
      the `config` of that station, and the writer moves both back.
    * Per module the directory `modules/<number>-<slug>/`. The number is
      padded with zeros to two digits, or to the digits of the largest
      module number, and the slug is the module title in lowercase ASCII
      letters and digits joined by hyphens, at most 40 characters long (the
      directory is `modules/<number>/` when no such character remains). The
      payload holds no directory name, and the loader takes the module from
      `number` of `module.yaml`. The directory holds `module.yaml`, the list
      files `objectives.yaml`, `rules.yaml`, `items.yaml` and
      `assessment.yaml`, each when its list is not empty, and one file
      `lessons/<lesson key>.md` per lesson, because the loader takes the
      lesson key from the file name.

  ## Fields

  Every field of an entry is written, in the order of task 0008, step 5,
  with these exceptions, for which the normalizer fills in the same value
  when the field is absent:

    * a field without value (`url` of a source, `domain` of an objective,
      `lesson` of an exam item, `validity_months` and `refresher_mode` of a
      qualification, `module` of a station of another kind than `module`);
    * an empty list or map in the places that task 0016, step 12 names:
      `areas_elsewhere` of a module, `objectives` of an item or a format,
      and `cite` of a rule or an item;
    * the empty `options` or `config` of an item and the empty `options` of
      a feedback question, because each item kind takes one of the two and a
      question of kind `scale` or `free_text` takes no options;
    * `position` of a qualification: the writer lists the qualifications in
      the order of the payload, and without `position` the normalizer keeps
      the order of the file.

  The target of a `module_completed` requirement is written as the integer
  that the validator expects, and the normalizer turns it back into the
  string of the payload.

  A lesson file holds the front matter with `title` and `position` and one
  container directive per block with the attributes `provenance`,
  `collapsed_on`, `cite`, `key` (the `placeholder_key`), and for a `figure`
  or a `video` block (task 0018) `src`, `alt`, `decorative`, `size`,
  `title`, `embed`, `poster` and `captions`, in this order, where the block
  has them. A value of lowercase letters, digits, `_`, `,` and `-` stands
  bare, every other value in double quotes. The body follows the opening
  line unchanged.

  ## Media

  A `media/` reference of a block is written with its delivery path
  (`Espalier.Catalog.Pack.MediaPath.delivery_path/1`), and the media files
  of the payload are copied from the media store to these paths: images as
  `.webp`, SVG files as `.svg`, videos as `.webm` and captions as `.vtt`.
  `media_files/1` lists the image, SVG and video files and
  `captions_files/1` the captions with their assets. `write/2` reads the
  payload and the asset rows and copies the files inside the transaction
  that holds the shared lock of the program, so no publish of the program
  can run meanwhile, its `program_media` rows stay, a deletion of their
  assets answers `asset_in_use`, and no copied file can be removed before
  the copy ends. A pack on disk therefore holds every media file of its
  lessons in its delivery format. A pack imported again on the same
  installation finds its assets by the digests of the delivery files.

  ## YAML

  `Ymlr` encodes each string, and the writer lays out maps and lists in
  block style with the keys in field order, as ymlr does. A string keeps its
  exact value:

    * a one-line string stays as ymlr writes it, plain or in single quotes,
      unless ymlr chooses double quotes or the string holds U+FEFF, or ymlr
      writes it plain and a YAML reader could take it for another type: a
      text of digits, signs, dots, `_`, `:`, `e`, `t`, `z` and spaces that
      starts with a digit, a sign or a dot (`1.0.0`, `2026-03-01`, `.5`,
      `12:30`), a spelling of NaN or infinity of YAML 1.2 (`.nan`, `.NaN`,
      `.NAN`, `.inf`, `.Inf`, `.INF`, each also after `-` or `+`), a text
      with a tab, `=` or `<<`. Each of these is double-quoted;
    * a multi-line string becomes the literal block scalar of ymlr (`|-`)
      when it starts with a character other than whitespace, does not end
      with a line break, holds no line of spaces and tabs only, and holds
      only characters that need no escape; any other multi-line string is
      double-quoted. The front matter of a lesson file loses the line break
      before its closing `---`, so no block scalar there may keep one;
    * a double-quoted string is `JSON.encode!/1` of the string, a valid
      YAML scalar, with `\\uXXXX` for DEL, the C1 controls, U+2028, U+2029,
      U+FEFF, U+FFFE and U+FFFF, which a YAML reader takes as line breaks or
      rejects unescaped.

  A map key goes through the same rules, always on one line.

  The writer raises `ArgumentError` for a block that no lesson file can
  hold: a body line that starts with `:::`, or a `cite` entry with a comma
  or a double quote. The validator of task 0008 admits no such block.
  """

  import Ecto.Query, only: [from: 2]

  alias Espalier.Catalog.Pack.{MediaPath, Publisher}
  alias Espalier.Catalog.Program
  alias Espalier.Interop.Payload
  alias Espalier.Media.{Asset, Store}
  alias Espalier.Repo

  @areas ~w(subject method self social)
  @max_slug 40

  # The time that the read of the payload takes at most, on top of the wait
  # for a publish of the same pack.
  @read_margin :timer.minutes(1)

  # A string that ymlr leaves unquoted and that a YAML reader could take for
  # another type: a number, a date or a time of YAML 1.2 or YAML 1.1
  # (`.5`, `1_000`, `12:30`, `2026-03-01`, `1.0.0` for safety), a spelling
  # of NaN or infinity of YAML 1.2 with an optional sign (`.NaN`, `-.Inf`,
  # `+.inf`), a text with a tab, which can end a key (`a:\tb`), and the
  # YAML 1.1 types `=` and `<<`.
  @retyped ~r/\A[-+.0-9][-+.0-9_:eEtTzZ ]*\z|\A[-+]?\.(?:nan|NaN|NAN|inf|Inf|INF)\z|\t|\A(?:=|<<)\z/

  # Characters that need no escape in a literal block scalar: tab, line
  # feed, printable ASCII and the printable characters above U+009F, except
  # U+00A0, U+2028, U+2029 and U+FEFF.
  @literal ~r/\A[\t\n\x{20}-\x{7E}\x{A1}-\x{2027}\x{202A}-\x{D7FF}\x{E000}-\x{FEFE}\x{FF00}-\x{FFFD}\x{10000}-\x{10FFFF}]*\z/u

  # A line of spaces and tabs only, which a literal block scalar can take
  # for indentation.
  @blank_line ~r/^[ \t]+$/m

  # Characters that JSON.encode!/1 leaves unescaped and that a YAML reader
  # takes as line breaks or rejects.
  @escaped ~r/[\x{7F}-\x{9F}\x{2028}\x{2029}\x{FEFF}\x{FFFE}\x{FFFF}]/u

  # An attribute value that stands without quotes.
  @bare ~r/\A[a-z0-9_,-]+\z/

  @typedoc """
  Why a pack was not written: the program is not published, the target is
  a directory that is not empty or no directory, or a file operation failed
  on the path relative to the target (`.` for the target itself).
  """
  @type error ::
          :not_published | :not_empty | :not_directory | {:file, Path.t(), File.posix()}

  @doc """
  Writes the payload of the published `program` as a content pack into the
  directory `path`, which must be empty or missing.

  The program is read again and its payload built in one transaction that
  first takes `pg_advisory_xact_lock_shared(hashtext(<program slug>))`. The
  slug is the pack key, so the lock conflicts with the exclusive lock of
  `Espalier.Catalog.Pack.Publisher` on the same pack: a publish of the pack
  that runs ends before the payload is read, and one that starts waits
  until it is read, so the payload comes from one published version. The
  `:timeout` of the transaction is `Publisher.transaction_timeout/0` plus
  one minute, because the lock waits for a publish. The files are written
  and the media files copied inside that transaction, while the lock is
  held (section "Media" of the moduledoc).

  Returns `{:ok, version}` with the `version` of the pack it wrote, which
  can be newer than the `pack_version` of `program` when a publish ran in
  between, and `{:error, :not_published}` for a program that is not
  published, also when the stored program is no longer published, without
  touching `path`.
  """
  @spec write(Ecto.Schema.schema(), Path.t()) :: {:ok, String.t()} | {:error, error()}
  def write(%Program{status: :published} = program, path) when is_binary(path) do
    published_payload(program, fn payload ->
      with :ok <- prepare(path),
           :ok <- write_files(render(payload), path),
           :ok <- copy_media(payload, path),
           do: {:ok, payload["version"]}
    end)
  end

  def write(%Program{}, path) when is_binary(path), do: {:error, :not_published}

  @doc """
  Writes `payload`, a map in the shape of the normalized map of a content
  pack, as a content pack into the directory `path`, which must be empty or
  missing.
  """
  @spec write_payload(Payload.t(), Path.t()) :: :ok | {:error, error()}
  def write_payload(payload, path) when is_map(payload) and is_binary(path) do
    with :ok <- prepare(path),
         :ok <- write_files(render(payload), path),
         do: copy_media(payload, path)
  end

  @doc """
  The image, SVG and video files of the media of `payload` as `{delivery
  path, asset}`, ordered by path. A path whose asset no longer exists is
  left out.
  """
  @spec media_files(Payload.t()) :: [{String.t(), Asset.t()}]
  def media_files(payload), do: payload |> media_assets() |> Enum.reject(&captions?/1)

  @doc """
  The captions files of the media of `payload` as `{path, asset}`, ordered
  by path. A path whose asset no longer exists is left out.
  """
  @spec captions_files(Payload.t()) :: [{String.t(), Asset.t()}]
  def captions_files(payload), do: payload |> media_assets() |> Enum.filter(&captions?/1)

  defp captions?({_path, %Asset{kind: kind}}), do: kind == :captions

  defp media_assets(payload) do
    media = Map.get(payload, "media") || []
    ids = Enum.map(media, & &1["asset_id"])
    assets = Map.new(Repo.all(from(a in Asset, where: a.id in ^ids)), &{&1.id, &1})

    for entry <- Enum.sort_by(media, & &1["path"]),
        %Asset{} = asset <- [Map.get(assets, entry["asset_id"])],
        do: {MediaPath.delivery_path(entry["path"]), asset}
  end

  # The delivery files of the store at their delivery paths. A path whose
  # asset is gone or not ready answers the error of a missing file.
  # sobelow_skip ["Traversal.FileModule"]
  defp copy_media(payload, path) do
    found = media_files(payload) ++ captions_files(payload)

    expected =
      for entry <- Map.get(payload, "media") || [], do: MediaPath.delivery_path(entry["path"])

    case expected -- Enum.map(found, &elem(&1, 0)) do
      [missing | _rest] -> {:error, {:file, missing, :enoent}}
      [] -> Enum.reduce_while(found, :ok, &copy_entry(&1, &2, path))
    end
  end

  defp copy_entry({rel, asset}, :ok, path) do
    case copy_asset(asset, Path.join(path, rel)) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, {:file, rel, reason}}}
    end
  end

  # The source comes from the store, the target from the caller's directory
  # and a delivery path that passed MediaPath.check/1.
  # sobelow_skip ["Traversal.FileModule"]
  defp copy_asset(%Asset{status: :ready, sha256: sha256, ext: ext}, target) do
    with :ok <- File.mkdir_p(Path.dirname(target)),
         do: File.cp(Store.path(sha256, ext), target)
  end

  defp copy_asset(%Asset{}, _target), do: {:error, :enoent}

  @doc """
  Returns the files of the content pack of `payload` as a list of
  `{relative path, content}`: the files that `write_payload/2` writes, in
  the order of the moduledoc (task 0016a: the files of a draft of the pack
  workbench).
  """
  @spec render(Payload.t()) :: [{String.t(), String.t()}]
  def render(payload) when is_map(payload), do: files(payload)

  @doc """
  Reads the payload of the published `program` as `write/2` does, in one
  transaction under `pg_advisory_xact_lock_shared(hashtext(<program slug>))`
  with its timeout, and returns `{:ok, files}` with the files of
  `render/1`, or `{:error, :not_published}` for a program that is not
  published, also when the stored program is no longer published.
  """
  @spec render_program(Ecto.Schema.schema()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, :not_published}
  def render_program(%Program{status: :published} = program) do
    published_payload(program, &{:ok, render(&1)})
  end

  def render_program(%Program{}), do: {:error, :not_published}

  @doc """
  Runs `fun` with the payload of the published `program` inside the
  transaction that holds the shared lock of the program, as `write/2`
  reads it, and returns its result, or `{:error, :not_published}`. The
  workbench reads the captions of a program from the store this way (task
  0018).
  """
  @spec with_program_payload(Ecto.Schema.schema(), (Payload.t() ->
                                                      {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def with_program_payload(%Program{status: :published} = program, fun) when is_function(fun, 1),
    do: published_payload(program, fun)

  def with_program_payload(%Program{}, _fun), do: {:error, :not_published}

  ## Payload

  # A program keeps its slug across publishes, because the publisher upserts
  # it by the slug. `fun` runs with the payload while the lock is held.
  defp published_payload(%Program{id: id, slug: slug}, fun) do
    Repo.transact(
      fn ->
        Repo.query!("SELECT pg_advisory_xact_lock_shared(hashtext($1))", [slug])

        case Repo.get(Program, id) do
          %Program{status: :published} = program -> fun.(Payload.build(program))
          _other -> {:error, :not_published}
        end
      end,
      timeout: read_timeout()
    )
  end

  defp read_timeout do
    case Publisher.transaction_timeout() do
      :infinity -> :infinity
      timeout -> timeout + @read_margin
    end
  end

  ## Target

  # The path comes from the caller, the command line of `mix espalier.export`
  # or a test; no request reaches it. A missing directory is created with
  # its missing parents.
  # sobelow_skip ["Traversal.FileModule"]
  defp prepare(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        case File.ls(path) do
          {:ok, []} -> :ok
          {:ok, _entries} -> {:error, :not_empty}
          {:error, reason} -> {:error, {:file, ".", reason}}
        end

      {:ok, %File.Stat{}} ->
        {:error, :not_directory}

      {:error, :enoent} ->
        with {:error, reason} <- File.mkdir_p(path), do: {:error, {:file, ".", reason}}

      {:error, reason} ->
        {:error, {:file, ".", reason}}
    end
  end

  # Every relative path comes from files/1: fixed names, a module directory
  # in the key format and lesson keys, which the validator restricts to the
  # key format, so no write leaves the target directory.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_files(files, path) do
    Enum.reduce_while(files, :ok, fn {rel, content}, :ok ->
      file = Path.join(path, rel)

      with :ok <- File.mkdir_p(Path.dirname(file)),
           :ok <- File.write(file, content) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {:file, rel, reason}}}
      end
    end)
  end

  ## Files

  defp files(payload) do
    stations = payload["stations"]
    modules = payload["modules"]
    width = number_width(modules)

    [{"pack.yaml", yaml(pack(payload))}] ++
      list_file("sources.yaml", payload["sources"], &source/1) ++
      list_file("glossary.yaml", payload["glossary"], &term/1) ++
      list_file("segments.yaml", payload["segments"], &segment/1) ++
      list_file("stations.yaml", stations, &station/1) ++
      feedback_file(stations) ++
      list_file("qualifications.yaml", payload["qualifications"], &qualification/1) ++
      list_file("formats.yaml", payload["formats"], &format/1) ++
      Enum.flat_map(modules, &module_files(&1, width))
  end

  defp list_file(_name, [], _entry), do: []
  defp list_file(name, entries, entry), do: [{name, yaml(Enum.map(entries, entry))}]

  defp pack(payload) do
    fields([
      {"schema", payload["schema"]},
      {"key", payload["key"]},
      {"title", payload["title"]},
      {"locale", payload["locale"]},
      {"license", payload["license"]},
      {"version", payload["version"]},
      {"alignment", payload["alignment"]}
    ])
  end

  defp source(source) do
    fields([
      {"key", source["key"]},
      {"title", source["title"]},
      {"publisher", source["publisher"]},
      {"url", source["url"]},
      {"edition_date", source["edition_date"]},
      {"retrieved_on", source["retrieved_on"]},
      {"kind", source["kind"]}
    ])
  end

  defp term(term) do
    fields([
      {"slug", term["slug"]},
      {"label", term["label"]},
      {"short_text", term["short_text"]}
    ])
  end

  defp segment(segment) do
    fields([
      {"key", segment["key"]},
      {"label", segment["label"]},
      {"description", segment["description"]},
      {"default_path", segment["default_path"]}
    ])
  end

  defp station(%{"kind" => kind} = station) do
    config =
      if kind == "feedback",
        do: Map.drop(station["config"], ["intro", "questions"]),
        else: station["config"]

    fields([
      {"kind", kind},
      {"title", station["title"]},
      {"module", station["module"]},
      {"config", json(config)}
    ])
  end

  defp feedback_file(stations) do
    case Enum.find(stations, &(&1["kind"] == "feedback")) do
      nil ->
        []

      %{"config" => config} ->
        feedback =
          fields([
            {"intro", config["intro"]},
            {"questions", Enum.map(config["questions"], &question/1)}
          ])

        [{"feedback.yaml", yaml(feedback)}]
    end
  end

  defp question(question) do
    fields([
      {"key", question["key"]},
      {"kind", question["kind"]},
      {"label", question["label"]},
      {"options", non_empty(Enum.map(question["options"], &key_label/1))}
    ])
  end

  defp qualification(qualification) do
    fields([
      {"code", qualification["code"]},
      {"title", qualification["title"]},
      {"audience", qualification["audience"]},
      {"unlocks", qualification["unlocks"]},
      {"add_on", qualification["add_on"]},
      {"validity_kind", qualification["validity_kind"]},
      {"validity_months", qualification["validity_months"]},
      {"refresher_mode", qualification["refresher_mode"]},
      {"phases", qualification["phases"]},
      {"requirements", Enum.map(qualification["requirements"], &requirement/1)}
    ])
  end

  # The validator takes the module number of a `module_completed` target as
  # an integer, and the payload holds it as a string.
  defp requirement(%{"kind" => "module_completed", "target" => target}),
    do: fields([{"kind", "module_completed"}, {"target", String.to_integer(target)}])

  defp requirement(requirement),
    do: fields([{"kind", requirement["kind"]}, {"target", requirement["target"]}])

  defp format(format) do
    fields([
      {"key", format["key"]},
      {"title", format["title"]},
      {"description", format["description"]},
      {"phases", format["phases"]},
      {"attendance_counts", format["attendance_counts"]},
      {"objectives", non_empty(format["objectives"])}
    ])
  end

  ## Modules

  defp module_files(module, width) do
    base = "modules/" <> module_dir(module, width)

    [{base <> "/module.yaml", yaml(module_yaml(module))}] ++
      list_file(base <> "/objectives.yaml", module["objectives"], &objective/1) ++
      list_file(base <> "/rules.yaml", module["rules"], &rule/1) ++
      list_file(base <> "/items.yaml", module["items"], &item/1) ++
      list_file(base <> "/assessment.yaml", module["assessments"], &assessment/1) ++
      Enum.map(module["lessons"], &{"#{base}/lessons/#{&1["key"]}.md", lesson(&1)})
  end

  defp number_width(modules) do
    modules
    |> Enum.map(&(&1["number"] |> Integer.to_string() |> String.length()))
    |> Enum.max(fn -> 2 end)
    |> max(2)
  end

  defp module_dir(module, width) do
    number = module["number"] |> Integer.to_string() |> String.pad_leading(width, "0")

    case slug(module["title"]) do
      "" -> number
      slug -> number <> "-" <> slug
    end
  end

  @doc """
  The slug of a module directory: `title` in lowercase ASCII letters and
  digits, letters without their accents, every other run of characters
  joined into one hyphen, at most #{@max_slug} characters and without a
  leading or trailing hyphen. The result is empty when no such character
  remains. The workbench of task 0016a takes the key of an empty pack from
  it.
  """
  @spec slug(String.t()) :: String.t()
  def slug(title) when is_binary(title) do
    title
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.slice(0, @max_slug)
    |> String.trim("-")
  end

  defp module_yaml(module) do
    fields([
      {"number", module["number"]},
      {"title", module["title"]},
      {"summary", module["summary"]},
      {"phases", module["phases"]},
      {"domains", module["domains"]},
      {"single_path", module["single_path"]},
      {"refresher_unit", module["refresher_unit"]},
      {"areas_elsewhere", areas_elsewhere(module["areas_elsewhere"])}
    ])
  end

  defp areas_elsewhere(areas) when areas == %{}, do: nil

  # The payload holds only the areas that the module names.
  defp areas_elsewhere(areas) do
    fields(
      for area <- @areas, Map.has_key?(areas, area) do
        %{"where" => where, "reason" => reason} = Map.fetch!(areas, area)
        {area, fields([{"where", where}, {"reason", reason}])}
      end
    )
  end

  defp objective(objective) do
    fields([
      {"key", objective["key"]},
      {"statement", objective["statement"]},
      {"area", objective["area"]},
      {"depth", objective["depth"]},
      {"phase", objective["phase"]},
      {"domain", objective["domain"]},
      {"taught_in", objective["taught_in"]}
    ])
  end

  defp rule(rule) do
    fields([
      {"number", rule["number"]},
      {"statement", rule["statement"]},
      {"action", rule["action"]},
      {"cite", non_empty(rule["cite"])}
    ])
  end

  defp item(item) do
    fields([
      {"key", item["key"]},
      {"kind", item["kind"]},
      {"lesson", item["lesson"]},
      {"stem", item["stem"]},
      {"core", item["core"]},
      {"phase", item["phase"]},
      {"provenance", item["provenance"]},
      {"objectives", non_empty(item["objectives"])},
      {"rules", item["rules"]},
      {"reveals", item["reveals"]},
      {"cite", non_empty(item["cite"])},
      {"options", non_empty(Enum.map(item["options"], &option/1))},
      {"config", item_config(item["config"])}
    ])
  end

  defp option(option) do
    fields([
      {"key", option["key"]},
      {"label", option["label"]},
      {"correct", option["correct"]},
      {"feedback", option["feedback"]}
    ])
  end

  # The configs in the shapes of the normalizer, with the keys in the order
  # of task 0008, step 5; any other map in key order.
  defp item_config(config) when config == %{}, do: nil

  defp item_config(%{"slots" => slots} = config) when map_size(config) == 1 do
    fields([
      {"slots",
       Enum.map(slots, fn slot ->
         fields([
           {"key", slot["key"]},
           {"label", slot["label"]},
           {"options", Enum.map(slot["options"], &option/1)}
         ])
       end)}
    ])
  end

  defp item_config(
         %{"categories" => categories, "cases" => cases, "expected" => expected} = config
       )
       when map_size(config) == 3 do
    fields([
      {"categories", Enum.map(categories, &key_label/1)},
      {"cases",
       Enum.map(cases, fn entry ->
         fields([
           {"key", entry["key"]},
           {"text", entry["text"]},
           {"feedback", entry["feedback"]}
         ])
       end)},
      {"expected", json(expected)}
    ])
  end

  defp item_config(%{"checks" => checks} = config) when map_size(config) == 1 do
    fields([
      {"checks",
       Enum.map(checks, fn check ->
         fields([
           {"key", check["key"]},
           {"label", check["label"]},
           {"required", check["required"]}
         ])
       end)}
    ])
  end

  defp item_config(config), do: json(config)

  defp assessment(assessment) do
    fields([
      {"key", assessment["key"]},
      {"title", assessment["title"]},
      {"kind", assessment["kind"]},
      {"counts_for_credential", assessment["counts_for_credential"]},
      {"max_wrong", assessment["max_wrong"]},
      {"core_required", assessment["core_required"]},
      {"items", assessment["items"]}
    ])
  end

  defp key_label(entry), do: fields([{"key", entry["key"]}, {"label", entry["label"]}])

  ## Lessons

  defp lesson(lesson) do
    front = yaml(fields([{"title", lesson["title"]}, {"position", lesson["position"]}]))
    "---\n" <> front <> "---\n\n" <> Enum.map_join(lesson["blocks"], "\n", &block/1)
  end

  defp block(block) do
    attributes =
      ([
         {"provenance", block["provenance"]},
         {"collapsed_on", list_attribute(block["collapsed_on"])},
         {"cite", list_attribute(Enum.map(block["cite"], &cite!/1))},
         {"key", block["placeholder_key"]}
       ] ++ media_attributes(block["media"]))
      |> Enum.reject(fn {_name, value} -> is_nil(value) end)
      |> Enum.map_join(" ", &attribute/1)

    ":::#{block["kind"]}{#{attributes}}\n#{body!(block["body"])}\n:::\n"
  end

  # The attributes of a figure or a video with the delivery paths of their
  # media/ references.
  defp media_attributes(%{} = media) do
    captions =
      for %{"src" => src, "lang" => lang} <- media["captions"] || [] do
        delivery(src) <> ":" <> lang
      end

    [
      {"src", delivery(media["src"])},
      {"alt", media["alt"]},
      {"decorative", if(media["decorative"] == true, do: "true")},
      {"size", media["size"]},
      {"title", media["title"]},
      {"embed", media["embed"]},
      {"poster", delivery(media["poster"])},
      {"captions", list_attribute(captions)}
    ]
  end

  defp media_attributes(_media), do: []

  defp delivery("media/" <> _rest = path), do: MediaPath.delivery_path(path)
  defp delivery(value), do: value

  defp list_attribute([]), do: nil
  defp list_attribute(values), do: Enum.join(values, ",")

  # The splitter separates the entries of `cite` at commas and ends a
  # quoted value at the next double quote.
  defp cite!(cite) do
    if String.contains?(cite, [",", "\""]),
      do: raise(ArgumentError, "the `cite` entry #{inspect(cite)} holds a comma or a quote"),
      else: cite
  end

  defp attribute({name, value}) do
    if Regex.match?(@bare, value), do: "#{name}=#{value}", else: ~s(#{name}="#{value}")
  end

  # The splitter reads a line that starts with `:::` as a directive line.
  defp body!(body) do
    if body |> String.split(["\r\n", "\n"]) |> Enum.any?(&String.starts_with?(&1, ":::")),
      do: raise(ArgumentError, "a block body holds a line that starts with `:::`"),
      else: body
  end

  ## YAML

  # Ordered fields: the pairs whose value is nil are left out.
  defp fields(pairs), do: {:fields, Enum.reject(pairs, fn {_key, value} -> is_nil(value) end)}

  defp non_empty([]), do: nil
  defp non_empty(list), do: list

  # A JSON value of the payload (a station config, the `expected` map of a
  # classification): maps in key order, lists in their order.
  defp json(map) when is_map(map),
    do: {:fields, map |> Enum.sort() |> Enum.map(fn {key, value} -> {key, json(value)} end)}

  defp json(list) when is_list(list), do: Enum.map(list, &json/1)
  defp json(value), do: value

  defp yaml(data), do: IO.iodata_to_binary([node(data, 0), "\n"])

  # The layout of ymlr: the entries of a map at `level` and the elements of
  # a list at `level` are indented by two spaces per level.
  defp node({:fields, []}, _level), do: "{}"

  defp node({:fields, pairs}, level) do
    pairs
    |> Enum.map(fn {key, value} -> [key(key), ":" | member(value, level)] end)
    |> Enum.intersperse(indent(level))
  end

  defp node([], _level), do: "[]"

  defp node(list, level) when is_list(list) do
    list
    |> Enum.map(&["- " | node(&1, level + 1)])
    |> Enum.intersperse(indent(level))
  end

  defp node(value, level), do: scalar(value, level)

  defp member(value, level) when value in [[], {:fields, []}], do: [" " | node(value, level)]

  defp member({:fields, _pairs} = value, level),
    do: [indent(level), "  " | node(value, level + 1)]

  defp member(list, level) when is_list(list), do: [indent(level), "  " | node(list, level + 1)]
  defp member(value, level), do: [" " | scalar(value, level + 1)]

  defp indent(level), do: ["\n" | List.duplicate("  ", level)]

  defp scalar(nil, _level), do: "null"
  defp scalar(value, _level) when is_boolean(value), do: Atom.to_string(value)
  defp scalar(value, _level) when is_integer(value), do: Integer.to_string(value)

  defp scalar(text, level) when is_binary(text) do
    if String.contains?(text, "\n") do
      if literal?(text), do: Ymlr.Encoder.encode(text, level, []), else: quoted(text)
    else
      single_line(text)
    end
  end

  defp key(text) do
    if String.contains?(text, "\n"), do: quoted(text), else: single_line(text)
  end

  defp single_line(text) do
    encoded = text |> Ymlr.Encoder.encode(0, []) |> IO.iodata_to_binary()

    cond do
      String.starts_with?(encoded, "\"") -> quoted(text)
      Regex.match?(@escaped, text) -> quoted(text)
      encoded == text and Regex.match?(@retyped, text) -> quoted(text)
      true -> encoded
    end
  end

  defp literal?(text) do
    not String.ends_with?(text, "\n") and Regex.match?(@literal, text) and
      not String.starts_with?(text, [" ", "\t", "\n"]) and
      not Regex.match?(@blank_line, text)
  end

  defp quoted(text) do
    text
    |> JSON.encode!()
    |> String.replace(@escaped, fn <<char::utf8>> ->
      "\\u" <> (char |> Integer.to_string(16) |> String.pad_leading(4, "0"))
    end)
  end
end
