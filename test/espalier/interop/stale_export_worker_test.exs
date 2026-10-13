defmodule Espalier.Interop.StaleExportWorkerTest do
  @moduledoc """
  The sweep of interrupted exports (task 0016): an export that is `queued`
  or `running` and was last changed longer than `interrupted_after/0` ago
  (one hour) becomes `failed`, and its build directory, partial zip and zip
  are removed. A recent export and a `done` export keep their status and
  their files. The limit lies above the timeout of the export job, so the
  sweep finds no export interrupted whose job still runs. Afterwards the
  sweep applies the retention of `Espalier.Interop.prune_exports/1`. The
  crontab of `config/config.exs` runs the job every 15 minutes.
  """
  # The tests set :export_dir in the application environment.
  use Espalier.DataCase, async: false

  import ExUnit.CaptureLog

  alias Espalier.{Interop, LearningFixtures}
  alias Espalier.Interop.{Export, ExportWorker, StaleExportWorker}

  @error "The build was interrupted; request the export again."

  # The limit of the sweep in minutes.
  defp limit, do: div(StaleExportWorker.interrupted_after(), :timer.minutes(1))

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "espalier-stale-exports-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    previous = Application.fetch_env(:espalier, :export_dir)
    Application.put_env(:espalier, :export_dir, dir)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, :export_dir, value)
        :error -> Application.delete_env(:espalier, :export_dir)
      end
    end)

    program = LearningFixtures.publish_demo!()
    %{module: LearningFixtures.module!(program, 1)}
  end

  # An export of `module` in `status`, last changed `minutes` ago, with the
  # files that a build leaves: the build directory with a file, the partial
  # zip and the zip. A `done` export names its zip.
  defp export!(module, status, minutes) do
    id = Ecto.UUID.generate()

    export =
      Repo.insert!(%Export{
        id: id,
        program_id: module.program_id,
        module_id: module.id,
        scorm_version: :scorm12,
        status: status,
        file_name: if(status == :done, do: "#{id}.zip")
      })

    changed = DateTime.add(DateTime.utc_now(:second), -minutes, :minute)
    Repo.update_all(from(e in Export, where: e.id == ^export.id), set: [updated_at: changed])

    dir = Interop.export_dir()
    File.mkdir_p!(Path.join(dir, "#{export.id}.build"))
    File.write!(Path.join([dir, "#{export.id}.build", "content.json"]), "{}")
    File.write!(Path.join(dir, "#{export.id}.zip.part"), "partial")
    File.write!(Path.join(dir, "#{export.id}.zip"), "zip")

    Repo.get!(Export, export.id)
  end

  defp files(%Export{id: id}) do
    dir = Interop.export_dir()
    Enum.filter(["#{id}.build", "#{id}.zip.part", "#{id}.zip"], &File.exists?(Path.join(dir, &1)))
  end

  defp sweep! do
    capture_log([level: :warning], fn -> assert perform_job(StaleExportWorker, %{}) == :ok end)
  end

  test "the limit is twice the job timeout and at least one hour" do
    timeout = ExportWorker.build_timeout()

    assert ExportWorker.timeout(%Oban.Job{}) == timeout
    assert timeout == :timer.minutes(30)
    assert StaleExportWorker.interrupted_after() == max(2 * timeout, :timer.hours(1))
    assert StaleExportWorker.interrupted_after() == :timer.hours(1)
    assert timeout < StaleExportWorker.interrupted_after()
  end

  test "fails a running export older than the limit and removes its files", %{module: module} do
    export = export!(module, :running, limit() + 1)
    assert files(export) == ["#{export.id}.build", "#{export.id}.zip.part", "#{export.id}.zip"]

    log = sweep!()

    failed = Repo.get!(Export, export.id)
    assert failed.status == :failed
    assert failed.error == @error
    assert failed.file_name == nil
    assert DateTime.compare(failed.updated_at, export.updated_at) == :gt
    assert files(export) == []
    assert log =~ "export interrupted: export #{export.id}"
  end

  test "fails a queued export older than the limit, whose job is then cancelled", %{
    module: module
  } do
    export = export!(module, :queued, limit() + 30)

    log = sweep!()

    assert %Export{status: :failed, error: @error} = Repo.get!(Export, export.id)
    assert files(export) == []
    assert log =~ export.id
    assert {:cancel, _reason} = perform_job(ExportWorker, %{export_id: export.id})
  end

  test "leaves a running export within the limit and its files", %{module: module} do
    export = export!(module, :running, limit() - 1)

    log = sweep!()

    assert Repo.get!(Export, export.id) == export
    assert files(export) == ["#{export.id}.build", "#{export.id}.zip.part", "#{export.id}.zip"]
    refute log =~ export.id
  end

  test "leaves a done export and its package", %{module: module} do
    export = export!(module, :done, 24 * 60)

    sweep!()

    assert Repo.get!(Export, export.id) == export
    assert "#{export.id}.zip" in files(export)
  end

  test "applies the retention: deletes an expired export and removes orphaned files",
       %{module: module} do
    expired = export!(module, :done, 8 * 24 * 60)
    kept = export!(module, :done, 6 * 24 * 60)
    orphan = Ecto.UUID.generate()
    File.write!(Path.join(Interop.export_dir(), "#{orphan}.zip"), "zip")

    sweep!()

    assert Repo.get(Export, expired.id) == nil
    assert files(expired) == []
    assert Repo.get!(Export, kept.id) == kept
    assert "#{kept.id}.zip" in files(kept)
    refute File.exists?(Path.join(Interop.export_dir(), "#{orphan}.zip"))
  end

  test "removes no file of an export whose job has set it running", %{module: module} do
    export = export!(module, :queued, limit() + 1)

    # The job starts before the sweep: the change to running renews
    # updated_at, so the sweep leaves the export and its files.
    assert {:ok, running} = Interop.transition_export(export, [:queued], %{status: :running})

    sweep!()

    assert Repo.get!(Export, export.id) == running
    assert files(export) == ["#{export.id}.build", "#{export.id}.zip.part", "#{export.id}.zip"]
  end

  test "config/config.exs runs the job every 15 minutes" do
    config = Config.Reader.read!("config/config.exs", env: :prod, target: :host)

    crontab =
      config
      |> get_in([:espalier, Oban, :plugins])
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> opts[:crontab]
        _plugin -> nil
      end)

    assert {"*/15 * * * *", StaleExportWorker} in crontab
  end
end
