defmodule Espalier.Interop.StaleExportWorker do
  @moduledoc """
  Ends the exports whose build was interrupted and applies the retention
  of exports (task 0016): the crontab of `config :espalier, Oban` runs the
  job every 15 minutes.

  An export stays `queued` or `running` when its job ends without a status
  change, for example when the node stops during a build, when Oban ends
  the job after `Espalier.Interop.ExportWorker.build_timeout/0`, or when
  the status change to `failed` fails (`Espalier.Interop.ExportWorker`).
  The job sets every export with status `queued` or `running` whose
  `updated_at` lies more than `interrupted_after/0` back to `failed`, with
  the text "The build was interrupted; request the export again." in
  `error`, in one conditional `UPDATE ... RETURNING id`. It logs the id of
  each and removes `<EXPORT_DIR>/<id>.build`, `<id>.zip.part` and
  `<id>.zip` of exactly these ids.

  `interrupted_after/0` is twice the build timeout of the export worker and
  at least one hour. The worker sets `running` when a build starts, and
  Oban ends a job after the build timeout, so the export of a job that
  still runs does not meet the limit. The worker changes the status only
  from the statuses it expects (`Espalier.Interop.transition_export/3`):
  should a build reach its end after the sweep set its export to
  `failed`, for example after a pause of the node, it removes its package
  and leaves the status `failed`. The queue `exports` has one
  slot, so an export that waits longer than the limit behind other
  exports counts as interrupted as well, and its export job, when it runs
  later, finds it `failed` and is cancelled.

  Afterwards the job runs `Espalier.Interop.prune_exports(:all)`: it
  deletes the exports beyond the age and count limits of
  `Espalier.Interop.retention/0` with their files and removes the files
  below `EXPORT_DIR` that belong to no export.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  require Logger

  alias Espalier.{Interop, Repo}
  alias Espalier.Interop.{Export, ExportWorker}

  @min_interrupted_after :timer.hours(1)
  @error "The build was interrupted; request the export again."

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    fail_interrupted()
    _pruned = Interop.prune_exports(:all)
    :ok
  end

  @doc """
  The time in milliseconds after which an export in status `queued` or
  `running` counts as interrupted: twice
  `Espalier.Interop.ExportWorker.build_timeout/0`, and at least one hour,
  so always longer than the longest run of an export job.
  """
  @spec interrupted_after() :: pos_integer()
  def interrupted_after, do: max(2 * ExportWorker.build_timeout(), @min_interrupted_after)

  defp fail_interrupted do
    now = DateTime.utc_now(:second)
    stale_before = DateTime.add(now, -interrupted_after(), :millisecond)

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
      Interop.remove_export_files(id)
    end)
  end
end
