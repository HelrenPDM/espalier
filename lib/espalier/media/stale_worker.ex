defmodule Espalier.Media.StaleWorker do
  @moduledoc """
  The sweep of the media store (task 0018, step 8), every 15 minutes in the
  queue `default`:

    * fails with `interrupted` every asset in `processing` whose
      `updated_at` lies more than `stale_processing_seconds` (600) back,
      and logs each one with the asset id and the failure code. A running
      job sets `updated_at` every `heartbeat_seconds` (60), so only an
      asset whose job ended without a status, at a stop of the node or a
      kill at the timeout of the job, stays that long unchanged;
    * removes every entry of `incoming/` and `work/` whose modification time
      lies more than one hour back and that no asset in `queued` or
      `processing` names (an incoming file carries the id of its asset, the
      work directory of a run of a job carries it before the run id, as
      `<asset id>-<run id>`, and a staging directory of a draft download
      carries none);
    * removes every stored file older than one hour whose digest no asset
      names in `sha256` or `poster_sha256`, which a crash between the move
      into the store and the row update can leave, under the advisory lock
      `espalier.media.files`;
    * removes every file below `uploads/` whose modification time lies more
      than one hour back. The `plug-*` directories stay: `Plug.Upload`
      creates one directory per boot and per period of about 12 days,
      shares it between all request processes and keeps its path for each
      process, so a removed directory would fail the next upload of a
      process that still holds the path.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Espalier.Media
  alias Espalier.Media.{Asset, Store}
  alias Espalier.Repo

  @hour 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    fail_interrupted()
    sweep_dir(Store.incoming_root(), &incoming_asset_id/1)
    sweep_dir(Store.work_root(), &Store.work_asset_id/1)
    sweep_files()
    sweep_uploads()
    :ok
  end

  defp fail_interrupted do
    cutoff = DateTime.add(DateTime.utc_now(:second), -Media.stale_processing_seconds(), :second)

    from(a in Asset,
      where: a.status == :processing and a.updated_at < ^cutoff,
      select: a.id
    )
    |> Repo.all()
    |> Enum.each(&Media.fail(&1, :interrupted))
  end

  # Entries whose name carries the id of an asset in queued or processing
  # stay; every other entry older than an hour goes. `asset_id` reads the
  # asset id from a name or answers :error.
  # The names come from listings of the store directories.
  # sobelow_skip ["Traversal.FileModule"]
  defp sweep_dir(dir, asset_id) do
    entries = for name <- list(dir), do: {name, asset_id.(name)}
    active = active_ids(for {_name, {:ok, id}} <- entries, do: id)

    for {name, owner} <- entries, not active?(owner, active), old?(Path.join(dir, name)) do
      File.rm_rf(Path.join(dir, name))
    end

    :ok
  end

  # An incoming file is named by the id of its asset alone.
  defp incoming_asset_id(name) do
    case Ecto.UUID.cast(name) do
      {:ok, ^name} -> {:ok, name}
      _other -> :error
    end
  end

  defp active_ids(ids) do
    from(a in Asset,
      where: a.id in ^Enum.uniq(ids) and a.status in [:queued, :processing],
      select: a.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp active?({:ok, id}, active), do: MapSet.member?(active, id)
  defp active?(:error, _active), do: false

  defp sweep_files do
    candidates =
      for aa <- list(Store.files_root()),
          bb <- list(Path.join(Store.files_root(), aa)),
          name <- list(Path.join([Store.files_root(), aa, bb])),
          {:ok, {sha256, ext}} <- [Store.parse_name(name)],
          old?(Store.path(sha256, ext)),
          do: {sha256, ext}

    unless candidates == [] do
      {:ok, :ok} = Repo.transact(fn -> remove_orphans(candidates) end)
    end

    :ok
  end

  # Under the file lock, so that a file that a new asset names in the
  # meantime stays.
  # Every path comes from Espalier.Media.Store, built from MEDIA_DIR and a
  # digest, a UUID or a fixed name (ASVS 5.3.2).
  # sobelow_skip ["Traversal.FileModule"]
  defp remove_orphans(candidates) do
    Store.lock_files()
    digests = Enum.map(candidates, &elem(&1, 0))

    named =
      from(a in Asset,
        where: a.sha256 in ^digests or a.poster_sha256 in ^digests,
        select: [a.sha256, a.poster_sha256]
      )
      |> Repo.all()
      |> List.flatten()
      |> MapSet.new()

    for {sha256, ext} <- candidates, not MapSet.member?(named, sha256) do
      File.rm(Store.path(sha256, ext))
    end

    {:ok, :ok}
  end

  # The names come from listings of the uploads directory of the store.
  # sobelow_skip ["Traversal.FileModule"]
  defp sweep_uploads do
    root = Store.uploads_root()

    for name <- list(root) do
      path = Path.join(root, name)

      if String.starts_with?(name, "plug-") and File.dir?(path),
        do: sweep_plug_dir(path),
        else: remove_old_file(path)
    end

    :ok
  end

  # The files of Plug.Upload lie in plug-* directories, which stay (see the
  # module documentation).
  defp sweep_plug_dir(path) do
    for file <- list(path), do: remove_old_file(Path.join(path, file))
    :ok
  end

  # The path comes from a listing of the uploads directory of the store.
  # sobelow_skip ["Traversal.FileModule"]
  defp remove_old_file(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> if old?(path), do: File.rm(path)
      _other -> :ok
    end
  end

  defp list(dir) do
    case File.ls(dir) do
      {:ok, names} -> names
      {:error, _reason} -> []
    end
  end

  defp old?(path) do
    case File.lstat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime < System.os_time(:second) - @hour
      {:error, _reason} -> false
    end
  end
end
