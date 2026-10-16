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

  Task 0018 (step 16): the captions below `media/` stay text files, every
  other media file becomes a queued asset of origin `pack` and a media
  entry at its delivery path, the opening lines of the directives follow
  the new paths, and an ingest error or two files with one delivery path
  reject the archive. A media file that equals the delivery file of an
  asset that the program of the pack key uses attaches that asset, also
  when an older asset shares the delivery file, and sets the time of its
  last change again.
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
  alias Espalier.Catalog.Pack.{Diff, Importer, Publisher}
  alias Espalier.Catalog.PackImport
  alias Espalier.Media.{Asset, ProcessWorker}
  alias Espalier.{MediaFixtures, Workbench, ZipFixtures}
  alias Espalier.Workbench.{DraftDir, PackDraft, PackDraftFile}
  alias EspalierWeb.PackMultipart

  @moduletag :tmp_dir

  @lesson "modules/01-basics/lessons/01-intro.md"
  @demo_media ["media/assistant-demo.webm", "media/release-checks.svg"]
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

      # The captions stay a text file; the WebM and the SVG become media
      # entries of queued pack assets at their delivery paths (task 0018).
      expected = Map.drop(disk_files(demo_path()), @demo_media)
      assert Map.has_key?(expected, "modules/02-checking/lessons/02-second-lesson.md")
      assert Map.has_key?(expected, "media/assistant-demo-en.vtt")
      assert stored_files(draft) == expected
      assert Enum.map(draft.files, & &1.path) == expected |> Map.keys() |> Enum.sort()

      assert Enum.map(draft.media, & &1.path) == @demo_media

      for %{path: path, media_asset: asset} <- draft.media do
        assert %Asset{status: :queued, origin: :pack, created_by_id: created_by} = asset
        assert created_by == user.id
        assert asset.source_name == Path.basename(path)
        assert asset.incoming_bytes == byte_size(read!(demo_path(), path))
      end

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

  describe "the media of an archive (task 0018, step 16)" do
    test "a PNG becomes a media entry at its WebP path, and the opening lines follow", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!("minimal")
      ffmpeg_image!(Path.join(pack, "media/photos/photo.png"), "png", "image2pipe")
      write!(pack, "media/Notes.txt", "not a media path\n")

      write!(
        pack,
        @lesson,
        read!(pack, @lesson) <>
          """

          :::figure{src=media/photos/photo.png alt="A test pattern." provenance=invented}
          The file media/photos/photo.png shows a test pattern.
          :::
          """
      )

      original = read!(pack, @lesson)
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      assert {:ok, %PackDraft{} = draft, skipped} = create(scope, upload, "minimal.zip")

      # The media file is no skipped file; a file below media/ that fails the
      # path rules is.
      assert skipped == %{paths: ["media/Notes.txt"], omitted: 0}

      assert [%{path: "media/photos/photo.webp", media_asset: asset}] = draft.media
      assert %Asset{kind: :image, status: :queued, origin: :pack} = asset
      assert asset.source_name == "photo.png"

      # Only the opening line of the directive changes; the body keeps its
      # text.
      assert stored_files(draft)[@lesson] ==
               String.replace(
                 original,
                 ":::figure{src=media/photos/photo.png ",
                 ":::figure{src=media/photos/photo.webp "
               )

      assert stored_files(draft)[@lesson] =~ "The file media/photos/photo.png shows"
      refute Map.has_key?(stored_files(draft), "media/photos/photo.png")

      # The check finds the reference at the new path.
      assert {:ok, %{report: %{"errors" => []}}} = Workbench.check_draft(scope, draft.id, nil)
    end

    test "a delivery file of an asset of the program attaches that asset", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      # Two ready assets share the delivery file of the SVG: the older one
      # would win the digest match of the ingest, and the program of the
      # pack key uses the newer one.
      svg = "media/release-checks.svg"
      webm = "media/assistant-demo.webm"
      pack = copy_pack!(demo_path())
      mapping = MediaFixtures.demo_media!(pack)
      newer = Repo.get!(Asset, mapping[svg])

      older =
        MediaFixtures.stored_asset!(Path.join(pack, svg), :svg, "svg", %{}, svg)
        |> Ecto.Changeset.change(inserted_at: DateTime.add(newer.inserted_at, -86_400))
        |> Repo.update!()

      assert older.sha256 == newer.sha256

      assert {:ok, %PackImport{status: :validated} = pack_import} =
               Importer.import(pack, nil, media: mapping)

      assert {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)

      # The archive holds the delivery files of the program, as the archive
      # of an exported pack does.
      count = Repo.aggregate(Asset, :count)
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      assert {:ok, %PackDraft{} = draft, _skipped} = create(scope, upload, "demo.zip")
      assert media_assets(draft) == %{svg => newer.id, webm => mapping[webm]}
      assert Repo.aggregate(Asset, :count) == count
      refute_enqueued(worker: ProcessWorker)

      # The import of the draft keeps the media of the program.
      assert {:ok, %PackImport{status: :validated} = reimport} =
               Workbench.import_draft(scope, draft.id, draft.lock_version)

      assert Diff.compute(reimport.payload).media == %{added: [], changed: [], archived: []}

      # Without the program, the ingest takes the oldest asset with that
      # delivery file.
      other = copy_pack!(demo_path())
      replace!(other, "pack.yaml", "key: ai-assistant-basics-demo", "key: another-key")
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(other))

      assert {:ok, %PackDraft{} = draft, _skipped} = create(scope, upload, "other.zip")
      assert media_assets(draft) == %{svg => older.id, webm => mapping[webm]}
    end

    test "an asset of the program that an archive links counts as changed now",
         %{scope: scope, tmp_dir: tmp_dir} do
      pack = copy_pack!(demo_path())
      mapping = MediaFixtures.demo_media!(pack)

      assert {:ok, %PackImport{status: :validated} = pack_import} =
               Importer.import(pack, nil, media: mapping)

      assert {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)

      # The captions stay a text file of the draft, and an asset that the
      # archive does not name keeps its time.
      linked = Map.take(mapping, @demo_media)
      other = MediaFixtures.insert_asset!(%{origin: :pack})
      age!([other.id | Map.values(mapping)])
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      assert {:ok, %PackDraft{} = draft, _skipped} = create(scope, upload, "demo.zip")
      assert media_assets(draft) == linked
      assert Enum.all?(Map.values(linked), &recent?/1)
      refute recent?(mapping["media/assistant-demo-en.vtt"])
      refute recent?(other.id)
    end

    test "a media file that the ingest rejects rejects the archive with an entry at its path",
         %{scope: scope, tmp_dir: tmp_dir} do
      pack = copy_pack!("minimal")
      write!(pack, "media/broken.png", "a text, no PNG\n")
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      assert create(scope, upload, "pack.zip") ==
               {:error,
                [
                  %{
                    "file" => "media/broken.png",
                    "line" => nil,
                    "message" => "the file is no supported media file"
                  }
                ]}

      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "two media files with one delivery path reject the archive", %{
      scope: scope,
      tmp_dir: tmp_dir
    } do
      pack = copy_pack!("minimal")
      ffmpeg_image!(Path.join(pack, "media/photo.jpg"), "mjpeg", "mjpeg")
      ffmpeg_image!(Path.join(pack, "media/photo.png"), "png", "image2pipe")
      upload = upload!(tmp_dir, ZipFixtures.zip_dir!(pack))

      assert create(scope, upload, "pack.zip") ==
               {:error,
                [
                  %{
                    "file" => "media/photo.jpg",
                    "line" => nil,
                    "message" =>
                      "media/photo.jpg and media/photo.png both become media/photo.webp; rename one"
                  }
                ]}

      assert Repo.aggregate(PackDraft, :count) == 0
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

  # A still image of a test pattern, written by ffmpeg of the shell with the
  # encoder `codec` and the muxer `format`.
  defp ffmpeg_image!(path, codec, format) do
    File.mkdir_p!(Path.dirname(path))
    executable = System.find_executable("ffmpeg") || flunk("ffmpeg is not on the PATH")

    args =
      ~w(-nostdin -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=96x64 -frames:v 1) ++
        ["-c:v", codec, "-f", format, path]

    {output, status} = System.cmd(executable, args, stderr_to_stdout: true)
    assert status == 0, output
  end

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

  # Sets the time of the last change of the assets `ids` 60 days back.
  defp age!(ids) do
    old = DateTime.add(DateTime.utc_now(:second), -60 * 86_400)
    count = length(ids)

    {^count, _rows} =
      Repo.update_all(from(a in Asset, where: a.id in ^ids), set: [updated_at: old])

    :ok
  end

  # Whether the asset `id` changed within the last minute.
  defp recent?(id),
    do: DateTime.diff(DateTime.utc_now(), Repo.get!(Asset, id).updated_at) < 60

  # The media entries of a draft as path => asset id.
  defp media_assets(%PackDraft{media: media}), do: Map.new(media, &{&1.path, &1.media_asset_id})

  defp stored_files(%PackDraft{id: id}) do
    Repo.all(from f in PackDraftFile, where: f.pack_draft_id == ^id, select: {f.path, f.content})
    |> Map.new()
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(3, "0")
end
