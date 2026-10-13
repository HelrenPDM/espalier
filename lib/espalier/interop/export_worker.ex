defmodule Espalier.Interop.ExportWorker do
  @moduledoc """
  Builds the SCORM package of one export (task 0016, step 9). The job runs
  in the Oban queue `exports`, which has one slot, so concurrent requests
  queue up (ASVS 15.2.2), and its arguments hold the export id only.

  The worker sets the status `running` and builds the package in the
  directory `<EXPORT_DIR>/<id>.build/`. It checks that the program and the
  module are still published and reads the content in one transaction that
  first takes `pg_advisory_xact_lock_shared(hashtext(<program slug>))`. The
  slug is the pack key, so the lock conflicts with the exclusive lock of
  `Espalier.Catalog.Pack.Publisher` on the same pack, and the content comes
  from one published version. The `:timeout` of the transaction is
  `Publisher.transaction_timeout/0` plus one minute, because the lock waits
  for a publish that runs. The files are written after the transaction.
  The package holds:

    * `content.json`, written with `JSON.encode!/1` (ASVS 1.2.3): the keys
      of `Espalier.Interop.Payload.module/2` plus `schema` (1) and
      `policies`, which maps each `placeholder_key` of the module's blocks
      that has a published policy version to `key`, `number`,
      `effective_from` and `body` of the current version from
      `Espalier.Policies.current_versions/0`, the shape of the `policy`
      field of a placeholder block in the catalog views (task 0013, step
      21).
    * every file of `config :espalier, :scorm_player_dir` (default
      `priv/scorm_player`, the output of `npm --prefix frontend run
      build:scorm`) with `scorm.html` renamed to `index.html`, which puts
      `LICENSE` and `NOTICE` at the package root (Apache-2.0 section 4);
    * every file below `<scorm_xsd_dir>/12/` or `<scorm_xsd_dir>/2004/`
      (`config :espalier, :scorm_xsd_dir`, default `priv/scorm/xsd`, where
      `mix espalier.scorm_xsd` fetches them, see
      `Espalier.Interop.SchemaFiles`) at the same relative path from the
      package root;
    * `imsmanifest.xml` from `Espalier.Interop.manifest/2`, with one `file`
      element for every other file of the package, sorted by path.

  It zips the directory with `:zip.create/3` into `<id>.zip.part`, renames
  that file to `<id>.zip`, removes the build directory and sets the status
  `done` with `file_name`. On any error, the status changes to `running`
  and `done` included, it sets `failed` with a short text in `error`, logs
  the cause and then removes the build directory and the partial files.
  The status changes first: when the change to `done` committed but its
  answer was lost, the export is `done`, keeps its package and the job
  ends without an error. When the change to `failed` fails as well, the
  worker logs its cause, keeps the files and the job ends with the error;
  `Espalier.Interop.StaleExportWorker` ends such an export later and
  removes its files. A player directory without `scorm.html`, `LICENSE` or
  `NOTICE` fails the export with a text that names the missing files and
  the build command, so that no package leaves without the license files.

  Every status change goes through `Espalier.Interop.transition_export/3`,
  which changes the row only while it has one of the named statuses:

    * `queued` to `running`: when the sweep has set the export to `failed`
      in the meantime, the job is cancelled and touches no file;
    * `running` to `done`: when the export is no longer `running`, the
      worker removes the zip and its partial files, logs `export status not
      set to done: export <id> is no longer running, package removed` and
      cancels the job without a status change;
    * `queued` or `running` to `failed`: when the export has another status,
      the worker logs `export status not set to failed: export <id> is no
      longer queued or running`.

  After the change to `done`, the worker applies the count rule of
  `Espalier.Interop.prune_exports/1`, so that `EXPORT_DIR` holds at most
  `max_packages` packages plus the one of a build that runs. A failure of
  that step leaves the export `done` and logs `export retention not
  applied` with the cause; the sweep applies the rule again.

  The job runs at most `build_timeout/0` (30 minutes), the `timeout/1` of
  `Oban.Worker`. Oban 2.24 starts `:timer.exit_after/2` with
  `Oban.TimeoutError` for the job process, which ends the process from
  outside: no `rescue` and no `catch` of the worker runs, the open read
  transaction rolls back with the end of its connection owner, and Oban
  records the job as failed and, with one attempt, discards it. The
  export then stays `queued` or `running` with its partial files, and the
  sweep sets it to `failed` and removes the files once its `updated_at`
  lies `Espalier.Interop.StaleExportWorker.interrupted_after/0` back,
  which is always longer than the timeout. The sweep therefore finds no
  export interrupted whose job still runs. Should a job outlast both, for
  example after a pause of the node, the conditional status changes above
  keep the row and the files consistent.
  """
  use Oban.Worker, queue: :exports, max_attempts: 1

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Pack.Publisher
  alias Espalier.Catalog.Program
  alias Espalier.{Interop, Policies, Repo}
  alias Espalier.Interop.{Export, Payload}

  # The time that the read of the content takes at most, on top of the wait
  # for a publish of the same pack.
  @read_margin :timer.minutes(1)

  @player_entry "scorm.html"
  @required_player_files [@player_entry, "LICENSE", "NOTICE"]
  @build_command "npm --prefix frontend run build:scorm"
  @schema_command "mix espalier.scorm_xsd"
  @failed "The package could not be built; the server log names the cause."

  # The directory of the schema files below :scorm_xsd_dir per version.
  @xsd_dirs %{scorm12: "12", scorm2004: "2004"}
  @version_labels %{scorm12: "SCORM 1.2", scorm2004: "SCORM 2004 4th edition"}

  # The longest run of one job; the sweep of interrupted exports derives its
  # limit from it.
  @build_timeout :timer.minutes(30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"export_id" => id}}) do
    case Repo.get(Export, id) do
      %Export{status: :queued} = export -> run(export)
      %Export{status: status} -> {:cancel, "export #{id} is #{status}"}
      nil -> {:cancel, "export #{id} is gone"}
    end
  end

  @impl Oban.Worker
  def timeout(%Oban.Job{}), do: @build_timeout

  @doc """
  The longest run of an export job in milliseconds, 30 minutes: the
  `timeout/1` of the worker, after which Oban ends the job.
  """
  @spec build_timeout() :: pos_integer()
  def build_timeout, do: @build_timeout

  defp run(export) do
    paths = Interop.export_paths(export.id)

    case build_and_finish(export, paths) do
      :ok ->
        apply_retention(export)
        :ok

      {:cancel, _reason} = cancel ->
        cancel

      {:error, message} ->
        case mark_failed(export, message) do
          :done ->
            :ok

          :not_done ->
            remove_partial(export)
            {:error, message}

          :unknown ->
            {:error, message}
        end
    end
  end

  # Every exception and exit of the status changes to `running` and `done`
  # and of the build ends as the short text of a failed export; the log
  # names the cause.
  defp build_and_finish(export, paths) do
    case Interop.transition_export(export, [:queued], %{status: :running}) do
      {:ok, running} ->
        with :ok <- build(running, paths), do: finish(running, paths)

      {:error, :stale} ->
        {:cancel, "export #{export.id} is no longer queued"}
    end
  rescue
    exception ->
      log_exception(export, "export failed", :error, exception, __STACKTRACE__)
      {:error, @failed}
  catch
    kind, reason ->
      log_exception(export, "export failed", kind, reason, __STACKTRACE__)
      {:error, @failed}
  end

  # The sweep may have set the export to `failed` while the build ran; the
  # package of a build that lost that race leaves with the job.
  defp finish(export, paths) do
    attrs = %{status: :done, file_name: Path.basename(paths.zip)}

    case Interop.transition_export(export, [:running], attrs) do
      {:ok, _done} ->
        :ok

      {:error, :stale} ->
        remove_partial(export)

        Logger.warning(
          "export status not set to done: export #{export.id} is no longer running, " <>
            "package removed"
        )

        {:cancel, "export #{export.id} is no longer running"}
    end
  end

  # Sets `failed` and tells the caller whether the files of the export may
  # go: `:not_done` after the change, and when the sweep has already ended
  # the export; `:done` when the export is done after all, because the
  # change to `done` committed although its answer was lost; `:unknown`
  # when the change fails, so that the files stay until
  # `Espalier.Interop.StaleExportWorker` ends the export.
  defp mark_failed(export, message) do
    case Interop.transition_export(export, [:queued, :running], %{status: :failed, error: message}) do
      {:ok, _failed} ->
        :not_done

      {:error, :stale} ->
        stale_outcome(export)
    end
  rescue
    exception ->
      log_exception(export, "export status not set to failed", :error, exception, __STACKTRACE__)
      :unknown
  catch
    kind, reason ->
      log_exception(export, "export status not set to failed", kind, reason, __STACKTRACE__)
      :unknown
  end

  defp stale_outcome(export) do
    case Repo.get(Export, export.id) do
      %Export{status: :done} ->
        Logger.warning(
          "export status not set to failed: export #{export.id} is done, package kept"
        )

        :done

      _other ->
        Logger.warning(
          "export status not set to failed: export #{export.id} is no longer queued or running"
        )

        :not_done
    end
  end

  defp build(export, paths) do
    player_dir = player_dir()
    xsd_dir = Path.join(xsd_dir(), Map.fetch!(@xsd_dirs, export.scorm_version))

    with :ok <- check_player(player_dir),
         {:ok, xsd_files} <- schema_files(xsd_dir, export.scorm_version),
         {:ok, content} <- published_content(export),
         entries = entries(player_dir, xsd_dir, xsd_files, content),
         :ok <- check_unique(entries) do
      write_package(export, paths, entries, content)
    else
      {:error, message} = error ->
        Logger.error("export failed: export #{export.id}, #{message}")
        error
    end
  end

  ## Checks

  defp check_player(dir) do
    case Enum.reject(@required_player_files, &File.regular?(Path.join(dir, &1))) do
      [] ->
        :ok

      missing ->
        {:error,
         "The SCORM player build lacks #{Enum.join(missing, ", ")}. " <>
           "Run `#{@build_command}` and request the export again."}
    end
  end

  defp schema_files(dir, version) do
    case files_below(dir) do
      [] ->
        {:error,
         "The schema files of #{Map.fetch!(@version_labels, version)} are missing. " <>
           "Run `#{@schema_command}` and request the export again."}

      files ->
        {:ok, files}
    end
  end

  # The program and the module must still be published and live when the
  # job runs. The check and the content are read under the shared lock of
  # the pack: a publish of the pack that runs ends before the read, and one
  # that starts waits for it.
  defp published_content(%Export{program_id: program_id, module_id: module_id}) do
    Repo.transact(
      fn ->
        with slug when is_binary(slug) <-
               Repo.one(from p in Program, where: p.id == ^program_id, select: p.slug),
             :ok <- lock_pack_shared!(slug),
             %Program{status: :published} = program <- Repo.get(Program, program_id),
             %CatalogModule{archived_at: nil, program_id: ^program_id} = module <-
               Repo.get(CatalogModule, module_id) do
          {:ok, content(program, module)}
        else
          _other -> {:error, "The module is no longer published."}
        end
      end,
      timeout: read_timeout()
    )
  end

  defp lock_pack_shared!(slug) do
    Repo.query!("SELECT pg_advisory_xact_lock_shared(hashtext($1))", [slug])
    :ok
  end

  # The wait for a publish of the same pack and the read itself.
  defp read_timeout do
    case Publisher.transaction_timeout() do
      :infinity -> :infinity
      timeout -> timeout + @read_margin
    end
  end

  # Two sources that would land at one path of the package, the manifest
  # included.
  defp check_unique(entries) do
    paths = ["imsmanifest.xml" | Enum.map(entries, &elem(&1, 0))]

    case paths -- Enum.uniq(paths) do
      [] -> :ok
      [path | _rest] -> {:error, "Two files of the package would share the path #{path}."}
    end
  end

  ## Content

  defp content(program, module) do
    content = program |> Payload.build() |> Payload.module(module.number)
    Map.merge(content, %{"schema" => 1, "policies" => policies(content)})
  end

  defp policies(%{"module" => module}) do
    keys =
      for lesson <- module["lessons"],
          %{"kind" => "placeholder", "placeholder_key" => key} <- lesson["blocks"],
          is_binary(key),
          into: MapSet.new(),
          do: key

    for version <- Policies.current_versions(),
        MapSet.member?(keys, version.policy.key),
        into: %{} do
      {version.policy.key,
       %{
         "key" => version.policy.key,
         "number" => version.number,
         "effective_from" => Date.to_iso8601(version.effective_from),
         "body" => version.body
       }}
    end
  end

  ## Package

  # The files of the package other than the manifest, as {relative path,
  # source}: a file to copy or the bytes of content.json.
  defp entries(player_dir, xsd_dir, xsd_files, content) do
    player =
      for rel <- files_below(player_dir) do
        target = if rel == @player_entry, do: "index.html", else: rel
        {target, {:copy, Path.join(player_dir, rel)}}
      end

    schemas = for rel <- xsd_files, do: {rel, {:copy, Path.join(xsd_dir, rel)}}

    [{"content.json", {:data, JSON.encode!(content)}} | player ++ schemas]
  end

  # The paths come from EXPORT_DIR and the export id, and the relative
  # paths of the entries from listings of the configured player and schema
  # directories; no request reaches them.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_package(export, paths, entries, content) do
    File.mkdir_p!(paths.build)

    Enum.each(entries, fn {rel, source} ->
      target = Path.join(paths.build, rel)
      File.mkdir_p!(Path.dirname(target))

      case source do
        {:copy, from} -> File.cp!(from, target)
        {:data, data} -> File.write!(target, data)
      end
    end)

    files = entries |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    manifest =
      Interop.manifest(export.scorm_version, %{
        identifier: identifier(content),
        title: content["module"]["title"],
        files: files
      })

    File.write!(Path.join(paths.build, "imsmanifest.xml"), manifest)

    {:ok, _part} =
      :zip.create(
        String.to_charlist(paths.part),
        Enum.map(["imsmanifest.xml" | files], &String.to_charlist/1),
        cwd: String.to_charlist(paths.build)
      )

    File.rename!(paths.part, paths.zip)
    File.rm_rf!(paths.build)
    :ok
  end

  # The program slug follows the key format of content packs, so the
  # identifier is an XML name.
  defp identifier(%{"program" => %{"slug" => slug}, "module" => %{"number" => number}}),
    do: "espalier-#{slug}-module-#{number}"

  # The regular files below `dir` as relative paths with forward slashes,
  # sorted; dot files included.
  defp files_below(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.sort()
  end

  # Best effort: the build directory, the partial zip and the zip of the
  # export. Interop.remove_export_files/1 builds the paths from EXPORT_DIR
  # and the export id only and logs a failed removal.
  defp remove_partial(export) do
    _result = Interop.remove_export_files(export.id)
    :ok
  end

  # The count rule of the retention after an export reached `done`, which
  # keeps that export. A failure leaves the export `done`; the sweep
  # applies the rule again.
  defp apply_retention(export) do
    _pruned = Interop.prune_exports(:count, keep: export.id)
    :ok
  rescue
    exception ->
      Logger.error(
        "export retention not applied\n" <> Exception.format(:error, exception, __STACKTRACE__)
      )
  catch
    kind, reason ->
      Logger.error(
        "export retention not applied\n" <> Exception.format(kind, reason, __STACKTRACE__)
      )
  end

  defp player_dir do
    :espalier
    |> Application.get_env(:scorm_player_dir, Application.app_dir(:espalier, "priv/scorm_player"))
    |> Path.expand()
  end

  defp xsd_dir do
    :espalier
    |> Application.get_env(:scorm_xsd_dir, Application.app_dir(:espalier, "priv/scorm/xsd"))
    |> Path.expand()
  end

  defp log_exception(export, prefix, kind, reason, stacktrace) do
    Logger.error("#{prefix}: export #{export.id}\n" <> Exception.format(kind, reason, stacktrace))
  end
end
