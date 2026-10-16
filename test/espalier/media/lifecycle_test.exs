defmodule Espalier.Media.LifecycleTest do
  @moduledoc """
  The life of a media job (task 0018, step 8) beyond its result: the
  heartbeat that sets `updated_at` while the job runs and ends with it, the
  sweep of `Espalier.Media.StaleWorker` after a job that a kill ended, an
  exception that fails the asset with `conversion_failed` at once, a run
  that ends while a later run of its asset runs and leaves the work
  directory of that run, and a deletion during the job. The progress
  callback of a video conversion and the heartbeat during a command
  without progress each stop the running command; after a deletion through
  the library during the scan, a job of every kind stops before its next
  step and logs its stop and no failure. A cancel that no command of the
  job took does not reach a later command of the calling process, and
  without `kill` on the `PATH` a cancelled command runs to its end.

  Each test runs with a store of its own and short heartbeat intervals
  (`Espalier.MediaFixtures.media_env!/1`). The module is synchronous,
  because it changes `config :espalier, :media`, the `PATH` and the level of
  the log, and because the jobs run in other processes on the shared
  connection of the SQL sandbox. The processes of a command are found
  through their working directory in `/proc`.
  """
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures

  alias Espalier.Accounts.Scope
  alias Espalier.{Media, MediaFixtures}
  alias Espalier.Media.{Asset, Command, StaleWorker, Store}
  alias Espalier.Test.LogForwarder

  setup do
    MediaFixtures.media_env!(heartbeat_seconds: 1)

    socket_dir =
      Path.join(
        System.tmp_dir!(),
        "espalier-clamd-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
      )

    File.mkdir_p!(socket_dir)
    on_exit(fn -> File.rm_rf!(socket_dir) end)

    user = user_fixture()
    %{socket_dir: socket_dir, author: %{Scope.for_user(user) | roles: [:learner, :author]}}
  end

  describe "heartbeat" do
    test "a job without progress sets updated_at every heartbeat_seconds", %{
      socket_dir: socket_dir
    } do
      test = self()

      # The scan sends no progress: the fake clamd sets updated_at an hour
      # back, waits for more than two heartbeats and reports what it finds.
      socket =
        fake_clamd(socket_dir, fn ->
          [asset] = Repo.all(Asset)
          set_updated_at!(asset, ago(3600))
          Process.sleep(2_500)
          send(test, {:during_scan, Repo.get!(Asset, asset.id).updated_at})
          "stream: OK\0"
        end)

      MediaFixtures.put_media_env!(clamav_socket: socket)
      asset = pack_asset!("media/a.vtt", MediaFixtures.vtt())

      assert %Asset{status: :ready} = Media.process_now(asset)
      assert_received {:during_scan, updated_at}
      assert DateTime.diff(DateTime.utc_now(), updated_at) <= 2
    end

    test "a job killed at its timeout stops its heartbeat, and the sweep then fails the asset",
         %{socket_dir: socket_dir} do
      MediaFixtures.put_media_env!(stale_processing_seconds: 2)
      test = self()

      socket =
        fake_clamd(socket_dir, fn ->
          send(test, :scanning)
          Process.sleep(60_000)
          "stream: OK\0"
        end)

      MediaFixtures.put_media_env!(clamav_socket: socket)
      asset = pack_asset!("media/a.vtt", MediaFixtures.vtt())

      # A process without a link, as the task of an Oban job, which the
      # timeout of the job ends with a kill.
      job = spawn(fn -> Media.process(asset.id) end)
      assert_receive :scanning, 5_000

      # While the job runs, the heartbeat moves updated_at.
      set_updated_at!(asset, ago(3600))
      wait_until(fn -> DateTime.diff(DateTime.utc_now(), updated_at(asset)) <= 2 end)

      # A beat that runs at the kill still ends its update.
      Process.exit(job, :kill)
      Process.sleep(300)
      killed_at = updated_at(asset)
      Process.sleep(3_200)

      assert updated_at(asset) == killed_at
      assert %Asset{status: :processing} = Repo.get!(Asset, asset.id)

      assert perform_job(StaleWorker, %{}) == :ok

      assert %Asset{status: :failed, failure: :interrupted, incoming_bytes: 0} =
               Repo.get!(Asset, asset.id)
    end
  end

  describe "exceptions" do
    test "an exception in a job fails the asset with conversion_failed at once and is raised again",
         %{socket_dir: socket_dir} do
      LogForwarder.attach()
      asset = pack_asset!("media/a.png", MediaFixtures.png(4, 4))

      # Without ffprobe on the PATH, Espalier.Media.Command.executable!/1
      # raises inside the job.
      previous = System.get_env("PATH")
      System.put_env("PATH", socket_dir)
      on_exit(fn -> System.put_env("PATH", previous) end)

      assert_raise RuntimeError, "ffprobe is not installed", fn -> Media.process(asset.id) end
      System.put_env("PATH", previous)

      assert %Asset{status: :failed, failure: :conversion_failed, incoming_bytes: 0} =
               Repo.get!(Asset, asset.id)

      refute File.exists?(Store.incoming_path(asset.id))
      assert MediaFixtures.work_dirs(asset.id) == []

      message = "media asset #{asset.id} failed: conversion_failed"
      assert_received {:log_event, %{level: :error, msg: {:string, ^message}}}
    end
  end

  describe "runs of one asset" do
    test "a run that ends leaves the work directory of a later run of its asset", %{
      socket_dir: socket_dir
    } do
      first = fake_clamd(socket_dir, held_scan(:first), "first.sock")
      MediaFixtures.put_media_env!(clamav_socket: first)
      content = MediaFixtures.vtt()
      asset = pack_asset!("media/a.vtt", content)

      run_1 = Task.async(fn -> Media.process(asset.id) end)
      assert_receive {:scanning, :first, first_clamd}, 5_000
      [first_dir] = MediaFixtures.work_dirs(asset.id)

      # The sweep fails the asset while its first job still runs, and an
      # import of the same file starts it again, so a second job claims it.
      assert Media.fail(asset.id, :interrupted) == 1

      assert {:ok, %Asset{status: :queued} = again, :existing} =
               ingest_pack_file("media/a.vtt", content)

      assert again.id == asset.id

      second = fake_clamd(socket_dir, held_scan(:second), "second.sock")
      MediaFixtures.put_media_env!(clamav_socket: second)
      run_2 = Task.async(fn -> Media.process(asset.id) end)
      assert_receive {:scanning, :second, second_clamd}, 5_000
      assert [second_dir] = MediaFixtures.work_dirs(asset.id) -- [first_dir]

      # The first run ends and removes its own directory only.
      send(first_clamd, :answer)
      assert Task.await(run_1, 10_000) == :ok
      refute File.exists?(first_dir)
      assert File.dir?(second_dir)

      send(second_clamd, :answer)
      assert Task.await(run_2, 10_000) == :ok
      assert MediaFixtures.work_dirs(asset.id) == []
    end
  end

  describe "deletion during the job" do
    @tag timeout: 120_000
    test "a deletion during a video conversion ends ffmpeg through the progress callback", %{
      author: author
    } do
      # A heartbeat beyond the test leaves the progress callback as the only
      # path to the cancel.
      MediaFixtures.put_media_env!(heartbeat_seconds: 600)
      log_info!()
      asset = pack_asset!("media/long.mkv", long_video!())

      deleter =
        Task.async(fn ->
          wait_until(fn -> progress(asset) > 0 end, 60_000)
          [work_dir] = MediaFixtures.work_dirs(asset.id)
          running = processes_in(work_dir)
          :ok = Media.delete_asset(author, asset.id)
          {work_dir, running, System.monotonic_time(:millisecond)}
        end)

      assert Media.process(asset.id) == :ok
      ended = System.monotonic_time(:millisecond)
      {work_dir, running, deleted} = Task.await(deleter, 60_000)

      # timeout and ffmpeg ran in the work directory, and both ended with
      # the job, within one progress interval and the end of ffmpeg.
      assert length(running) == 2
      assert ended - deleted < 10_000
      assert processes_in(work_dir) == []

      refute Repo.get(Asset, asset.id)
      refute File.exists?(work_dir)
      refute File.exists?(Store.incoming_path(asset.id))
      assert stored_files() == []

      message = "media asset #{asset.id} stopped, because it is no longer processing"
      assert_received {:log_event, %{level: :info, msg: {:string, ^message}}}
    end

    test "a deletion while a command runs without progress stops it through the heartbeat", %{
      author: author,
      socket_dir: socket_dir
    } do
      log_info!()

      # An ffprobe that sleeps and reports nothing, on a PATH with timeout
      # and kill, so that only the heartbeat can stop it.
      bin = Path.join(socket_dir, "bin")
      File.mkdir_p!(bin)

      for name <- ["timeout", "kill"] do
        File.ln_s!(
          System.find_executable(name) || flunk("#{name} is not on the PATH"),
          Path.join(bin, name)
        )
      end

      sleep = System.find_executable("sleep") || flunk("sleep is not on the PATH")
      File.write!(Path.join(bin, "ffprobe"), "#!/bin/sh\nexec #{sleep} 60\n")
      File.chmod!(Path.join(bin, "ffprobe"), 0o755)
      previous = System.get_env("PATH")
      System.put_env("PATH", bin)
      on_exit(fn -> System.put_env("PATH", previous) end)

      asset = pack_asset!("media/a.png", MediaFixtures.png(4, 4))

      deleter =
        Task.async(fn ->
          wait_until(fn ->
            case MediaFixtures.work_dirs(asset.id) do
              [work_dir] -> length(processes_in(work_dir)) == 2
              _none -> false
            end
          end)

          [work_dir] = MediaFixtures.work_dirs(asset.id)
          :ok = Media.delete_asset(author, asset.id)
          {work_dir, System.monotonic_time(:millisecond)}
        end)

      assert Media.process(asset.id) == :ok
      ended = System.monotonic_time(:millisecond)
      {work_dir, deleted} = Task.await(deleter, 15_000)
      System.put_env("PATH", previous)

      # timeout and the probe ended within a heartbeat (one second here).
      assert ended - deleted < 5_000
      assert processes_in(work_dir) == []
      refute File.exists?(work_dir)
      refute Repo.get(Asset, asset.id)
      assert stored_files() == []

      message = "media asset #{asset.id} stopped, because it is no longer processing"
      assert_received {:log_event, %{level: :info, msg: {:string, ^message}}}
      refute_received {:log_event, %{level: :error}}
    end

    test "a deletion through the library during the scan stops a job of every kind before its next step",
         %{author: author, socket_dir: socket_dir} do
      log_info!()

      # Media.delete_asset/2 removes the row and the incoming file while
      # clamd scans, and the scan answers clean.
      socket =
        fake_clamd(socket_dir, fn ->
          for asset <- Repo.all(from a in Asset, where: a.status == :processing) do
            :ok = Media.delete_asset(author, asset.id)
          end

          "stream: OK\0"
        end)

      MediaFixtures.put_media_env!(clamav_socket: socket)

      sources = [
        {"media/a.png", MediaFixtures.png(4, 4)},
        {"media/a.svg", ~s(<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"/>)},
        {"media/a.vtt", MediaFixtures.vtt()},
        {"media/long.mkv", long_video!(1)}
      ]

      for {name, content} <- sources do
        asset = pack_asset!(name, content)

        assert Media.process(asset.id) == :ok

        message = "media asset #{asset.id} stopped, because it is no longer processing"
        assert_received {:log_event, %{level: :info, msg: {:string, ^message}}}
        refute_received {:log_event, %{level: :error}}
        refute Repo.get(Asset, asset.id)
        refute File.exists?(Store.incoming_path(asset.id))
        assert MediaFixtures.work_dirs(asset.id) == []
      end

      assert stored_files() == []
    end

    test "a cancel of the heartbeat that no command took does not stop a later command of the caller",
         %{socket_dir: socket_dir} do
      # The row goes during the scan, and the job stops at the check after
      # the scan, before any command, so the cancel that the heartbeat sends
      # meanwhile stays unread in the job.
      socket =
        fake_clamd(socket_dir, fn ->
          [asset] = Repo.all(Asset)
          Repo.delete!(asset)
          Process.sleep(2_500)
          "stream: OK\0"
        end)

      MediaFixtures.put_media_env!(clamav_socket: socket)
      asset = pack_asset!("media/a.svg", ~s(<svg xmlns="http://www.w3.org/2000/svg"/>))

      assert Media.process(asset.id) == :ok

      marker = Path.join(socket_dir, "started")
      touch = System.find_executable("touch") || flunk("touch is not on the PATH")
      assert {:ok, ""} = Command.run(touch, [marker], timeout: 5, cd: socket_dir)
      assert File.exists?(marker)
    end
  end

  describe "cancel without kill" do
    test "a cancelled command runs to its end, answers :cancelled and logs a warning", %{
      socket_dir: dir
    } do
      LogForwarder.attach()
      sleep = System.find_executable("sleep") || flunk("sleep is not on the PATH")

      # A PATH with timeout and without kill.
      bin = Path.join(dir, "bin")
      File.mkdir_p!(bin)
      File.ln_s!(Command.timeout_path(), Path.join(bin, "timeout"))
      previous = System.get_env("PATH")
      System.put_env("PATH", bin)
      on_exit(fn -> System.put_env("PATH", previous) end)

      test = self()

      spawn(fn ->
        wait_until(fn -> length(processes_in(dir)) == 2 end)
        Command.cancel(test)
      end)

      started = System.monotonic_time(:millisecond)
      assert Command.run(sleep, ["2"], timeout: 10, cd: dir) == {:error, :cancelled}
      assert System.monotonic_time(:millisecond) - started >= 2_000
      System.put_env("PATH", previous)

      message = "kill is not installed, so a cancelled media command runs until it ends"
      assert_received {:log_event, %{level: :warning, msg: {:string, ^message}}}
    end
  end

  ## Helpers

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(:second), -seconds, :second)

  defp set_updated_at!(%Asset{id: id}, at) do
    {1, _rows} = Repo.update_all(from(a in Asset, where: a.id == ^id), set: [updated_at: at])
    :ok
  end

  defp updated_at(%Asset{id: id}), do: Repo.get!(Asset, id).updated_at

  defp progress(%Asset{id: id}) do
    case Repo.get(Asset, id) do
      %Asset{progress: progress} -> progress
      nil -> 0
    end
  end

  # A queued asset of origin pack from a file below the test store.
  defp pack_asset!(name, content) do
    {:ok, asset, :created} = ingest_pack_file(name, content)
    asset
  end

  defp ingest_pack_file(name, content) do
    dir = Path.join(Media.dir(), "pack-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, Path.basename(name))
    File.write!(path, content)

    Media.ingest_pack_file(%{path: path, file_name: name}, nil)
  end

  # The answer of a fake clamd that tells the test which scan it holds and
  # answers clean once the test sends :answer to the clamd.
  defp held_scan(name) do
    test = self()

    fn ->
      send(test, {:scanning, name, self()})

      receive do
        :answer -> "stream: OK\0"
      end
    end
  end

  # A Matroska file with `seconds` of MPEG-4 video; ten minutes take far
  # longer to convert than the test waits.
  defp long_video!(seconds \\ 600) do
    dir = Path.join(Media.dir(), "source")
    File.mkdir_p!(dir)
    path = Path.join(dir, "long.mkv")

    {output, status} =
      System.cmd(
        System.find_executable("ffmpeg") || flunk("ffmpeg is not on the PATH"),
        ["-nostdin", "-hide_banner", "-loglevel", "error", "-y"] ++
          ["-f", "lavfi", "-i", "testsrc2=s=320x240:r=25", "-t", Integer.to_string(seconds)] ++
          ["-c:v", "mpeg4", "-q:v", "31", path],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.read!(path)
  end

  defp stored_files do
    root = Store.files_root()
    if File.dir?(root), do: Path.wildcard(Path.join(root, "**/*.*")), else: []
  end

  # The info lines of Espalier.Media pass the level :warning of the test
  # configuration and reach the handler of this test.
  defp log_info! do
    LogForwarder.attach()
    Logger.put_module_level(Media, :info)
    on_exit(fn -> Logger.delete_module_level(Media) end)
  end

  # The processes whose working directory is `dir`, also after its removal.
  defp processes_in(dir) do
    for entry <- File.ls!("/proc"),
        match?({_pid, ""}, Integer.parse(entry)),
        {:ok, cwd} <- [File.read_link(Path.join(["/proc", entry, "cwd"]))],
        cwd in [dir, dir <> " (deleted)"],
        do: entry
  end

  defp wait_until(fun, timeout \\ 10_000) do
    wait(fun, System.monotonic_time(:millisecond) + timeout)
  end

  defp wait(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("the condition was not met in time")

      true ->
        Process.sleep(50)
        wait(fun, deadline)
    end
  end

  # A fake clamd on a Unix socket `name` in `dir`: it accepts connections one
  # after the other, reads each stream, and answers what `reply` returns. A
  # job that ended meanwhile closed its connection, so the answer may find
  # no reader.
  defp fake_clamd(dir, reply, name \\ "clamd.sock") do
    socket = Path.join(dir, name)
    test = self()

    start_supervised!(
      Supervisor.child_spec({Task, fn -> listen(socket, test, reply) end}, id: make_ref())
    )

    assert_receive :listening
    socket
  end

  defp listen(socket, test, reply) do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, ifaddr: {:local, socket}, active: false, packet: :raw])

    send(test, :listening)
    accept(listen, reply)
  end

  defp accept(listen, reply) do
    {:ok, connection} = :gen_tcp.accept(listen)
    {:ok, "zINSTREAM\0"} = :gen_tcp.recv(connection, 10, 5_000)
    :ok = read_chunks(connection)
    _sent = :gen_tcp.send(connection, reply.())
    :gen_tcp.close(connection)
    accept(listen, reply)
  end

  defp read_chunks(connection) do
    {:ok, <<length::32>>} = :gen_tcp.recv(connection, 4, 5_000)

    if length == 0 do
      :ok
    else
      {:ok, _chunk} = :gen_tcp.recv(connection, length, 5_000)
      read_chunks(connection)
    end
  end
end
