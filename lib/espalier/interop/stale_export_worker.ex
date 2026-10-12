defmodule Espalier.Interop.StaleExportWorker do
  @moduledoc """
  Ends the exports whose build was interrupted (task 0016): the crontab of
  `config :espalier, Oban` runs the job every 15 minutes.

  An export stays `queued` or `running` when its job ends without a status
  change, for example when the node stops during a build or the status
  change to `failed` fails (`Espalier.Interop.ExportWorker`). The job sets
  every export with status `queued` or `running` whose `updated_at` lies
  more than one hour back to `failed`, with the text "The build was
  interrupted; request the export again." in `error`, logs the id of each,
  and removes `<EXPORT_DIR>/<id>.build`, `<id>.zip.part` and `<id>.zip`,
  which an export that never became `done` leaves behind.

  The hour is the limit of this rule. The export worker sets `running`
  when a build starts, so a build that still runs one hour later counts as
  interrupted, and the job removes its files. The queue `exports` has
  one slot, so an export that waits longer than one hour behind other
  exports counts as interrupted as well, and its export job, when it runs
  later, finds it `failed` and is cancelled. With one slot and builds that
  end within minutes, neither case occurs in normal operation.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  require Logger

  alias Espalier.{Interop, Repo}
  alias Espalier.Interop.Export

  @max_age_seconds 3_600
  @error "The build was interrupted; request the export again."

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now(:second)
    stale_before = DateTime.add(now, -@max_age_seconds, :second)

    {_count, ids} =
      Repo.update_all(
        from(e in Export,
          where: e.status in [:queued, :running] and e.updated_at < ^stale_before,
          select: e.id
        ),
        set: [status: :failed, error: @error, updated_at: now]
      )

    Enum.each(ids, fn id ->
      Logger.warning("export interrupted: export #{id} set to failed")
      remove_files(id)
    end)

    :ok
  end

  # The paths come from EXPORT_DIR and the export id only.
  # sobelow_skip ["Traversal.FileModule"]
  defp remove_files(id) do
    dir = Interop.export_dir()

    for name <- ["#{id}.build", "#{id}.zip.part", "#{id}.zip"],
        do: File.rm_rf(Path.join(dir, name))

    :ok
  end
end
