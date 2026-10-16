defmodule Espalier.Workbench.CheckTest do
  @moduledoc """
  Task 0016a, steps 6 and 14 (bullet "Check"; ASVS 5.3.2 and 15.2.2):
  `Espalier.Workbench.check_draft/3` runs the loader and the validator of
  task 0008 on the files of a draft and reports the lines that
  `mix espalier.validate` prints for the same files, carries the payload
  whose alignment matrix the check view renders, applies an overlay for one
  check only, stores nothing and leaves no directory behind.
  `Espalier.Workbench.DraftDir.with_dir/2` removes its directory in every
  outcome and writes nothing outside it, and
  `Espalier.Workbench.CheckLimiter` answers `checks_busy` at once while
  every slot is taken. A download builds its zip in a slot of
  `CheckLimiter` and sends it in a slot of
  `Espalier.Workbench.DownloadLimiter` (task 0018, step 16): a check and an
  import run while two transfers are in progress, a third download and a
  second download of the same author answer `checks_busy` without a zip,
  and the staging directory goes before the slot of the download is freed,
  also when the transfer raises.

  Each test points `TMPDIR` at its own `tmp_dir`, so that the directories
  that a check leaves behind are the ones of this test only, also while
  other test runs on the same machine check drafts.
  """
  # The tests change TMPDIR and the setting :pack_drafts, and the
  # CheckLimiter is one server per node, hence async: false.
  use Espalier.DataCase, async: false

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  import Espalier.PackFixtures,
    only: [
      copy_pack!: 1,
      demo_path: 0,
      line_of!: 3,
      line_of!: 4,
      read!: 2,
      replace!: 4,
      write!: 3
    ]

  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.{Alignment, PackImport}
  alias Espalier.Catalog.Pack.{Loader, Report, Validator}
  alias Espalier.Workbench
  alias Espalier.Workbench.{CheckLimiter, DownloadLimiter, DraftDir, PackDraft, PackDraftFile}
  alias Espalier.ZipFixtures
  alias EspalierWeb.Admin.PackJSON
  alias EspalierWeb.PackMultipart

  @moduletag :tmp_dir

  @items1 "modules/01-basics/items.yaml"
  @objectives2 "modules/02-checking/objectives.yaml"
  @backdated ~U[2026-01-01 00:00:00Z]

  setup %{tmp_dir: tmp_dir} do
    previous = System.get_env("TMPDIR")
    System.put_env("TMPDIR", tmp_dir)
    on_exit(fn -> restore_env("TMPDIR", previous) end)

    user = user_with_role_fixture(:author)
    %{scope: %{Scope.for_user(user) | roles: [:learner, :author]}, user: user}
  end

  describe "the report of a check" do
    test "equals the lines of mix espalier.validate for the demo pack, which has none", %{
      scope: scope
    } do
      draft = draft!(scope, demo_path())

      # The WebM and the SVG are media entries and the captions a text file
      # (task 0018, step 16); the check writes an empty file at the path of
      # each entry, so the loader and the validator find every reference.
      assert Enum.map(draft.media, & &1.path) == [
               "media/assistant-demo.webm",
               "media/release-checks.svg"
             ]

      assert "media/assistant-demo-en.vtt" in Enum.map(draft.files, & &1.path)
      refute Enum.any?(draft.files, &(&1.path in Enum.map(draft.media, fn m -> m.path end)))

      assert {:ok, check} = Workbench.check_draft(scope, draft.id, nil)
      assert validate_lines(demo_path()) == []
      assert Report.report_lines(check.report) == validate_lines(demo_path())
      assert check.report == %{"errors" => [], "warnings" => []}
      assert check.lock_version == 1
      assert %{"key" => "ai-assistant-basics-demo", "alignment" => "strict"} = check.payload
      assert draft_dirs() == []
    end

    test "names a media reference without a media entry at the line of its block", %{
      scope: scope
    } do
      draft = draft!(scope, demo_path())
      svg = Enum.find(draft.media, &(&1.path == "media/release-checks.svg"))
      {:ok, draft} = Workbench.delete_media(scope, draft.id, svg.id, draft.lock_version)

      lesson = "modules/02-checking/lessons/02-second-lesson.md"
      line = line_of!(demo_path(), lesson, ":::figure")

      assert {:ok, check} = Workbench.check_draft(scope, draft.id, nil)

      assert [%{"file" => ^lesson, "line" => ^line, "message" => message}] =
               check.report["errors"]

      assert message =~ "media/release-checks.svg"
      assert check.payload == nil
      assert draft_dirs() == []
    end

    test "adds the host check of the installation to the report", %{scope: scope} do
      pack = copy_pack!(demo_path())
      lesson = "modules/02-checking/lessons/02-second-lesson.md"

      write!(
        pack,
        lesson,
        read!(pack, lesson) <>
          """

          :::video{src=https://cdn.example.org/clips/intro.webm title="An external clip" provenance=invented}
          The transcript of the external clip.
          :::
          """
      )

      draft = draft!(scope, pack)
      line = line_of!(pack, lesson, "cdn.example.org")

      assert {:ok, check} = Workbench.check_draft(scope, draft.id, nil)

      assert check.report["errors"] == [
               %{
                 "file" => lesson,
                 "line" => line,
                 "message" => "host cdn.example.org is not in MEDIA_EXTERNAL_HOSTS"
               }
             ]

      assert check.payload == nil
    end

    test "equals the loader errors of a pack with a YAML syntax error, without a payload", %{
      scope: scope
    } do
      pack = copy_pack!("minimal")
      replace!(pack, "formats.yaml", "phases: [anchor]", "phases: [anchor")
      draft = draft!(scope, pack)

      assert {:ok, check} = Workbench.check_draft(scope, draft.id, nil)
      assert {:error, [_ | _] = loader_errors} = Loader.load(pack)
      assert Report.report_lines(check.report) == Report.lines(loader_errors, [])
      assert Report.report_lines(check.report) == validate_lines(pack)

      assert ["formats.yaml:" <> rest] = Report.report_lines(check.report)
      assert rest =~ "YAML syntax error: "
      assert check.report["warnings"] == []
      assert check.payload == nil
      assert draft_dirs() == []
    end

    test "equals the validator errors of a pack with an unknown objective, without a payload", %{
      scope: scope
    } do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "objectives: [m1-method-build-prompt]",
        "objectives: [m1-method-missing]"
      )

      draft = draft!(scope, pack)

      assert {:ok, check} = Workbench.check_draft(scope, draft.id, nil)
      assert Report.report_lines(check.report) == validate_lines(pack)

      assert Report.report_lines(check.report) == [
               "#{@items1}:#{line_of!(pack, @items1, "[m1-method-missing]")}: " <>
                 "unknown objective `m1-method-missing` in `objectives`"
             ]

      assert check.payload == nil
    end

    test "carries the matrix and the alignment error of a pack in strict mode", %{scope: scope} do
      pack = copy_pack!("minimal")
      orphan_exam_item!(pack)
      draft = draft!(scope, pack)

      assert {:ok, check} = Workbench.check_draft(scope, draft.id, nil)
      assert Report.report_lines(check.report) == validate_lines(pack)
      item_line = line_of!(pack, @items1, "key: m1-exam-2")
      assert [line] = Report.report_lines(check.report)
      assert String.starts_with?(line, "#{@items1}:#{item_line}: ")
      assert check.report["warnings"] == []

      # The checks before the alignment pass, so the payload is there.
      assert %{"alignment" => "strict", "modules" => [_, _] = modules} = check.payload
      matrix = Alignment.matrix(check.payload)
      assert length(matrix) == 12 * length(modules)
      assert Enum.frequencies_by(matrix, & &1.module) == %{1 => 12, 2 => 12}

      assert %{mode: "strict", matrix: ^matrix, errors: [error], warnings: []} =
               PackJSON.alignment(check.payload, check.report)

      assert error == %{
               "check" => 2,
               "module" => 1,
               "key" => "m1-exam-2",
               "file" => @items1,
               "line" => item_line,
               "message" => hd(check.report["errors"])["message"]
             }
    end

    test "equals the warning line of a pack with a check 4 finding", %{scope: scope} do
      pack = copy_pack!("minimal")
      replace!(pack, @objectives2, "depth: apply", "depth: know")
      draft = draft!(scope, pack)

      assert {:ok, check} = Workbench.check_draft(scope, draft.id, nil)
      assert Report.report_lines(check.report) == validate_lines(pack)
      line = line_of!(pack, @objectives2, "key: m2-method-release-check")
      assert [warning] = Report.report_lines(check.report)
      assert String.starts_with?(warning, "#{@objectives2}:#{line}: warning: ")
      assert check.report["errors"] == []

      assert %{errors: [], warnings: [%{"check" => 4, "key" => "m2-method-release-check"}]} =
               PackJSON.alignment(check.payload, check.report)
    end
  end

  describe "a check stores nothing" do
    test "it changes no row and answers the lock_version that it checked", %{scope: scope} do
      draft = draft!(scope, demo_path())
      file = file!(draft, "modules/02-checking/objectives.yaml")
      content = Repo.get!(PackDraftFile, file.id).content

      assert {:ok, %PackDraft{lock_version: 2}} =
               Workbench.update_file(scope, draft.id, file.id, content <> "\n", 1)

      counts = row_counts()
      assert {:ok, check} = Workbench.check_draft(scope, draft.id, nil)
      assert check.lock_version == 2
      assert row_counts() == counts

      overlay = %{file_id: file.id, content: content}
      assert {:ok, %{lock_version: 2}} = Workbench.check_draft(scope, draft.id, overlay)
      assert row_counts() == counts
      assert draft_dirs() == []
    end

    test "an overlay changes the report and leaves the stored file and the draft unchanged", %{
      scope: scope
    } do
      draft = draft!(scope, copy_pack!("minimal"))
      file = file!(draft, @objectives2)
      backdate!(draft)
      stored_draft = Repo.get!(PackDraft, draft.id)
      stored_file = Repo.get!(PackDraftFile, file.id)

      content = String.replace(stored_file.content, "depth: apply", "depth: know")
      assert content != stored_file.content

      assert {:ok, plain} = Workbench.check_draft(scope, draft.id, nil)
      assert plain.report == %{"errors" => [], "warnings" => []}

      assert {:ok, overlaid} =
               Workbench.check_draft(scope, draft.id, %{file_id: file.id, content: content})

      # The report of the overlay is the report of a pack with that content.
      changed = copy_pack!("minimal")
      write!(changed, @objectives2, content)
      assert [_warning] = validate_lines(changed)
      assert Report.report_lines(overlaid.report) == validate_lines(changed)
      assert overlaid.lock_version == stored_draft.lock_version

      assert Repo.get!(PackDraftFile, file.id) == stored_file
      assert Repo.get!(PackDraft, draft.id) == stored_draft
      assert stored_draft.updated_at == @backdated

      assert {:ok, again} = Workbench.check_draft(scope, draft.id, nil)
      assert again.report == plain.report
      assert draft_dirs() == []
    end

    test "an overlay with a file of another draft answers not_found", %{scope: scope} do
      draft = draft!(scope, copy_pack!("minimal"))
      other = draft!(scope, copy_pack!("minimal"))
      other_file = file!(other, "pack.yaml")

      assert Workbench.check_draft(scope, draft.id, %{file_id: other_file.id, content: "x"}) ==
               {:error, :not_found}

      assert Workbench.check_draft(scope, draft.id, %{file_id: "not-a-uuid", content: "x"}) ==
               {:error, :not_found}
    end

    test "an overlay with U+0000 or above max_file_bytes/0 answers its content error", %{
      scope: scope
    } do
      draft = draft!(scope, copy_pack!("minimal"))
      file = file!(draft, "pack.yaml")

      assert Workbench.check_draft(scope, draft.id, %{file_id: file.id, content: "key: a\0b\n"}) ==
               {:error, :nul_character}

      too_large = String.duplicate("a", Workbench.max_file_bytes() + 1)

      assert Workbench.check_draft(scope, draft.id, %{file_id: file.id, content: too_large}) ==
               {:error, :file_too_large}

      assert draft_dirs() == []
    end
  end

  describe "DraftDir.with_dir/2" do
    test "writes the files below a new directory and removes it afterwards" do
      files = [{"pack.yaml", "schema: 1\n"}, {"modules/01-a/lessons/01-b.md", "text\n"}]

      dir =
        DraftDir.with_dir(files, fn dir ->
          assert Path.dirname(dir) == System.tmp_dir!()
          assert Path.basename(dir) =~ ~r/\Aespalier-draft-[A-Za-z0-9_-]{16}\z/
          assert File.read!(Path.join(dir, "pack.yaml")) == "schema: 1\n"
          assert File.read!(Path.join(dir, "modules/01-a/lessons/01-b.md")) == "text\n"
          dir
        end)

      refute File.exists?(dir)
      assert draft_dirs() == []
    end

    test "removes its directory when its function raises" do
      test = self()

      assert_raise RuntimeError, "the check failed", fn ->
        DraftDir.with_dir([{"pack.yaml", "schema: 1\n"}], fn dir ->
          send(test, {:dir, dir})
          raise "the check failed"
        end)
      end

      assert_received {:dir, dir}
      refute File.exists?(dir)
      assert draft_dirs() == []
    end

    test "answers invalid_path for a bad path and writes nothing outside its directory", %{
      tmp_dir: tmp_dir
    } do
      for path <- [
            "../escape.yaml",
            "../../escape.yaml",
            "modules/01-a/../../escape.yaml",
            "modules\\01-a\\module.yaml",
            "README.md"
          ] do
        files = [{"pack.yaml", "schema: 1\n"}, {path, "escaped\n"}]

        assert DraftDir.with_dir(files, fn _dir -> flunk("the function ran for #{path}") end) ==
                 {:error, :invalid_path}

        assert File.ls!(tmp_dir) == []
        refute File.exists?(Path.join(Path.dirname(tmp_dir), "escape.yaml"))
      end
    end
  end

  describe "the limit of parallel checks" do
    setup do
      previous = Application.fetch_env(:espalier, :pack_drafts)
      Application.put_env(:espalier, :pack_drafts, max_drafts: 50, max_parallel_checks: 1)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:espalier, :pack_drafts, value)
          :error -> Application.delete_env(:espalier, :pack_drafts)
        end
      end)
    end

    test "a check and an import answer checks_busy at once while a holder takes the slot", %{
      scope: scope
    } do
      draft = draft!(scope, copy_pack!("minimal"))
      imports = Repo.aggregate(PackImport, :count)
      holder = hold_slot!()

      {micros, answers} =
        :timer.tc(fn ->
          {Workbench.check_draft(scope, draft.id, nil),
           Workbench.import_draft(scope, draft.id, draft.lock_version)}
        end)

      assert answers == {{:error, :checks_busy}, {:error, :checks_busy}}
      # Neither waited for the slot: the holder holds it still, and both
      # answered in far less than the budget of the loader.
      assert Process.alive?(holder)
      assert micros < 2_000_000
      assert Repo.aggregate(PackImport, :count) == imports

      release!(holder)
      assert {:ok, check} = Workbench.check_draft(scope, draft.id, nil)
      assert check.report == %{"errors" => [], "warnings" => []}
      assert draft_dirs() == []
    end

    test "a download answers checks_busy while a holder takes the slot, and a stale import needs no slot",
         %{scope: scope, user: user} do
      draft = draft!(scope, copy_pack!("minimal"))
      holder = hold_slot!()

      # The download takes its slot of the downloads, finds no slot for the
      # build, builds nothing and frees its slot of the downloads.
      assert Workbench.download(scope, draft.id, &no_zip/1) == {:error, :checks_busy}
      assert DownloadLimiter.run(user.id, fn -> :free end) == :free

      # The version check runs before the slot, so a stale import answers
      # stale_draft also while every slot is taken.
      assert Workbench.import_draft(scope, draft.id, draft.lock_version + 1) ==
               {:error, {:stale_draft, draft.lock_version}}

      assert Workbench.import_draft(scope, Ecto.UUID.generate(), 1) == {:error, :not_found}

      release!(holder)

      assert {:ok, [_ | _]} =
               Workbench.download(scope, draft.id, fn %{path: zip} ->
                 :zip.unzip(String.to_charlist(zip), [:memory])
               end)
    end

    test "two transfers hold no slot of the checks, and a third download answers checks_busy",
         %{scope: scope} do
      draft = draft!(scope, copy_pack!("minimal"))
      transfers = for scope <- [scope, author_scope!()], do: start_transfer!(scope, draft)

      # Both zips lie on disk while they are sent, and the one slot of the
      # checks is free: a check and an import run.
      for {_task, _pid, zip, _dir} <- transfers, do: assert(File.regular?(zip))
      assert {:ok, %{report: %{"errors" => []}}} = Workbench.check_draft(scope, draft.id, nil)

      assert {:ok, %PackImport{status: :validated}} =
               Workbench.import_draft(scope, draft.id, draft.lock_version)

      # Both slots of the downloads are taken, so a third author builds no
      # zip.
      assert Workbench.download(author_scope!(), draft.id, &no_zip/1) == {:error, :checks_busy}

      for {task, pid, _zip, dir} <- transfers do
        send(pid, :sent)
        assert Task.await(task, 5_000) == {:ok, dir}
        refute File.exists?(dir)
      end

      assert [_ | _] = download!(author_scope!(), draft.id)
    end

    test "a user runs one download at a time", %{scope: scope} do
      draft = draft!(scope, copy_pack!("minimal"))
      {task, pid, _zip, dir} = start_transfer!(scope, draft)

      # One of the two slots of the downloads is free, yet the second
      # download of the same author answers at once and builds nothing,
      # while another author downloads.
      assert Workbench.download(scope, draft.id, &no_zip/1) == {:error, :checks_busy}
      assert [_ | _] = download!(author_scope!(), draft.id)

      send(pid, :sent)
      assert Task.await(task, 5_000) == {:ok, dir}
      assert [_ | _] = download!(scope, draft.id)
    end

    test "a transfer that raises removes the staging directory and frees both slots",
         %{scope: scope, user: user} do
      draft = draft!(scope, copy_pack!("minimal"))
      test = self()

      assert_raise RuntimeError, "the transfer failed", fn ->
        Workbench.download(scope, draft.id, fn %{dir: dir} ->
          send(test, {:dir, dir})
          raise "the transfer failed"
        end)
      end

      assert_received {:dir, dir}
      refute File.exists?(dir)
      assert DownloadLimiter.run(user.id, fn -> :free end) == :free
      assert CheckLimiter.run(fn -> :free end) == :free
    end

    test "a holder that dies frees its slot", %{scope: scope} do
      draft = draft!(scope, copy_pack!("minimal"))
      holder = hold_slot!()
      assert Workbench.check_draft(scope, draft.id, nil) == {:error, :checks_busy}

      ref = Process.monitor(holder)
      Process.exit(holder, :kill)
      assert_receive {:DOWN, ^ref, :process, ^holder, :killed}
      await_free_slot!()

      assert {:ok, %{report: %{"errors" => []}}} = Workbench.check_draft(scope, draft.id, nil)
    end
  end

  ## Helpers

  # Starts a draft from a zip of the pack directory `pack`.
  defp draft!(scope, pack) do
    upload =
      ZipFixtures.write!(
        Path.join(System.tmp_dir!(), "upload-#{System.unique_integer([:positive])}.zip"),
        ZipFixtures.zip_dir!(pack)
      )

    assert {:ok, %PackDraft{} = draft, _skipped} =
             Workbench.create_from_upload(scope, upload, "pack.zip", PackMultipart.max_bytes())

    File.rm!(upload)
    draft
  end

  defp file!(%PackDraft{files: files}, path) do
    file = Enum.find(files, &(&1.path == path))
    assert file, "the draft holds no file #{path}"
    file
  end

  # The lines that `mix espalier.validate` prints for the pack directory.
  defp validate_lines(pack) do
    {errors, warnings} =
      case Loader.load(pack) do
        {:ok, loaded} -> Validator.validate(loaded)
        {:error, errors} -> {errors, []}
      end

    Report.lines(errors, warnings)
  end

  # Removes the objectives of the exam item m1-exam-2, which the exam
  # m1-exam lists: an alignment error (check 2) in strict mode.
  defp orphan_exam_item!(pack) do
    number = line_of!(pack, @items1, "objectives:", after: "key: m1-exam-2")
    lines = pack |> read!(@items1) |> String.split("\n") |> List.delete_at(number - 1)
    write!(pack, @items1, Enum.join(lines, "\n"))
  end

  # Moves updated_at of the draft and its files to a past second, so that a
  # write in the same second as the creation would show.
  defp backdate!(%PackDraft{id: id}) do
    Repo.update_all(from(d in PackDraft, where: d.id == ^id), set: [updated_at: @backdated])

    Repo.update_all(from(f in PackDraftFile, where: f.pack_draft_id == ^id),
      set: [updated_at: @backdated]
    )
  end

  defp row_counts do
    Map.new([PackDraft, PackDraftFile, PackImport, AuditEvent], fn schema ->
      {schema, Repo.aggregate(schema, :count)}
    end)
  end

  defp draft_dirs, do: Path.wildcard(Path.join(System.tmp_dir!(), "espalier-draft-*"))

  # The function of a download that must not build a zip.
  defp no_zip(_zip), do: flunk("the download built a zip")

  # The entries of the zip of a download.
  defp download!(scope, draft_id) do
    assert {:ok, entries} =
             Workbench.download(scope, draft_id, fn %{path: zip} ->
               :zip.unzip(String.to_charlist(zip), [:memory])
             end)

    entries
  end

  # The scope of another author.
  defp author_scope! do
    user = user_with_role_fixture(:author)
    %{Scope.for_user(user) | roles: [:learner, :author]}
  end

  # Starts a download of `draft` for `scope` in a task whose transfer waits
  # for :sent, as a slow transfer would. Returns the task, the process that
  # waits, the zip and its staging directory.
  defp start_transfer!(scope, draft) do
    test = self()

    task =
      Task.async(fn ->
        Workbench.download(scope, draft.id, fn %{path: zip, dir: dir} ->
          send(test, {:sending, self(), zip, dir})

          receive do
            :sent -> {:ok, dir}
          end
        end)
      end)

    assert_receive {:sending, pid, zip, dir}, 5_000
    {task, pid, zip, dir}
  end

  # A process that takes a slot of the CheckLimiter and holds it until it
  # receives :release. The test supervises it, so that ExUnit stops it, and
  # the limiter frees its slot, also after a failed assertion.
  defp hold_slot! do
    test = self()

    holder =
      start_supervised!(
        {Task,
         fn ->
           CheckLimiter.run(fn ->
             send(test, :holding)

             receive do
               :release -> :ok
             end
           end)
         end},
        id: make_ref()
      )

    assert_receive :holding, 1_000
    holder
  end

  # Ends the holder; it frees its slot before it exits.
  defp release!(holder) do
    ref = Process.monitor(holder)
    send(holder, :release)
    assert_receive {:DOWN, ^ref, :process, ^holder, :normal}, 1_000
  end

  # The server learns of the death of a holder through its own monitor,
  # whose message can arrive after the one of the test.
  defp await_free_slot!(tries \\ 100) do
    case CheckLimiter.run(fn -> :free end) do
      :free ->
        :ok

      {:error, :checks_busy} when tries > 0 ->
        Process.sleep(10)
        await_free_slot!(tries - 1)

      {:error, :checks_busy} ->
        flunk("the slot of the dead holder stays taken")
    end
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
