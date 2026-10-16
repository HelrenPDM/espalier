defmodule EspalierWeb.Admin.PackDraftMediaControllerTest do
  @moduledoc """
  The media entries of a workbench draft (task 0018, step 16): attach,
  rename and delete through `EspalierWeb.Admin.PackDraftMediaController`
  with the answers of the file routes of task 0016a (`lock_version`,
  `stale_draft`, `path_taken`, `invalid_path`, `media_limit`, 404), a
  captions asset that becomes a text file of the draft, the pipelines of
  the three routes, and the staged download with the media files in the
  archive and 409 `download_too_large` (ASVS 5.4.1, 5.4.2).
  """
  # The tests change the application environment :media, and the download
  # uses the one CheckLimiter of the node and the shared media store.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  alias Espalier.Accounts.Scope
  alias Espalier.Media.{Asset, Store}
  alias Espalier.{MediaFixtures, Repo, Workbench}
  alias Espalier.Workbench.{PackDraft, PackDraftFile, PackDraftMedia}

  @svg "media/release-checks.svg"
  @webm "media/assistant-demo.webm"
  @vtt "media/assistant-demo-en.vtt"

  @asset_keys ~w(animated bytes duration_ms ext failure failure_detail has_alpha has_audio height
                 id inserted_at kind origin poster_url progress source_name status title
                 updated_at url width)

  setup %{conn: conn} do
    author = user_with_role_fixture(:author)
    conn = log_in_user(conn, author)
    scope = %{Scope.for_user(author) | roles: [:learner, :author]}
    {:ok, draft} = Workbench.create_empty(scope, "Media draft")
    mapping = MediaFixtures.demo_media!()

    %{
      conn: conn,
      scope: scope,
      draft: draft,
      token: get_session(conn, :user_token),
      svg: Repo.get!(Asset, mapping[@svg]),
      webm: Repo.get!(Asset, mapping[@webm]),
      vtt: Repo.get!(Asset, mapping[@vtt])
    }
  end

  describe "POST /api/admin/pack-drafts/:id/media" do
    test "adds an SVG, a video and an image asset at their delivery paths", %{
      conn: conn,
      draft: draft,
      svg: svg,
      webm: webm
    } do
      conn = attach(conn, draft, svg, "media/diagrams/release-checks.svg", 1)
      body = json_response(conn, 201)
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert body["lock_version"] == 2

      assert [
               %{
                 "id" => svg_entry,
                 "path" => "media/diagrams/release-checks.svg",
                 "asset" => asset
               }
             ] =
               body["media"]

      assert asset |> Map.keys() |> Enum.sort() == @asset_keys
      assert asset["id"] == svg.id
      assert asset["kind"] == "svg"
      assert asset["url"] == "/media/#{svg.sha256}.svg"
      assert is_binary(svg_entry)

      # The files of the draft are unchanged.
      assert length(body["files"]) == 6
      refute Enum.any?(body["files"], &String.starts_with?(&1["path"], "media/"))

      conn = attach(conn, draft, webm, "media/clip.webm", 2)
      assert json_response(conn, 201)["lock_version"] == 3

      # An image asset that still converts may join a draft.
      image = asset!(kind: :image, status: :queued, sha256: nil, ext: nil, title: "Photo")
      conn = attach(conn, draft, image, "media/photos/desk-photo.webp", 3)
      body = json_response(conn, 201)
      assert body["lock_version"] == 4

      assert Enum.map(body["media"], &{&1["path"], &1["asset"]["id"]}) == [
               {"media/clip.webm", webm.id},
               {"media/diagrams/release-checks.svg", svg.id},
               {"media/photos/desk-photo.webp", image.id}
             ]

      assert Enum.find(body["media"], &(&1["asset"]["id"] == image.id))["asset"]["status"] ==
               "queued"

      assert Repo.aggregate(
               from(m in PackDraftMedia, where: m.pack_draft_id == ^draft.id),
               :count
             ) ==
               3

      # The single view of the draft holds the same entries.
      conn = json_request(conn, :get, "/api/admin/pack-drafts/#{draft.id}")

      assert Enum.map(json_response(conn, 200)["media"], & &1["path"]) == [
               "media/clip.webm",
               "media/diagrams/release-checks.svg",
               "media/photos/desk-photo.webp"
             ]
    end

    test "answers 422 invalid_path for a wrong extension or a path outside media/", %{
      conn: conn,
      draft: draft,
      svg: svg,
      webm: webm
    } do
      image = asset!(kind: :image, title: "Photo")

      for {asset, path} <- [
            {svg, "media/release-checks.webp"},
            {svg, "media/release-checks.png"},
            {svg, "media/release-checks"},
            {svg, "modules/01-first-module/release-checks.svg"},
            {svg, "release-checks.svg"},
            {svg, "media/a/b/c/d/release-checks.svg"},
            {svg, "media/Release Checks.svg"},
            {svg, "media/../release-checks.svg"},
            {svg, "/media/release-checks.svg"},
            {svg, "media/release-checks.SVG"},
            {webm, "media/clip.mp4"},
            {webm, "media/clip.svg"},
            {image, "media/photo.png"},
            {image, "media/photo.jpg"}
          ] do
        conn = attach(conn, draft, asset, path, 1)

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"path" => ["invalid_path"]}
               },
               path
      end

      assert Repo.get!(PackDraft, draft.id).lock_version == 1
      assert Repo.aggregate(PackDraftMedia, :count) == 0
    end

    test "a captions asset becomes a text file of the draft", %{
      conn: conn,
      draft: draft,
      vtt: vtt
    } do
      conn = attach(conn, draft, vtt, "media/captions/demo-en.vtt", 1)
      body = json_response(conn, 201)

      assert body["lock_version"] == 2
      assert body["media"] == []
      assert "media/captions/demo-en.vtt" in Enum.map(body["files"], & &1["path"])

      stored =
        Repo.get_by!(PackDraftFile, pack_draft_id: draft.id, path: "media/captions/demo-en.vtt")

      assert stored.content == File.read!(Store.path(vtt.sha256, "vtt"))
      assert Repo.aggregate(PackDraftMedia, :count) == 0

      # The editor reads it as a file of the draft.
      conn = json_request(conn, :get, "/api/admin/pack-drafts/#{draft.id}/files/#{stored.id}")
      assert json_response(conn, 200)["content"] == stored.content
    end

    test "a captions asset needs a .vtt path below media/", %{
      conn: conn,
      draft: draft,
      vtt: vtt
    } do
      for path <- [
            "media/demo-en.webp",
            "media/demo-en.svg",
            "captions/demo-en.vtt",
            "demo-en.vtt"
          ] do
        conn = attach(conn, draft, vtt, path, 1)

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"path" => ["invalid_path"]}
               },
               path
      end
    end

    test "answers 422 not_ready for a captions asset that is not ready", %{
      conn: conn,
      draft: draft
    } do
      for status <- [:queued, :processing, :failed] do
        captions =
          asset!(kind: :captions, status: status, sha256: nil, ext: nil, title: "Captions")

        conn = attach(conn, draft, captions, "media/captions-en.vtt", 1)

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"media_asset_id" => ["not_ready"]}
               },
               Atom.to_string(status)
      end

      assert Repo.get!(PackDraft, draft.id).lock_version == 1
    end

    test "answers 409 path_taken for a path that the draft holds", %{
      conn: conn,
      draft: draft,
      svg: svg,
      vtt: vtt
    } do
      other = asset!(kind: :svg, ext: "svg", title: "Other diagram")
      conn = attach(conn, draft, svg, "media/diagram.svg", 1)
      assert json_response(conn, 201)["lock_version"] == 2

      conn = attach(conn, draft, other, "media/diagram.svg", 2)
      assert json_response(conn, 409) == %{"error" => "path_taken"}

      conn = attach(conn, draft, svg, "media/diagram.svg", 2)
      assert json_response(conn, 409) == %{"error" => "path_taken"}

      # A captions text file and a second attach at its path.
      conn = attach(conn, draft, vtt, "media/demo-en.vtt", 2)
      assert json_response(conn, 201)["lock_version"] == 3
      conn = attach(conn, draft, vtt, "media/demo-en.vtt", 3)
      assert json_response(conn, 409) == %{"error" => "path_taken"}

      assert Repo.get!(PackDraft, draft.id).lock_version == 3
    end

    test "answers 409 media_limit above max_draft_media", %{
      conn: conn,
      draft: draft,
      svg: svg,
      webm: webm,
      vtt: vtt
    } do
      put_media(max_draft_media: 1)

      conn = attach(conn, draft, svg, "media/diagram.svg", 1)
      assert json_response(conn, 201)["lock_version"] == 2

      conn = attach(conn, draft, webm, "media/clip.webm", 2)
      assert json_response(conn, 409) == %{"error" => "media_limit"}

      # A captions asset is a text file and counts against the files only.
      conn = attach(conn, draft, vtt, "media/clip-en.vtt", 2)
      assert json_response(conn, 201)["lock_version"] == 3
    end

    test "answers 409 too_many_files when files and media entries reach max_files", %{
      conn: conn,
      draft: draft,
      svg: svg,
      webm: webm
    } do
      conn = attach(conn, draft, svg, "media/diagram.svg", 1)
      assert json_response(conn, 201)["lock_version"] == 2

      # The skeleton holds 6 files; fill the draft to max_files with one
      # media entry.
      now = DateTime.utc_now(:second)
      missing = Workbench.max_files() - 6 - 1

      rows =
        for n <- 1..missing do
          %{
            id: Ecto.UUID.generate(),
            pack_draft_id: draft.id,
            path:
              "modules/01-first-module/lessons/#{String.pad_leading("#{n}", 4, "0")}-filler.md",
            content: "x",
            inserted_at: now,
            updated_at: now
          }
        end

      for chunk <- Enum.chunk_every(rows, 500), do: Repo.insert_all(PackDraftFile, chunk)

      conn = attach(conn, draft, webm, "media/clip.webm", 2)
      assert json_response(conn, 409) == %{"error" => "too_many_files"}
      assert Repo.aggregate(PackDraftMedia, :count) == 1
    end

    test "answers 409 stale_draft with the stored lock_version", %{
      conn: conn,
      draft: draft,
      svg: svg
    } do
      for version <- [2, 7] do
        conn = attach(conn, draft, svg, "media/diagram.svg", version)
        assert json_response(conn, 409) == %{"error" => "stale_draft", "lock_version" => 1}
      end

      assert Repo.aggregate(PackDraftMedia, :count) == 0
    end

    test "answers 404 for an unknown asset or draft", %{conn: conn, draft: draft, svg: svg} do
      conn =
        json_request(conn, :post, "/api/admin/pack-drafts/#{draft.id}/media", %{
          media_asset_id: Ecto.UUID.generate(),
          path: "media/diagram.svg",
          lock_version: 1
        })

      assert json_response(conn, 404) == %{"error" => "not_found"}

      conn =
        json_request(conn, :post, "/api/admin/pack-drafts/#{Ecto.UUID.generate()}/media", %{
          media_asset_id: svg.id,
          path: "media/diagram.svg",
          lock_version: 1
        })

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "answers 422 for a malformed body", %{conn: conn, draft: draft, svg: svg} do
      for {body, member} <- [
            {%{media_asset_id: "not-a-uuid", path: "media/a.svg", lock_version: 1},
             "media_asset_id"},
            {%{media_asset_id: svg.id, path: "", lock_version: 1}, "path"},
            {%{media_asset_id: svg.id, path: "media/a.svg", lock_version: 0}, "lock_version"},
            {%{media_asset_id: svg.id, path: "media/a.svg"}, "lock_version"},
            {%{media_asset_id: svg.id, lock_version: 1}, "path"},
            {%{media_asset_id: svg.id, path: "media/a.svg", lock_version: 1, kind: "svg"}, "kind"}
          ] do
        conn = json_request(conn, :post, "/api/admin/pack-drafts/#{draft.id}/media", body)

        assert %{"error" => "validation_failed", "fields" => fields} = json_response(conn, 422),
               inspect(body)

        assert Map.keys(fields) == [member], inspect(body)
      end
    end
  end

  describe "PATCH /api/admin/pack-drafts/:id/media/:media_id" do
    setup %{scope: scope, draft: draft, svg: svg, webm: webm} do
      {:ok, _draft} = attach!(scope, draft, svg, "media/diagram.svg", 1)
      {:ok, _draft} = attach!(scope, draft, webm, "media/clip.webm", 2)

      %{
        svg_entry: entry!(draft, "media/diagram.svg"),
        webm_entry: entry!(draft, "media/clip.webm")
      }
    end

    test "moves an entry to another path with the delivery extension", %{
      conn: conn,
      draft: draft,
      svg_entry: entry
    } do
      conn = rename(conn, draft, entry, "media/checks/release.svg", 3)
      body = json_response(conn, 200)

      assert body["lock_version"] == 4

      assert Enum.map(body["media"], &{&1["id"], &1["path"]}) == [
               {entry!(draft, "media/checks/release.svg").id, "media/checks/release.svg"},
               {entry!(draft, "media/clip.webm").id, "media/clip.webm"}
             ]
    end

    test "answers 422 invalid_path for a wrong extension", %{
      conn: conn,
      draft: draft,
      svg_entry: entry
    } do
      for path <- ["media/diagram.webp", "media/diagram.vtt", "stations.svg", "media/Diagram.svg"] do
        conn = rename(conn, draft, entry, path, 3)

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"path" => ["invalid_path"]}
               },
               path
      end

      assert Repo.get!(PackDraft, draft.id).lock_version == 3
    end

    test "answers 409 path_taken and stale_draft", %{
      conn: conn,
      draft: draft,
      svg_entry: svg_entry,
      webm_entry: webm_entry,
      scope: scope
    } do
      other = asset!(kind: :svg, ext: "svg", title: "Other")
      {:ok, _draft} = attach!(scope, draft, other, "media/other.svg", 3)

      conn = rename(conn, draft, svg_entry, "media/other.svg", 4)
      assert json_response(conn, 409) == %{"error" => "path_taken"}

      conn = rename(conn, draft, webm_entry, "media/clip.webm", 2)
      assert json_response(conn, 409) == %{"error" => "stale_draft", "lock_version" => 4}

      assert entry!(draft, "media/diagram.svg").id == svg_entry.id
    end

    test "answers 404 for an unknown entry and an entry of another draft", %{
      conn: conn,
      draft: draft,
      scope: scope,
      svg: svg
    } do
      conn = rename(conn, draft, %{id: Ecto.UUID.generate()}, "media/x.svg", 3)
      assert json_response(conn, 404) == %{"error" => "not_found"}

      {:ok, other} = Workbench.create_empty(scope, "Other draft")
      {:ok, _other} = attach!(scope, other, svg, "media/diagram.svg", 1)
      foreign = entry!(other, "media/diagram.svg")

      conn = rename(conn, draft, foreign, "media/x.svg", 3)
      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert entry!(other, "media/diagram.svg").id == foreign.id
    end
  end

  describe "DELETE /api/admin/pack-drafts/:id/media/:media_id" do
    setup %{scope: scope, draft: draft, svg: svg} do
      {:ok, _draft} = attach!(scope, draft, svg, "media/diagram.svg", 1)
      %{entry: entry!(draft, "media/diagram.svg")}
    end

    test "removes the entry with lock_version in the query and keeps the asset", %{
      conn: conn,
      draft: draft,
      entry: entry,
      svg: svg
    } do
      conn =
        json_request(
          conn,
          :delete,
          "/api/admin/pack-drafts/#{draft.id}/media/#{entry.id}?lock_version=2"
        )

      body = json_response(conn, 200)
      assert body["lock_version"] == 3
      assert body["media"] == []
      assert Repo.get(PackDraftMedia, entry.id) == nil
      assert Repo.get!(Asset, svg.id)
    end

    test "answers 409 stale_draft, 404 and 422", %{conn: conn, draft: draft, entry: entry} do
      path = "/api/admin/pack-drafts/#{draft.id}/media/#{entry.id}"

      conn = json_request(conn, :delete, path <> "?lock_version=1")
      assert json_response(conn, 409) == %{"error" => "stale_draft", "lock_version" => 2}

      conn = json_request(conn, :delete, path)

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"lock_version" => ["missing_field"]}
             }

      conn = json_request(conn, :delete, path <> "?lock_version=0")
      assert %{"error" => "validation_failed"} = json_response(conn, 422)

      conn =
        json_request(
          conn,
          :delete,
          "/api/admin/pack-drafts/#{draft.id}/media/#{Ecto.UUID.generate()}?lock_version=2"
        )

      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert Repo.get(PackDraftMedia, entry.id)
    end
  end

  describe "the pipelines of the draft media routes" do
    setup %{scope: scope, draft: draft, svg: svg} do
      {:ok, _draft} = attach!(scope, draft, svg, "media/diagram.svg", 1)
      %{entry: entry!(draft, "media/diagram.svg")}
    end

    test "answer 403 reauth_required without a recent second factor", %{
      conn: conn,
      token: token,
      draft: draft,
      entry: entry,
      webm: webm
    } do
      assert {1, _} = override_session(token, mfa_at: minutes_ago(11))

      for {method, path, body} <- routes(draft, entry, webm) do
        conn = json_request(conn, method, path, body)
        assert json_response(conn, 403) == %{"error" => "reauth_required"}, "#{method} #{path}"
      end

      assert Repo.get!(PackDraft, draft.id).lock_version == 2
    end

    test "answer 403 csrf without the token", %{
      conn: conn,
      draft: draft,
      entry: entry,
      webm: webm
    } do
      for {method, path, body} <- routes(draft, entry, webm) do
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> dispatch(@endpoint, method, path, body && JSON.encode!(body))

        assert json_response(response, 403) == %{"error" => "csrf"}, "#{method} #{path}"
      end

      assert Repo.get!(PackDraft, draft.id).lock_version == 2
    end

    test "answer 403 forbidden for a learner and 401 without a session", %{
      draft: draft,
      entry: entry,
      webm: webm
    } do
      learner = log_in_user(api_conn(), user_fixture())

      for {method, path, body} <- routes(draft, entry, webm) do
        conn = json_request(learner, method, path, body)
        assert json_response(conn, 403) == %{"error" => "forbidden"}, "#{method} #{path}"

        conn = json_request(api_conn(), method, path, body)
        assert json_response(conn, 401) == %{"error" => "unauthenticated"}, "#{method} #{path}"
      end

      assert Repo.get!(PackDraft, draft.id).lock_version == 2
    end
  end

  describe "GET /api/admin/pack-drafts/:id/download" do
    test "sends the media files in the archive at their draft paths", %{
      conn: conn,
      scope: scope,
      draft: draft,
      svg: svg,
      webm: webm,
      vtt: vtt
    } do
      {:ok, _draft} = attach!(scope, draft, svg, "media/diagrams/release-checks.svg", 1)
      {:ok, _draft} = attach!(scope, draft, webm, "media/clip.webm", 2)
      {:ok, _draft} = attach!(scope, draft, vtt, "media/clip-en.vtt", 3)
      staging_before = work_dirs()

      conn = json_request(conn, :get, "/api/admin/pack-drafts/#{draft.id}/download")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/zip"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="media-draft-draft.zip")
             ]

      entries = unzip!(conn.resp_body)
      paths = Enum.map(entries, &elem(&1, 0))

      assert paths == Enum.sort(paths)

      for path <- ["media/clip-en.vtt", "media/clip.webm", "media/diagrams/release-checks.svg"],
          do: assert(path in paths)

      files = Map.new(entries)
      assert files["media/clip.webm"] == File.read!(Store.path(webm.sha256, "webm"))

      assert files["media/diagrams/release-checks.svg"] ==
               File.read!(Store.path(svg.sha256, "svg"))

      assert files["media/clip-en.vtt"] == File.read!(Store.path(vtt.sha256, "vtt"))

      for file <- Repo.all(from f in PackDraftFile, where: f.pack_draft_id == ^draft.id),
          do: assert(files[file.path] == file.content)

      # WebM entries are stored without compression.
      {:ok, listing} = :zip.list_dir(conn.resp_body)

      sizes =
        for {:zip_file, name, info, _comment, _offset, comp_size} <- listing,
            into: %{},
            do: {List.to_string(name), {elem(info, 1), comp_size}}

      assert {size, size} = sizes["media/clip.webm"]
      assert size == webm.bytes

      # The staging directory is removed after the send.
      assert work_dirs() == staging_before
    end

    test "answers 409 download_too_large above export_max_mb", %{
      conn: conn,
      scope: scope,
      draft: draft,
      webm: webm
    } do
      put_media(export_max_mb: 1)
      {:ok, _draft} = attach!(scope, draft, webm, "media/clip.webm", 1)

      webm |> Ecto.Changeset.change(bytes: 1_048_576 + 1) |> Repo.update!()

      conn = json_request(conn, :get, "/api/admin/pack-drafts/#{draft.id}/download")
      assert json_response(conn, 409) == %{"error" => "download_too_large"}

      webm |> Ecto.Changeset.change(bytes: 1_000_000) |> Repo.update!()
      conn = json_request(conn, :get, "/api/admin/pack-drafts/#{draft.id}/download")
      assert conn.status == 200
    end

    test "answers 409 media_not_ready for an entry that is not ready", %{
      conn: conn,
      scope: scope,
      draft: draft
    } do
      image = asset!(kind: :image, status: :queued, sha256: nil, ext: nil, title: "Photo")
      {:ok, _draft} = attach!(scope, draft, image, "media/photo.webp", 1)
      staging_before = work_dirs()

      conn = json_request(conn, :get, "/api/admin/pack-drafts/#{draft.id}/download")

      assert json_response(conn, 409) == %{
               "error" => "media_not_ready",
               "media" => [
                 %{"path" => "media/photo.webp", "status" => "queued", "failure" => nil}
               ]
             }

      assert work_dirs() == staging_before
    end
  end

  ## Helpers

  defp minutes_ago(minutes), do: DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

  defp attach(conn, draft, asset, path, lock_version) do
    json_request(conn, :post, "/api/admin/pack-drafts/#{draft.id}/media", %{
      media_asset_id: asset.id,
      path: path,
      lock_version: lock_version
    })
  end

  defp attach!(scope, draft, asset, path, lock_version) do
    Workbench.attach_media(scope, draft.id, %{media_asset_id: asset.id, path: path}, lock_version)
  end

  defp rename(conn, draft, entry, path, lock_version) do
    json_request(conn, :patch, "/api/admin/pack-drafts/#{draft.id}/media/#{entry.id}", %{
      path: path,
      lock_version: lock_version
    })
  end

  defp entry!(draft, path), do: Repo.get_by!(PackDraftMedia, pack_draft_id: draft.id, path: path)

  defp routes(draft, entry, asset) do
    base = "/api/admin/pack-drafts/#{draft.id}/media"

    [
      {:post, base, %{media_asset_id: asset.id, path: "media/clip.webm", lock_version: 2}},
      {:patch, "#{base}/#{entry.id}", %{path: "media/moved.svg", lock_version: 2}},
      {:delete, "#{base}/#{entry.id}?lock_version=2", nil}
    ]
  end

  # A ready asset row without a stored file, unless attributes say otherwise.
  defp asset!(attrs) do
    attrs = Map.new(attrs)

    Repo.insert!(
      struct!(
        %Asset{
          kind: :image,
          status: :ready,
          title: "Photo",
          source_name: "photo.png",
          source_sha256: MediaFixtures.random_sha256(),
          sha256: MediaFixtures.random_sha256(),
          ext: "webp",
          bytes: 100,
          incoming_bytes: 0,
          progress: 100,
          origin: :upload
        },
        attrs
      )
    )
  end

  defp put_media(changes) do
    previous = Application.fetch_env!(:espalier, :media)
    Application.put_env(:espalier, :media, Keyword.merge(previous, changes))
    on_exit(fn -> Application.put_env(:espalier, :media, previous) end)
  end

  defp work_dirs do
    case File.ls(Store.work_root()) do
      {:ok, entries} -> Enum.sort(entries)
      {:error, :enoent} -> []
    end
  end

  defp unzip!(archive) do
    {:ok, entries} = :zip.unzip(archive, [:memory])
    entries |> Enum.map(fn {name, content} -> {List.to_string(name), content} end) |> Enum.sort()
  end
end
