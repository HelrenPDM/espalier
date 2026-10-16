defmodule Espalier.Catalog.Pack.Importer do
  @moduledoc """
  Validates a content pack directory and stores it as a `PackImport`
  (task 0008, step 9; README section 11).

  The importer runs `Espalier.Catalog.Pack.Loader.load/1` and, when the pack
  loads, `Espalier.Catalog.Pack.Validator.run/1`. An import without errors is
  `validated` and holds the normalized map of the pack in `payload`; an
  import with errors is `failed` and holds no payload. In both cases
  `report` holds the `errors` and the `warnings` of the validator with every
  member of their entries, so that the alignment entries keep `check`,
  `module` and `key`. The report is stored with string keys, so the returned
  import equals the import read back from the database.

  `Espalier.Catalog.Pack.Report.stored/2` bounds the report: at most 100
  entries per file and 1,000 per list, each followed by a closing entry for
  the entries left out, and every string member one line of at most 1,000
  characters. The report therefore stays a few MB at most, whatever the
  pack holds, and the loader bounds the decoded data of the pack, from which
  the payload is built, to 32 MiB (`Espalier.Catalog.Pack.Loader.max_pack_bytes/0`).

  `Espalier.Catalog.Pack.Publisher.publish/1` applies a validated import to
  the catalog tables. The upload of task 0015 calls `import/2` with the id of
  the signed-in author, and the mix tasks and the release function with
  `nil`.

  ## Media (task 0018, step 10)

  `Espalier.Catalog.Pack.Hosts.check/2` checks the external files and the
  embeds of the lessons against `MEDIA_EXTERNAL_HOSTS` and
  `MEDIA_EMBED_HOSTS` of the installation, or against the option `hosts:`
  (`%{external: [...], embed: [...]}`), and each finding is an error at the
  file and line of its block. After a successful validation, every file
  below `media/` that a block references is ingested into the media library
  (`Espalier.Media.ingest_pack_file/2`, origin `pack`); unreferenced files
  are not. The option `media: %{path => asset_id}` links those paths to
  existing assets instead of reading the files, which the workbench and the
  test fixtures use. A file whose bytes equal the delivery file of an asset
  that the program of the pack key uses (`program_media`) links to that
  asset in the same way, the asset at the same path first, so that a pack
  that `mix espalier.export` wrote imports without a media change also when
  two assets share that delivery file. An asset that the import links in
  one of these two ways gets the time of its last change set again, as an
  ingest of the same file does (`touch_linked/1`). Two referenced paths
  with the same delivery path, such as `media/photo.jpg` and
  `media/photo.png`, and every ingest error are errors at the path of the
  file, and the import fails.
  The payload gains `"media"`, a list of `%{"path", "asset_id", "kind"}`
  sorted by path, and `media_asset_ids` holds its asset ids, so that the
  uses of an asset need no scan of the payloads.
  """

  import Ecto.Query

  alias Espalier.Catalog.Pack.{Entries, Hosts, Loader, MediaPath, Report, Validator}
  alias Espalier.Catalog.Pack.Schema.Cast
  alias Espalier.Catalog.{PackImport, Program, ProgramMedia}
  alias Espalier.Media
  alias Espalier.Media.{Asset, Store}
  alias Espalier.Repo

  @typedoc "A `%Espalier.Catalog.PackImport{}`."
  @type pack_import :: Ecto.Schema.schema()

  @doc """
  Loads and validates the pack at `path` and inserts a `PackImport` with
  `imported_by_id` set to `actor_id`.

  Returns `{:ok, pack_import}` for a `validated` and for a `failed` import,
  and `{:error, changeset}` when the import cannot be stored. `pack_key` and
  `pack_version` hold the `key` and `version` of `pack.yaml` when they are
  texts of at most 255 characters without a NUL character, and stay `nil`
  otherwise, for example when `pack.yaml` cannot be read. A `validated`
  import always holds both, because the validator rejects a `key` or a
  `version` that does not fit its column.

  The insert does not rescue database errors. The validator rejects every
  value that the columns of `pack_imports` and of the catalog cannot hold
  (a NUL character, a string over 255 characters for a `varchar(255)`
  column, an integer over 2147483647), the loader rejects a pack whose
  decoded data exceeds 32 MiB, and `Espalier.Catalog.Pack.Report.stored/2`
  escapes NUL and every other control character in the report and bounds
  its size, so that the `report` and `payload` columns hold what the import
  stores.
  """
  @spec import(Path.t(), Ecto.UUID.t() | nil, keyword()) ::
          {:ok, pack_import()} | {:error, Ecto.Changeset.t()}
  def import(path, actor_id, opts \\ [])
      when is_binary(path) and (is_nil(actor_id) or is_binary(actor_id)) do
    path |> prepare(actor_id, opts) |> Repo.insert()
  end

  @doc """
  Loads and validates the pack at `path` and returns the changeset of its
  `PackImport`. It writes the media assets of the pack and their jobs, but
  not the import row, so that a caller can insert that row in a transaction
  of its own together with further rows (task 0015: the audit event of the
  upload). `import/3` inserts this changeset.

  Options: `media: %{path => asset_id}` and `hosts: %{external: hosts,
  embed: hosts}` (see the section "Media").
  """
  @spec prepare(Path.t(), Ecto.UUID.t() | nil, keyword()) :: Ecto.Changeset.t()
  def prepare(path, actor_id, opts \\ [])
      when is_binary(path) and (is_nil(actor_id) or is_binary(actor_id)) do
    PackImport.changeset(%PackImport{imported_by_id: actor_id}, attrs(path, actor_id, opts))
  end

  defp attrs(path, actor_id, opts) do
    case Loader.load(path) do
      {:ok, loaded} ->
        loaded
        |> Validator.run()
        |> add_errors(Hosts.check(loaded, hosts(opts)))
        |> with_media(loaded, actor_id, opts)
        |> run_attrs(loaded_meta(loaded))

      {:error, errors} ->
        failed_attrs(Loader.pack_meta(path), errors, [])
    end
  end

  defp hosts(opts) do
    Keyword.get_lazy(opts, :hosts, fn ->
      %{external: Media.external_hosts(), embed: Media.embed_hosts()}
    end)
  end

  defp add_errors(result, []), do: result

  defp add_errors(result, errors),
    do: %{result | errors: Entries.sort(result.errors ++ errors), payload: nil}

  # After a validation without errors: the referenced media files become
  # assets, and the payload names them.
  defp with_media(%{errors: [], payload: %{} = payload} = result, loaded, actor_id, opts) do
    paths = payload |> references() |> Enum.sort()
    files = Map.new(Map.get(loaded, :media, []), &{&1.path, &1})
    mapping = Keyword.get(opts, :media, %{})

    case collisions(paths) do
      [] ->
        unmapped =
          for path <- paths,
              not Map.has_key?(mapping, path),
              %{} = file <- [Map.get(files, path)],
              do: file

        mapping = Map.merge(mapping, program_media(payload["key"], unmapped))
        :ok = mapping |> Map.take(paths) |> Map.values() |> touch_linked()

        {entries, errors} =
          Enum.reduce(paths, {[], []}, &media_entry(&1, &2, files, mapping, actor_id))

        if errors == [] do
          entries = Enum.reverse(entries)
          %{result | payload: Map.put(payload, "media", entries)}
        else
          add_errors(result, Enum.reverse(errors))
        end

      errors ->
        add_errors(result, errors)
    end
  end

  defp with_media(result, _loaded, _actor_id, _opts), do: result

  defp media_entry(path, {entries, errors}, files, mapping, actor_id) do
    kind = path |> MediaPath.kind() |> Atom.to_string()

    case Map.fetch(mapping, path) do
      {:ok, asset_id} ->
        {[%{"path" => path, "asset_id" => asset_id, "kind" => kind} | entries], errors}

      :error ->
        file = Map.fetch!(files, path).file

        case Media.ingest_pack_file(%{path: file, file_name: path}, actor_id) do
          {:ok, asset, _created_or_existing} ->
            {[%{"path" => path, "asset_id" => asset.id, "kind" => kind} | entries], errors}

          {:error, reason} ->
            {entries, [%{file: path, line: 1, message: ingest_message(reason)} | errors]}
        end
    end
  end

  @doc """
  Links media files of a pack to the assets that the program of its pack
  key uses (task 0018, step 10). `media` holds the files as
  `Espalier.Catalog.Pack.Loader.media_file/0`, `%{path, file, bytes}` with
  the absolute path of the file. Returns `%{path => asset_id}` for every
  file that equals the delivery file of a `ready` asset of the
  `program_media` rows of the program whose slug is `slug`, the asset at
  the same path first; `%{}` for a `slug` that is no string or names no
  program with such assets.

  Two assets can share one delivery file, because two sources can convert
  to the same bytes, and the ingest takes the oldest of them; the asset of
  the program keeps a pack that `mix espalier.export` wrote from changing
  its media on a new import. Only a file with the extension and the size of
  a candidate is read for its digest. The importer applies it to the
  referenced files without a `media:` mapping, and
  `Espalier.Workbench.create_from_upload/4` to the media files of an
  archive.
  """
  @spec program_media(term(), [Loader.media_file()]) :: %{String.t() => Ecto.UUID.t()}
  def program_media(slug, [_file | _rest] = media) when is_binary(slug) do
    case program_assets(slug) do
      [] ->
        %{}

      used ->
        for %{path: path, file: file, bytes: bytes} <- media,
            asset = program_asset(path, file, bytes, used),
            into: %{},
            do: {path, asset.id}
    end
  end

  def program_media(_slug, _media), do: %{}

  @doc """
  Sets `updated_at` of the assets `asset_ids` to now in one update, as an
  ingest of the same file does (`Espalier.Media.ingest_pack_file/2`). The
  importer applies it to the assets that it links through the option
  `media:` or `program_media/2` without an ingest, and
  `Espalier.Workbench.create_from_upload/4` to the assets that
  `program_media/2` links for the media files of an archive. The retention
  of unused pack media (`Espalier.Media.RetentionWorker`) therefore counts
  its days from the last import or archive that named such an asset. An
  asset in `processing` keeps its `updated_at`, which the heartbeat of its
  job sets.
  """
  @spec touch_linked([Ecto.UUID.t()]) :: :ok
  def touch_linked([]), do: :ok

  def touch_linked(asset_ids) when is_list(asset_ids) do
    Repo.update_all(
      from(a in Asset, where: a.id in ^asset_ids and a.status != :processing),
      set: [updated_at: DateTime.utc_now(:second)]
    )

    :ok
  end

  # The ready assets of the program_media rows of the program `slug`,
  # ordered by path.
  defp program_assets(slug) do
    Repo.all(
      from m in ProgramMedia,
        join: p in Program,
        on: p.id == m.program_id,
        join: a in Asset,
        on: a.id == m.media_asset_id,
        where: p.slug == ^slug and a.status == :ready,
        order_by: [asc: m.path],
        select: %{path: m.path, id: a.id, sha256: a.sha256, ext: a.ext, bytes: a.bytes}
    )
  end

  defp program_asset(path, file, bytes, used) do
    ext = path |> Path.extname() |> String.trim_leading(".")

    case Enum.filter(used, &(&1.ext == ext and &1.bytes == bytes)) do
      [] ->
        nil

      candidates ->
        digest = Store.sha256_file(file)
        matches = Enum.filter(candidates, &(&1.sha256 == digest))
        Enum.find(matches, &(&1.path == path)) || List.first(matches)
    end
  end

  defp ingest_message(:unsupported_type), do: "the file is no supported media file"

  defp ingest_message(:extension_mismatch),
    do: "the content of the file does not fit its extension"

  defp ingest_message(:too_many_pixels),
    do: "the image has more than #{Entries.number(Media.max_input_pixels())} pixels"

  defp ingest_message(:media_too_large), do: "the file exceeds the size limit of its kind"

  defp ingest_message(:storage_full),
    do: "the media store is full (MEDIA_STORAGE_MAX_GB); delete unused media first"

  defp ingest_message(reason), do: "the file could not be stored (#{reason})"

  # The media/ paths that the blocks reference: the src of a figure, the src
  # of a video file, its poster and its captions.
  defp references(payload) do
    for module <- Map.get(payload, "modules", []),
        lesson <- Map.get(module, "lessons", []),
        %{"media" => %{} = media} <- Map.get(lesson, "blocks", []),
        path <- block_paths(media),
        uniq: true,
        do: path
  end

  defp block_paths(media) do
    captions = for %{"src" => src} <- media["captions"] || [], do: src

    [media["src"], media["poster"] | captions]
    |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "media/")))
  end

  # Two paths that become the same delivery file cannot both stay in a pack
  # that the platform writes again.
  defp collisions(paths) do
    paths
    |> Enum.group_by(&MediaPath.delivery_path/1)
    |> Enum.filter(fn {_delivery, group} -> length(group) > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {delivery, [first, second | _rest]} ->
      %{
        file: first,
        line: 1,
        message: "#{first} and #{second} both become #{delivery}; rename one"
      }
    end)
  end

  defp run_attrs(%{errors: [], warnings: warnings, payload: payload}, meta)
       when is_map(payload) do
    asset_ids = payload |> Map.get("media", []) |> Enum.map(& &1["asset_id"]) |> Enum.uniq()

    meta
    |> meta_attrs()
    |> Map.merge(%{
      status: :validated,
      report: Report.stored([], warnings),
      payload: payload,
      media_asset_ids: asset_ids
    })
  end

  defp run_attrs(%{errors: errors, warnings: warnings}, meta),
    do: failed_attrs(meta, errors, warnings)

  defp failed_attrs(meta, errors, warnings) do
    meta
    |> meta_attrs()
    |> Map.merge(%{status: :failed, report: Report.stored(errors, warnings), payload: nil})
  end

  defp loaded_meta(%{files: %{"pack.yaml" => %{data: %{} = data}}}),
    do: %{key: data["key"], version: data["version"]}

  defp loaded_meta(_loaded), do: %{key: nil, version: nil}

  defp meta_attrs(meta) do
    %{
      pack_key: meta_value(Map.get(meta, :key)),
      pack_version: meta_value(Map.get(meta, :version))
    }
  end

  # pack_key and pack_version are varchar(255) columns, which count code
  # points and reject a NUL character.
  defp meta_value(value) when is_binary(value) do
    if String.valid?(value) and Cast.fits_column?(value) and not String.contains?(value, <<0>>),
      do: value,
      else: nil
  end

  defp meta_value(_value), do: nil
end
