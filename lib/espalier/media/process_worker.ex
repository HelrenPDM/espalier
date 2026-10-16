defmodule Espalier.Media.ProcessWorker do
  @moduledoc """
  The job that processes one media asset (task 0018, step 8), in the queue
  `media` for images, SVG files and captions and `media_video` for videos.
  `config/config.exs` runs two `media` jobs and one `media_video` job at a
  time in the server.

  A job runs once (`max_attempts: 1`). `Espalier.Media.process/1` takes the
  asset from `queued` to `processing` with a conditional update, so a job
  that finds its asset taken, done or failed does nothing. The timeout of
  the job lies beyond the deadline of its commands and its scan, so
  `Espalier.Media.Command` records `timeout` first. An exception in the job
  fails its asset with `conversion_failed`. A job that ends without a
  status, at a stop of the node or at a kill by its timeout, leaves its
  asset in `processing`; the heartbeat of `Espalier.Media.process/1` ends
  with the job, and `Espalier.Media.StaleWorker` fails the asset with
  `interrupted` once its `updated_at` is `stale_processing_seconds` old.
  """
  use Oban.Worker, queue: :media, max_attempts: 1

  alias Espalier.Media

  @kinds %{"image" => :image, "svg" => :svg, "video" => :video, "captions" => :captions}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"asset_id" => asset_id}}), do: Media.process(asset_id)

  @impl Oban.Worker
  def timeout(%Oban.Job{args: args}) do
    Media.job_timeout_ms(Map.get(@kinds, args["kind"], :video))
  end
end
