defmodule Espalier.Media.Store do
  @moduledoc """
  The content-addressed media store below `MEDIA_DIR` (task 0018, step 4).
  It owns every path of the store:

    * `files/<aa>/<bb>/<sha256>.<ext>` for delivery files and posters, where
      `<aa>` and `<bb>` are the first four hex digits of the digest;
    * `incoming/<asset id>` for a file that waits for processing;
    * `work/<asset id>-<run id>/` for the outputs of one run of a job, and
      `work/<uuid>/` for the staging directory of a draft download;
    * `uploads/` for the temporary files of `Plug.Upload` (`PLUG_TMPDIR`).

  Every path is built from `MEDIA_DIR` and a lower-case SHA-256 hex digest
  of 64 characters, an extension of the closed list `webp`, `svg`, `webm`
  and `vtt`, or a UUID; anything else raises `ArgumentError` (ASVS 5.3.2).
  No title, file name or other request value becomes part of a path. The
  store lies outside `priv/static`, and only `EspalierWeb.MediaController`
  serves its files (ASVS 5.3.1).

  A file that several assets share is stored once. `remove/2` deletes a
  file only under the advisory lock `espalier.media.files` after it checked
  that no asset names the digest; `Espalier.Media.ProcessWorker` and the
  orphan sweep of `Espalier.Media.StaleWorker` take the same lock, so a
  file that a new asset reuses is never deleted under it.
  """

  import Ecto.Query

  alias Espalier.Media
  alias Espalier.Media.Asset
  alias Espalier.Repo

  @extensions ~w(webp svg webm vtt)
  @block 1_048_576
  @uuid "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

  @typedoc "A lower-case SHA-256 hex digest of 64 characters."
  @type sha256 :: String.t()

  @doc "The extensions of the delivery files."
  @spec extensions() :: [String.t()]
  def extensions, do: @extensions

  @doc "The root of the store: `MEDIA_DIR` expanded."
  @spec root() :: Path.t()
  def root, do: Path.expand(Media.dir())

  @doc "The directory of the delivery files and posters."
  @spec files_root() :: Path.t()
  def files_root, do: Path.join(root(), "files")

  @doc "The directory of the incoming files."
  @spec incoming_root() :: Path.t()
  def incoming_root, do: Path.join(root(), "incoming")

  @doc "The directory of the work directories."
  @spec work_root() :: Path.t()
  def work_root, do: Path.join(root(), "work")

  @doc "The directory of the temporary upload files (`PLUG_TMPDIR`)."
  @spec uploads_root() :: Path.t()
  def uploads_root, do: Path.join(root(), "uploads")

  @doc "The path of the delivery file or poster with `sha256` and `ext`."
  @spec path(sha256(), String.t()) :: Path.t()
  def path(sha256, ext) do
    sha256 = digest!(sha256)
    ext = ext!(ext)
    <<aa::binary-size(2), bb::binary-size(2), _rest::binary>> = sha256
    Path.join([files_root(), aa, bb, sha256 <> "." <> ext])
  end

  @doc "The path of the incoming file of the asset `asset_id`."
  @spec incoming_path(String.t()) :: Path.t()
  def incoming_path(asset_id), do: Path.join(incoming_root(), uuid!(asset_id))

  @doc """
  The work directory of the run `run_id` of a job of the asset `asset_id`,
  `work/<asset id>-<run id>`. Each run of a job takes a new run id, so two
  runs of one asset never share a directory.
  """
  @spec work_dir(String.t(), String.t()) :: Path.t()
  def work_dir(asset_id, run_id),
    do: Path.join(work_root(), uuid!(asset_id) <> "-" <> uuid!(run_id))

  @doc """
  The asset id of a name `<asset id>-<run id>` below `work/`, or `:error`
  for any other name, such as the name of a staging directory.
  """
  @spec work_asset_id(String.t()) :: {:ok, String.t()} | :error
  def work_asset_id(name) do
    case Regex.run(~r/\A(#{@uuid})-#{@uuid}\z/, name) do
      [_match, asset_id] -> {:ok, asset_id}
      nil -> :error
    end
  end

  @doc """
  Creates a new staging directory for a draft download, `work/<uuid>`, and
  returns its path. It lies on the file system of the store, so the
  download places media files there as hard links.
  """
  @spec staging_dir() :: Path.t()
  # Every path comes from Espalier.Media.Store, built from MEDIA_DIR and a
  # digest, a UUID or a fixed name (ASVS 5.3.2).
  # sobelow_skip ["Traversal.FileModule"]
  def staging_dir do
    dir = Path.join(work_root(), Ecto.UUID.generate())
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  True for the errors of a full volume: `:enospc`, and `:edquot` for an
  exhausted disk quota of the user that runs the node.
  """
  @spec full?(term()) :: boolean()
  def full?(reason), do: reason in [:enospc, :edquot]

  @doc """
  Places a file for processing at `incoming/<asset_id>`: `{:move, path}`
  moves an upload with `File.rename/2` (a copy and a removal when the
  upload lies on another file system), and `{:copy, path}` copies a pack
  file, which stays where it is.
  """
  @spec accept_incoming({:move | :copy, Path.t()}, String.t()) :: :ok | {:error, term()}
  # The source is an upload of Plug.Upload or a file of a loaded pack; the
  # target comes from the store.
  # sobelow_skip ["Traversal.FileModule"]
  def accept_incoming({mode, source}, asset_id) when mode in [:move, :copy] do
    target = incoming_path(asset_id)
    File.mkdir_p!(incoming_root())

    result = if mode == :move, do: move(source, target), else: File.cp(source, target)
    with :ok <- result, do: File.chmod(target, 0o640)
  end

  # A rename, or a copy and a removal across file systems.
  # sobelow_skip ["Traversal.FileModule"]
  defp move(source, target) do
    case File.rename(source, target) do
      {:error, :exdev} -> with :ok <- File.cp(source, target), do: File.rm(source)
      result -> result
    end
  end

  @doc """
  Moves the finished file `file` of a work directory into the store under
  its SHA-256 digest with `ext`, and returns `{sha256, bytes}`: `digest/1`
  and `place/3` in one step. Call it under the advisory lock
  `espalier.media.files`.
  """
  @spec put(Path.t(), String.t()) :: {sha256(), non_neg_integer()}
  def put(file, ext) do
    {sha256, bytes} = digest(file)
    :ok = place(file, ext, sha256)
    {sha256, bytes}
  end

  @doc """
  The SHA-256 digest, computed in blocks of 1 MiB, and the size of `file`.
  """
  @spec digest(Path.t()) :: {sha256(), non_neg_integer()}
  def digest(file) do
    %File.Stat{size: bytes} = File.stat!(file)
    {sha256_file(file), bytes}
  end

  @doc """
  Moves `file`, whose digest is `sha256`, to its place in the store. An
  existing file with the same digest stays, gets the current modification
  time, and `file` is removed, so that the orphan sweep keeps it. The work
  directory lies on the file system of the store, so the move is a rename.
  Call it under the advisory lock `espalier.media.files`.
  """
  @spec place(Path.t(), String.t(), sha256()) :: :ok
  # Every path comes from Espalier.Media.Store, built from MEDIA_DIR and a
  # digest, a UUID or a fixed name (ASVS 5.3.2).
  # sobelow_skip ["Traversal.FileModule"]
  def place(file, ext, sha256) do
    target = path(sha256, ext)
    File.mkdir_p!(Path.dirname(target))

    if File.regular?(target) do
      File.touch!(target)
      File.rm!(file)
    else
      File.rename!(file, target)
      File.chmod!(target, 0o640)
    end

    :ok
  end

  @doc "The lower-case SHA-256 hex digest of the file at `path`, read in blocks of 1 MiB."
  @spec sha256_file(Path.t()) :: sha256()
  # The caller passes a file of the store, a work directory, an upload or a
  # loaded pack.
  # sobelow_skip ["Traversal.FileModule"]
  def sha256_file(path) do
    path
    |> File.stream!(@block)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc """
  Deletes the stored file `sha256` with `ext` unless an asset names the
  digest in `sha256` or `poster_sha256`. It takes the advisory lock
  `espalier.media.files` in a transaction of its own and deletes the file
  before that transaction commits.
  """
  @spec remove(sha256(), String.t()) :: :ok
  # Every path comes from Espalier.Media.Store, built from MEDIA_DIR and a
  # digest, a UUID or a fixed name (ASVS 5.3.2).
  # sobelow_skip ["Traversal.FileModule"]
  def remove(sha256, ext) do
    path = path(sha256, ext)

    {:ok, :ok} =
      Repo.transact(fn ->
        lock_files()

        unless named?(sha256) do
          _ignored = File.rm(path)
        end

        {:ok, :ok}
      end)

    :ok
  end

  @doc """
  Takes the transaction-scoped advisory lock `espalier.media.files`. A
  transaction that also takes the quota lock takes that one first.
  """
  @spec lock_files() :: :ok
  def lock_files do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext('espalier.media.files'))")
    :ok
  end

  @doc "True when an asset names `sha256` as its delivery file or its poster."
  @spec named?(sha256()) :: boolean()
  def named?(sha256) do
    Repo.exists?(from a in Asset, where: a.sha256 == ^sha256 or a.poster_sha256 == ^sha256)
  end

  @doc """
  Returns `{sha256, ext}` for a name `<sha256>.<ext>` of the store, or
  `:error` for any other name.
  """
  @spec parse_name(String.t()) :: {:ok, {sha256(), String.t()}} | :error
  def parse_name(name) do
    case Regex.run(~r/\A([0-9a-f]{64})\.(webp|svg|webm|vtt)\z/, name) do
      [_match, sha256, ext] -> {:ok, {sha256, ext}}
      nil -> :error
    end
  end

  defp digest!(sha256) when is_binary(sha256) do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, sha256),
      do: sha256,
      else: raise(ArgumentError, "a media digest must be 64 lower-case hex digits")
  end

  defp digest!(_sha256),
    do: raise(ArgumentError, "a media digest must be 64 lower-case hex digits")

  defp ext!(ext) when ext in @extensions, do: ext

  defp ext!(_ext),
    do: raise(ArgumentError, "a media extension must be one of #{inspect(@extensions)}")

  defp uuid!(uuid) when is_binary(uuid) do
    if Regex.match?(~r/\A#{@uuid}\z/, uuid),
      do: uuid,
      else: raise(ArgumentError, "a media store name must be a lower-case UUID")
  end

  defp uuid!(_uuid), do: raise(ArgumentError, "a media store name must be a lower-case UUID")
end
