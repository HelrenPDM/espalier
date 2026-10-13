defmodule Espalier.Interop.RetentionTest do
  @moduledoc """
  The retention of exports (task 0016, ASVS 15.2.2 and 5.3.2):
  `Espalier.Interop.prune_exports/1` and `Espalier.Interop.transition_export/3`.

  - The count rule keeps the newest `max_packages` exports with status
    `done` and deletes every older one with its package; it touches no
    export in another status.
  - The age rule deletes the exports with status `done` or `failed` whose
    `updated_at` lies more than `max_age_days` back, with their files, and
    keeps a younger one and a `running` one.
  - The orphan step removes only the direct entries of `EXPORT_DIR` named
    `<uuid>.build`, `<uuid>.zip.part` or `<uuid>.zip` without an export row,
    and removes a symbolic link of that name without touching its target.
  - A file that cannot be removed with its row is logged, and the next run
    removes it as an orphan.
  - A conditional transition changes an export only from the named
    statuses.
  """
  # The tests set :export_dir and :export_retention in the application
  # environment and the log level of Espalier.Interop for the node, and the
  # orphan step reads the whole EXPORT_DIR.
  use Espalier.DataCase, async: false

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import ExUnit.CaptureLog

  alias Espalier.Accounts.Scope
  alias Espalier.{Interop, LearningFixtures}
  alias Espalier.Interop.Export

  setup do
    dir = tmp_dir!("retention")
    put_env(:export_dir, dir)
    put_env(:export_retention, max_age_days: 7, max_packages: 100)
    Logger.put_module_level(Interop, :info)
    on_exit(fn -> Logger.delete_module_level(Interop) end)

    program = LearningFixtures.publish_demo!()
    %{dir: dir, module: LearningFixtures.module!(program, 1)}
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

  defp tmp_dir!(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "espalier-#{name}-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    on_exit(fn ->
      # A test may leave a directory without write permission.
      System.cmd("chmod", ["-R", "u+rwx", dir])
      File.rm_rf!(dir)
    end)

    dir
  end

  # An export of `module` in `status`, last changed `minutes` ago and
  # requested one minute before that. A `done` export names its zip, and
  # every export gets the files of a build: the build directory with a
  # file, the partial zip and the zip.
  # `opts` may fix the `:id` and the time `:at` of the last change, which
  # is otherwise `minutes` ago.
  defp export!(module, status, minutes, opts \\ []) do
    id = Keyword.get_lazy(opts, :id, &Ecto.UUID.generate/0)

    changed =
      Keyword.get_lazy(opts, :at, fn ->
        DateTime.add(DateTime.utc_now(:second), -minutes, :minute)
      end)

    Repo.insert!(%Export{
      id: id,
      program_id: module.program_id,
      module_id: module.id,
      scorm_version: :scorm12,
      status: status,
      file_name: if(status == :done, do: "#{id}.zip"),
      inserted_at: DateTime.add(changed, -1, :minute),
      updated_at: changed
    })

    write_files!(id)
    Repo.get!(Export, id)
  end

  defp write_files!(id) do
    paths = Interop.export_paths(id)
    File.mkdir_p!(paths.build)
    File.write!(Path.join(paths.build, "content.json"), "{}")
    File.write!(paths.part, "partial")
    File.write!(paths.zip, "zip")
  end

  defp files(id) do
    dir = Interop.export_dir()
    Enum.filter(["#{id}.build", "#{id}.zip.part", "#{id}.zip"], &File.exists?(Path.join(dir, &1)))
  end

  defp all_files(id), do: ["#{id}.build", "#{id}.zip.part", "#{id}.zip"]

  defp exists?(%Export{id: id}), do: Repo.get(Export, id) != nil

  defp prune!(mode), do: with_log([level: :info], fn -> Interop.prune_exports(mode) end)

  describe "retention/0" do
    test "reads both limits and rejects a value that is no positive integer" do
      assert Interop.retention() == %{max_age_days: 7, max_packages: 100}

      put_env(:export_retention, max_packages: 3)
      assert Interop.retention() == %{max_age_days: 7, max_packages: 3}

      for value <- [0, -1, 1.5, "7", nil] do
        put_env(:export_retention, max_age_days: value)

        assert_raise ArgumentError,
                     ~r/max_age_days must be a positive integer/,
                     &Interop.retention/0
      end
    end

    test "config/config.exs keeps a done or failed export 7 days and at most 100 packages" do
      config = Config.Reader.read!("config/config.exs", env: :prod, target: :host)
      assert config[:espalier][:export_retention] == [max_age_days: 7, max_packages: 100]
    end
  end

  describe "the count rule" do
    test "keeps the newest done exports and deletes every older one with its files",
         %{module: module} do
      put_env(:export_retention, max_age_days: 7, max_packages: 2)
      oldest = export!(module, :done, 40)
      older = export!(module, :done, 30)
      newer = export!(module, :done, 20)
      newest = export!(module, :done, 10)
      queued = export!(module, :queued, 50)
      running = export!(module, :running, 50)
      failed = export!(module, :failed, 50)

      {result, log} = prune!(:count)

      assert Enum.sort(result.deleted) == Enum.sort([oldest.id, older.id])
      assert result.orphans == []
      refute exists?(oldest) or exists?(older)
      assert files(oldest.id) == [] and files(older.id) == []
      assert log =~ "export deleted: export #{oldest.id}, beyond the newest 2 packages"

      for kept <- [newer, newest, queued, running, failed] do
        assert Repo.get!(Export, kept.id) == kept
        assert files(kept.id) == all_files(kept.id)
      end

      # The routes of a deleted export find no row.
      scope = %{Scope.for_user(user_with_role_fixture(:author)) | roles: [:learner, :author]}
      assert Interop.get_export(scope, oldest.id) == {:error, :not_found}
    end

    test "keeps the export named by keep among exports of the same second", %{module: module} do
      put_env(:export_retention, max_age_days: 7, max_packages: 1)
      at = DateTime.add(DateTime.utc_now(:second), -10, :minute)

      # Equal timestamps leave the order to the id, which ranks `first`
      # above `second`; only `keep` saves `second`.
      first = export!(module, :done, 10, id: "ffffffff-ffff-4fff-bfff-ffffffffffff", at: at)
      second = export!(module, :done, 10, id: "00000000-0000-4000-8000-000000000000", at: at)

      assert {%{deleted: [deleted]}, _log} =
               with_log(fn -> Interop.prune_exports(:count, keep: second.id) end)

      assert deleted == first.id
      assert exists?(second)
      assert files(second.id) == all_files(second.id)
    end

    test "deletes nothing while the done exports stay within the limit", %{module: module} do
      exports = for minutes <- [30, 20, 10], do: export!(module, :done, minutes)

      assert {%{deleted: [], orphans: []}, _log} = prune!(:count)
      assert Enum.all?(exports, &exists?/1)
    end
  end

  describe "the age rule" do
    test "deletes done and failed exports older than max_age_days with their files",
         %{module: module} do
      day = 24 * 60
      old_done = export!(module, :done, 8 * day)
      old_failed = export!(module, :failed, 8 * day)
      young_done = export!(module, :done, 6 * day)
      young_failed = export!(module, :failed, 6 * day)
      old_running = export!(module, :running, 8 * day)

      {result, log} = prune!(:all)

      assert Enum.sort(result.deleted) == Enum.sort([old_done.id, old_failed.id])
      refute exists?(old_done) or exists?(old_failed)
      assert files(old_done.id) == [] and files(old_failed.id) == []
      assert log =~ "export deleted: export #{old_failed.id}, older than 7 days"

      for kept <- [young_done, young_failed, old_running] do
        assert Repo.get!(Export, kept.id) == kept
        assert files(kept.id) == all_files(kept.id)
      end
    end
  end

  describe "the orphan step" do
    test "removes only uuid-named direct entries without an export row",
         %{dir: dir, module: module} do
      kept = export!(module, :running, 5)
      orphan = Ecto.UUID.generate()
      write_files!(orphan)

      # A symbolic link of an orphan name to a directory outside EXPORT_DIR.
      outside = tmp_dir!("outside")
      File.write!(Path.join(outside, "keep.txt"), "keep")
      linked = Ecto.UUID.generate()
      File.ln_s!(outside, Path.join(dir, "#{linked}.build"))

      other = Ecto.UUID.generate()

      others = [
        "notes.txt",
        "#{other}.zip.bak",
        "#{other}.tar",
        "#{String.upcase(other)}.zip",
        "x#{other}.zip",
        "#{other}.zip.part.old"
      ]

      for name <- others, do: File.write!(Path.join(dir, name), "other")
      File.mkdir_p!(Path.join(dir, "nested"))
      File.write!(Path.join([dir, "nested", "#{other}.zip"]), "nested")

      {result, log} = prune!(:all)

      assert Enum.sort(result.orphans) ==
               Enum.sort(["#{linked}.build" | all_files(orphan)])

      assert result.deleted == []
      assert files(orphan) == []
      refute File.exists?(Path.join(dir, "#{linked}.build"))
      assert File.read!(Path.join(outside, "keep.txt")) == "keep"
      assert files(kept.id) == all_files(kept.id)
      assert Enum.all?(others, &File.exists?(Path.join(dir, &1)))
      assert File.exists?(Path.join([dir, "nested", "#{other}.zip"]))
      assert log =~ "export file without export removed: #{orphan}.zip"
    end

    test "a missing EXPORT_DIR removes nothing" do
      put_env(:export_dir, Path.join(tmp_dir!("missing"), "absent"))

      assert {%{deleted: [], orphans: []}, _log} = prune!(:all)
    end
  end

  test "a file that is not removed with its row goes with the next run", %{module: module} do
    export = export!(module, :failed, 8 * 24 * 60)
    build = Interop.export_paths(export.id).build
    File.chmod!(build, 0o555)
    # A root process may write into the directory anyway.
    blocked? = match?({:error, _reason}, File.write(Path.join(build, "probe"), ""))

    {result, log} = prune!(:all)

    assert result.deleted == [export.id]
    refute exists?(export)

    if blocked? do
      assert log =~ "export file not removed: #{export.id}.build, "
      assert files(export.id) == ["#{export.id}.build"]
    end

    File.chmod!(build, 0o755)
    {result, _log} = prune!(:all)

    assert result.deleted == []
    if blocked?, do: assert(result.orphans == ["#{export.id}.build"])
    assert files(export.id) == []
  end

  describe "transition_export/3" do
    test "changes the status only from the named statuses", %{module: module} do
      export = export!(module, :queued, 5)

      assert {:ok, running} = Interop.transition_export(export, [:queued], %{status: :running})
      assert running.status == :running
      assert DateTime.compare(running.updated_at, export.updated_at) == :gt
      assert Repo.get!(Export, export.id) == running

      # The row is running, so a second change from queued finds no row.
      assert Interop.transition_export(export, [:queued], %{status: :running}) ==
               {:error, :stale}

      assert Repo.get!(Export, export.id) == running
    end

    test "leaves an export failed by the sweep failed", %{module: module} do
      export = export!(module, :running, 5)

      Repo.update_all(from(e in Export, where: e.id == ^export.id),
        set: [status: :failed, error: "The build was interrupted; request the export again."]
      )

      failed = Repo.get!(Export, export.id)

      assert Interop.transition_export(export, [:running], %{
               status: :done,
               file_name: "#{export.id}.zip"
             }) == {:error, :stale}

      assert Interop.transition_export(export, [:queued], %{status: :running}) ==
               {:error, :stale}

      assert Repo.get!(Export, export.id) == failed
    end

    test "answers stale for an export that is gone", %{module: module} do
      export = export!(module, :done, 5)
      Repo.delete!(export)

      assert Interop.transition_export(export, [:done], %{status: :failed, error: "x"}) ==
               {:error, :stale}
    end
  end
end
