defmodule Espalier.Workbench.ImportTest do
  @moduledoc """
  Task 0016a, steps 7, 10 and 14 (bullet "Import from a draft"):
  `Espalier.Workbench.import_draft/3` imports the files of a draft through
  `Espalier.Catalog.import_pack/3` and gives the import that an upload of a
  zip of the same files gives, in status, report and payload; its audit
  event `pack.imported` names the draft. A stale `lock_version` imports
  nothing, and the draft stays after an import.
  """
  # The import runs in a slot of the CheckLimiter, one server per node,
  # hence async: false.
  use Espalier.DataCase, async: false

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  import Espalier.PackFixtures,
    only: [copy_pack!: 1, demo_path: 0, line_of!: 4, read!: 2, write!: 3]

  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog
  alias Espalier.Catalog.Pack.Archive
  alias Espalier.Catalog.PackImport
  alias Espalier.Workbench
  alias Espalier.Workbench.{PackDraft, PackDraftFile}
  alias Espalier.ZipFixtures
  alias EspalierWeb.PackMultipart

  @key "ai-assistant-basics-demo"
  @items1 "modules/01-basics/items.yaml"

  setup do
    user = user_with_role_fixture(:author)
    %{scope: %{Scope.for_user(user) | roles: [:learner, :author]}, user: user}
  end

  describe "import_draft/3" do
    @tag :tmp_dir
    test "gives the status, the report and the payload of an upload of the same files", %{
      scope: scope,
      user: user,
      tmp_dir: tmp_dir
    } do
      upload =
        ZipFixtures.write!(Path.join(tmp_dir, "demo.zip"), ZipFixtures.zip_dir!(demo_path()))

      draft = draft!(scope, upload)

      assert {:ok, %PackImport{} = from_draft} =
               Workbench.import_draft(scope, draft.id, draft.lock_version)

      # The upload of POST /api/admin/packs: the archive checks, the pack
      # root and Catalog.import_pack/2 on the extracted directory.
      assert {:ok, %PackImport{} = from_upload} =
               Archive.with_extracted(upload, PackMultipart.max_bytes(), fn dir ->
                 Catalog.import_pack(scope, Archive.pack_root(dir))
               end)

      draft_import = Repo.get!(PackImport, from_draft.id)
      upload_import = Repo.get!(PackImport, from_upload.id)

      assert draft_import.status == :validated
      assert %{"key" => @key} = draft_import.payload
      assert draft_import.status == upload_import.status
      assert draft_import.report == upload_import.report
      assert draft_import.payload == upload_import.payload

      assert {draft_import.pack_key, draft_import.pack_version} ==
               {upload_import.pack_key, upload_import.pack_version}

      assert draft_import.imported_by_id == user.id

      event = imported_event!(draft_import.id)
      assert event.actor_id == user.id
      assert event.subject_type == imported_event!(upload_import.id).subject_type

      assert event.details == %{
               "pack_key" => @key,
               "status" => "validated",
               "pack_draft_id" => draft.id
             }

      assert imported_event!(upload_import.id).details == %{
               "pack_key" => @key,
               "status" => "validated"
             }
    end

    @tag :tmp_dir
    test "leaves the draft, which imports again", %{scope: scope, tmp_dir: tmp_dir} do
      draft = draft!(scope, zip!(tmp_dir, demo_path()))
      contents = contents(draft)

      assert {:ok, %PackImport{status: :validated} = first} =
               Workbench.import_draft(scope, draft.id, draft.lock_version)

      assert {:ok, stayed} = Workbench.get_draft(scope, draft.id)
      assert stayed.lock_version == draft.lock_version
      assert stayed.title == draft.title
      assert contents(stayed) == contents
      assert Repo.aggregate(PackDraft, :count) == 1

      assert {:ok, %PackImport{status: :validated} = second} =
               Workbench.import_draft(scope, draft.id, draft.lock_version)

      assert second.id != first.id
      assert Repo.get!(PackImport, second.id).payload == Repo.get!(PackImport, first.id).payload
    end

    @tag :tmp_dir
    test "answers stale_draft for another lock_version and creates no import", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      draft = draft!(scope, zip!(tmp_dir, demo_path()))
      file = Enum.find(draft.files, &(&1.path == "pack.yaml"))
      content = Repo.get!(PackDraftFile, file.id).content

      assert {:ok, %PackDraft{lock_version: 2}} =
               Workbench.update_file(scope, draft.id, file.id, content <> "\n", 1)

      imports = Repo.aggregate(PackImport, :count)

      assert Workbench.import_draft(scope, draft.id, 1) == {:error, {:stale_draft, 2}}
      assert Workbench.import_draft(scope, draft.id, 3) == {:error, {:stale_draft, 2}}
      assert Repo.aggregate(PackImport, :count) == imports
      assert imported_events() == []

      assert {:ok, %PackImport{status: :validated}} = Workbench.import_draft(scope, draft.id, 2)
    end

    @tag :tmp_dir
    test "of a draft with an error gives a failed import with the report of the files", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!("minimal")
      # The exam item m1-exam-2 without objectives: a check 2 error in strict mode.
      number = line_of!(pack, @items1, "objectives:", after: "key: m1-exam-2")
      lines = pack |> read!(@items1) |> String.split("\n") |> List.delete_at(number - 1)
      write!(pack, @items1, Enum.join(lines, "\n"))
      draft = draft!(scope, zip!(tmp_dir, pack))

      assert {:ok, %PackImport{} = failed} =
               Workbench.import_draft(scope, draft.id, draft.lock_version)

      stored = Repo.get!(PackImport, failed.id)
      assert stored.status == :failed
      assert stored.payload == nil
      assert {stored.pack_key, stored.pack_version} == {"minimal-pack", "0.1.0"}

      assert %{"errors" => [%{"check" => 2, "key" => "m1-exam-2", "file" => @items1}]} =
               stored.report

      assert {:ok, direct} = Catalog.import_pack(scope, pack)
      assert stored.report == Repo.get!(PackImport, direct.id).report

      assert imported_event!(stored.id).details == %{
               "pack_key" => "minimal-pack",
               "status" => "failed",
               "pack_draft_id" => draft.id
             }

      assert {:ok, _draft} = Workbench.get_draft(scope, draft.id)
    end
  end

  ## Helpers

  defp zip!(tmp_dir, pack) do
    name = "pack-#{System.unique_integer([:positive])}.zip"
    ZipFixtures.write!(Path.join(tmp_dir, name), ZipFixtures.zip_dir!(pack))
  end

  defp draft!(scope, upload) do
    assert {:ok, %PackDraft{} = draft, %{paths: [], omitted: 0}} =
             Workbench.create_from_upload(scope, upload, "pack.zip", PackMultipart.max_bytes())

    draft
  end

  defp contents(%PackDraft{id: id}) do
    Repo.all(
      from f in PackDraftFile,
        where: f.pack_draft_id == ^id,
        order_by: f.path,
        select: {f.path, f.content}
    )
  end

  defp imported_events do
    Repo.all(from e in AuditEvent, where: e.action == "pack.imported")
  end

  defp imported_event!(import_id) do
    Repo.one!(
      from e in AuditEvent, where: e.action == "pack.imported" and e.subject_id == ^import_id
    )
  end
end
