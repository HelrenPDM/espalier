defmodule Espalier.Media.StaleWorkerTest do
  @moduledoc """
  The sweep of task 0018, step 8: interrupted assets, entries of
  `incoming/` and `work/` that no queued or processing asset names, orphan
  stored files, and the old files of `Plug.Upload` below `uploads/`, whose
  `plug-*` directories stay for the request processes that keep their path.

  Each test runs with a store of its own (`Espalier.MediaFixtures.media_env!/1`),
  and the module is synchronous because it removes store files and changes
  `config :espalier, :media`. Ages come from `File.touch!/2` with a past
  time and from `updated_at` set back in the row.
  """
  use Espalier.DataCase, async: false

  alias Espalier.{Media, MediaFixtures}
  alias Espalier.Media.{Asset, StaleWorker, Store}
  alias Espalier.Test.LogForwarder

  setup do
    MediaFixtures.media_env!()
    :ok
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(:second), -seconds, :second)

  defp age!(path, seconds), do: File.touch!(path, System.os_time(:second) - seconds)

  defp sweep, do: assert(perform_job(StaleWorker, %{}) == :ok)

  defp status(%Asset{id: id}), do: Repo.get!(Asset, id).status

  # A file at `path` with an age of `seconds`.
  defp file!(path, seconds) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "leftover")
    age!(path, seconds)
    path
  end

  # A directory at `path` with one file, both with an age of `seconds`.
  defp dir!(path, seconds) do
    file!(Path.join(path, "out.webm"), seconds)
    age!(path, seconds)
    path
  end

  describe "interrupted assets" do
    test "an asset in processing whose updated_at lies more than stale_processing_seconds back fails with interrupted" do
      LogForwarder.attach()
      stale = Media.stale_processing_seconds()
      assert stale == 600
      assert stale >= 5 * Media.heartbeat_seconds()

      # The window is the same for every kind; a running job of any length
      # keeps updated_at young through its heartbeat.
      stale_captions =
        MediaFixtures.insert_asset!(%{
          kind: :captions,
          status: :processing,
          updated_at: ago(stale + 60)
        })

      stale_video =
        MediaFixtures.insert_asset!(%{
          kind: :video,
          status: :processing,
          updated_at: ago(stale + 60)
        })

      young_captions =
        MediaFixtures.insert_asset!(%{
          kind: :captions,
          status: :processing,
          updated_at: ago(stale - 60)
        })

      young_video =
        MediaFixtures.insert_asset!(%{
          kind: :video,
          status: :processing,
          updated_at: ago(stale - 60)
        })

      queued = MediaFixtures.insert_asset!(%{status: :queued, updated_at: ago(10 * stale)})

      sweep()

      for asset <- [stale_captions, stale_video] do
        assert %Asset{status: :failed, failure: :interrupted, incoming_bytes: 0} =
                 Repo.get!(Asset, asset.id)

        id = asset.id

        message = "media asset #{id} failed: interrupted"
        assert_received {:log_event, %{level: :error, msg: {:string, ^message}}}
      end

      assert status(young_captions) == :processing
      assert status(young_video) == :processing
      assert status(queued) == :queued
    end

    test "the window follows stale_processing_seconds" do
      MediaFixtures.put_media_env!(stale_processing_seconds: 30)
      asset = MediaFixtures.insert_asset!(%{status: :processing, updated_at: ago(45)})

      sweep()

      assert %Asset{status: :failed, failure: :interrupted} = Repo.get!(Asset, asset.id)
    end
  end

  describe "incoming and work entries" do
    test "entries older than an hour go unless a queued or processing asset names them" do
      queued = MediaFixtures.insert_asset!(%{status: :queued})
      processing = MediaFixtures.insert_asset!(%{status: :processing})
      failed = MediaFixtures.insert_asset!(%{status: :failed})
      running = Store.work_dir(processing.id, Ecto.UUID.generate())

      kept = [
        file!(Store.incoming_path(queued.id), 7200),
        file!(Store.incoming_path(processing.id), 7200),
        file!(Store.incoming_path(Ecto.UUID.generate()), 1800),
        # Two runs of a job of one asset, as after a restart of a failed
        # asset whose first job still runs.
        dir!(running, 7200),
        dir!(Store.work_dir(processing.id, Ecto.UUID.generate()), 7200),
        dir!(Store.work_dir(queued.id, Ecto.UUID.generate()), 7200),
        dir!(Store.work_dir(failed.id, Ecto.UUID.generate()), 1800),
        dir!(Path.join(Store.work_root(), Ecto.UUID.generate()), 1800)
      ]

      removed = [
        file!(Store.incoming_path(failed.id), 7200),
        file!(Store.incoming_path(Ecto.UUID.generate()), 7200),
        file!(Path.join(Store.incoming_root(), "not-a-uuid"), 7200),
        file!(Path.join(Store.incoming_root(), String.upcase(queued.id)), 7200),
        dir!(Path.join(Store.work_root(), queued.id <> "-x"), 7200),
        dir!(Path.join(Store.work_root(), processing.id), 7200),
        dir!(Store.work_dir(failed.id, Ecto.UUID.generate()), 7200),
        dir!(Store.work_dir(Ecto.UUID.generate(), Ecto.UUID.generate()), 7200),
        # A staging directory of a draft download carries no asset id.
        dir!(Path.join(Store.work_root(), Ecto.UUID.generate()), 7200)
      ]

      sweep()

      for path <- kept, do: assert(File.exists?(path), "#{path} was removed")
      for path <- removed, do: refute(File.exists?(path), "#{path} was kept")
      assert File.exists?(Path.join(running, "out.webm"))
    end
  end

  describe "orphan stored files" do
    test "a stored file older than an hour goes when no asset names it as delivery file or poster" do
      named = MediaFixtures.store_file!("named delivery", "svg")
      poster = MediaFixtures.store_file!("named poster", "webp")
      MediaFixtures.insert_asset!(%{sha256: named, poster_sha256: poster})
      orphan = MediaFixtures.store_file!("orphan", "webm")
      young_orphan = MediaFixtures.store_file!("young orphan", "vtt")

      for {sha256, ext} <- [{named, "svg"}, {poster, "webp"}, {orphan, "webm"}],
          do: age!(Store.path(sha256, ext), 7200)

      # A name outside the store scheme is left alone.
      other = file!(Path.join([Store.files_root(), "ab", "cd", "notes.txt"]), 7200)

      sweep()

      assert File.exists?(Store.path(named, "svg"))
      assert File.exists?(Store.path(poster, "webp"))
      refute File.exists?(Store.path(orphan, "webm"))
      assert File.exists?(Store.path(young_orphan, "vtt"))
      assert File.exists?(other)
    end

    test "a file whose digest an asset names with another extension is kept" do
      sha256 = MediaFixtures.store_file!("shared digest", "webp")
      MediaFixtures.insert_asset!(%{sha256: sha256, ext: "svg"})
      age!(Store.path(sha256, "webp"), 7200)

      sweep()

      assert File.exists?(Store.path(sha256, "webp"))
    end
  end

  describe "uploads" do
    test "old files below plug-* directories go, and the directories stay" do
      root = Store.uploads_root()
      old_file = file!(Path.join([root, "plug-1700-aaaa", "multipart-1"]), 7200)
      young_file = file!(Path.join([root, "plug-1700-bbbb", "multipart-2"]), 600)
      emptied = Path.join(root, "plug-1700-aaaa")
      age!(emptied, 7200)
      empty = Path.join(root, "plug-1600-cccc")
      File.mkdir_p!(empty)
      age!(empty, 7200)
      other = file!(Path.join([root, "other", "file"]), 7200)
      loose = file!(Path.join(root, "multipart-3"), 7200)

      sweep()

      refute File.exists?(old_file)
      assert File.exists?(young_file)
      assert File.dir?(emptied)
      assert File.dir?(empty)
      assert File.exists?(other)
      refute File.exists?(loose)
    end

    test "a process that keeps the path of its plug-* directory uploads again after a sweep" do
      # Plug.Upload creates its directories below the roots it read at start
      # and keeps the directory of each process in a table; the test points
      # the roots at uploads/ of the test store, as PLUG_TMPDIR does in
      # compose.yaml.
      root = Store.uploads_root()
      File.mkdir_p!(root)
      {roots, suffix} = :persistent_term.get(Plug.Upload)
      :persistent_term.put(Plug.Upload, {[root], suffix})
      on_exit(fn -> :persistent_term.put(Plug.Upload, {roots, suffix}) end)

      first = Plug.Upload.random_file!("media")
      dir = Path.dirname(first)
      assert Path.dirname(dir) == root
      assert "plug-" <> _rest = Path.basename(dir)

      # The upload moved its file out, and the empty directory turned old.
      File.rm!(first)
      age!(dir, 7200)

      sweep()

      assert File.dir?(dir)
      second = Plug.Upload.random_file!("media")
      assert Path.dirname(second) == dir
      assert File.exists?(second)
    end
  end

  test "a sweep of an empty store does nothing" do
    sweep()
    assert File.ls!(Store.root()) == []
  end
end
