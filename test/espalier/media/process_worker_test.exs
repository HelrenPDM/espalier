defmodule Espalier.Media.ProcessWorkerTest do
  @moduledoc """
  The job of task 0018, step 8, that processes one media asset: `perform/1`
  through `Oban.Testing.perform_job/2`, its options, and `timeout/1` per
  kind, which lies beyond the deadlines of the commands of the job plus the
  scan timeout of the size limit of the kind, so that
  `Espalier.Media.Command` records `timeout` first.

  The module runs synchronously: the ingest takes the advisory lock of the
  quota, and the store lies in a directory of its own per test.
  """
  use Espalier.DataCase, async: false

  alias Espalier.{Media, MediaFixtures}
  alias Espalier.Media.{Asset, Clamd, ProcessWorker, Store}

  setup do
    MediaFixtures.media_env!()
    :ok
  end

  defp pack_file!(name, content) do
    dir = Path.join(Media.dir(), "pack-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, Path.basename(name))
    File.write!(path, content)
    %{path: path, file_name: name}
  end

  test "perform/1 processes the asset of the job, and a second run does nothing" do
    content = MediaFixtures.vtt()

    assert {:ok, asset, :created} =
             Media.ingest_pack_file(pack_file!("media/a.vtt", content), nil)

    assert [%Oban.Job{args: args}] = all_enqueued(worker: ProcessWorker)
    assert args == %{"asset_id" => asset.id, "kind" => "captions"}

    assert perform_job(ProcessWorker, args) == :ok
    assert %Asset{status: :ready, ext: "vtt", sha256: sha256} = ready = Repo.get!(Asset, asset.id)
    assert File.read!(Store.path(sha256, "vtt")) == content

    assert perform_job(ProcessWorker, args) == :ok
    assert Repo.get!(Asset, asset.id) == ready
  end

  test "perform/1 of a failing asset ends :ok with the asset failed" do
    assert {:ok, asset, :created} =
             Media.ingest_pack_file(
               pack_file!("media/a.vtt", MediaFixtures.vtt_with_style()),
               nil
             )

    assert perform_job(ProcessWorker, %{"asset_id" => asset.id, "kind" => "captions"}) == :ok
    assert %Asset{status: :failed, failure: :invalid_captions} = Repo.get!(Asset, asset.id)
  end

  test "perform/1 of a deleted asset does nothing" do
    assert perform_job(ProcessWorker, %{"asset_id" => Ecto.UUID.generate(), "kind" => "svg"}) ==
             :ok
  end

  test "a job runs once, in the queue media by default" do
    job = ProcessWorker.new(%{"asset_id" => Ecto.UUID.generate(), "kind" => "image"})
    assert job.changes.max_attempts == 1
    assert job.changes.queue == "media"
  end

  test "timeout/1 lies beyond the command deadlines plus the scan timeout of each kind" do
    image_ms = Media.image_timeout_seconds() * 1000

    video_ms =
      (Media.video_timeout_seconds(Media.video_max_ms()) + Media.image_timeout_seconds()) * 1000

    for {kind, commands_ms} <- [
          image: image_ms,
          svg: image_ms,
          captions: image_ms,
          video: video_ms
        ] do
      timeout = ProcessWorker.timeout(%Oban.Job{args: %{"kind" => Atom.to_string(kind)}})
      scan_ms = Clamd.scan_timeout_ms(Media.max_bytes(kind))

      assert timeout == Media.job_timeout_ms(kind)
      assert timeout == commands_ms + scan_ms + 60_000
    end

    # The defaults of config/config.exs and README section 6.11: 120 s for
    # an image job, 4 times 60 minutes for a video plus the poster, and the
    # scan of 20 MiB or 1,024 MiB.
    # Image: 120 + 60 seconds and the scan of 20 MiB (60 + 5 seconds). Video:
    # max(600, 25 * 3600) + 120 + 60 seconds and the scan of 1024 MiB (60 + 256).
    assert ProcessWorker.timeout(%Oban.Job{args: %{"kind" => "image"}}) == 245_000
    assert ProcessWorker.timeout(%Oban.Job{args: %{"kind" => "video"}}) == 90_496_000

    # A job without a known kind takes the largest timeout.
    assert ProcessWorker.timeout(%Oban.Job{args: %{"kind" => "other"}}) ==
             Media.job_timeout_ms(:video)
  end

  test "timeout/1 follows the settings of the media limits" do
    MediaFixtures.put_media_env!(video_max_minutes: 1, video_max_mb: 100, image_max_mb: 5)

    # max(600, 4 * 60) + 120 + 60 seconds and the scan of 100 MiB.
    assert ProcessWorker.timeout(%Oban.Job{args: %{"kind" => "video"}}) ==
             (max(600, 25 * 60) + 120 + 60) * 1000 + Clamd.scan_timeout_ms(100 * 1_048_576)

    assert ProcessWorker.timeout(%Oban.Job{args: %{"kind" => "image"}}) ==
             (120 + 60) * 1000 + Clamd.scan_timeout_ms(5 * 1_048_576)
  end
end
