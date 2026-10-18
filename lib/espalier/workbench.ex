defmodule Espalier.Workbench do
  @moduledoc """
  The Workbench context: drafts of content packs that authors edit in the
  admin area (task 0016a; README section 15, decision D18).

  A draft is a set of files of the pack layout (`Espalier.Workbench.Paths`)
  with their text. It starts from an empty skeleton, a published program, an
  import with a payload or an uploaded zip archive. A check runs the loader
  and the validator of task 0008 on the files without saving anything, an
  import runs the importer through `Espalier.Catalog.import_pack/3`, and a
  download returns the files as a zip archive in the pack layout. Content
  packs stay the only import and export format.

  Every public function takes the scope first and answers
  `{:error, :forbidden}` for a scope without the role `author`; an unknown
  or malformed id answers `{:error, :not_found}`.

  ## Limits (ASVS 2.1.3, 2.3.2 and 15.2.2)

    * `max_files/0`: 2,000 files per draft, the entries of an archive;
    * `max_file_bytes/0`: 1,048,576 bytes per file, the limit of the loader;
    * `max_draft_bytes/0`: five times `PACK_UPLOAD_MAX_MB` per draft, the
      bound on the declared sizes of an uploaded archive;
    * `max_drafts/0`: 50 drafts in total;
    * `max_parallel_checks/0`: 2 checks, imports and zip builds of draft
      downloads at once per node (`Espalier.Workbench.CheckLimiter`);
    * `max_parallel_downloads/0`: 2 downloads of drafts at once per node and
      one per user (`Espalier.Workbench.DownloadLimiter`);
    * `download_min_bytes_per_second/0` and `download_floor_seconds/0`: the
      deadline of the transfer of a download, the time of its zip at
      262,144 bytes (256 KiB) per second and at least 60 seconds.

  A content is valid UTF-8, holds no U+0000, which a PostgreSQL `text`
  column cannot store, and has at most `max_file_bytes/0` bytes. Other
  control characters are stored, and the check reports them with line and
  column, as the loader does.

  ## Changes

  Each file change locks the draft row with `FOR UPDATE`, compares the
  `lock_version` of the request with the stored one and answers
  `{:error, {:stale_draft, current}}` when they differ, applies the limits
  to the draft after the change, writes the file and increments
  `lock_version`, all in one `Repo.transact/1`. The row lock orders the
  changes of one draft, so two requests with the same `lock_version` give
  one change and one `stale_draft`. A change that writes `pack.yaml` parses
  it before the transaction with `Espalier.Catalog.Pack.Loader.pack_meta_text/1`
  and stores its `title` and `key` as `title` and `pack_key` of the draft.

  File changes write no audit event (data minimization, README section 2);
  `pack_draft.created` and `pack_draft.deleted` record the start and the end
  of a draft, and `pack.imported` names the draft of an import.

  ## Media (task 0018, step 16)

  A draft holds media entries (`Espalier.Workbench.PackDraftMedia`): a
  `media/` path and an asset of the media library, at most
  `Espalier.Media.max_draft_media/0` per draft, and at most `max_files/0`
  files and media entries together. `attach_media/4`, `rename_media/5` and
  `delete_media/4` follow the file changes: the row lock of the draft, the
  `lock_version`, the path rules (`Espalier.Workbench.Paths.check_media/2`:
  the delivery extension of the asset) and a path that no file and no media
  entry of the draft holds. A captions asset becomes a text file of the
  draft at a `.vtt` path, read from the store under the limits of the files.

  A draft from a program or an import holds one media entry per image, SVG
  and video file of `Espalier.Interop.PackWriter.media_files/1` and the
  captions of `PackWriter.captions_files/1` as text files. A draft from an
  archive keeps the captions as text files, ingests every other media file
  into the library (origin `pack`), attaches it under its delivery path and
  rewrites the directives of the lessons to that path. A media file that
  equals the delivery file of an asset that the program of the pack key
  uses attaches that asset instead, the asset at the same path first, as
  the import does (`Espalier.Catalog.Pack.Importer.program_media/2`). The
  check and the import write an empty file at the path of each media entry,
  so that the loader sees the path, and the import links the paths to their
  assets. The download stages the files below the media store and places
  each media file there as a hard link to its store file. It builds the zip
  in a slot of `Espalier.Workbench.CheckLimiter`, which it frees once the
  zip is written, and keeps its slot of `Espalier.Workbench.DownloadLimiter`
  until the zip is sent and removed.
  """

  import Ecto.Query, warn: false

  alias Espalier.Accounts.Scope
  alias Espalier.{Audit, Catalog, Repo}
  alias Espalier.Catalog.Pack.{Archive, Directives, Entries, Hosts, Importer, Loader, MediaPath}
  alias Espalier.Catalog.Pack.{Report, Validator}
  alias Espalier.Catalog.Pack.Schema.Cast
  alias Espalier.Catalog.{PackImport, Program}
  alias Espalier.Interop.PackWriter
  alias Espalier.Media
  alias Espalier.Media.{Asset, Store}

  alias Espalier.Workbench.{
    CheckLimiter,
    DownloadLimiter,
    DraftDir,
    PackDraft,
    PackDraftFile,
    PackDraftMedia,
    Paths,
    Skeleton
  }

  @default_settings [
    max_drafts: 50,
    max_parallel_checks: 2,
    max_parallel_downloads: 2,
    download_min_bytes_per_second: 262_144,
    download_floor_seconds: 60
  ]

  # The rows of one insert_all statement: below the 65,535 parameters of a
  # PostgreSQL statement (six per row) and at most 8 MiB of content.
  @chunk_rows 1_000
  @chunk_bytes 8 * 1_048_576

  @max_title 255
  @max_download_key 200

  @typedoc "A file of a draft as `{path, content}`."
  @type file :: {String.t(), String.t()}

  @typedoc "The answer of `check_draft/3`."
  @type check :: %{
          lock_version: pos_integer(),
          report: %{String.t() => [map()]},
          payload: map() | nil
        }

  ## Limits

  @doc "The largest number of files of a draft, the entries of an archive (2,000)."
  @spec max_files() :: pos_integer()
  def max_files, do: Archive.max_entries()

  @doc "The largest number of bytes of a file, the limit of the loader (1,048,576)."
  @spec max_file_bytes() :: pos_integer()
  def max_file_bytes, do: Loader.max_file_bytes()

  @doc """
  The largest sum of the bytes of the files of a draft: five times
  `PACK_UPLOAD_MAX_MB` (104,857,600 bytes with the default of 20), the bound
  on the declared sizes of an uploaded archive.
  """
  @spec max_draft_bytes() :: pos_integer()
  def max_draft_bytes, do: 5 * Application.get_env(:espalier, :pack_upload_max_mb, 20) * 1_048_576

  @doc """
  The largest number of drafts, from `config :espalier, :pack_drafts,
  max_drafts:` (default 50). Raises `ArgumentError` for a value that is no
  positive integer.
  """
  @spec max_drafts() :: pos_integer()
  def max_drafts, do: setting(:max_drafts)

  @doc """
  The largest number of checks, imports and zip builds of draft downloads
  that run at once on a node, from
  `config :espalier, :pack_drafts, max_parallel_checks:` (default 2). The
  transfer of a download runs outside these slots. Raises `ArgumentError`
  for a value that is no positive integer.
  """
  @spec max_parallel_checks() :: pos_integer()
  def max_parallel_checks, do: setting(:max_parallel_checks)

  @doc """
  The largest number of draft downloads that run at once on a node, from
  `config :espalier, :pack_drafts, max_parallel_downloads:` (default 2); a
  user runs one download at a time. A download holds its slot from the zip
  build to the end of the transfer. Raises `ArgumentError` for a value that
  is no positive integer.
  """
  @spec max_parallel_downloads() :: pos_integer()
  def max_parallel_downloads, do: setting(:max_parallel_downloads)

  @doc """
  The lowest average rate of the transfer of a draft download in bytes per
  second, from `config :espalier, :pack_drafts,
  download_min_bytes_per_second:` (default 262,144, 256 KiB or about 2
  Mbit/s). A zip with 1,024 MB of media, the limit `export_max_mb`, takes
  about 68 minutes at this rate. Raises `ArgumentError` for a value that is
  no positive integer.
  """
  @spec download_min_bytes_per_second() :: pos_integer()
  def download_min_bytes_per_second, do: setting(:download_min_bytes_per_second)

  @doc """
  The shortest deadline of the transfer of a draft download in seconds,
  from `config :espalier, :pack_drafts, download_floor_seconds:` (default
  60), so that a small zip also reaches a slow client. Raises
  `ArgumentError` for a value that is no positive integer.
  """
  @spec download_floor_seconds() :: pos_integer()
  def download_floor_seconds, do: setting(:download_floor_seconds)

  defp setting(key) do
    config = Application.get_env(:espalier, :pack_drafts, [])

    case Keyword.get(config, key, Keyword.fetch!(@default_settings, key)) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError,
              "pack_drafts #{key} must be a positive integer, got: #{inspect(value)}"
    end
  end

  @doc """
  Checks a content against the content rules: at most `max_file_bytes/0`
  bytes (`:file_too_large`), valid UTF-8 (`:invalid_encoding`) and no U+0000
  (`:nul_character`).
  """
  @spec check_content(term()) ::
          :ok | {:error, :file_too_large | :invalid_encoding | :nul_character}
  def check_content(content) when is_binary(content) do
    cond do
      byte_size(content) > max_file_bytes() -> {:error, :file_too_large}
      not String.valid?(content) -> {:error, :invalid_encoding}
      String.contains?(content, <<0>>) -> {:error, :nul_character}
      true -> :ok
    end
  end

  def check_content(_content), do: {:error, :invalid_encoding}

  ## Reads

  @doc """
  Returns the drafts, newest `updated_at` first, each with `file_count` and
  `bytes` from one aggregate query and without files.
  """
  @spec list_drafts(Scope.t()) :: {:ok, [PackDraft.t()]} | {:error, :forbidden}
  def list_drafts(%Scope{} = scope) do
    with :ok <- require_author(scope) do
      usage =
        from f in PackDraftFile,
          group_by: f.pack_draft_id,
          select: %{
            pack_draft_id: f.pack_draft_id,
            files: count(f.id),
            bytes: sum(fragment("octet_length(?)", f.content))
          }

      drafts =
        Repo.all(
          from d in PackDraft,
            left_join: u in subquery(usage),
            on: u.pack_draft_id == d.id,
            order_by: [desc: d.updated_at, desc: d.inserted_at, desc: d.id],
            select: d,
            select_merge: %{file_count: coalesce(u.files, 0), bytes: coalesce(u.bytes, 0)}
        )

      {:ok, drafts}
    end
  end

  @doc """
  Returns the draft with its files ordered by path, each with id, path,
  `bytes` (`octet_length(content)`) and `updated_at` and without content,
  and its media entries ordered by path with their assets.
  """
  @spec get_draft(Scope.t(), term()) :: {:ok, PackDraft.t()} | {:error, :forbidden | :not_found}
  def get_draft(%Scope{} = scope, id) do
    with :ok <- require_author(scope),
         {:ok, id} <- uuid(id),
         %PackDraft{} = draft <- Repo.get(PackDraft, id) do
      {:ok, with_files(draft)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Returns the draft (without files) and its file `file_id` with content. A
  file of another draft answers `{:error, :not_found}`.
  """
  @spec get_file(Scope.t(), term(), term()) ::
          {:ok, PackDraft.t(), PackDraftFile.t()} | {:error, :forbidden | :not_found}
  def get_file(%Scope{} = scope, draft_id, file_id) do
    with :ok <- require_author(scope),
         {:ok, draft_id} <- uuid(draft_id),
         {:ok, file_id} <- uuid(file_id),
         {%PackDraft{} = draft, %PackDraftFile{} = file} <-
           Repo.one(
             from f in PackDraftFile,
               join: d in PackDraft,
               on: d.id == f.pack_draft_id,
               where: f.id == ^file_id and d.id == ^draft_id,
               select: {d, f}
           ) do
      {:ok, draft, %{file | bytes: byte_size(file.content)}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp with_files(%PackDraft{id: id} = draft) do
    files = Repo.all(from f in files_without_content(), where: f.pack_draft_id == ^id)

    media =
      Repo.all(
        from m in PackDraftMedia,
          where: m.pack_draft_id == ^id,
          order_by: m.path,
          preload: :media_asset
      )

    %{
      draft
      | files: files,
        media: media,
        file_count: length(files),
        bytes: files |> Enum.map(& &1.bytes) |> Enum.sum()
    }
  end

  # The files of a draft without content, ordered by path, with `bytes`.
  defp files_without_content do
    from f in PackDraftFile,
      order_by: f.path,
      select: struct(f, [:id, :path, :pack_draft_id, :inserted_at, :updated_at]),
      select_merge: %{bytes: fragment("octet_length(?)", f.content)}
  end

  ## File changes

  @doc """
  Adds the file `path` with `content` to the draft. Answers `{:ok, draft}`
  as `get_draft/2` returns it, or `{:error, reason}` with `:invalid_path`,
  `:path_taken`, `:file_too_large`, `:invalid_encoding`, `:nul_character`,
  `:too_many_files`, `:draft_too_large` or `{:stale_draft, current}`.
  """
  def create_file(%Scope{} = scope, draft_id, %{path: path, content: content}, lock_version) do
    with :ok <- require_author(scope),
         {:ok, draft_id} <- uuid(draft_id),
         :ok <- Paths.check(path),
         :ok <- check_content(content) do
      meta = written_meta(path, content)
      change(draft_id, lock_version, &insert_file(&1, path, content, meta))
    end
  end

  @doc """
  Replaces the content of the file `file_id` of the draft. Answers as
  `create_file/4`, and `{:error, :not_found}` for a file of another draft.
  """
  def update_file(%Scope{} = scope, draft_id, file_id, content, lock_version) do
    with :ok <- require_author(scope),
         {:ok, draft_id} <- uuid(draft_id),
         {:ok, file_id} <- uuid(file_id),
         :ok <- check_content(content),
         {:ok, path, _stored} <- peek_file(draft_id, file_id, lock_version, false) do
      meta = written_meta(path, content)
      change(draft_id, lock_version, &replace_content(&1, file_id, content, meta))
    end
  end

  @doc """
  Moves the file `file_id` of the draft to `path`. Answers as
  `update_file/5`; a path that the draft holds already answers
  `{:error, :path_taken}` and leaves `lock_version` unchanged.
  """
  def rename_file(%Scope{} = scope, draft_id, file_id, path, lock_version) do
    with :ok <- require_author(scope),
         {:ok, draft_id} <- uuid(draft_id),
         {:ok, file_id} <- uuid(file_id),
         :ok <- Paths.check(path),
         {:ok, old_path, stored} <-
           peek_file(draft_id, file_id, lock_version, path == "pack.yaml") do
      meta = moved_meta(old_path, path, stored)
      change(draft_id, lock_version, &move_file(&1, file_id, path, meta))
    end
  end

  @doc """
  Removes the file `file_id` from the draft. Answers as `update_file/5`.
  """
  def delete_file(%Scope{} = scope, draft_id, file_id, lock_version) do
    with :ok <- require_author(scope),
         {:ok, draft_id} <- uuid(draft_id),
         {:ok, file_id} <- uuid(file_id) do
      change(draft_id, lock_version, &remove_file(&1, file_id))
    end
  end

  @doc """
  Adds the library asset `media_asset_id` to the draft at `path`. An image,
  SVG or video asset becomes a media entry; its path must carry the
  delivery extension of the asset. A captions asset in status `ready`
  becomes a text file at a `.vtt` path with the content of its delivery
  file. Answers as `create_file/4`, and `{:error, :media_limit}`,
  `{:error, :not_found}` for an unknown asset, or `{:error,
  {:validation_failed, "media_asset_id", "not_ready"}}` for a captions
  asset that is not ready.
  """
  def attach_media(
        %Scope{} = scope,
        draft_id,
        %{media_asset_id: asset_id, path: path},
        lock_version
      ) do
    with :ok <- require_author(scope),
         {:ok, draft_id} <- uuid(draft_id),
         {:ok, asset_id} <- uuid(asset_id),
         %Asset{} = asset <- Repo.get(Asset, asset_id) || {:error, :not_found} do
      attach(asset, draft_id, path, lock_version)
    end
  end

  defp attach(%Asset{kind: :captions} = asset, draft_id, path, lock_version) do
    with :ok <- captions_path(path),
         {:ok, content} <- captions_content(asset),
         :ok <- check_content(content) do
      change(draft_id, lock_version, &insert_file(&1, path, content, :keep))
    end
  end

  defp attach(%Asset{} = asset, draft_id, path, lock_version) do
    with :ok <- Paths.check_media(path, asset) do
      change(draft_id, lock_version, &insert_media(&1, path, asset.id))
    end
  end

  defp captions_path(path) do
    if Paths.check(path) == :ok and String.starts_with?(path, "media/") and
         String.ends_with?(path, ".vtt"),
       do: :ok,
       else: {:error, :invalid_path}
  end

  # The delivery file of a ready captions asset, which the browser never
  # reads through /media/ for this.
  # Every path comes from Espalier.Media.Store, built from MEDIA_DIR and a
  # digest, a UUID or a fixed name (ASVS 5.3.2).
  # sobelow_skip ["Traversal.FileModule"]
  defp captions_content(%Asset{status: :ready, sha256: sha256, ext: "vtt"}) do
    case File.read(Store.path(sha256, "vtt")) do
      {:ok, content} -> {:ok, content}
      {:error, _reason} -> {:error, {:validation_failed, "media_asset_id", "not_ready"}}
    end
  end

  defp captions_content(%Asset{}),
    do: {:error, {:validation_failed, "media_asset_id", "not_ready"}}

  @doc """
  Moves the media entry `media_id` of the draft to `path`, which must carry
  the delivery extension of its asset. Answers as `rename_file/5`.
  """
  def rename_media(%Scope{} = scope, draft_id, media_id, path, lock_version) do
    with :ok <- require_author(scope),
         {:ok, draft_id} <- uuid(draft_id),
         {:ok, media_id} <- uuid(media_id) do
      change(draft_id, lock_version, &move_media(&1, media_id, path))
    end
  end

  @doc """
  Removes the media entry `media_id` from the draft; the asset stays in the
  library. Answers as `delete_file/4`.
  """
  def delete_media(%Scope{} = scope, draft_id, media_id, lock_version) do
    with :ok <- require_author(scope),
         {:ok, draft_id} <- uuid(draft_id),
         {:ok, media_id} <- uuid(media_id) do
      change(draft_id, lock_version, &remove_media(&1, media_id))
    end
  end

  defp insert_media(draft, path, asset_id) do
    with :ok <- path_free(draft.id, path),
         :ok <- within_limits(draft.id, 0, 0, 1),
         {:ok, _media} <-
           %PackDraftMedia{pack_draft_id: draft.id, media_asset_id: asset_id}
           |> PackDraftMedia.changeset(%{path: path})
           |> Repo.insert()
           |> media_result(),
         do: {:ok, :keep}
  end

  defp move_media(draft, media_id, path) do
    with {:ok, media} <- locked_media(draft.id, media_id),
         :ok <- Paths.check_media(path, media.media_asset),
         :ok <- media_path_free(draft.id, path, media),
         {:ok, _media} <-
           media |> PackDraftMedia.changeset(%{path: path}) |> Repo.update() |> media_result(),
         do: {:ok, :keep}
  end

  defp remove_media(draft, media_id) do
    with {:ok, media} <- locked_media(draft.id, media_id),
         {:ok, _deleted} <- Repo.delete(media),
         do: {:ok, :keep}
  end

  defp locked_media(draft_id, media_id) do
    case Repo.one(
           from m in PackDraftMedia,
             where: m.id == ^media_id and m.pack_draft_id == ^draft_id,
             preload: :media_asset
         ) do
      nil -> {:error, :not_found}
      media -> {:ok, media}
    end
  end

  defp media_path_free(_draft_id, path, %PackDraftMedia{path: path}), do: :ok
  defp media_path_free(draft_id, path, _media), do: path_free(draft_id, path)

  # A deleted asset fails the foreign key; a taken path the unique index.
  defp media_result({:error, %Ecto.Changeset{errors: errors}} = error) do
    cond do
      Keyword.has_key?(errors, :media_asset_id) ->
        {:error, :not_found}

      Keyword.has_key?(errors, :pack_draft_id) or Keyword.has_key?(errors, :path) ->
        {:error, :path_taken}

      true ->
        error
    end
  end

  defp media_result(result), do: result

  # The changes of a file, each run by change/3 under the row lock of the
  # draft; each returns {:ok, meta} for the title and the pack key.

  defp insert_file(draft, path, content, meta) do
    with :ok <- path_free(draft.id, path),
         :ok <- within_limits(draft.id, 1, byte_size(content)),
         {:ok, _file} <-
           %PackDraftFile{pack_draft_id: draft.id}
           |> PackDraftFile.changeset(%{path: path, content: content})
           |> Repo.insert()
           |> path_result(),
         do: {:ok, meta}
  end

  defp replace_content(draft, file_id, content, meta) do
    with {:ok, file} <- locked_file(draft.id, file_id),
         :ok <- within_limits(draft.id, 0, byte_size(content) - file.bytes),
         {:ok, _file} <- file |> PackDraftFile.changeset(%{content: content}) |> Repo.update(),
         do: {:ok, meta}
  end

  defp move_file(draft, file_id, path, meta) do
    with {:ok, file} <- locked_file(draft.id, file_id),
         :ok <- path_free(draft.id, path, file),
         {:ok, _file} <-
           file |> PackDraftFile.changeset(%{path: path}) |> Repo.update() |> path_result(),
         do: {:ok, meta}
  end

  defp remove_file(draft, file_id) do
    with {:ok, file} <- locked_file(draft.id, file_id),
         {:ok, _deleted} <- Repo.delete(file),
         do: {:ok, if(file.path == "pack.yaml", do: :remove, else: :keep)}
  end

  # A write of pack.yaml parses it before the transaction, so that no parse
  # runs while the row lock is held.
  defp written_meta("pack.yaml", content), do: {:write, Loader.pack_meta_text(content)}
  defp written_meta(_path, _content), do: :keep

  defp moved_meta(path, path, _stored), do: :keep
  defp moved_meta(_old_path, "pack.yaml", stored), do: {:write, Loader.pack_meta_text(stored)}
  defp moved_meta("pack.yaml", _path, _stored), do: :remove
  defp moved_meta(_old_path, _path, _stored), do: :keep

  # Reads the path of a file and the lock_version of its draft in one
  # statement, and the stored content when `content?`. A lock_version that
  # differs from the stored one answers stale_draft before any parse, so the
  # parse of pack.yaml before the transaction always reads the version that
  # the transaction checks again.
  defp peek_file(draft_id, file_id, lock_version, content?) do
    query =
      from f in PackDraftFile,
        join: d in PackDraft,
        on: d.id == f.pack_draft_id,
        where: f.id == ^file_id and d.id == ^draft_id

    query =
      if content?,
        do: select(query, [f, d], {d.lock_version, f.path, f.content}),
        else: select(query, [f, d], {d.lock_version, f.path, nil})

    case Repo.one(query) do
      nil -> {:error, :not_found}
      {^lock_version, path, content} -> {:ok, path, content}
      {current, _path, _content} -> {:error, {:stale_draft, current}}
    end
  end

  # One file change: the draft row under FOR UPDATE, the lock check, the
  # change of `fun` (which returns {:ok, meta}) and the new lock_version, in
  # one transaction. `meta` is :keep, :remove (pack.yaml removed) or
  # {:write, pack_meta} (pack.yaml written).
  defp change(draft_id, lock_version, fun) do
    Repo.transact(fn ->
      with {:ok, draft} <- lock_draft(draft_id),
           :ok <- check_version(draft, lock_version),
           {:ok, meta} <- fun.(draft) do
        changes = Map.put(meta_changes(draft, meta), :lock_version, draft.lock_version + 1)
        updated = draft |> Ecto.Changeset.change(changes) |> Repo.update!()
        {:ok, with_files(updated)}
      end
    end)
  end

  defp lock_draft(id) do
    case Repo.one(from d in PackDraft, where: d.id == ^id, lock: "FOR UPDATE") do
      nil -> {:error, :not_found}
      draft -> {:ok, draft}
    end
  end

  defp check_version(%PackDraft{lock_version: version}, version), do: :ok

  defp check_version(%PackDraft{lock_version: current}, _version),
    do: {:error, {:stale_draft, current}}

  defp locked_file(draft_id, file_id) do
    query =
      from f in files_without_content(),
        where: f.id == ^file_id and f.pack_draft_id == ^draft_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  end

  # A rename to the path that the file holds already changes nothing.
  defp path_free(_draft_id, path, %PackDraftFile{path: path}), do: :ok
  defp path_free(draft_id, path, _file), do: path_free(draft_id, path)

  # No file and no media entry of the draft holds the path.
  defp path_free(draft_id, path) do
    taken? =
      Repo.exists?(
        from f in PackDraftFile, where: f.pack_draft_id == ^draft_id and f.path == ^path
      ) or
        Repo.exists?(
          from m in PackDraftMedia, where: m.pack_draft_id == ^draft_id and m.path == ^path
        )

    if taken?, do: {:error, :path_taken}, else: :ok
  end

  defp path_result({:error, %Ecto.Changeset{errors: errors}} = error) do
    if Keyword.has_key?(errors, :pack_draft_id) or Keyword.has_key?(errors, :path),
      do: {:error, :path_taken},
      else: error
  end

  defp path_result(result), do: result

  # The limits apply to the draft after the change. A change that adds no
  # file or no byte passes, so that a draft above a lowered limit can still
  # shrink.
  # `max_files/0` counts the files and the media entries together.
  defp within_limits(draft_id, added_files, added_bytes, added_media \\ 0) do
    {files, bytes} =
      Repo.one(
        from f in PackDraftFile,
          where: f.pack_draft_id == ^draft_id,
          select: {count(f.id), coalesce(sum(fragment("octet_length(?)", f.content)), 0)}
      )

    media = Repo.aggregate(from(m in PackDraftMedia, where: m.pack_draft_id == ^draft_id), :count)
    added = added_files + added_media

    cond do
      added_media > 0 and media + added_media > Media.max_draft_media() -> {:error, :media_limit}
      added > 0 and files + media + added > max_files() -> {:error, :too_many_files}
      added_bytes > 0 and bytes + added_bytes > max_draft_bytes() -> {:error, :draft_too_large}
      true -> :ok
    end
  end

  defp meta_changes(_draft, :keep), do: %{}
  defp meta_changes(_draft, :remove), do: %{pack_key: nil}

  defp meta_changes(draft, {:write, meta}) do
    %{title: usable(meta.title) || draft.title, pack_key: usable(meta.key)}
  end

  # A title or a key of pack.yaml lands in a varchar(255) column: a string
  # of 1 to 255 characters without U+0000.
  defp usable(value) when is_binary(value) do
    length = value |> String.codepoints() |> length()

    if String.valid?(value) and length in 1..@max_title and not String.contains?(value, <<0>>),
      do: value,
      else: nil
  end

  defp usable(_value), do: nil

  ## Drafts

  @doc """
  Deletes the draft with its files and writes the audit event
  `pack_draft.deleted` in the same transaction.
  """
  def delete_draft(%Scope{} = scope, id) do
    with :ok <- require_author(scope),
         {:ok, id} <- uuid(id) do
      Repo.transact(fn -> delete_locked(scope, id) end)
    end
  end

  defp delete_locked(scope, id) do
    with {:ok, draft} <- lock_draft(id), do: delete_audited(scope, draft)
  end

  defp delete_audited(scope, draft) do
    file_count =
      Repo.aggregate(from(f in PackDraftFile, where: f.pack_draft_id == ^draft.id), :count)

    Repo.delete!(draft)

    {:ok, _event} =
      Audit.record(scope, "pack_draft.deleted", draft, %{
        pack_key: draft.pack_key,
        file_count: file_count
      })

    {:ok, draft}
  end

  @doc """
  Starts a draft from the empty skeleton of `Espalier.Workbench.Skeleton`
  with the pack title `name`.
  """
  def create_empty(%Scope{} = scope, name) when is_binary(name) do
    with :ok <- require_author(scope),
         :ok <- check_name(name) do
      files = name |> Skeleton.payload() |> PackWriter.render()
      create_draft(scope, %{source: "empty"}, {files, []}, nil)
    end
  end

  @doc """
  Starts a draft from the published program `slug` with the files of
  `Espalier.Interop.PackWriter.render_program/1`, the media entries of its
  image, SVG and video files and its captions as text files, all read under
  the shared lock of the program. A program that is unknown or not
  published answers `{:error, :not_found}`.
  """
  def create_from_program(%Scope{} = scope, slug) when is_binary(slug) do
    with :ok <- require_author(scope),
         %Program{status: :published} = program <- Catalog.get_program_by_slug(slug),
         {:ok, start} <- PackWriter.with_program_payload(program, &payload_start/1) do
      create_draft(scope, %{source: "program", program_slug: slug}, start, nil)
    else
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, {:media_not_ready, _entries}} = error -> error
      _other -> {:error, :not_found}
    end
  end

  @doc """
  Starts a draft from the payload of the import `import_id` (status
  `validated` or `published`). A `failed` import holds no payload and
  answers `{:error, :no_payload}`.
  """
  def create_from_import(%Scope{} = scope, import_id) do
    with {:ok, %PackImport{} = pack_import} <- Catalog.get_pack_import(scope, import_id),
         {:ok, payload} <- start_payload(pack_import),
         {:ok, start} <- payload_start(payload) do
      create_draft(scope, %{source: "import", pack_import_id: pack_import.id}, start, nil)
    end
  end

  defp start_payload(%PackImport{status: status, payload: %{} = payload})
       when status in [:validated, :published],
       do: {:ok, payload}

  defp start_payload(%PackImport{}), do: {:error, :no_payload}

  @doc """
  Starts a draft from the uploaded zip archive at `upload_path`.
  `Espalier.Catalog.Pack.Archive.with_extracted/3` checks and extracts it
  with `max_bytes`, and `Espalier.Workbench.DraftDir.read_pack/1` reads the
  pack at its root or in its one top-level directory. `filename` is the file
  name that the client sent; it gives the title when `pack.yaml` gives none.

  Answers `{:ok, draft, skipped}`, `{:error, entries}` with the report
  entries of a rejected archive, or `{:error, reason}`.
  """
  def create_from_upload(%Scope{} = scope, upload_path, filename, max_bytes)
      when is_binary(upload_path) and is_integer(max_bytes) do
    with :ok <- require_author(scope),
         {:ok, files, media, skipped} <-
           Archive.with_extracted(upload_path, max_bytes, &read_archive(&1, actor_id(scope))),
         {:ok, draft} <-
           create_draft(scope, %{source: "upload"}, {files, media}, upload_title(filename)) do
      {:ok, draft, skipped}
    end
  end

  # The text files of the pack in an extracted archive, its media files as
  # library assets, and the skipped paths.
  defp read_archive(dir, actor_id) do
    root = Archive.pack_root(dir)

    with {:ok, files, skipped} <- DraftDir.read_pack(root),
         {:ok, files, media} <- ingest_archive_media(root, files, actor_id) do
      {:ok, files, media, skipped}
    end
  end

  # The start of a draft from a payload: the rendered files plus the
  # captions as text files, and one media entry per image, SVG and video
  # file. A captions file that is not ready in the store answers
  # {:media_not_ready, entries}, because its text cannot be read yet.
  defp payload_start(payload) do
    {captions, missing} =
      payload
      |> PackWriter.captions_files()
      |> Enum.reduce({[], []}, fn {path, asset}, {acc, missing} ->
        case captions_content(asset) do
          {:ok, content} ->
            {[{path, content} | acc], missing}

          {:error, _reason} ->
            {acc, [missing_entry(path, asset) | missing]}
        end
      end)

    if missing == [] do
      media = for {path, asset} <- PackWriter.media_files(payload), do: {path, asset.id}
      {:ok, {PackWriter.render(payload) ++ Enum.reverse(captions), media}}
    else
      {:error, {:media_not_ready, Enum.reverse(missing)}}
    end
  end

  # The media files of an extracted archive other than captions: each is
  # ingested into the library and placed at its delivery path, and the
  # directives of the lessons follow the new paths. An ingest error is a
  # report entry at the path of the file, which rejects the archive.
  # The limits of a draft and the delivery collisions are checked on the
  # paths before any file becomes an asset with a conversion job.
  defp ingest_archive_media(root, files, actor_id) do
    media = DraftDir.read_media(root)
    planned = for {path, _file} <- media, do: {path, MediaPath.delivery_path(path), nil}

    case {archive_limits(files, media), delivery_collisions(planned)} do
      {:ok, []} -> ingest_media(media, files, actor_id)
      {:ok, collisions} -> {:error, collisions}
      {error, _collisions} -> error
    end
  end

  defp archive_limits(files, media) do
    cond do
      length(media) > Media.max_draft_media() -> {:error, :media_limit}
      length(files) + length(media) > max_files() -> {:error, :too_many_files}
      Repo.aggregate(PackDraft, :count) >= max_drafts() -> {:error, :draft_limit}
      true -> :ok
    end
  end

  defp ingest_media(media, files, actor_id) do
    linked = program_media(files_meta(files).key, media)

    results =
      for {path, file} <- media do
        case ingest_file(path, file, linked, actor_id) do
          {:ok, asset_id} -> {:ok, path, MediaPath.delivery_path(path), asset_id}
          {:error, reason} -> {:error, path, reason}
        end
      end

    errors = for {:error, path, reason} <- results, do: archive_entry(path, media_message(reason))
    attached = for {:ok, path, delivery, asset_id} <- results, do: {path, delivery, asset_id}
    collisions = delivery_collisions(attached)

    if errors == [] and collisions == [] do
      mapping =
        for {path, delivery, _id} <- attached, path != delivery, into: %{}, do: {path, delivery}

      files = Enum.map(files, &rename_references(&1, mapping))
      {:ok, files, Enum.map(attached, fn {_path, delivery, id} -> {delivery, id} end)}
    else
      {:error, errors ++ collisions}
    end
  end

  # A media file of an archive whose pack key names a program, and that
  # equals the delivery file of an asset of that program, links to that
  # asset, as the import of the same files does, so that an archive of an
  # exported pack keeps the assets of its program also when two assets
  # share one delivery file. A linked asset gets the time of its last change
  # set again, as an ingest of the same file does, so that the retention of
  # unused pack media counts its days from this archive. The walk of
  # DraftDir.read_media/1 found the files as regular files below the
  # extracted archive.
  # sobelow_skip ["Traversal.FileModule"]
  defp program_media(key, media) do
    files =
      for {path, file} <- media,
          {:ok, %File.Stat{type: :regular, size: bytes}} <- [File.lstat(file)],
          do: %{path: path, file: file, bytes: bytes}

    linked = Importer.program_media(key, files)
    :ok = linked |> Map.values() |> Importer.touch_linked()
    linked
  end

  defp ingest_file(path, file, linked, actor_id) do
    case Map.fetch(linked, path) do
      {:ok, asset_id} ->
        {:ok, asset_id}

      :error ->
        with {:ok, asset, _created_or_existing} <-
               Media.ingest_pack_file(%{path: file, file_name: path}, actor_id),
             do: {:ok, asset.id}
    end
  end

  defp rename_references({path, content}, mapping) when map_size(mapping) > 0 do
    if String.ends_with?(path, ".md"),
      do: {path, Directives.rename_media(content, mapping)},
      else: {path, content}
  end

  defp rename_references(file, _mapping), do: file

  defp delivery_collisions(attached) do
    attached
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.filter(fn {_delivery, paths} -> length(paths) > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {delivery, paths} ->
      [first, second | _rest] = Enum.sort(paths)
      archive_entry(first, "#{first} and #{second} both become #{delivery}; rename one")
    end)
  end

  defp archive_entry(path, message), do: %{"file" => path, "line" => nil, "message" => message}

  defp media_message(:unsupported_type), do: "the file is no supported media file"

  defp media_message(:extension_mismatch),
    do: "the content of the file does not fit its extension"

  defp media_message(:too_many_pixels),
    do: "the image has more than #{Entries.number(Media.max_input_pixels())} pixels"

  defp media_message(:media_too_large), do: "the file exceeds the size limit of its kind"

  defp media_message(:storage_full),
    do: "the media store is full (MEDIA_STORAGE_MAX_GB); delete unused media first"

  defp media_message(reason), do: "the file could not be stored (#{reason})"

  # The file name of the client without its directories and without `.zip`.
  # The name becomes the title of the pack and of the draft, a varchar(255)
  # column that counts code points; the request schema counts graphemes.
  defp check_name(name) do
    if usable(name),
      do: :ok,
      else: {:error, {:validation_failed, "name", "max_length"}}
  end

  defp upload_title(filename) when is_binary(filename) do
    filename
    |> String.replace_invalid()
    |> String.split(["/", "\\"])
    |> List.last()
    |> String.replace(~r/\.zip\z/i, "")
    |> String.replace(<<0>>, "")
    |> String.codepoints()
    |> Enum.take(@max_title)
    |> Enum.join()
    |> case do
      "" -> nil
      title -> title
    end
  end

  defp upload_title(_filename), do: nil

  # Checks the files and the media entries, then counts and inserts under a
  # transaction-scoped advisory lock, so that concurrent creations count one
  # after the other. `start` holds the files as {path, content} and the
  # media entries as {path, asset_id}.
  defp create_draft(scope, details, {files, media} = start, fallback_title) do
    with :ok <- check_files(files),
         :ok <- check_media_entries(files, media) do
      meta = files_meta(files)
      title = usable(meta.title) || fallback_title || "Untitled draft"

      Repo.transact(fn -> insert_counted(scope, details, start, title, usable(meta.key)) end)
    end
  end

  defp check_media_entries(files, media) do
    paths = MapSet.new(files, &elem(&1, 0))

    cond do
      length(media) > Media.max_draft_media() -> {:error, :media_limit}
      length(files) + length(media) > max_files() -> {:error, :too_many_files}
      Enum.any?(media, &MapSet.member?(paths, elem(&1, 0))) -> {:error, :path_taken}
      length(Enum.uniq_by(media, &elem(&1, 0))) < length(media) -> {:error, :path_taken}
      true -> :ok
    end
  end

  defp insert_counted(scope, details, start, title, pack_key) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext('espalier.pack_drafts'))")

    if Repo.aggregate(PackDraft, :count) >= max_drafts(),
      do: {:error, :draft_limit},
      else: insert_draft(scope, details, start, title, pack_key)
  end

  defp insert_draft(scope, details, {files, media}, title, pack_key) do
    draft =
      Repo.insert!(%PackDraft{
        title: title,
        pack_key: pack_key,
        lock_version: 1,
        created_by_id: actor_id(scope)
      })

    insert_files(draft.id, files)

    with :ok <- insert_media_entries(draft.id, media) do
      details =
        details
        |> Map.put(:pack_key, pack_key)
        |> Map.put(:file_count, length(files))

      {:ok, _event} = Audit.record(scope, "pack_draft.created", draft, details)
      {:ok, with_files(draft)}
    end
  end

  defp insert_files(draft_id, files) do
    now = DateTime.utc_now(:second)

    files
    |> Enum.map(fn {path, content} ->
      %{
        id: Ecto.UUID.generate(),
        pack_draft_id: draft_id,
        path: path,
        content: content,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> chunks()
    |> Enum.each(&Repo.insert_all(PackDraftFile, &1))
  end

  defp insert_media_entries(_draft_id, []), do: :ok

  defp insert_media_entries(draft_id, media) do
    now = DateTime.utc_now(:second)

    rows =
      for {path, asset_id} <- media do
        %{
          id: Ecto.UUID.generate(),
          pack_draft_id: draft_id,
          media_asset_id: asset_id,
          path: path,
          inserted_at: now,
          updated_at: now
        }
      end

    # An asset deleted since the start read it fails the foreign key, which
    # answers not_found as the attachment of a missing asset does.
    try do
      {_count, nil} = Repo.insert_all(PackDraftMedia, rows)
      :ok
    rescue
      error in Postgrex.Error ->
        if error.postgres[:code] == :foreign_key_violation,
          do: {:error, :not_found},
          else: reraise(error, __STACKTRACE__)
    end
  end

  # Chunks of at most @chunk_rows rows and, beyond the first row, at most
  # @chunk_bytes of content.
  defp chunks(rows) do
    rows
    |> Enum.chunk_while(
      {[], 0, 0},
      fn row, {acc, count, bytes} ->
        size = byte_size(row.content)

        if acc != [] and (count == @chunk_rows or bytes + size > @chunk_bytes),
          do: {:cont, Enum.reverse(acc), {[row], 1, size}},
          else: {:cont, {[row | acc], count + 1, bytes + size}}
      end,
      fn
        {[], _count, _bytes} -> {:cont, {[], 0, 0}}
        {acc, _count, _bytes} -> {:cont, Enum.reverse(acc), {[], 0, 0}}
      end
    )
  end

  defp check_files(files) do
    cond do
      length(files) > max_files() ->
        {:error, :too_many_files}

      files |> Enum.map(fn {_path, content} -> byte_size(content) end) |> Enum.sum() >
          max_draft_bytes() ->
        {:error, :draft_too_large}

      true ->
        Enum.reduce_while(files, {:ok, MapSet.new()}, &check_file/2)
        |> case do
          {:ok, _paths} -> :ok
          error -> error
        end
    end
  end

  defp check_file({path, content}, {:ok, paths}) do
    with :ok <- Paths.check(path),
         :ok <- check_content(content),
         false <- MapSet.member?(paths, path) do
      {:cont, {:ok, MapSet.put(paths, path)}}
    else
      true -> {:halt, {:error, :path_taken}}
      error -> {:halt, error}
    end
  end

  defp files_meta(files) do
    case List.keyfind(files, "pack.yaml", 0) do
      {"pack.yaml", content} -> Loader.pack_meta_text(content)
      nil -> %{key: nil, version: nil, title: nil}
    end
  end

  ## Check, import and download

  @doc """
  Runs the loader and the validator of task 0008 on the files of the draft
  without saving anything. `overlay` is `nil` or `%{file_id, content}`: the
  unsaved content of one file of the draft, which replaces its stored
  content for this check only.

  Returns `{:ok, check}` with the `lock_version` that was checked, `report`
  as `Espalier.Catalog.Pack.Report.stored/2` and `payload`, the normalized
  map of `Espalier.Catalog.Pack.Validator.run/1` or `nil`, or
  `{:error, :checks_busy}` when `Espalier.Workbench.CheckLimiter` has no free
  slot. The contents of the draft are read only inside a slot.
  """
  @spec check_draft(Scope.t(), term(), nil | %{file_id: term(), content: term()}) ::
          {:ok, check()} | {:error, term()}
  def check_draft(%Scope{} = scope, id, overlay) do
    with :ok <- require_author(scope),
         {:ok, id} <- uuid(id),
         :ok <- overlay_content(overlay) do
      CheckLimiter.run(fn -> check_in_slot(id, overlay) end)
    end
  end

  # The contents of a draft are read only inside a slot, so that requests
  # beyond max_parallel_checks/0 hold no draft in memory.
  defp check_in_slot(id, overlay) do
    with {:ok, draft} <- read_files(id),
         {:ok, files} <- apply_overlay(draft.files, overlay),
         :ok <- overlay_size(files) do
      in_dir(files, draft.media, &{:ok, check_dir(&1, draft.lock_version)})
    end
  end

  # Runs `fun` on a temporary directory with the files and an empty file at
  # the path of each media entry, in a task of
  # Espalier.Workbench.CheckLimiter.
  defp in_dir(files, media, fun) do
    entries = file_pairs(files) ++ Enum.map(media, &{&1.path, :media})
    DraftDir.with_dir(entries, &await_in(&1, fun))
  end

  defp await_in(dir, fun), do: CheckLimiter.await(fn -> fun.(dir) end)

  defp overlay_content(nil), do: :ok
  defp overlay_content(%{content: content}), do: check_content(content)

  defp apply_overlay(files, nil), do: {:ok, files}

  defp apply_overlay(files, %{file_id: file_id, content: content}) do
    with {:ok, file_id} <- uuid(file_id),
         :ok <- check_content(content),
         true <- Enum.any?(files, &(&1.id == file_id)) do
      {:ok, Enum.map(files, &if(&1.id == file_id, do: %{&1 | content: content}, else: &1))}
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  defp overlay_size(files) do
    if files |> Enum.map(&byte_size(&1.content)) |> Enum.sum() > max_draft_bytes(),
      do: {:error, :draft_too_large},
      else: :ok
  end

  defp check_dir(dir, lock_version) do
    case Loader.load(dir) do
      {:ok, loaded} ->
        %{errors: errors, warnings: warnings, payload: payload} = Validator.run(loaded)

        hosts =
          Hosts.check(loaded, %{external: Media.external_hosts(), embed: Media.embed_hosts()})

        errors = Entries.sort(errors ++ hosts)
        payload = if hosts == [], do: payload
        %{lock_version: lock_version, report: Report.stored(errors, warnings), payload: payload}

      {:error, errors} ->
        %{lock_version: lock_version, report: Report.stored(errors, []), payload: nil}
    end
  end

  @doc """
  Imports the files of the draft through `Espalier.Catalog.import_pack/3`,
  whose audit event `pack.imported` names the draft, in a slot of
  `Espalier.Workbench.CheckLimiter`. A `lock_version` that differs from the
  stored one answers `{:error, {:stale_draft, current}}` and imports
  nothing. The draft stays.
  """
  def import_draft(%Scope{} = scope, id, lock_version) do
    with :ok <- require_author(scope),
         {:ok, id} <- uuid(id),
         :ok <- current_version(id, lock_version) do
      CheckLimiter.run(fn -> import_in_slot(scope, id, lock_version) end)
    end
  end

  defp import_in_slot(scope, id, lock_version) do
    with {:ok, draft} <- read_files(id),
         :ok <- check_version(draft, lock_version) do
      media = Map.new(draft.media, &{&1.path, &1.media_asset_id})

      in_dir(
        draft.files,
        draft.media,
        &Catalog.import_pack(scope, &1, audit: %{pack_draft_id: id}, media: media)
      )
    end
  end

  # The lock_version alone, so that a stale or unknown draft answers without
  # a slot and without reading any content.
  defp current_version(id, lock_version) do
    case Repo.one(from d in PackDraft, where: d.id == ^id, select: d.lock_version) do
      nil -> {:error, :not_found}
      ^lock_version -> :ok
      current -> {:error, {:stale_draft, current}}
    end
  end

  @doc """
  Builds the zip archive of the draft, one entry per file and media entry
  in path order, so that the pack sits at the root of the archive, and
  returns the result of `fun`, which receives `%{name: name, path: zip,
  dir: dir}`: the download name `<pack key>-draft.zip`, or `pack-draft.zip`
  without a usable pack key, the path of the zip and its staging directory.
  The controller sends the zip in `fun`.

  The sum of `bytes` and `poster_bytes` of the media entries must stay
  within `Espalier.Media.export_max_mb/0` (`{:error,
  :download_too_large}`). The files are staged in a new directory below
  `MEDIA_DIR/work/` (`Espalier.Media.Store.staging_dir/0`): the text files
  are written there, and each media file is a hard link to its store file,
  which keeps the bytes when a change of the draft and a deletion remove the
  store file meanwhile. A store file that is missing answers `{:error,
  {:media_not_ready, entries}}`. The zip is written into the same directory
  with `:zip.create/3`, which reads every file in blocks and stores `.webp`
  and `.webm` entries uncompressed.

  A download takes a slot of `Espalier.Workbench.DownloadLimiter`, at most
  `max_parallel_downloads/0` per node and one per user, and builds the zip
  in a slot of `Espalier.Workbench.CheckLimiter`, which it frees once the
  zip is written. When either server has no slot for it, the download
  answers `{:error, :checks_busy}` and builds nothing. The contents of the
  draft are read only inside the slot of the build. `fun` runs in the slot
  of the download alone, so a slow transfer holds no slot of the checks and
  imports. The staging directory is removed when `fun` returns or raises
  and on any failure of the build, before the slot of the download is
  freed. So at most `max_parallel_downloads/0` zips of downloads lie on disk
  per node, also while their transfers run.
  """
  @spec download(Scope.t(), term(), (map() -> result)) :: result | {:error, term()}
        when result: term()
  def download(%Scope{} = scope, id, fun) when is_function(fun, 1) do
    with :ok <- require_author(scope),
         {:ok, id} <- uuid(id) do
      DownloadLimiter.run(actor_id(scope), fn -> download_in_slot(id, fun) end)
    end
  end

  # Builds the zip in a slot of CheckLimiter, which the build frees, and runs
  # `fun` in the slot of the download. The staging directory goes when `fun`
  # returns or raises.
  # sobelow_skip ["Traversal.FileModule"]
  defp download_in_slot(id, fun) do
    with {:ok, %{dir: dir} = zip} <- CheckLimiter.run(fn -> build_zip(id) end) do
      # The draft that the build read is no longer referenced; a collection
      # frees its contents before the transfer starts.
      :erlang.garbage_collect()

      try do
        fun.(zip)
      after
        File.rm_rf(dir)
      end
    end
  end

  # The staging directory comes from Espalier.Media.Store.staging_dir/0. Any
  # failure of the staging and the zip, an exception and a full disk
  # included, removes it; a built zip passes it on to the transfer.
  # sobelow_skip ["Traversal.FileModule"]
  defp build_zip(id) do
    with {:ok, draft} <- read_files(id),
         :ok <- download_size(draft.media) do
      dir = Store.staging_dir()

      try do
        stage_and_zip(dir, draft)
      else
        {:ok, _zip} = built ->
          built

        error ->
          File.rm_rf(dir)
          error
      catch
        kind, reason ->
          File.rm_rf(dir)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end

  defp stage_and_zip(dir, draft) do
    with {:ok, paths} <- stage(dir, draft) do
      zip = Path.join(dir, "draft.zip")

      {:ok, _zip} =
        :zip.create(String.to_charlist(zip), Enum.map(paths, &String.to_charlist/1),
          cwd: String.to_charlist(Path.join(dir, "pack")),
          uncompress: {:add, [~c".webp", ~c".webm"]}
        )

      {:ok, %{name: download_name(draft.pack_key), path: zip, dir: dir}}
    end
  end

  defp download_size(media) do
    bytes =
      media
      |> Enum.map(&((&1.media_asset.bytes || 0) + (&1.media_asset.poster_bytes || 0)))
      |> Enum.sum()

    if bytes > Media.export_max_mb() * 1_048_576, do: {:error, :download_too_large}, else: :ok
  end

  # The text files and a hard link per media entry below `dir/pack`. The
  # paths pass the path rules again before they are joined with the
  # directory.
  # sobelow_skip ["Traversal.FileModule"]
  defp stage(dir, draft) do
    root = Path.join(dir, "pack")

    for file <- draft.files, Paths.check(file.path) == :ok do
      target = Path.join(root, file.path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, file.content)
    end

    missing =
      for media <- draft.media,
          MediaPath.check(media.path) == :ok,
          link_media(media, Path.join(root, media.path)) != :ok,
          do: missing_entry(media.path, media.media_asset)

    if missing == [] do
      paths = Enum.map(draft.files, & &1.path) ++ Enum.map(draft.media, & &1.path)
      {:ok, Enum.sort(paths)}
    else
      {:error, {:media_not_ready, missing}}
    end
  end

  # The source comes from the store and the target from the staging directory
  # and a path that passed MediaPath.check/1.
  # sobelow_skip ["Traversal.FileModule"]
  defp link_media(%PackDraftMedia{media_asset: %Asset{status: :ready} = asset}, target) do
    File.mkdir_p!(Path.dirname(target))
    File.ln(Store.path(asset.sha256, asset.ext), target)
  end

  defp link_media(_media, _target), do: {:error, :not_ready}

  # An entry of {:media_not_ready, entries}: the path, the state of the
  # asset, or "missing" for a ready asset without its file, and the code of
  # a failed asset, as the publish gate gives them.
  defp missing_entry(path, %Asset{} = asset) do
    %{
      "path" => path,
      "status" => missing_status(asset),
      "failure" => asset.failure && Atom.to_string(asset.failure)
    }
  end

  defp missing_status(%Asset{status: :ready}), do: "missing"
  defp missing_status(%Asset{status: status}), do: Atom.to_string(status)

  defp download_name(key) do
    if Cast.key?(key) and String.length(key) <= @max_download_key,
      do: key <> "-draft.zip",
      else: "pack-draft.zip"
  end

  # The draft with lock_version, pack_key and every file with its content,
  # in one statement, so that the files belong to the version read.
  # The files and the media entries are read under FOR SHARE on the draft
  # row, which every change locks with FOR UPDATE, so both belong to the
  # version read.
  defp read_files(id) do
    Repo.transact(fn ->
      case Repo.one(from d in PackDraft, where: d.id == ^id, lock: "FOR SHARE", select: d.id) do
        nil -> {:error, :not_found}
        _id -> read_locked(id)
      end
    end)
  end

  defp read_locked(id) do
    rows =
      Repo.all(
        from d in PackDraft,
          left_join: f in PackDraftFile,
          on: f.pack_draft_id == d.id,
          where: d.id == ^id,
          order_by: f.path,
          select: {d, f}
      )

    case rows do
      [] ->
        {:error, :not_found}

      [{draft, _file} | _rest] ->
        media =
          Repo.all(
            from m in PackDraftMedia,
              where: m.pack_draft_id == ^draft.id,
              order_by: m.path,
              preload: :media_asset
          )

        files = for {_draft, %PackDraftFile{} = file} <- rows, do: file
        {:ok, %{draft | files: files, media: media}}
    end
  end

  defp file_pairs(files), do: Enum.map(files, &{&1.path, &1.content})

  ## Helpers

  defp require_author(scope) do
    if Scope.has_role?(scope, :author), do: :ok, else: {:error, :forbidden}
  end

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :not_found}
    end
  end

  defp actor_id(%Scope{user: %{id: id}}), do: id
  defp actor_id(_scope), do: nil
end
