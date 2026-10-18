defmodule Espalier.Media do
  @moduledoc """
  The media library of task 0018: images, SVG files, videos and captions
  that lessons place through the block kinds `figure` and `video`.

  ## Limits

  The runtime settings of README section 6.11 and the fixed limits of
  `config :espalier, :media` (step 4) are read through the functions of this
  module. A fixed limit that is no positive integer raises `ArgumentError`,
  as `Espalier.Interop.retention/0` does.
  """

  import Ecto.Query

  require Logger

  alias Espalier.Accounts.Scope
  alias Espalier.Audit
  alias Espalier.Catalog.Pack.Publisher
  alias Espalier.Catalog.{PackImport, Program, ProgramMedia}
  alias Espalier.Media.{Asset, Clamd, Command, Processor, ProcessWorker, Sniff, Store}
  alias Espalier.Repo
  alias Espalier.SecurityLog
  alias Espalier.Workbench.{PackDraft, PackDraftMedia}

  @fixed_limits [
    :svg_max_bytes,
    :captions_max_bytes,
    :max_input_pixels,
    :max_video_pixels,
    :max_frames,
    :image_timeout_seconds,
    :video_timeout_factor,
    :video_timeout_floor_seconds,
    :heartbeat_seconds,
    :stale_processing_seconds,
    :max_pack_media,
    :max_draft_media,
    :export_max_mb
  ]

  @mib 1_048_576

  @typedoc "The kinds of media assets."
  @type kind :: :image | :svg | :video | :captions

  ## Limits

  @doc """
  Returns the fixed limit `key` of `config :espalier, :media`. Raises
  `ArgumentError` for an unknown key or a value that is no positive integer.
  """
  @spec limit(atom()) :: pos_integer()
  def limit(key) when key in @fixed_limits do
    case Keyword.get(config(), key) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError, "media #{key} must be a positive integer, got: #{inspect(value)}"
    end
  end

  @doc "The largest SVG file in bytes (1,048,576)."
  @spec svg_max_bytes() :: pos_integer()
  def svg_max_bytes, do: limit(:svg_max_bytes)

  @doc "The largest captions file in bytes (524,288)."
  @spec captions_max_bytes() :: pos_integer()
  def captions_max_bytes, do: limit(:captions_max_bytes)

  @doc "The largest width times height of an input image (40,000,000)."
  @spec max_input_pixels() :: pos_integer()
  def max_input_pixels, do: limit(:max_input_pixels)

  @doc "The largest width times height of a video frame (8,294,400, 3840 by 2160)."
  @spec max_video_pixels() :: pos_integer()
  def max_video_pixels, do: limit(:max_video_pixels)

  @doc "The largest number of frames of an animated image (1,000)."
  @spec max_frames() :: pos_integer()
  def max_frames, do: limit(:max_frames)

  @doc "The deadline in seconds of an image, SVG or captions job (120)."
  @spec image_timeout_seconds() :: pos_integer()
  def image_timeout_seconds, do: limit(:image_timeout_seconds)

  @doc "The largest number of media files of a pack (500)."
  @spec max_pack_media() :: pos_integer()
  def max_pack_media, do: limit(:max_pack_media)

  @doc "The largest number of media entries of a workbench draft (500)."
  @spec max_draft_media() :: pos_integer()
  def max_draft_media, do: limit(:max_draft_media)

  @doc "The largest sum of media in MB of a SCORM package or a draft download (1,024)."
  @spec export_max_mb() :: pos_integer()
  def export_max_mb, do: limit(:export_max_mb)

  @doc """
  The deadline in seconds of the conversion of a video of `duration_ms`:
  `max(video_timeout_floor_seconds, video_timeout_factor * duration)`.
  """
  @spec video_timeout_seconds(non_neg_integer()) :: pos_integer()
  def video_timeout_seconds(duration_ms) when is_integer(duration_ms) and duration_ms >= 0 do
    max(
      limit(:video_timeout_floor_seconds),
      ceil(limit(:video_timeout_factor) * duration_ms / 1000)
    )
  end

  @doc """
  The number of days after which an unused asset of origin `pack` is deleted,
  from `config :espalier, :media_retention, unused_days:` (default 30).
  Raises `ArgumentError` for a value that is no positive integer.
  """
  @spec unused_days() :: pos_integer()
  def unused_days do
    case Keyword.get(Application.get_env(:espalier, :media_retention, []), :unused_days, 30) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError,
              "media_retention unused_days must be a positive integer, got: #{inspect(value)}"
    end
  end

  @doc "The root of the media store, `MEDIA_DIR`, as given."
  @spec dir() :: String.t()
  def dir, do: Keyword.fetch!(config(), :dir)

  @doc """
  The largest upload in bytes of `kind`: `MEDIA_IMAGE_MAX_MB` for images,
  `svg_max_bytes`, `captions_max_bytes` and `MEDIA_VIDEO_MAX_MB`.
  """
  @spec max_bytes(kind()) :: pos_integer()
  def max_bytes(:image), do: setting(:image_max_mb, 20) * @mib
  def max_bytes(:svg), do: svg_max_bytes()
  def max_bytes(:captions), do: captions_max_bytes()
  def max_bytes(:video), do: setting(:video_max_mb, 1024) * @mib

  @doc "The largest upload of any kind in bytes, the length of the upload parser."
  @spec max_upload_bytes() :: pos_integer()
  def max_upload_bytes, do: max(max_bytes(:image), max_bytes(:video))

  @doc "The longest video in milliseconds (`MEDIA_VIDEO_MAX_MINUTES`)."
  @spec video_max_ms() :: pos_integer()
  def video_max_ms, do: setting(:video_max_minutes, 60) * 60_000

  @doc "The height of a converted video (`MEDIA_VIDEO_MAX_HEIGHT`)."
  @spec video_max_height() :: pos_integer()
  def video_max_height, do: setting(:video_max_height, 1080)

  @doc "The longest edge of a converted image (`MEDIA_IMAGE_MAX_EDGE`)."
  @spec image_max_edge() :: pos_integer()
  def image_max_edge, do: setting(:image_max_edge, 2560)

  @doc "The storage quota in bytes (`MEDIA_STORAGE_MAX_GB`)."
  @spec storage_max_bytes() :: pos_integer()
  def storage_max_bytes, do: setting(:storage_max_gb, 50) * 1024 * @mib

  @doc "The threads per ffmpeg and ffprobe process (`MEDIA_FFMPEG_THREADS`)."
  @spec ffmpeg_threads() :: pos_integer()
  def ffmpeg_threads, do: setting(:ffmpeg_threads, 2)

  @doc "The hosts of `MEDIA_EXTERNAL_HOSTS` as `{host, port | nil}`."
  @spec external_hosts() :: [{String.t(), pos_integer() | nil}]
  def external_hosts, do: setting(:external_hosts, [])

  @doc "The hosts of `MEDIA_EMBED_HOSTS` as `{host, port | nil}`."
  @spec embed_hosts() :: [{String.t(), pos_integer() | nil}]
  def embed_hosts, do: setting(:embed_hosts, [])

  @doc "`:click` or `:auto` (`MEDIA_EMBED_CONSENT`)."
  @spec embed_consent() :: :click | :auto
  def embed_consent, do: setting(:embed_consent, :click)

  @doc "The path of the clamd socket (`MEDIA_CLAMAV_SOCKET`), or `nil`."
  @spec clamav_socket() :: String.t() | nil
  def clamav_socket, do: setting(:clamav_socket, nil)

  ## Paths and URLs

  @mimes %{
    "webp" => "image/webp",
    "svg" => "image/svg+xml",
    "webm" => "video/webm",
    "vtt" => "text/vtt"
  }

  @doc "The type of a delivery file by its extension."
  @spec mime(String.t() | nil) :: String.t() | nil
  def mime(ext), do: Map.get(@mimes, ext)

  @doc "The URL of the delivery file of a `ready` asset below `/media/`, or `nil`."
  @spec url(Asset.t()) :: String.t() | nil
  def url(%Asset{status: :ready, sha256: sha256, ext: ext}) when is_binary(sha256),
    do: "/media/#{sha256}.#{ext}"

  def url(%Asset{}), do: nil

  @doc "The URL of the poster of a `ready` asset below `/media/`, or `nil`."
  @spec poster_url(Asset.t()) :: String.t() | nil
  def poster_url(%Asset{status: :ready, poster_sha256: sha256}) when is_binary(sha256),
    do: "/media/#{sha256}.webp"

  def poster_url(%Asset{}), do: nil

  @doc "The delivery extension of `kind`."
  @spec delivery_ext(kind()) :: String.t()
  def delivery_ext(:image), do: "webp"
  def delivery_ext(:svg), do: "svg"
  def delivery_ext(:video), do: "webm"
  def delivery_ext(:captions), do: "vtt"

  ## Ingest

  @doc """
  Adds an uploaded file of the library (`origin: :upload`) for an author.
  The file at `path` is moved into the store. Returns `{:ok, asset,
  :created}` for a new asset and `{:ok, asset, :existing}` when an asset of
  the same source or with the same delivery file exists.

  Errors: `:forbidden`, `:unsupported_type`, `:extension_mismatch`,
  `:too_many_pixels` (the detection of `Espalier.Media.Sniff`),
  `:media_too_large` (the limit of the detected kind) and `:storage_full`.
  """
  @spec ingest(Scope.t(), %{path: Path.t(), file_name: String.t()}, keyword()) ::
          {:ok, Asset.t(), :created | :existing} | {:error, atom()}
  def ingest(scope, file, opts \\ [])

  def ingest(%Scope{} = scope, %{path: path, file_name: file_name}, _opts) do
    with :ok <- author(scope) do
      do_ingest({:move, path}, file_name, :upload, scope)
    end
  end

  @doc """
  Adds a media file of a content pack (`origin: :pack`) for the importer.
  The file is copied and stays in the pack. It runs no role check, because
  `Espalier.Catalog.import_pack/3` checks the role of the author and the
  Mix tasks and release functions run as the operator; `actor_id` becomes
  `created_by_id`, and no audit event is written.
  """
  @spec ingest_pack_file(%{path: Path.t(), file_name: String.t()}, String.t() | nil) ::
          {:ok, Asset.t(), :created | :existing} | {:error, atom()}
  def ingest_pack_file(%{path: path, file_name: file_name}, actor_id) do
    do_ingest({:copy, path}, file_name, :pack, actor_id)
  end

  defp do_ingest({_mode, path} = source, file_name, origin, actor) do
    with {:ok, %{kind: kind}} <- Sniff.detect(path, file_name),
         {:ok, bytes} <- file_size(path),
         :ok <- size(kind, bytes) do
      new = %{kind: kind, bytes: bytes, file_name: file_name, origin: origin, actor: actor}
      place_and_record(source, new)
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: bytes}} -> {:ok, bytes}
      {:error, _posix} -> {:error, :unsupported_type}
    end
  end

  # The copy is placed before the transaction, so that a long copy holds no
  # lock; it stays only for a new asset (a failed asset that starts again
  # moved it to its own incoming path). An exception, such as a lost
  # database connection, removes the copy as well, because no asset row
  # counts it against the quota.
  defp place_and_record({_mode, path} = source, new) do
    id = Ecto.UUID.generate()
    new = Map.merge(new, %{id: id, sha256: Store.sha256_file(path)})

    result =
      try do
        case Store.accept_incoming(source, id) do
          :ok -> insert_or_reuse(new)
          {:error, reason} -> placement_error(reason)
        end
      catch
        kind, reason ->
          remove_incoming(id)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    unless match?({:ok, _asset, :created}, result), do: remove_incoming(id)
    result
  end

  @doc false
  # The answer to a copy or move into incoming/ that failed with `reason`:
  # storage_full for a full volume or an exhausted disk quota
  # (Espalier.Media.Store.full?/1), and a raise of File.Error for any other
  # reason. Public, so that a test can pass the reasons of a full volume,
  # which no test can produce on its file system.
  @spec placement_error(term()) :: {:error, :storage_full}
  def placement_error(reason) do
    if Store.full?(reason),
      do: {:error, :storage_full},
      else: raise(File.Error, reason: reason, action: "place", path: "incoming")
  end

  defp size(kind, bytes) do
    if bytes > max_bytes(kind), do: {:error, :media_too_large}, else: :ok
  end

  defp insert_or_reuse(new) do
    Repo.transact(fn ->
      lock_quota()

      case existing(new.sha256) do
        %Asset{status: :failed} = asset -> retry(asset, new)
        %Asset{} = asset -> reuse(asset, new)
        nil -> insert(new)
      end
    end)
    |> case do
      {:ok, {asset, created_or_existing}} -> {:ok, asset, created_or_existing}
      {:error, reason} -> {:error, reason}
    end
  end

  # The asset of the same source, or else the oldest ready asset whose
  # delivery file has the digest of this source: a pack exported by this
  # installation holds delivery files. FOR NO KEY UPDATE waits for a
  # deletion that runs (FOR UPDATE), after which the row is gone, and passes
  # the FOR KEY SHARE of a publish, so an upload does not wait for one.
  defp existing(sha256) do
    Repo.one(from(a in Asset, where: a.source_sha256 == ^sha256, lock: "FOR NO KEY UPDATE")) ||
      Repo.one(
        from a in Asset,
          where: a.sha256 == ^sha256 and a.status == :ready,
          order_by: [asc: a.inserted_at, asc: a.id],
          limit: 1,
          lock: "FOR NO KEY UPDATE"
      )
  end

  defp reuse(%Asset{} = asset, new) do
    changes =
      []
      |> then(&if(asset.status == :processing, do: &1, else: [{:updated_at, now()} | &1]))
      |> then(&if(new.origin == :upload, do: [{:origin, :upload} | &1], else: &1))

    asset =
      if changes == [],
        do: asset,
        else: asset |> Ecto.Changeset.change(changes) |> Repo.update!()

    {:ok, {asset, :existing}}
  end

  # A failed asset of the same source starts again with the new copy. An
  # actor of the new ingest becomes the creator, so that the scan of the
  # new job names the person whose copy it reads, and an upload writes
  # media.uploaded as for a new asset. An ingest without an actor keeps the
  # creator. The copy moves to the incoming path of the asset after the
  # writes, so that an exception of a write leaves it at its own path, where
  # place_and_record/2 removes it.
  defp retry(%Asset{} = asset, new) do
    with :ok <- quota(new.bytes) do
      asset =
        asset
        |> Ecto.Changeset.change(
          status: :queued,
          failure: nil,
          failure_detail: nil,
          incoming_bytes: new.bytes,
          progress: 0,
          origin: if(new.origin == :upload, do: :upload, else: asset.origin),
          created_by_id: actor_id(new.actor) || asset.created_by_id
        )
        |> Repo.update!()

      {:ok, _job} = Oban.insert(job(asset))

      if new.origin == :upload do
        {:ok, _event} = Audit.record(new.actor, "media.uploaded", asset, %{kind: asset.kind})
      end

      :ok = File.rename(Store.incoming_path(new.id), Store.incoming_path(asset.id))
      {:ok, {asset, :existing}}
    end
  end

  defp insert(new) do
    with :ok <- quota(new.bytes) do
      asset =
        Repo.insert!(%Asset{
          id: new.id,
          kind: new.kind,
          status: :queued,
          title: title(new.file_name, new.kind),
          source_name: source_name(new.file_name),
          source_sha256: new.sha256,
          incoming_bytes: new.bytes,
          progress: 0,
          origin: new.origin,
          created_by_id: actor_id(new.actor)
        })

      {:ok, _job} = Oban.insert(job(asset))

      if new.origin == :upload do
        {:ok, _event} = Audit.record(new.actor, "media.uploaded", asset, %{kind: asset.kind})
      end

      {:ok, {asset, :created}}
    end
  end

  defp actor_id(%Scope{user: %{id: id}}), do: id
  defp actor_id(id) when is_binary(id), do: id
  defp actor_id(_actor), do: nil

  defp job(%Asset{} = asset) do
    queue = if asset.kind == :video, do: :media_video, else: :media

    ProcessWorker.new(%{"asset_id" => asset.id, "kind" => Atom.to_string(asset.kind)},
      queue: queue
    )
  end

  # The file name without its extension, valid UTF-8 without U+0000, at
  # most 255 characters as cut/2 counts them.
  defp title(file_name, kind) do
    title =
      file_name
      |> clean_name()
      |> Path.basename()
      |> Path.rootname()
      |> cut(Asset.max_title())

    if String.trim(title) == "", do: Atom.to_string(kind), else: title
  end

  # At most 255 characters as cut/2 counts them, the extension kept.
  defp source_name(file_name) do
    name = file_name |> clean_name() |> Path.basename()
    ext = Path.extname(name)

    if code_points(name) <= 255,
      do: name,
      else: cut(Path.rootname(name), 255 - code_points(ext)) <> ext
  end

  # The longest prefix of whole graphemes with at most `max` characters.
  # Both columns are varchar(255), whose length PostgreSQL counts in code
  # points, so a letter with a combining accent or an emoji sequence counts
  # with each of its code points.
  defp cut(text, max) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {kept, count} ->
      count = count + code_points(grapheme)
      if count <= max, do: {:cont, {[grapheme | kept], count}}, else: {:halt, {kept, count}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp code_points(text), do: text |> String.codepoints() |> length()

  defp clean_name(name) do
    name |> String.replace_invalid("_") |> String.replace(<<0>>, "")
  end

  # Every path comes from Espalier.Media.Store, built from MEDIA_DIR and a
  # digest, a UUID or a fixed name (ASVS 5.3.2).
  # sobelow_skip ["Traversal.FileModule"]
  defp remove_incoming(id) do
    _ignored = File.rm(Store.incoming_path(id))
    :ok
  end

  ## Quota

  @doc """
  The bytes that the store holds or expects: the sum of `bytes`,
  `poster_bytes` and `incoming_bytes` over all assets. A file that several
  assets share counts once per asset, which overstates the use.
  """
  @spec used_bytes() :: non_neg_integer()
  def used_bytes do
    from(a in Asset,
      select:
        coalesce(sum(coalesce(a.bytes, 0) + coalesce(a.poster_bytes, 0) + a.incoming_bytes), 0)
    )
    |> Repo.one()
    |> to_integer()
  end

  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value

  # The quota lock serializes the ingests and the ready transitions, so two
  # of them count one after the other. A transaction that also takes the
  # file lock takes this one first.
  defp lock_quota do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext('espalier.media'))")
    :ok
  end

  defp quota(extra) do
    if used_bytes() + extra > storage_max_bytes(), do: {:error, :storage_full}, else: :ok
  end

  ## Processing

  @doc """
  Processes the asset `asset_id` in the calling process: moves it from
  `queued` to `processing` with a conditional update (a no-op when another
  worker took it or it is no longer queued), scans it when
  `MEDIA_CLAMAV_SOCKET` is set, runs the processor of its kind, and stores
  the outputs and the facts, or records the failure. Returns `:ok`.

  While the job runs, a heartbeat sets `updated_at` of the asset every
  `heartbeat_seconds/0`, so that `Espalier.Media.StaleWorker` tells a
  running job from an interrupted one. An exception or exit in the job
  fails the asset with `conversion_failed` at once and is raised again.

  A job whose asset is deleted, or leaves `processing` otherwise, stops.
  The progress update of a video conversion or the heartbeat stops its
  running command (`Espalier.Media.Command.cancel/1`). Between two steps
  the job reads the status of its asset: after the scan, before each
  command and before it writes the output of the SVG rebuild, the captions
  check or the check of an animated WebP. A stopped job starts no further
  command, stores no file, changes no status and logs `media asset <id>
  stopped, because it is no longer processing` at `info`. A result or a
  failure that the job reaches anyway changes no row and logs the same
  line in place of a failure line.
  """
  @spec process(String.t()) :: :ok
  def process(asset_id) do
    {count, _rows} =
      Repo.update_all(
        from(a in Asset, where: a.id == ^asset_id and a.status == :queued),
        set: [status: :processing, progress: 0, updated_at: now()]
      )

    # A deletion between the claim and the read leaves nothing to process.
    with 1 <- count, %Asset{} = asset <- Repo.get(Asset, asset_id) do
      run(asset)
    else
      _other -> :ok
    end
  end

  @doc """
  Processes a `queued` asset in the calling process, as the import paths of
  the Mix tasks and the release functions do, which run Oban without
  queues. Returns the asset as it ends: `ready`, `failed`, or as another
  worker left it.
  """
  @spec process_now(Asset.t()) :: Asset.t()
  def process_now(%Asset{id: id} = asset) do
    :ok = process(id)
    Repo.get(Asset, id) || asset
  end

  @doc """
  The timeout of the job of `kind` in milliseconds: the largest deadline of
  its commands (with `MEDIA_VIDEO_MAX_MINUTES` for the duration of a video)
  plus the scan timeout of the size limit of the kind plus 60 seconds, so
  that `Espalier.Media.Command` reaches its deadline first.
  """
  @spec job_timeout_ms(kind()) :: pos_integer()
  def job_timeout_ms(kind) do
    commands =
      case kind do
        :video -> video_timeout_seconds(video_max_ms()) + image_timeout_seconds()
        _other -> image_timeout_seconds()
      end

    (commands + 60) * 1000 + Clamd.scan_timeout_ms(max_bytes(kind))
  end

  @doc "The interval in seconds of the heartbeat of a running job (60)."
  @spec heartbeat_seconds() :: pos_integer()
  def heartbeat_seconds, do: limit(:heartbeat_seconds)

  @doc """
  The age in seconds of `updated_at` after which `Espalier.Media.StaleWorker`
  fails an asset in `processing` with `interrupted` (600, ten heartbeats).
  """
  @spec stale_processing_seconds() :: pos_integer()
  def stale_processing_seconds, do: limit(:stale_processing_seconds)

  # Each run takes a work directory of its own, so that a run that ends
  # never removes the directory of a later run of the same asset. Every
  # path comes from Espalier.Media.Store, built from MEDIA_DIR and a digest,
  # a UUID or a fixed name (ASVS 5.3.2).
  # sobelow_skip ["Traversal.FileModule"]
  defp run(%Asset{} = asset) do
    incoming = Store.incoming_path(asset.id)
    work_dir = Store.work_dir(asset.id, Ecto.UUID.generate())
    heartbeat = start_heartbeat(asset.id)

    try do
      File.mkdir_p!(work_dir)

      result =
        with :ok <- scan(asset, incoming),
             :ok <- proceed(asset),
             {:ok, detection} <- detect(incoming, asset) do
          Processor.run(asset.kind, incoming, detection, processor_opts(asset, work_dir))
        end

      settle(asset, incoming, work_dir, result)
    catch
      kind, reason ->
        fail_crashed(asset, incoming, work_dir)
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      stop_heartbeat(heartbeat)
      _ignored = File.rm_rf(work_dir)
    end

    :ok
  end

  # A cancelled job found its asset deleted or no longer in processing. It
  # changes no status and leaves the incoming file, which the deletion
  # removes and which a new job of a failed asset that starts again needs.
  defp settle(%Asset{id: id}, _incoming, _work_dir, {:error, :cancelled, nil}), do: stopped(id)

  # Otherwise the incoming file and, for a failure, the work directory go
  # before the status changes: a failed asset can start again with a new
  # copy at the same incoming path (insert_or_reuse/1), which this job must
  # not remove.
  # sobelow_skip ["Traversal.FileModule"]
  defp settle(%Asset{} = asset, incoming, work_dir, result) do
    _ignored = File.rm(incoming)
    if match?({:error, _failure, _detail}, result), do: File.rm_rf(work_dir)
    finish(asset, result)
  end

  # An exception or exit of the job fails its asset at once and removes the
  # incoming file and the work directory first, as every failure does. When
  # that record fails as well, the asset waits for the sweep of StaleWorker,
  # and the first error goes on.
  # sobelow_skip ["Traversal.FileModule"]
  defp fail_crashed(%Asset{} = asset, incoming, work_dir) do
    _ignored = File.rm(incoming)
    _ignored = File.rm_rf(work_dir)
    finish(asset, {:error, :conversion_failed, nil})
  rescue
    _exception -> :ok
  end

  # The heartbeat runs in a process of its own and sets updated_at of the
  # asset every heartbeat_seconds while the asset is in processing. It
  # monitors the job and ends with it; it holds no link, so its own failure
  # never ends the job. An update that finds no row in processing means that
  # the asset was deleted or failed meanwhile: the heartbeat then cancels
  # the command of the job and ends.
  defp start_heartbeat(asset_id) do
    job = self()
    interval = heartbeat_seconds() * 1000
    {:ok, pid} = Task.start(fn -> beat(asset_id, job, Process.monitor(job), interval) end)
    pid
  end

  defp beat(asset_id, job, ref, interval) do
    receive do
      {__MODULE__, :stop} -> :ok
      {:DOWN, ^ref, :process, ^job, _reason} -> :ok
    after
      interval ->
        case touch(asset_id) do
          0 -> Command.cancel(job)
          _count_or_error -> beat(asset_id, job, ref, interval)
        end
    end
  end

  # A failed update, for example while the database is away, skips one beat.
  defp touch(asset_id) do
    {count, _rows} =
      Repo.update_all(
        from(a in Asset, where: a.id == ^asset_id and a.status == :processing),
        set: [updated_at: now()]
      )

    count
  rescue
    _exception -> :error
  end

  # Waits for the end of the heartbeat, which a beat delays by at most the
  # query timeout of the repo, and then drops a cancel that it sent after
  # the last command of the job.
  defp stop_heartbeat(pid) do
    ref = Process.monitor(pid)
    send(pid, {__MODULE__, :stop})

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end

    Command.drop_cancel()
  end

  defp processor_opts(%Asset{} = asset, work_dir) do
    started = System.monotonic_time(:millisecond)

    [
      work_dir: work_dir,
      deadline: started + image_timeout_seconds() * 1000,
      on_duration: fn duration_ms ->
        started + (video_timeout_seconds(duration_ms) + image_timeout_seconds()) * 1000
      end,
      on_progress: progress_callback(asset),
      proceed: fn -> if processing?(asset.id), do: :ok, else: :halt end
    ]
  end

  # A deletion, or a failure by the sweep, while no command runs (the scan,
  # the detection or a step in the BEAM) stops the job before its next
  # step; the heartbeat and the progress update reach only a running
  # command.
  defp proceed(%Asset{id: id}) do
    if processing?(id), do: :ok, else: {:error, :cancelled, nil}
  end

  # A failed read, for example while the database is away, lets the job go
  # on, as a failed heartbeat does.
  defp processing?(id) do
    Repo.exists?(from a in Asset, where: a.id == ^id and a.status == :processing)
  rescue
    _exception -> true
  end

  defp stopped(id) do
    Logger.info("media asset #{id} stopped, because it is no longer processing")
    :ok
  end

  # Updates progress at most once per two seconds. An update that finds the
  # asset no longer in processing (deleted, or failed by the sweep) answers
  # :halt, which stops the conversion (Espalier.Media.Command).
  defp progress_callback(%Asset{id: id}) do
    fn percent ->
      now = System.monotonic_time(:millisecond)
      last = Process.get({__MODULE__, :progress_at})

      if last == nil or now - last >= 2_000 do
        Process.put({__MODULE__, :progress_at}, now)
        update_progress(id, percent)
      else
        :ok
      end
    end
  end

  # A failed update, for example while the database is away, skips that
  # update, as touch/1 skips a beat, and the conversion goes on.
  defp update_progress(id, percent) do
    {count, _rows} =
      Repo.update_all(
        from(a in Asset, where: a.id == ^id and a.status == :processing),
        set: [progress: percent, updated_at: now()]
      )

    if count == 0, do: :halt, else: :ok
  rescue
    _exception -> :ok
  end

  # The scan reads the incoming file before ffprobe, xmerl or the WebVTT
  # check touch it; without MEDIA_CLAMAV_SOCKET no scan runs.
  defp scan(%Asset{} = asset, incoming) do
    if Clamd.enabled?() do
      case Clamd.scan(incoming) do
        :clean ->
          :ok

        {:found, signature} ->
          SecurityLog.event(:upload_validation, %{
            user_id: asset.created_by_id,
            reason: Clamd.signature_reason(signature)
          })

          {:error, :malware_found, nil}

        {:error, error} ->
          {:error, :scan_failed, Clamd.reason_tag(error)}
      end
    else
      :ok
    end
  end

  # The ingest checked the extension; the job checks the signature and the
  # header again, under a name with an extension of the kind of the asset.
  defp detect(incoming, %Asset{} = asset) do
    [ext | _rest] = Map.fetch!(Sniff.extensions(), asset.kind)

    case Sniff.detect(incoming, "source." <> ext) do
      {:ok, %{kind: kind} = detection} when kind == asset.kind -> {:ok, detection}
      {:error, :too_many_pixels} -> {:error, :too_many_pixels, nil}
      _other -> {:error, :conversion_failed, nil}
    end
  end

  defp finish(%Asset{} = asset, {:ok, outputs}) do
    delivery = Store.digest(outputs.delivery)
    poster = if outputs.poster, do: Store.digest(outputs.poster)

    case Repo.transact(fn -> store_outputs(asset, outputs, delivery, poster) end) do
      {:ok, :storage_full} -> finish(asset, {:error, :storage_full, nil})
      {:ok, :done} -> :ok
    end
  end

  # A failure that changes no row, because the asset was deleted or failed
  # by the sweep meanwhile, logs the stop of the job in place of the
  # failure. A finding logs the security event upload_validation instead.
  defp finish(%Asset{} = asset, {:error, failure, detail}) do
    {count, _rows} =
      Repo.update_all(
        from(a in Asset, where: a.id == ^asset.id and a.status == :processing),
        set: [
          status: :failed,
          failure: failure,
          failure_detail: detail,
          incoming_bytes: 0,
          updated_at: now()
        ]
      )

    cond do
      count == 0 -> stopped(asset.id)
      failure == :malware_found -> :ok
      true -> log_failure(asset.id, failure, detail)
    end

    :ok
  end

  defp log_failure(id, failure, nil), do: Logger.error("media asset #{id} failed: #{failure}")

  defp log_failure(id, failure, detail),
    do: Logger.error("media asset #{id} failed: #{failure} (#{detail})")

  # Under the quota lock and then the file lock: the quota without the
  # incoming file of this asset and with its outputs, the conditional
  # change to ready, and the move of the outputs into the store, so that a
  # file that the asset names is never removed under it.
  defp store_outputs(asset, outputs, {_sha256, bytes} = delivery, poster) do
    lock_quota()
    Store.lock_files()
    poster_bytes = if poster, do: elem(poster, 1), else: 0

    if used_bytes() - incoming_bytes(asset.id) + bytes + poster_bytes > storage_max_bytes(),
      do: {:ok, :storage_full},
      else: {:ok, ready(asset, outputs, delivery, poster)}
  end

  defp ready(asset, outputs, {sha256, bytes}, poster) do
    {count, _rows} =
      Repo.update_all(
        from(a in Asset, where: a.id == ^asset.id and a.status == :processing),
        set:
          [
            status: :ready,
            sha256: sha256,
            ext: outputs.ext,
            bytes: bytes,
            poster_sha256: poster && elem(poster, 0),
            poster_bytes: poster && elem(poster, 1),
            incoming_bytes: 0,
            progress: 100,
            updated_at: now()
          ] ++ Map.to_list(outputs.facts)
      )

    if count == 1 do
      Store.place(outputs.delivery, outputs.ext, sha256)
      if poster, do: Store.place(outputs.poster, "webp", elem(poster, 0))
    else
      stopped(asset.id)
    end

    :done
  end

  defp incoming_bytes(id) do
    Repo.one(from a in Asset, where: a.id == ^id, select: a.incoming_bytes) || 0
  end

  @doc """
  Fails an asset in `processing` with `failure` (the stale sweep uses
  `:interrupted`) and logs the asset id and the code. Returns the number of
  changed rows.
  """
  @spec fail(String.t(), atom()) :: non_neg_integer()
  def fail(asset_id, failure) do
    {count, _rows} =
      Repo.update_all(
        from(a in Asset, where: a.id == ^asset_id and a.status == :processing),
        set: [status: :failed, failure: failure, incoming_bytes: 0, updated_at: now()]
      )

    if count == 1, do: log_failure(asset_id, failure, nil)

    count
  end

  ## Library

  @doc """
  Lists the assets of the library for an author, newest first. Filters:
  `:kind`, `:status`, `:unused` (no program, draft or validated import
  uses the asset), `:q` (a case-insensitive part of the title), `:limit`
  (1 to 100, default 50) and `:after` (the cursor `next` of the previous
  page). Returns `%{items: assets, next: cursor | nil}`.
  """
  @spec list_assets(Scope.t(), map()) ::
          {:ok, %{items: [Asset.t()], next: String.t() | nil}} | {:error, term()}
  def list_assets(%Scope{} = scope, filters) do
    with :ok <- author(scope),
         {:ok, cursor} <- decode_cursor(Map.get(filters, :after)) do
      limit = Map.get(filters, :limit) || 50

      assets =
        from(a in Asset, as: :asset)
        |> filter(:kind, Map.get(filters, :kind))
        |> filter(:status, Map.get(filters, :status))
        |> filter(:q, Map.get(filters, :q))
        |> filter(:unused, Map.get(filters, :unused))
        |> filter(:after, cursor)
        |> order_by([a], desc: a.inserted_at, desc: a.id)
        |> limit(^(limit + 1))
        |> Repo.all()

      {items, rest} = Enum.split(assets, limit)
      next = if rest == [], do: nil, else: encode_cursor(List.last(items))
      {:ok, %{items: items, next: next}}
    end
  end

  defp filter(query, _key, nil), do: query
  defp filter(query, :kind, kind), do: where(query, [a], a.kind == ^to_atom(kind, Asset, :kind))

  defp filter(query, :status, status),
    do: where(query, [a], a.status == ^to_atom(status, Asset, :status))

  defp filter(query, :q, q) do
    pattern = "%" <> String.replace(q, ["\\", "%", "_"], &("\\" <> &1)) <> "%"
    where(query, [a], ilike(a.title, ^pattern))
  end

  defp filter(query, :unused, false), do: query
  defp filter(query, :unused, true), do: where(query, [a], not exists(uses_query()))

  defp filter(query, :after, {inserted_at, id}) do
    where(
      query,
      [a],
      a.inserted_at < ^inserted_at or (a.inserted_at == ^inserted_at and a.id < ^id)
    )
  end

  defp to_atom(value, _schema, _field) when is_atom(value), do: value

  defp to_atom(value, schema, field) when is_binary(value) do
    Enum.find(Ecto.Enum.values(schema, field), &(Atom.to_string(&1) == value))
  end

  # The programs, drafts and validated imports that use the asset of the
  # outer query. The imports are matched by containment (`@>`), which the
  # GIN index on media_asset_ids serves; `= ANY` would scan the table.
  defp uses_query do
    from p in ProgramMedia,
      where: p.media_asset_id == parent_as(:asset).id,
      select: 1,
      union_all:
        ^from(d in PackDraftMedia, where: d.media_asset_id == parent_as(:asset).id, select: 1),
      union_all:
        ^from(i in PackImport,
          where:
            i.status == :validated and
              fragment("? @> ARRAY[?]", i.media_asset_ids, parent_as(:asset).id),
          select: 1
        )
  end

  defp encode_cursor(%Asset{inserted_at: inserted_at, id: id}) do
    Base.url_encode64("#{DateTime.to_iso8601(inserted_at)}|#{id}", padding: false)
  end

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) do
    with {:ok, text} <- Base.url_decode64(cursor, padding: false),
         [time, id] <- String.split(text, "|"),
         {:ok, inserted_at, 0} <- DateTime.from_iso8601(time),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, {inserted_at, id}}
    else
      _invalid -> {:error, {:validation_failed, "after", "invalid"}}
    end
  end

  @doc "Returns an asset with its uses for an author."
  @spec get_asset(Scope.t(), term()) ::
          {:ok, Asset.t(), uses()} | {:error, :forbidden | :not_found}
  def get_asset(%Scope{} = scope, id) do
    with :ok <- author(scope),
         {:ok, asset} <- fetch(id) do
      {:ok, asset, uses(asset)}
    end
  end

  @doc "Changes the title of an asset for an author."
  @spec update_asset(Scope.t(), term(), map()) ::
          {:ok, Asset.t()} | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
  def update_asset(%Scope{} = scope, id, attrs) do
    with :ok <- author(scope),
         {:ok, asset} <- fetch(id) do
      asset |> Asset.changeset(attrs) |> Repo.update()
    end
  end

  @doc """
  Deletes an asset for an author. The row is locked with `FOR UPDATE`; while
  a published program or a draft uses the asset the answer is
  `{:error, {:asset_in_use, uses}}`. Otherwise the row and the audit event
  `media.deleted` are written in one transaction, and the files are removed
  after the commit through `Espalier.Media.Store.remove/2`.
  """
  @spec delete_asset(Scope.t(), term()) ::
          :ok | {:error, :forbidden | :not_found | {:asset_in_use, uses()}}
  def delete_asset(%Scope{} = scope, id) do
    with :ok <- author(scope),
         {:ok, id} <- cast_id(id),
         {:ok, asset} <-
           Repo.transact(fn -> delete_locked(scope, id) end, timeout: lock_timeout()) do
      remove_files(asset)
    end
  end

  defp delete_locked(scope, id) do
    with %Asset{} = asset <- Repo.one(from a in Asset, where: a.id == ^id, lock: "FOR UPDATE"),
         :ok <- unused(uses(asset)) do
      Repo.delete!(asset)
      {:ok, _event} = Audit.record(scope, "media.deleted", asset, %{kind: asset.kind})
      {:ok, asset}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  The timeout of a transaction that locks an asset with `FOR UPDATE`: the
  lock waits for a publish that holds `FOR KEY SHARE` on the asset, so it
  takes the timeout of the publisher plus one minute.
  """
  @spec lock_timeout() :: timeout()
  def lock_timeout do
    case Publisher.transaction_timeout() do
      :infinity -> :infinity
      timeout -> timeout + 60_000
    end
  end

  defp unused(%{programs: [], drafts: []}), do: :ok
  defp unused(uses), do: {:error, {:asset_in_use, uses}}

  @doc """
  Removes the delivery file, the poster and an incoming file of a deleted
  asset, each unless another asset names its digest.
  """
  @spec remove_files(Asset.t()) :: :ok
  def remove_files(%Asset{} = asset) do
    if asset.sha256, do: Store.remove(asset.sha256, asset.ext)
    if asset.poster_sha256, do: Store.remove(asset.poster_sha256, "webp")
    remove_incoming(asset.id)
  end

  @typedoc "The uses of an asset."
  @type uses :: %{
          programs: [%{slug: String.t(), title: String.t()}],
          drafts: [%{id: String.t(), title: String.t(), path: String.t()}],
          imports: [%{id: String.t(), pack_key: String.t() | nil, inserted_at: DateTime.t()}]
        }

  @doc """
  The uses of an asset: the programs of `program_media`, the drafts of
  `pack_draft_media` and the imports in status `validated` whose
  `media_asset_ids` contain it, a containment that the GIN index of the
  column serves. A payload without media holds none.
  """
  @spec uses(Asset.t()) :: uses()
  def uses(%Asset{id: id}) do
    %{
      programs:
        Repo.all(
          from pm in ProgramMedia,
            join: p in Program,
            on: p.id == pm.program_id,
            where: pm.media_asset_id == ^id,
            distinct: true,
            order_by: [asc: p.slug],
            select: %{slug: p.slug, title: p.title}
        ),
      drafts:
        Repo.all(
          from dm in PackDraftMedia,
            join: d in PackDraft,
            on: d.id == dm.pack_draft_id,
            where: dm.media_asset_id == ^id,
            order_by: [asc: d.title, asc: dm.path],
            select: %{id: d.id, title: d.title, path: dm.path}
        ),
      imports:
        Repo.all(
          from i in PackImport,
            where:
              i.status == :validated and
                fragment("? @> ?", i.media_asset_ids, type(^[id], {:array, Ecto.UUID})),
            order_by: [desc: i.inserted_at],
            select: %{id: i.id, pack_key: i.pack_key, inserted_at: i.inserted_at}
        )
    }
  end

  @doc "The assets with the ids `ids` as a map of id to asset."
  @spec assets_by_id([String.t()]) :: %{String.t() => Asset.t()}
  def assets_by_id(ids) when is_list(ids) do
    ids = for id <- ids, {:ok, id} <- [Ecto.UUID.cast(id)], uniq: true, do: id
    Map.new(Repo.all(from a in Asset, where: a.id in ^ids), &{&1.id, &1})
  end

  @doc """
  The media policy of the installation in the form of the pack view:
  `external_hosts` and `embed_hosts` as `host` or `host:port`, and
  `embed_consent`.
  """
  @spec policy() :: %{
          external_hosts: [String.t()],
          embed_hosts: [String.t()],
          embed_consent: String.t()
        }
  def policy do
    %{
      external_hosts: Enum.map(external_hosts(), &host_text/1),
      embed_hosts: Enum.map(embed_hosts(), &host_text/1),
      embed_consent: Atom.to_string(embed_consent())
    }
  end

  defp host_text({host, nil}), do: host
  defp host_text({host, port}), do: "#{host}:#{port}"

  ## Serving

  @doc """
  True when `scope` may read the stored file `sha256` with `ext`: a `ready`
  asset names the digest as its delivery file with that extension, or as
  its poster for `webp`. An author reads every such file; another user only
  one that a published program uses through `program_media` (ASVS 8.2.2).
  """
  @spec servable(Scope.t() | nil, String.t(), String.t()) :: boolean()
  def servable(%Scope{user: %{}} = scope, sha256, ext) do
    query =
      from a in Asset,
        as: :asset,
        where: a.status == :ready,
        where:
          (a.sha256 == ^sha256 and a.ext == ^ext) or
            (a.poster_sha256 == ^sha256 and ^ext == "webp")

    query =
      if Scope.has_role?(scope, :author) do
        query
      else
        from a in query,
          join: pm in ProgramMedia,
          on: pm.media_asset_id == a.id,
          join: p in Program,
          on: p.id == pm.program_id and p.status == :published
      end

    Repo.exists?(query)
  end

  def servable(_scope, _sha256, _ext), do: false

  ## Helpers

  defp author(scope) do
    if Scope.has_role?(scope, :author), do: :ok, else: {:error, :forbidden}
  end

  defp fetch(id) do
    with {:ok, id} <- cast_id(id),
         %Asset{} = asset <- Repo.get(Asset, id) do
      {:ok, asset}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp now, do: DateTime.utc_now(:second)

  defp setting(key, default) do
    case Keyword.get(config(), key) do
      nil -> default
      value -> value
    end
  end

  defp config, do: Application.get_env(:espalier, :media, [])
end
