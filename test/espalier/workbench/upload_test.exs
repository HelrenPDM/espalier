defmodule Espalier.Workbench.UploadTest do
  @moduledoc """
  Task 0016a, steps 5 and 14 (bullet "Starting points", the zip archives;
  ASVS 5.2.2, 5.3.2 and 15.2.2): `Espalier.Workbench.create_from_upload/4`
  reads the pack at the root of an archive or in its one top-level
  directory byte for byte, lists every file outside the pack layout as
  skipped (at most 100 paths and a count), rejects a kept file that is no
  UTF-8 or above 1 MiB, an archive that `Espalier.Catalog.Pack.Archive`
  rejects and an archive without a file of the layout, each with entries
  of the archive report, and takes the title from `pack.yaml`, then from
  the upload file name, then "Untitled draft".
  """
  # Every creation takes the advisory lock of the drafts, which the sandbox
  # transaction of a test holds until the test ends, hence async: false.
  use Espalier.DataCase, async: false

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  import Espalier.PackFixtures,
    only: [
      copy_pack!: 1,
      demo_path: 0,
      fixture_path: 1,
      read!: 2,
      read_yaml!: 2,
      replace!: 4,
      write!: 3
    ]

  alias Espalier.Accounts.Scope
  alias Espalier.Workbench
  alias Espalier.Workbench.{DraftDir, PackDraft, PackDraftFile}
  alias Espalier.ZipFixtures
  alias EspalierWeb.PackMultipart

  @moduletag :tmp_dir

  @lesson "modules/01-basics/lessons/01-intro.md"
  @title_line "title: Minimal pack (test fixture)\n"

  setup do
    user = user_with_role_fixture(:author)
    %{scope: %{Scope.for_user(user) | roles: [:learner, :author]}, user: user}
  end

  describe "an archive with a pack" do
    test "in one top-level directory with a README.md holds the demo files byte for byte", %{
      scope: scope,
      user: user,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!(demo_path())
      write!(pack, "README.md", "# The demo pack\n")
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack, root: "ai-assistant-basics-demo"))

      assert {:ok, %PackDraft{} = draft, skipped} = create(scope, upload, "demo.zip")
      assert skipped == %{paths: ["README.md"], omitted: 0}

      expected = disk_files(demo_path())
      assert Map.has_key?(expected, "modules/02-checking/lessons/02-second-lesson.md")
      assert stored_files(draft) == expected
      assert Enum.map(draft.files, & &1.path) == expected |> Map.keys() |> Enum.sort()

      assert draft.title == read_yaml!(demo_path(), "pack.yaml")["title"]
      assert draft.pack_key == "ai-assistant-basics-demo"
      assert draft.lock_version == 1
      assert draft.created_by_id == user.id
    end

    test "at the root with more than 100 skipped files lists 100 paths and the count", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!("minimal")
      for n <- 1..105, do: write!(pack, "notes/note-#{pad(n)}.txt", "note #{n}\n")
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      assert {:ok, %PackDraft{} = draft, skipped} = create(scope, upload, "minimal.zip")
      assert DraftDir.max_skipped() == 100
      assert skipped == %{paths: for(n <- 1..100, do: "notes/note-#{pad(n)}.txt"), omitted: 5}
      assert stored_files(draft) == disk_files(fixture_path("minimal"))
    end
  end

  describe "a rejected archive" do
    test "with a lesson that is no UTF-8 answers an entry on that file", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!("minimal")
      write!(pack, @lesson, <<"---\ntitle: Intro\nposition: 1\n---\n", 0xFF, 0xFE, "\n">>)
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      assert {:error, [%{"file" => @lesson, "line" => nil, "message" => message}]} =
               create(scope, upload, "pack.zip")

      assert message =~ "UTF-8"
      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "with a lesson above 1 MiB answers an entry on that file", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!("minimal")

      write!(
        pack,
        @lesson,
        read!(pack, @lesson) <> String.duplicate("a", Workbench.max_file_bytes())
      )

      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      assert {:error, [%{"file" => @lesson, "line" => nil, "message" => message}]} =
               create(scope, upload, "pack.zip")

      assert message =~ "1 MiB"
      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "that Archive rejects answers the entries of the archive report", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      archive =
        ZipFixtures.build([
          ZipFixtures.entry("pack.yaml", "schema: 1\n"),
          ZipFixtures.entry("../../etc/passwd", "root::0:0::/:/bin/sh\n")
        ])

      assert create(scope, upload!(tmp_dir, archive), "pack.zip") ==
               {:error,
                [
                  %{
                    "file" => "../../etc/passwd",
                    "line" => nil,
                    "message" => "the name contains a .. component"
                  }
                ]}

      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "without any file of the layout answers one entry on .", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      archive =
        ZipFixtures.build([
          ZipFixtures.entry("README.md", "# Notes\n"),
          ZipFixtures.entry("docs/notes.txt", "notes\n"),
          ZipFixtures.entry("modules/A/module.yaml", "number: 1\n")
        ])

      assert {:error, [%{"file" => ".", "line" => nil, "message" => message}]} =
               create(scope, upload!(tmp_dir, archive), "pack.zip")

      assert is_binary(message)
      assert Repo.aggregate(PackDraft, :count) == 0
    end
  end

  describe "the title of a draft from an archive" do
    test "falls back to the upload file name without directories and .zip", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", @title_line, "")
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      for {filename, title} <- [
            {"C:\\Users\\x\\My pack.zip", "My pack"},
            {"/home/x/packs/Other pack.ZIP", "Other pack"},
            {"no-extension", "no-extension"}
          ] do
        assert {:ok, %PackDraft{} = draft, _skipped} = create(scope, upload, filename)
        assert draft.title == title, "#{filename} gave #{inspect(draft.title)}"
        assert draft.pack_key == "minimal-pack"
      end
    end

    test "falls back to the file name for a title that is empty or no string", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      for replacement <- ["title: \"\"\n", "title: [a, b]\n", "title: 42\n"] do
        pack = copy_pack!("minimal")
        replace!(pack, "pack.yaml", @title_line, replacement)
        upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

        assert {:ok, %PackDraft{title: "My pack"}, _skipped} =
                 create(scope, upload, "uploads/My pack.zip")
      end
    end

    test "is Untitled draft without a title in pack.yaml and without a file name", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", @title_line, "")
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      for filename <- ["", ".zip", "C:\\Users\\x\\"] do
        assert {:ok, %PackDraft{title: "Untitled draft"}, _skipped} =
                 create(scope, upload, filename)
      end
    end

    test "keeps at most 255 code points of a file name with combining marks", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", @title_line, "")
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))
      # Five graphemes of 61 code points each: 305 code points.
      filename = String.duplicate("a" <> String.duplicate("\u0301", 60), 5) <> ".zip"

      assert {:ok, %PackDraft{title: title}, _skipped} = create(scope, upload, filename)
      assert title |> String.codepoints() |> length() == 255
    end

    test "comes from pack.yaml when it holds one", %{scope: scope, tmp_dir: tmp_dir} do
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(copy_pack!("minimal")))

      assert {:ok, %PackDraft{title: "Minimal pack (test fixture)"}, _skipped} =
               create(scope, upload, "My pack.zip")
    end
  end

  ## Helpers

  defp create(scope, upload, filename),
    do: Workbench.create_from_upload(scope, upload, filename, PackMultipart.max_bytes())

  defp upload!(tmp_dir, archive) do
    name = "upload-#{System.unique_integer([:positive])}.zip"
    ZipFixtures.write!(Path.join(tmp_dir, name), archive)
  end

  # Every regular file below `dir` as relative path => content.
  defp disk_files(dir) do
    for path <- Path.wildcard(Path.join(dir, "**"), match_dot: true),
        File.regular?(path),
        into: %{},
        do: {Path.relative_to(path, dir), File.read!(path)}
  end

  defp stored_files(%PackDraft{id: id}) do
    Repo.all(from f in PackDraftFile, where: f.pack_draft_id == ^id, select: {f.path, f.content})
    |> Map.new()
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(3, "0")
end
