defmodule Espalier.Interop.ExportWorkerTest do
  @moduledoc """
  The export worker of task 0016 (step 9; step 13, bullet "Worker") on the
  published demo pack. `:scorm_player_dir` points to
  `test/fixtures/scorm_player/` (stand-ins of `scorm.html`, the two asset
  files, `LICENSE` and `NOTICE`), `:scorm_xsd_dir` to
  `test/fixtures/scorm_xsd/` (stand-ins of the schema files, with a nested
  directory below `2004/`), and every test writes to a fresh `EXPORT_DIR`.

  - The package of module 1 holds the player, `LICENSE`, `NOTICE`,
    `content.json` and exactly the schema files of its version at the root,
    and the media files of the module below `media/` (task 0018, step 17);
    the license files equal the fixtures byte for byte (Apache-2.0 section
    4), and the media files the store byte for byte, a WebM without
    compression.
  - Two paths of one asset and two videos with one poster give one file
    each in the package, and media above `export_max_mb` fail the export
    with a text that names the limit.
  - A media file that cannot be staged fails the export with "A media file
    of the module is missing." when its store file is gone, with the
    generic text when the build directory denies the write, and with a
    text that names the full volume for `enospc` and `edquot`; the log
    names the export, the path in the package and the POSIX reason.
  - The manifest parses, and its `file` elements and the zip entries other
    than `imsmanifest.xml` correspond one to one (ASVS 1.2.1 and 1.3.7).
  - `content.json` holds exactly the keys of `Payload.module/3` plus
    `schema` and `policies` (ASVS 1.2.3), with answer keys, the objectives
    and companion formats of the module, and the current version of a
    placeholder's policy.
  - A player build without `NOTICE` and any exception fail the export with
    a short text and leave no partial file, also an exception of the status
    change to `running`; a failing status change to `failed` ends the job
    with the error and the log names it.
  - An export requested before a second publish of the pack holds the
    content of the version published last.
  - A build whose export the sweep of interrupted exports has set to
    `failed` neither sets `done` nor `failed` again and leaves no file; a
    job whose change to `running` finds the export no longer `queued` is
    cancelled and writes no file.
  - After an export reaches `done`, the worker deletes the `done` exports
    beyond `max_packages` with their packages.
  """
  # The tests set :export_dir and :scorm_player_dir in the application
  # environment.
  use Espalier.DataCase, async: false

  import Espalier.CredentialsFixtures, only: [published_policy!: 2, user_with_role_fixture: 1]
  import ExUnit.CaptureLog

  require Record

  alias Espalier.Accounts.Scope
  alias Espalier.Catalog
  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.PackImport
  alias Espalier.{Interop, LearningFixtures, MediaFixtures, PackFixtures}
  alias Espalier.Interop.{Export, ExportWorker, Payload}
  alias Espalier.Media.{Asset, Store}

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

  # The media files of module 1 of the demo pack, the WebM and its captions,
  # as `{package path, demo file}`: each delivery file once at
  # `media/<sha256>.<ext>` (task 0018, step 17). The demo assets have no
  # poster.
  defp module1_media do
    for {rel, ext} <- [
          {"media/assistant-demo.webm", "webm"},
          {"media/assistant-demo-en.vtt", "vtt"}
        ] do
      file = Path.join(PackFixtures.demo_path(), rel)
      {sha256, _bytes} = Store.digest(file)
      {"media/#{sha256}.#{ext}", file}
    end
  end

  # The files of every package of module 1 of the demo pack, besides the
  # schema files.
  defp package_files, do: @package_files ++ Enum.map(module1_media(), &elem(&1, 0))

  # The content of module `number` of the published `program` as
  # content.json holds it, without `schema` and `policies`: the payload cut
  # by `Payload.module/3` with the asset rows of the media of the module.
  defp module_content(program, number) do
    payload = Payload.build(program)
    module = Enum.find(payload["modules"], &(&1["number"] == number))
    ids = Payload.media_asset_ids(payload, module)
    assets = Map.new(Repo.all(from a in Asset, where: a.id in ^ids), &{&1.id, &1})
    payload |> Payload.module(number, assets) |> json()
  end

  # The zip entries below media/ with their compressed and uncompressed
  # sizes.
  defp media_entries(zip) do
    {:ok, entries} = :zip.list_dir(String.to_charlist(zip))

    for {:zip_file, name, info, _comment, _offset, comp_size} <- entries,
        name = List.to_string(name),
        String.starts_with?(name, "media/"),
        into: %{},
        do: {name, {comp_size, elem(info, 1)}}
  end

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

  @interrupted "The build was interrupted; request the export again."

  # Plays the sweep of interrupted exports right after the change to
  # running: an AFTER trigger sets the row to failed in the transaction of
  # that change, so the worker builds while its export is already failed.
  # The rollback of the sandbox transaction removes the trigger.
  defp sweep_after_running! do
    Repo.query!("""
    CREATE FUNCTION espalier_test_sweep() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      UPDATE exports SET status = 'failed', error = '#{@interrupted}' WHERE id = NEW.id;
      RETURN NULL;
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER espalier_test_sweep AFTER UPDATE ON exports
    FOR EACH ROW WHEN (NEW.status = 'running') EXECUTE FUNCTION espalier_test_sweep()
    """)
  end

  # Plays a change to done that committed although the worker never saw
  # its answer: an AFTER trigger sets the row to done in the transaction of
  # the change to running, while the worker builds on. The rollback of the
  # sandbox transaction removes the trigger.
  defp done_after_running! do
    Repo.query!("""
    CREATE FUNCTION espalier_test_done() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      UPDATE exports SET status = 'done', file_name = NEW.id::text || '.zip' WHERE id = NEW.id;
      RETURN NULL;
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER espalier_test_done AFTER UPDATE ON exports
    FOR EACH ROW WHEN (NEW.status = 'running') EXECUTE FUNCTION espalier_test_done()
    """)
  end

  # Makes every change of an export row to `status` find no row, as the
  # conditional UPDATE does when another session has changed the status
  # first. The rollback of the sandbox transaction removes the trigger.
  defp skip_change_to!(status) do
    Repo.query!("""
    CREATE FUNCTION espalier_test_skip() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RETURN NULL;
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER espalier_test_skip BEFORE UPDATE ON exports
    FOR EACH ROW WHEN (NEW.status = '#{status}') EXECUTE FUNCTION espalier_test_skip()
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
        assert Enum.sort(entries(zip)) == Enum.sort(package_files() ++ schema_files(version))

        assert read_entry!(zip, "LICENSE") == File.read!(Path.join(@player, "LICENSE"))
        assert read_entry!(zip, "NOTICE") == File.read!(Path.join(@player, "NOTICE"))
        assert read_entry!(zip, "index.html") == File.read!(Path.join(@player, "scorm.html"))
        refute "scorm.html" in entries(zip)

        # The media files hold the bytes of the store, and the WebM is
        # stored without compression.
        for {rel, file} <- module1_media() do
          assert read_entry!(zip, rel) == File.read!(file), rel
        end

        [{webm, _file}, {vtt, _vtt_file}] = module1_media()
        sizes = media_entries(zip)
        assert {size, size} = sizes[webm]
        assert {_compressed, 288} = sizes[vtt]
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

        assert Enum.sort(entries -- package_files()) == schema_files(version)
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
               ~w(formats glossary media module policies program schema sources)

      assert content["schema"] == 1
      assert content["policies"] == %{}

      expected = module_content(program, 1)
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

    test "holds the SVG of its figure and no media of module 1", %{scope: scope} do
      program = LearningFixtures.publish_demo!()
      export = export!(scope, program, 2, :scorm12)
      zip = zip_path(export)
      content = content!(export)

      svg = Path.join(PackFixtures.demo_path(), "media/release-checks.svg")
      {sha256, _bytes} = Store.digest(svg)

      assert Map.keys(media_entries(zip)) == ["media/#{sha256}.svg"]
      assert read_entry!(zip, "media/#{sha256}.svg") == File.read!(svg)

      assert %{"media/release-checks.svg" => %{"url" => url, "kind" => "svg"}} =
               content["media"]

      assert url == "media/#{sha256}.svg"
      assert Map.drop(content, ["schema", "policies"]) == module_content(program, 2)
    end
  end

  describe "the media of a module" do
    # A copy of the demo pack whose first lesson of module 1 gains a second
    # video and two figures that name one SVG asset under two paths. The
    # loader needs a file at every referenced path; the mapping of the
    # importer links the paths to the assets.
    defp media_pack! do
      pack = PackFixtures.copy_pack!(PackFixtures.demo_path())
      PackFixtures.write!(pack, "media/second-clip.webm", "a stand-in of a second video")

      File.cp!(
        PackFixtures.path(pack, "media/release-checks.svg"),
        Path.join(pack, "media/checks-copy.svg")
      )

      PackFixtures.write!(
        pack,
        "modules/01-basics/lessons/01-first-lesson.md",
        PackFixtures.read!(pack, "modules/01-basics/lessons/01-first-lesson.md") <>
          """

          :::video{src=media/second-clip.webm title="A second clip" captions="media/assistant-demo-en.vtt:en" provenance=invented}
          :::

          :::figure{src=media/release-checks.svg alt="The release checks." provenance=invented}
          :::

          :::figure{src=media/checks-copy.svg alt="The release checks again." provenance=invented}
          :::
          """
      )

      pack
    end

    defp publish_with!(pack, media) do
      {:ok, %PackImport{status: :validated} = pack_import} =
        Importer.import(pack, nil, media: media)

      {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
      Catalog.get_program_by_slug(pack_import.pack_key)
    end

    # A file in `dir` with `content`, for an asset of the test store.
    defp file!(dir, name, content) do
      path = Path.join(dir, name)
      File.write!(path, content)
      path
    end

    test "two paths of one asset and two videos with one poster give one file each",
         %{scope: scope} do
      dir = tmp_dir!("media")
      demo = MediaFixtures.media_for(PackFixtures.demo_path())

      # One poster that both videos name, as two videos with the same black
      # first frame share one.
      poster = file!(dir, "poster.webp", "RIFF\x04\x00\x00\x00WEBP a stand-in poster")
      {poster_sha256, poster_bytes} = Store.digest(poster)
      File.mkdir_p!(Path.dirname(Store.path(poster_sha256, "webp")))
      File.cp!(poster, Store.path(poster_sha256, "webp"))

      facts = %{
        width: 640,
        height: 360,
        duration_ms: 8_008,
        has_audio: true,
        poster_sha256: poster_sha256,
        poster_bytes: poster_bytes
      }

      first =
        MediaFixtures.stored_asset!(
          Path.join(PackFixtures.demo_path(), "media/assistant-demo.webm"),
          :video,
          "webm",
          facts
        )

      second =
        MediaFixtures.stored_asset!(
          file!(dir, "second.webm", "a stand-in of a second video"),
          :video,
          "webm",
          facts
        )

      media =
        Map.merge(demo, %{
          "media/assistant-demo.webm" => first.id,
          "media/second-clip.webm" => second.id,
          "media/checks-copy.svg" => demo["media/release-checks.svg"]
        })

      program = publish_with!(media_pack!(), media)
      export = export!(scope, program, 1, :scorm2004)
      assert export.status == :done
      zip = zip_path(export)

      svg = Repo.get!(Asset, demo["media/release-checks.svg"])
      vtt = Repo.get!(Asset, demo["media/assistant-demo-en.vtt"])

      expected = [
        "media/#{first.sha256}.webm",
        "media/#{second.sha256}.webm",
        "media/#{poster_sha256}.webp",
        "media/#{svg.sha256}.svg",
        "media/#{vtt.sha256}.vtt"
      ]

      assert Enum.sort(Map.keys(media_entries(zip))) == Enum.sort(expected)
      assert entries(zip) == Enum.uniq(entries(zip))
      assert read_entry!(zip, "media/#{poster_sha256}.webp") == File.read!(poster)
      assert {size, size} = media_entries(zip)["media/#{poster_sha256}.webp"]

      # The manifest lists every media file once.
      files = attributes(manifest!(export), "//*[local-name()='file']/@href")
      assert Enum.filter(files, &String.starts_with?(&1, "media/")) == Enum.sort(expected)

      # content.json resolves both paths of the SVG to one file, and both
      # videos to one poster.
      content = content!(export)
      assert content["media"]["media/release-checks.svg"]["url"] == "media/#{svg.sha256}.svg"
      assert content["media"]["media/checks-copy.svg"]["url"] == "media/#{svg.sha256}.svg"

      for path <- ["media/assistant-demo.webm", "media/second-clip.webm"] do
        assert content["media"][path]["poster_url"] == "media/#{poster_sha256}.webp", path
      end

      assert Map.drop(content, ["schema", "policies"]) == module_content(program, 1)
    end

    test "media above export_max_mb fail the export with a text that names the limit",
         %{scope: scope} do
      put_env(:media, Keyword.put(Application.fetch_env!(:espalier, :media), :export_max_mb, 1))
      dir = tmp_dir!("media")

      # A delivery file of 1.1 MB in the place of the demo video.
      large =
        MediaFixtures.stored_asset!(
          file!(dir, "large.webm", :binary.copy("v", 1_100_000)),
          :video,
          "webm",
          %{width: 640, height: 360, duration_ms: 8_008, has_audio: true}
        )

      pack = PackFixtures.copy_pack!(PackFixtures.demo_path())

      media =
        pack
        |> MediaFixtures.media_for()
        |> Map.put("media/assistant-demo.webm", large.id)

      program = publish_with!(pack, media)
      export = request!(scope, program, 1, :scorm12)

      capture_log(fn ->
        assert {:error, message} = perform_job(ExportWorker, %{export_id: export.id})
        assert message =~ "exceed 1 MB"
      end)

      failed = Repo.get!(Export, export.id)
      assert failed.status == :failed

      assert failed.error ==
               "The media of this module exceed 1 MB; link large videos with an external URL."

      assert failed.file_name == nil
      assert File.ls!(Interop.export_dir()) == []

      # Module 2 holds one small SVG and stays within the limit.
      assert export!(scope, program, 2, :scorm12).status == :done
    end

    # The demo pack with a video of its own in place of the demo video, so
    # that a test may remove or block its store file.
    defp own_video!(dir) do
      video =
        MediaFixtures.stored_asset!(
          file!(dir, "clip.webm", "a stand-in of a video #{System.unique_integer([:positive])}"),
          :video,
          "webm",
          %{width: 640, height: 360, duration_ms: 8_008, has_audio: true}
        )

      pack = PackFixtures.copy_pack!(PackFixtures.demo_path())
      media = pack |> MediaFixtures.media_for() |> Map.put("media/assistant-demo.webm", video.id)
      {publish_with!(pack, media), video}
    end

    # Runs the job of `export`, which fails, and returns the failed export
    # and the log.
    defp failed_export!(export) do
      log =
        capture_log(fn ->
          assert {:error, _message} = perform_job(ExportWorker, %{export_id: export.id})
        end)

      failed = Repo.get!(Export, export.id)
      assert failed.status == :failed
      assert failed.file_name == nil
      assert File.ls!(Interop.export_dir()) == []
      {failed, log}
    end

    test "a store file that is gone fails the export as a missing media file, and the log names it",
         %{scope: scope} do
      {program, video} = own_video!(tmp_dir!("media"))
      File.rm!(Store.path(video.sha256, "webm"))
      export = request!(scope, program, 1, :scorm12)

      {failed, log} = failed_export!(export)

      assert failed.error == "A media file of the module is missing."

      assert log =~
               "export media file not staged: export #{export.id}, media/#{video.sha256}.webm: " <>
                 "enoent (no such file or directory)"
    end

    test "a media file that cannot be written fails the export with the generic text, and the log names the reason",
         %{scope: scope} do
      {program, _video} = own_video!(tmp_dir!("media"))
      export = request!(scope, program, 1, :scorm2004)

      # The media directory of the build exists without write permission, so
      # neither a link nor a copy can place a file there.
      media_dir = Path.join(Interop.export_paths(export.id).build, "media")
      File.mkdir_p!(media_dir)
      File.chmod!(media_dir, 0o555)
      on_exit(fn -> File.chmod(media_dir, 0o755) end)

      {failed, log} = failed_export!(export)

      assert failed.error == "The package could not be built; the server log names the cause."

      assert log =~
               ~r/export media file not staged: export #{export.id}, media\/[0-9a-f]{64}\.(webm|vtt): eacces \(permission denied\)/
    end

    test "a full export volume fails the staging with a text that names it, and the log names the reason" do
      for reason <- [:enospc, :edquot] do
        log =
          capture_log(fn ->
            assert ExportWorker.staging_error("an-export", "media/clip.webm", reason) ==
                     {:error,
                      "The volume of EXPORT_DIR is full; free space there and request the export again."}
          end)

        assert log =~
                 "export media file not staged: export an-export, media/clip.webm: #{reason} ("
      end
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
      expected = module_content(program, 1)
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

    test "keeps the package of an export that is done although its job failed",
         %{scope: scope, program: program} do
      player = tmp_dir!("player")
      File.cp_r!(@player, player)
      File.rm!(Path.join(player, "NOTICE"))
      put_env(:scorm_player_dir, player)
      export = request!(scope, program, 1, :scorm12)
      zip = Interop.export_paths(export.id).zip
      File.mkdir_p!(Path.dirname(zip))
      File.write!(zip, "package")
      done_after_running!()

      log = capture_log(fn -> assert :ok = perform_job(ExportWorker, %{export_id: export.id}) end)

      assert log =~ "export #{export.id} is done, package kept"
      assert Repo.get!(Export, export.id).status == :done
      assert File.read!(zip) == "package"
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

  describe "a race with the sweep of interrupted exports" do
    setup do
      %{program: LearningFixtures.publish_demo!()}
    end

    test "a build whose export was failed meanwhile sets no status and leaves no zip",
         %{scope: scope, program: program} do
      export = request!(scope, program, 1, :scorm12)
      sweep_after_running!()

      log =
        capture_log(fn ->
          assert {:cancel, reason} = perform_job(ExportWorker, %{export_id: export.id})
          assert reason =~ "no longer running"
        end)

      assert log =~
               "export status not set to done: export #{export.id} is no longer running, " <>
                 "package removed"

      failed = Repo.get!(Export, export.id)
      assert failed.status == :failed
      assert failed.error == @interrupted
      assert failed.file_name == nil
      assert File.ls!(Interop.export_dir()) == []
    end

    test "a failing build whose export was failed meanwhile keeps the text of the sweep",
         %{scope: scope, program: program} do
      player = tmp_dir!("player")
      File.cp_r!(@player, player)
      File.rm!(Path.join(player, "NOTICE"))
      put_env(:scorm_player_dir, player)
      export = request!(scope, program, 1, :scorm12)
      sweep_after_running!()

      log =
        capture_log(fn ->
          assert {:error, message} = perform_job(ExportWorker, %{export_id: export.id})
          assert message =~ "NOTICE"
        end)

      assert log =~
               "export status not set to failed: export #{export.id} is no longer queued or running"

      assert %Export{status: :failed, error: @interrupted} = Repo.get!(Export, export.id)
      assert File.ls!(Interop.export_dir()) == []
    end

    test "a job whose change to running finds the export no longer queued is cancelled",
         %{scope: scope, program: program} do
      export = request!(scope, program, 1, :scorm12)
      # Another file of the export, which the cancelled job must not touch.
      zip = Path.join(Interop.export_dir(), "#{export.id}.zip")
      File.write!(zip, "zip")
      skip_change_to!("running")

      assert {:cancel, reason} = perform_job(ExportWorker, %{export_id: export.id})
      assert reason =~ "no longer queued"

      assert Repo.get!(Export, export.id).status == :queued
      assert File.ls!(Interop.export_dir()) == ["#{export.id}.zip"]
      assert File.read!(zip) == "zip"
    end
  end

  test "deletes the done exports beyond max_packages after an export is done",
       %{scope: scope} do
    put_env(:export_retention, max_age_days: 7, max_packages: 1)
    program = LearningFixtures.publish_demo!()
    first = export!(scope, program, 1, :scorm12)
    assert File.exists?(zip_path(first))

    second = export!(scope, program, 2, :scorm12)

    assert Repo.get(Export, first.id) == nil
    assert Repo.get!(Export, second.id).status == :done
    assert File.ls!(Interop.export_dir()) == ["#{second.id}.zip"]
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
