defmodule Espalier.Interop.ExportWorkerTest do
  @moduledoc """
  The export worker of task 0016 (step 9; step 13, bullet "Worker") on the
  published demo pack. `:scorm_player_dir` points to
  `test/fixtures/scorm_player/` (stand-ins of `scorm.html`, the two asset
  files, `LICENSE` and `NOTICE`), `:scorm_xsd_dir` to
  `test/fixtures/scorm_xsd/` (stand-ins of the schema files, with a nested
  directory below `2004/`), and every test writes to a fresh `EXPORT_DIR`.

  - The package of module 1 holds the player, `LICENSE`, `NOTICE`,
    `content.json` and exactly the schema files of its version at the root;
    the license files equal the fixtures byte for byte (Apache-2.0 section
    4).
  - The manifest parses, and its `file` elements and the zip entries other
    than `imsmanifest.xml` correspond one to one (ASVS 1.2.1 and 1.3.7).
  - `content.json` holds exactly the keys of `Payload.module/2` plus
    `schema` and `policies` (ASVS 1.2.3), with answer keys, the objectives
    and companion formats of the module, and the current version of a
    placeholder's policy.
  - A player build without `NOTICE` and any exception fail the export with
    a short text and leave no partial file, also an exception of the status
    change to `running`; a failing status change to `failed` ends the job
    with the error and the log names it.
  - An export requested before a second publish of the pack holds the
    content of the version published last.
  """
  # The tests set :export_dir and :scorm_player_dir in the application
  # environment.
  use Espalier.DataCase, async: false

  import Espalier.CredentialsFixtures, only: [published_policy!: 2, user_with_role_fixture: 1]
  import ExUnit.CaptureLog

  require Record

  alias Espalier.Accounts.Scope
  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.{Interop, LearningFixtures, PackFixtures}
  alias Espalier.Interop.{Export, ExportWorker, Payload}

  Record.defrecordp(
    :xml_text,
    :xmlText,
    Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :xml_attribute,
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  @player Path.expand("../../fixtures/scorm_player", __DIR__)
  @xsd Path.expand("../../fixtures/scorm_xsd", __DIR__)
  @xsd_dirs %{scorm12: "12", scorm2004: "2004"}
  @build_command "npm --prefix frontend run build:scorm"

  # Every package holds these files at the root, besides the schema files.
  @package_files ~w(imsmanifest.xml index.html LICENSE NOTICE content.json
                    assets/player.js assets/player.css)

  @objective_members ~w(area depth domain key phase statement taught_in)

  setup do
    put_env(:export_dir, tmp_dir!("exports"))
    put_env(:scorm_player_dir, @player)
    put_env(:scorm_xsd_dir, @xsd)

    author = user_with_role_fixture(:author)
    %{scope: %{Scope.for_user(author) | roles: [:learner, :author]}}
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
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # Requests the export of module `number` and runs its job.
  defp request!(scope, program, number, version) do
    module = LearningFixtures.module!(program, number)
    {:ok, export} = Interop.request_export(scope, module.id, version)
    export
  end

  defp export!(scope, program, number, version) do
    export = request!(scope, program, number, version)
    assert perform_job(ExportWorker, %{export_id: export.id}) == :ok
    Repo.get!(Export, export.id)
  end

  defp zip_path(%Export{file_name: file_name}), do: Path.join(Interop.export_dir(), file_name)

  defp entries(zip) do
    {:ok, entries} = :zip.list_dir(String.to_charlist(zip))
    for {:zip_file, name, _info, _comment, _offset, _size} <- entries, do: List.to_string(name)
  end

  defp read_entry!(zip, name) do
    {:ok, [{_name, data}]} =
      :zip.extract(String.to_charlist(zip), [:memory, file_list: [String.to_charlist(name)]])

    data
  end

  defp content!(export), do: export |> zip_path() |> read_entry!("content.json") |> JSON.decode!()

  # xmerl reads the bytes and decodes them by the encoding of the
  # declaration.
  defp manifest!(export) do
    xml = export |> zip_path() |> read_entry!("imsmanifest.xml")
    {document, []} = :xmerl_scan.string(:binary.bin_to_list(xml), quiet: true)
    document
  end

  defp texts(document, path) do
    for node <- :xmerl_xpath.string(String.to_charlist(path), document),
        do: node |> xml_text(:value) |> List.to_string()
  end

  defp attributes(document, path) do
    for node <- :xmerl_xpath.string(String.to_charlist(path), document),
        do: node |> xml_attribute(:value) |> List.to_string()
  end

  # The files below `dir` as relative paths, sorted.
  defp files_below(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.sort()
  end

  defp schema_files(version), do: files_below(Path.join(@xsd, Map.fetch!(@xsd_dirs, version)))

  # The value as JSON gives it back.
  defp json(value), do: value |> JSON.encode!() |> JSON.decode!()

  # Makes every row operation `event` on `table` that matches `condition`
  # fail. The rollback of the sandbox transaction removes the trigger.
  defp fail_on!(table, event, condition) do
    Repo.query!("""
    CREATE FUNCTION espalier_test_fail() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'forced failure on %', TG_TABLE_NAME;
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER espalier_test_fail BEFORE #{event} ON #{table}
    FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION espalier_test_fail()
    """)
  end

  describe "the package of module 1" do
    setup do
      %{program: LearningFixtures.publish_demo!()}
    end

    test "holds the player, the license files, content.json and the schema files of its version",
         %{scope: scope, program: program} do
      for version <- [:scorm12, :scorm2004] do
        export = export!(scope, program, 1, version)

        assert export.status == :done
        assert export.file_name == "#{export.id}.zip"
        assert export.error == nil

        zip = zip_path(export)
        assert Enum.sort(entries(zip)) == Enum.sort(@package_files ++ schema_files(version))

        assert read_entry!(zip, "LICENSE") == File.read!(Path.join(@player, "LICENSE"))
        assert read_entry!(zip, "NOTICE") == File.read!(Path.join(@player, "NOTICE"))
        assert read_entry!(zip, "index.html") == File.read!(Path.join(@player, "scorm.html"))
        refute "scorm.html" in entries(zip)
      end

      # The worker leaves the two packages and no build directory or
      # partial file.
      assert Interop.export_dir() |> File.ls!() |> Enum.all?(&String.ends_with?(&1, ".zip"))
      assert length(File.ls!(Interop.export_dir())) == 2
    end

    test "copies exactly the files of the configured schema directory, nested ones included",
         %{scope: scope, program: program} do
      assert "common/anyElement.xsd" in schema_files(:scorm2004)

      for version <- [:scorm12, :scorm2004] do
        other = if version == :scorm12, do: :scorm2004, else: :scorm12
        entries = scope |> export!(program, 1, version) |> zip_path() |> entries()

        assert Enum.sort(entries -- @package_files) == schema_files(version)
        assert Enum.filter(schema_files(other), &(&1 in entries)) == []
      end
    end

    test "has a manifest whose file elements and zip entries correspond one to one",
         %{scope: scope, program: program} do
      for version <- [:scorm12, :scorm2004] do
        export = export!(scope, program, 1, version)
        document = manifest!(export)
        files = attributes(document, "//*[local-name()='file']/@href")

        assert files == Enum.sort(files)
        assert files == Enum.uniq(files)
        assert Enum.sort(files) == Enum.sort(entries(zip_path(export)) -- ["imsmanifest.xml"])
        assert "LICENSE" in files and "NOTICE" in files

        assert attributes(document, "/*[local-name()='manifest']/@identifier") ==
                 ["espalier-#{program.slug}-module-1"]

        title = LearningFixtures.module!(program, 1).title
        assert texts(document, "//*[local-name()='title']/text()") == [title, title]
        assert attributes(document, "//*[local-name()='resource']/@href") == ["index.html"]
      end
    end

    test "has content.json with the module, its objectives and formats, and the answer keys",
         %{scope: scope, program: program} do
      content = content!(export!(scope, program, 1, :scorm12))

      assert content |> Map.keys() |> Enum.sort() ==
               ~w(formats glossary module policies program schema sources)

      assert content["schema"] == 1
      assert content["policies"] == %{}

      expected = program |> Payload.build() |> Payload.module(1) |> json()
      assert Map.drop(content, ["schema", "policies"]) == expected

      module = content["module"]

      assert Enum.map(module["objectives"], & &1["key"]) == [
               "m1-subject-next-word",
               "m1-subject-varying-answers",
               "m1-method-check-claims",
               "m1-self-own-responsibility",
               "m1-social-team-transparency"
             ]

      for objective <- module["objectives"] do
        assert objective |> Map.keys() |> Enum.sort() == @objective_members
      end

      for item <- module["items"], item["kind"] != "poll" do
        assert [_ | _] = item["objectives"], item["key"]
      end

      assert [%{"key" => "workshop", "objectives" => workshop}] = content["formats"]
      assert workshop == ["m1-self-own-responsibility", "m1-social-team-transparency"]

      # The answer keys: every option carries correct and feedback, and every
      # choice item has a correct option.
      options = for item <- module["items"], option <- item["options"], do: {item, option}
      assert options != []

      for {_item, option} <- options do
        assert Map.has_key?(option, "correct") and Map.has_key?(option, "feedback")
        assert is_boolean(option["correct"])
      end

      for item <- module["items"], item["kind"] in ["single_choice", "multiple_choice"] do
        assert Enum.any?(item["options"], & &1["correct"]), item["key"]
      end
    end

    test "maps the placeholder of the module to the current version of its policy",
         %{scope: scope, program: program} do
      # The demo pack places the policy key input-rules in module 1; another
      # published policy stays out.
      _other = published_policy!("other-rules", %{body: "Other rules."})

      version =
        published_policy!("input-rules", %{
          body: "Enter no *personal data*.",
          effective_from: ~D[2026-02-01]
        })

      content = content!(export!(scope, program, 1, :scorm2004))

      assert content["policies"] == %{
               "input-rules" => %{
                 "key" => "input-rules",
                 "number" => version.number,
                 "effective_from" => "2026-02-01",
                 "body" => "Enter no *personal data*."
               }
             }
    end
  end

  describe "the package of module 2" do
    test "holds its three objectives, its areas elsewhere and no format", %{scope: scope} do
      program = LearningFixtures.publish_demo!()
      content = content!(export!(scope, program, 2, :scorm2004))

      assert length(content["module"]["objectives"]) == 3

      for objective <- content["module"]["objectives"] do
        assert objective |> Map.keys() |> Enum.sort() == @objective_members
      end

      assert content["module"]["areas_elsewhere"] |> Map.keys() |> Enum.sort() == [
               "self",
               "social"
             ]

      assert content["formats"] == []
    end
  end

  describe "the manifest of a module title with markup" do
    test "holds the title escaped", %{scope: scope} do
      title = ~s[Models <b>&</b> "you" & 'me']
      pack = PackFixtures.copy_pack!(PackFixtures.demo_path())

      PackFixtures.update_yaml!(
        pack,
        "modules/01-basics/module.yaml",
        &Map.put(&1, "title", title)
      )

      program = LearningFixtures.publish_demo!(pack)

      for version <- [:scorm12, :scorm2004] do
        export = export!(scope, program, 1, version)
        xml = export |> zip_path() |> read_entry!("imsmanifest.xml")

        refute xml =~ "<b>"
        assert xml =~ "Models &lt;b&gt;&amp;&lt;/b&gt; &quot;you&quot; &amp; &apos;me&apos;"
        assert texts(manifest!(export), "//*[local-name()='title']/text()") == [title, title]
      end
    end
  end

  describe "an export after a second publish of the pack" do
    test "holds the content of the version published last", %{scope: scope} do
      first = LearningFixtures.publish_demo!()
      export = request!(scope, first, 1, :scorm12)

      pack = PackFixtures.copy_pack!(PackFixtures.demo_path())
      PackFixtures.update_yaml!(pack, "pack.yaml", &Map.put(&1, "version", "1.1.0"))

      PackFixtures.update_yaml!(
        pack,
        "modules/01-basics/module.yaml",
        &Map.put(&1, "title", "Language models, second edition")
      )

      program = LearningFixtures.publish_demo!(pack)
      assert program.id == first.id
      assert program.pack_version == "1.1.0"

      assert perform_job(ExportWorker, %{export_id: export.id}) == :ok
      content = content!(Repo.get!(Export, export.id))

      assert content["module"]["title"] == "Language models, second edition"
      expected = program |> Payload.build() |> Payload.module(1) |> json()
      assert Map.drop(content, ["schema", "policies"]) == expected
    end
  end

  describe "a failed export" do
    setup do
      %{program: LearningFixtures.publish_demo!()}
    end

    test "names a missing NOTICE and the build command and writes no package",
         %{scope: scope, program: program} do
      player = tmp_dir!("player")
      File.cp_r!(@player, player)
      File.rm!(Path.join(player, "NOTICE"))
      put_env(:scorm_player_dir, player)
      export = request!(scope, program, 1, :scorm12)

      log =
        capture_log(fn ->
          assert {:error, message} = perform_job(ExportWorker, %{export_id: export.id})
          assert message =~ "NOTICE"
        end)

      assert log =~ export.id
      failed = Repo.get!(Export, export.id)
      assert failed.status == :failed
      assert failed.file_name == nil
      assert failed.error =~ "NOTICE"
      assert failed.error =~ @build_command
      refute failed.error =~ "LICENSE"
      assert File.ls!(Interop.export_dir()) == []
    end

    test "names every missing player file", %{scope: scope, program: program} do
      player = tmp_dir!("player")
      File.cp_r!(@player, player)
      File.rm!(Path.join(player, "scorm.html"))
      File.rm!(Path.join(player, "LICENSE"))
      put_env(:scorm_player_dir, player)
      export = request!(scope, program, 1, :scorm2004)

      capture_log(fn -> perform_job(ExportWorker, %{export_id: export.id}) end)

      failed = Repo.get!(Export, export.id)
      assert failed.status == :failed
      assert failed.error =~ "scorm.html, LICENSE"
      assert failed.error =~ @build_command
    end

    test "fails without the schema files of its version", %{scope: scope, program: program} do
      xsd = tmp_dir!("xsd")
      File.cp_r!(Path.join(@xsd, "12"), Path.join(xsd, "12"))
      put_env(:scorm_xsd_dir, xsd)
      export = request!(scope, program, 1, :scorm2004)

      capture_log(fn -> perform_job(ExportWorker, %{export_id: export.id}) end)

      failed = Repo.get!(Export, export.id)
      assert failed.status == :failed
      assert failed.error =~ "schema files of SCORM 2004"
      assert failed.error =~ "mix espalier.scorm_xsd"
    end

    test "fails for a module archived after the request", %{scope: scope, program: program} do
      export = request!(scope, program, 2, :scorm12)
      now = DateTime.utc_now(:second)

      Repo.update_all(from(m in CatalogModule, where: m.id == ^export.module_id),
        set: [archived_at: now]
      )

      capture_log(fn -> perform_job(ExportWorker, %{export_id: export.id}) end)

      failed = Repo.get!(Export, export.id)
      assert failed.status == :failed
      assert failed.error == "The module is no longer published."
    end

    test "turns an exception into a short text, logs it and removes the partial files",
         %{scope: scope, program: program} do
      export = request!(scope, program, 1, :scorm12)

      # A directory in the place of the partial zip lets :zip.create/3 fail
      # after the build directory is filled.
      part = Path.join(Interop.export_dir(), "#{export.id}.zip.part")
      File.mkdir_p!(Path.join(part, "blocker"))

      log =
        capture_log(fn ->
          assert {:error, message} = perform_job(ExportWorker, %{export_id: export.id})
          assert message =~ "could not be built"
        end)

      assert log =~ "export failed: export #{export.id}"
      failed = Repo.get!(Export, export.id)
      assert failed.status == :failed
      assert failed.error =~ "could not be built"
      assert File.ls!(Interop.export_dir()) == []
    end

    test "turns an exception of the status change to running into a failed export",
         %{scope: scope, program: program} do
      export = request!(scope, program, 1, :scorm12)
      fail_on!("exports", "UPDATE", "NEW.status = 'running'")

      log =
        capture_log(fn ->
          assert {:error, message} = perform_job(ExportWorker, %{export_id: export.id})
          assert message =~ "could not be built"
        end)

      assert log =~ "export failed: export #{export.id}"
      failed = Repo.get!(Export, export.id)
      assert failed.status == :failed
      assert failed.error =~ "could not be built"
      assert File.ls!(Interop.export_dir()) == []
    end

    test "ends the job with the error and logs it when the status change to failed fails",
         %{scope: scope, program: program} do
      player = tmp_dir!("player")
      File.cp_r!(@player, player)
      File.rm!(Path.join(player, "NOTICE"))
      put_env(:scorm_player_dir, player)
      export = request!(scope, program, 1, :scorm12)
      fail_on!("exports", "UPDATE", "NEW.status = 'failed'")

      log =
        capture_log(fn ->
          assert {:error, message} = perform_job(ExportWorker, %{export_id: export.id})
          assert message =~ "NOTICE"
        end)

      assert log =~ "export status not set to failed: export #{export.id}"
      assert log =~ "forced failure on exports"
      assert Repo.get!(Export, export.id).status == :running
      assert File.ls!(Interop.export_dir()) == []
    end
  end

  test "runs an export once", %{scope: scope} do
    program = LearningFixtures.publish_demo!()
    export = export!(scope, program, 2, :scorm12)

    assert {:cancel, _reason} = perform_job(ExportWorker, %{export_id: export.id})
    assert Repo.get!(Export, export.id).status == :done
  end
end

defmodule Espalier.Interop.PublishLockTest do
  @moduledoc """
  Task 0016: the export worker and the pack writer read a program under
  the shared advisory lock of its pack, which conflicts with the exclusive
  lock of `Espalier.Catalog.Pack.Publisher`. A publish of the pack that
  runs therefore ends before they read, and they read the version that it
  commits.

  The SQL sandbox serves every process of a test through one connection,
  so it cannot show a lock wait. As in `Espalier.Credentials.LockOrderTest`,
  each transaction runs on a connection of its own through
  `Ecto.Adapters.SQL.Sandbox.unboxed_run/2`, the rows are committed and
  deleted again on exit, and the module is synchronous, so no sandboxed
  test sees them.

  The scenario: a published program with one module and a queued export of
  it. A transaction in place of a publish takes the exclusive lock of the
  pack and renames the module. The export, or the write of the pack,
  starts and waits for the shared lock; then the transaction commits. The
  package and the pack hold the new title.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Program
  alias Espalier.{Interop, PackFixtures, Repo}
  alias Espalier.Interop.{Export, ExportWorker, PackWriter}

  # How long the test waits for the reader to reach its lock wait.
  @wait_ms 5_000

  # A wait of another session for the shared lock of a pack, in the
  # database of this session: the one-key form of the advisory lock stores
  # the low 32 bits of its key in objid, with objsubid 1.
  @waiting_sql """
  SELECT count(*) FROM pg_locks
  WHERE locktype = 'advisory' AND mode = 'ShareLock' AND NOT granted
    AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND objid = hashtext($1)::oid AND objsubid = 1
  """

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "espalier-publish-lock-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    previous = Application.fetch_env(:espalier, :export_dir)
    Application.put_env(:espalier, :export_dir, Path.join(dir, "exports"))
    File.mkdir_p!(Path.join(dir, "exports"))

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, :export_dir, value)
        :error -> Application.delete_env(:espalier, :export_dir)
      end
    end)

    data = unboxed(&insert_scenario!/0)
    on_exit(fn -> unboxed(fn -> delete_scenario!(data) end) end)
    Map.put(data, :dir, dir)
  end

  defp insert_scenario! do
    program =
      Repo.insert!(%Program{
        slug: "publish-lock-#{System.unique_integer([:positive])}",
        title: "Publish lock",
        locale: "en",
        status: :published,
        pack_version: "1.0.0"
      })

    module = Repo.insert!(%CatalogModule{program_id: program.id, number: 1, title: "Before"})

    export =
      Repo.insert!(%Export{
        program_id: program.id,
        module_id: module.id,
        scorm_version: :scorm12
      })

    %{program: program, module: module, export: export}
  end

  defp delete_scenario!(data) do
    Repo.delete_all(from e in Export, where: e.program_id == ^data.program.id)
    Repo.delete_all(from m in CatalogModule, where: m.program_id == ^data.program.id)
    Repo.delete_all(from p in Program, where: p.id == ^data.program.id)
  end

  # A transaction in place of a publish of the pack: it takes the lock of
  # the publisher, renames the module and commits on :commit.
  defp hold_publish!(data) do
    parent = self()

    publish = Task.async(fn -> unboxed(fn -> publish!(data, parent) end) end)
    assert_receive :held, 5_000
    publish
  end

  defp publish!(data, parent) do
    Repo.transact(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [data.program.slug])

      Repo.update_all(from(m in CatalogModule, where: m.id == ^data.module.id),
        set: [title: "After"]
      )

      send(parent, :held)

      receive do
        :commit -> {:ok, :committed}
      end
    end)
  end

  # Polls pg_locks until a session waits for the shared lock of the pack,
  # and returns false when none does within @wait_ms.
  defp await_lock_wait(slug, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + @wait_ms
    %{rows: [[waiting]]} = unboxed(fn -> Repo.query!(@waiting_sql, [slug]) end)

    cond do
      waiting > 0 ->
        true

      System.monotonic_time(:millisecond) > deadline ->
        false

      true ->
        Process.sleep(20)
        await_lock_wait(slug, deadline)
    end
  end

  defp commit!(publish) do
    send(publish.pid, :commit)
    assert {:ok, :committed} = Task.await(publish, 10_000)
  end

  test "an export waits for a publish of its pack and holds the version it commits", data do
    publish = hold_publish!(data)
    job = %Oban.Job{args: %{"export_id" => data.export.id}}
    export = Task.async(fn -> unboxed(fn -> ExportWorker.perform(job) end) end)

    assert await_lock_wait(data.program.slug)
    assert Task.yield(export, 0) == nil

    commit!(publish)
    assert :ok = Task.await(export, 15_000)

    done = unboxed(fn -> Repo.get!(Export, data.export.id) end)
    assert done.status == :done

    {:ok, [{_name, json}]} =
      :zip.extract(String.to_charlist(Path.join(Interop.export_dir(), done.file_name)), [
        :memory,
        file_list: [~c"content.json"]
      ])

    assert JSON.decode!(json)["module"]["title"] == "After"
  end

  test "the pack writer waits for a publish of the pack and writes the version it commits",
       data do
    out = Path.join(data.dir, "pack")
    publish = hold_publish!(data)
    writer = Task.async(fn -> unboxed(fn -> PackWriter.write(data.program, out) end) end)

    assert await_lock_wait(data.program.slug)
    assert Task.yield(writer, 0) == nil
    refute File.exists?(out)

    commit!(publish)
    assert {:ok, _version} = Task.await(writer, 15_000)

    assert PackFixtures.read_yaml!(out, "modules/01-after/module.yaml")["title"] == "After"
  end
end
