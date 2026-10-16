defmodule Espalier.Interop.MediaLockTest do
  @moduledoc """
  Task 0018, step 23: `Espalier.Interop.PackWriter.write/2` and
  `Espalier.Interop.ExportWorker` copy the media files of a program while
  they hold the shared advisory lock of its pack. A publish that drops the
  old media therefore waits for the copy, a deletion of those assets answers
  `asset_in_use` until that publish commits, and the written pack and the
  SCORM package hold every media file byte for byte after the deletion has
  removed the store files.

  The SQL sandbox serves every process of a test through one connection,
  so it cannot show a lock wait. As in `Espalier.Interop.PublishLockTest`,
  each transaction runs on a connection of its own through
  `Ecto.Adapters.SQL.Sandbox.unboxed_run/2`, the rows are committed and
  deleted again on exit, and the module is synchronous, so no sandboxed
  test sees them.

  The scenario: a published program whose lesson holds a figure with an SVG
  and a video with a poster and captions, their `ready` assets and
  `program_media` rows, and a queued export of the module. The store file
  of the video is a named pipe (`mkfifo`), so its copy waits until the test
  writes the bytes of the video into the pipe. While the copy waits, the
  test checks that the reader holds the shared lock of the pack, starts a
  transaction in place of a publish that takes the exclusive lock and
  deletes the media blocks and the `program_media` rows, sees it wait, and
  sees `Espalier.Media.delete_asset/2` answer `asset_in_use`. Then it writes
  the bytes: the copy ends, the reader commits, the publish follows, and
  the deletion of every asset removes the store files. A reader that copied
  the media after the commit of its read would reach the pipe without the
  lock, and the first check fails.

  The media store lies below `/dev/shm`, which is a file system of its own,
  so the export cannot hard-link the store files into `EXPORT_DIR` and
  copies them, as in the compose layout. `File.cp/2` copies in the file
  server of the node, which waits on the pipe as well, so the test touches
  no file while the copy waits. On exit, a raw open of the pipe for reading
  and writing ends a wait that a failed test left behind, before the store
  is removed.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Espalier.Accounts.{Scope, User}
  alias Espalier.{AccountsFixtures, Interop, Media, MediaFixtures, Repo}
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.{Block, Lesson, Program, ProgramMedia}
  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Interop.{Export, ExportWorker, PackWriter}
  alias Espalier.Media.{Asset, Store}

  # How long the test waits for a lock, the pipe and the readers.
  @wait_ms 10_000

  # The advisory locks of the pack with `mode` and `granted` in the database
  # of this session: the one-key form stores the low 32 bits of its key in
  # objid, with objsubid 1.
  @locks_sql """
  SELECT count(*) FROM pg_locks
  WHERE locktype = 'advisory' AND mode = $2 AND granted = $3
    AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND objid = hashtext($1)::oid AND objsubid = 1
  """

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  setup do
    tmp = tmp_dir!()
    media_dir = shm_dir!()
    MediaFixtures.put_media_env!(dir: media_dir)
    put_env(:export_dir, Path.join(tmp, "exports"))
    File.mkdir_p!(Interop.export_dir())

    # A hard link from the store into EXPORT_DIR fails across file systems.
    refute device(media_dir) == device(tmp)

    files = store_files!()

    on_exit(fn ->
      release_pipe(files.fifo)
      File.rm_rf!(media_dir)
    end)

    user = unboxed(fn -> AccountsFixtures.user_fixture() end)
    data = unboxed(fn -> insert_scenario!(files) end)
    on_exit(fn -> unboxed(fn -> delete_scenario!(data, user) end) end)

    Map.merge(data, %{
      files: files,
      tmp: tmp,
      scope: %{Scope.for_user(user) | roles: [:learner, :author]}
    })
  end

  defp put_env(key, value) do
    previous = Application.fetch_env(:espalier, key)
    Application.put_env(:espalier, key, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, key, value)
        :error -> Application.delete_env(:espalier, key)
      end
    end)
  end

  defp tmp_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "espalier-media-lock-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A directory for the media store on the file system of /dev/shm, which no
  # directory below System.tmp_dir!/0 shares.
  defp shm_dir! do
    unless File.dir?("/dev/shm"),
      do: flunk("the test needs /dev/shm for a media store on a file system of its own")

    dir =
      Path.join(
        "/dev/shm",
        "espalier-media-lock-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp device(path) do
    stat = File.stat!(path)
    {stat.major_device, stat.minor_device}
  end

  defp sha256(content), do: :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)

  # The bytes of the four media files, unique per test. The SVG, the poster
  # and the captions are files of the store; the store file of the video is
  # a named pipe, whose bytes the test writes during the copy.
  defp store_files! do
    n = System.unique_integer([:positive])

    files = %{
      svg:
        ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><title>#{n}</title></svg>),
      video: "a stand-in of a WebM video #{n}",
      poster: "RIFF a stand-in of a WebP poster #{n}",
      captions: MediaFixtures.vtt("A steady tone plays #{n}.")
    }

    MediaFixtures.store_file!(files.svg, "svg")
    MediaFixtures.store_file!(files.poster, "webp")
    MediaFixtures.store_file!(files.captions, "vtt")

    fifo = Store.path(sha256(files.video), "webm")
    File.mkdir_p!(Path.dirname(fifo))
    assert {_output, 0} = System.cmd("mkfifo", [fifo])
    Map.put(files, :fifo, fifo)
  end

  # Ends a wait on the pipe: an open for reading and writing never blocks
  # and gives a side that waits in its open the other end. The raw calls
  # bypass the file server, which may wait on the pipe itself.
  defp release_pipe(fifo) do
    with {:ok, info} when elem(info, 2) == :other <- :file.read_file_info(fifo, [:raw]),
         {:ok, fd} <- :file.open(fifo, [:read, :write, :raw]) do
      :file.close(fd)
    end
  end

  defp insert_scenario!(files) do
    svg = asset!(:svg, "svg", files.svg, %{width: 720, height: 200})

    video =
      asset!(:video, "webm", files.video, %{
        width: 640,
        height: 360,
        duration_ms: 8_008,
        has_audio: true,
        poster_sha256: sha256(files.poster),
        poster_bytes: byte_size(files.poster)
      })

    captions = asset!(:captions, "vtt", files.captions, %{duration_ms: 1_500})

    program =
      Repo.insert!(%Program{
        slug: "media-lock-#{System.unique_integer([:positive])}",
        title: "Media lock",
        locale: "en",
        status: :published,
        pack_version: "1.0.0"
      })

    module = Repo.insert!(%CatalogModule{program_id: program.id, number: 1, title: "Media"})

    lesson =
      Repo.insert!(%Lesson{module_id: module.id, key: "01-media", position: 1, title: "Media"})

    Repo.insert!(%Block{
      lesson_id: lesson.id,
      position: 1,
      kind: :figure,
      body: "",
      provenance: :invented,
      media: %{"src" => "media/diagram.svg", "alt" => "A diagram.", "size" => "full"}
    })

    Repo.insert!(%Block{
      lesson_id: lesson.id,
      position: 2,
      kind: :video,
      body: "",
      provenance: :invented,
      media: %{
        "src" => "media/clip.webm",
        "title" => "A clip",
        "captions" => [%{"src" => "media/clip-en.vtt", "lang" => "en"}]
      }
    })

    for {path, asset} <- [
          {"media/clip-en.vtt", captions},
          {"media/clip.webm", video},
          {"media/diagram.svg", svg}
        ] do
      Repo.insert!(%ProgramMedia{program_id: program.id, path: path, media_asset_id: asset.id})
    end

    export =
      Repo.insert!(%Export{program_id: program.id, module_id: module.id, scorm_version: :scorm12})

    %{
      program: program,
      lesson: lesson,
      export: export,
      assets: %{svg: svg, video: video, captions: captions}
    }
  end

  defp asset!(kind, ext, content, facts) do
    MediaFixtures.insert_asset!(
      Map.merge(
        %{
          kind: kind,
          title: "#{kind}",
          source_name: "#{kind}.#{ext}",
          sha256: sha256(content),
          ext: ext,
          bytes: byte_size(content)
        },
        facts
      )
    )
  end

  defp delete_scenario!(data, user) do
    program_id = data.program.id
    asset_ids = data.assets |> Map.values() |> Enum.map(& &1.id)

    Repo.delete_all(from e in Export, where: e.program_id == ^program_id)
    Repo.delete_all(from m in ProgramMedia, where: m.program_id == ^program_id)
    Repo.delete_all(from b in Block, where: b.lesson_id == ^data.lesson.id)
    Repo.delete_all(from l in Lesson, where: l.id == ^data.lesson.id)
    Repo.delete_all(from m in CatalogModule, where: m.program_id == ^program_id)
    Repo.delete_all(from p in Program, where: p.id == ^program_id)
    Repo.delete_all(from a in Asset, where: a.id in ^asset_ids)

    Repo.delete_all(
      from e in AuditEvent,
        where: e.actor_id == ^user.id or e.subject_id == ^user.id or e.subject_id in ^asset_ids
    )

    Repo.delete_all(from u in User, where: u.id == ^user.id)
  end

  # A process that opens the pipe of the video for writing, which waits
  # until the copy opens it for reading, reports that to the test, and
  # writes the bytes of the video on :go. It is not linked to the test, so
  # a failed test leaves it to on_exit and its own timeout.
  defp feed_pipe!(files) do
    test = self()

    feeder =
      spawn(fn ->
        {:ok, fd} = :file.open(files.fifo, [:write, :raw, :binary])
        send(test, {:copy_waits, self()})

        receive do
          :go -> :ok
        after
          3 * @wait_ms -> :ok
        end

        _written = :file.write(fd, files.video)
        :file.close(fd)
      end)

    on_exit(fn -> send(feeder, :go) end)
    feeder
  end

  # A transaction in place of a publish of the pack that drops the media:
  # it takes the lock of the publisher, deletes the media blocks and the
  # program_media rows and commits.
  defp drop_media!(data) do
    Repo.transact(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [data.program.slug])
      Repo.delete_all(from m in ProgramMedia, where: m.program_id == ^data.program.id)
      Repo.delete_all(from b in Block, where: b.lesson_id == ^data.lesson.id)
      {:ok, :committed}
    end)
  end

  defp locks(slug, mode, granted) do
    %{rows: [[count]]} = unboxed(fn -> Repo.query!(@locks_sql, [slug, mode, granted]) end)
    count
  end

  defp await_lock!(slug, mode, granted, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + @wait_ms

    cond do
      locks(slug, mode, granted) > 0 ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("no #{mode} lock of the pack with granted #{granted} after #{@wait_ms} ms")

      true ->
        Process.sleep(20)
        await_lock!(slug, mode, granted, deadline)
    end
  end

  # While the copy of the video waits on the pipe: the reader holds the
  # shared lock, a publish that drops the media waits for it, and the
  # deletion of the video answers asset_in_use. Then the bytes of the video
  # go into the pipe. Returns the task of the publish, which commits after
  # the reader. No call here touches a file.
  defp race_publish!(data, reader, feeder) do
    slug = data.program.slug
    assert_receive {:copy_waits, ^feeder}, @wait_ms

    assert locks(slug, "ShareLock", true) == 1,
           "the copy of a media file runs without the shared lock of the pack"

    publish = Task.async(fn -> unboxed(fn -> drop_media!(data) end) end)
    await_lock!(slug, "ExclusiveLock", false)

    assert {:error, {:asset_in_use, %{programs: [%{slug: ^slug}]}}} =
             unboxed(fn -> Media.delete_asset(data.scope, data.assets.video.id) end)

    assert Task.yield(reader, 0) == nil
    send(feeder, :go)
    publish
  end

  # Deletes every asset of the scenario, which the publish has left unused,
  # and checks that the store files are gone.
  defp delete_assets!(data) do
    for asset <- Map.values(data.assets) do
      assert unboxed(fn -> Media.delete_asset(data.scope, asset.id) end) == :ok
    end

    for {content, ext} <- media(data.files) do
      refute File.exists?(Store.path(sha256(content), ext)), ext
    end
  end

  defp media(files) do
    [
      {files.svg, "svg"},
      {files.video, "webm"},
      {files.poster, "webp"},
      {files.captions, "vtt"}
    ]
  end

  test "the pack writer copies the media under the shared lock, so the pack keeps every file",
       data do
    out = Path.join(data.tmp, "pack")
    feeder = feed_pipe!(data.files)
    writer = Task.async(fn -> unboxed(fn -> PackWriter.write(data.program, out) end) end)

    publish = race_publish!(data, writer, feeder)
    assert {:ok, "1.0.0"} = Task.await(writer, @wait_ms)
    assert {:ok, :committed} = Task.await(publish, @wait_ms)
    delete_assets!(data)

    # The pack holds the delivery files at their paths; posters stay out of
    # a pack, because an import makes them again.
    assert File.read!(Path.join(out, "media/diagram.svg")) == data.files.svg
    assert File.read!(Path.join(out, "media/clip.webm")) == data.files.video
    assert File.read!(Path.join(out, "media/clip-en.vtt")) == data.files.captions
  end

  test "the export stages the media under the shared lock, so the package keeps every file",
       data do
    feeder = feed_pipe!(data.files)
    job = %Oban.Job{args: %{"export_id" => data.export.id}}
    export = Task.async(fn -> unboxed(fn -> ExportWorker.perform(job) end) end)

    publish = race_publish!(data, export, feeder)
    assert :ok = Task.await(export, @wait_ms)
    assert {:ok, :committed} = Task.await(publish, @wait_ms)
    delete_assets!(data)

    done = unboxed(fn -> Repo.get!(Export, data.export.id) end)
    assert done.status == :done
    zip = String.to_charlist(Path.join(Interop.export_dir(), done.file_name))

    for {content, ext} <- media(data.files) do
      name = ~c"media/#{sha256(content)}.#{ext}"
      assert {:ok, [{^name, ^content}]} = :zip.extract(zip, [:memory, file_list: [name]])
    end
  end
end
