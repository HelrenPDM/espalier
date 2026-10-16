defmodule EspalierWeb.Admin.MediaControllerTest do
  @moduledoc """
  The media library routes (task 0018, step 15): the pipelines of every
  route (`:author` for the reads, `:author_write` with a second factor from
  the last 10 minutes for the changes, ASVS 7.5.1, 8.2.1, 8.3.1), the upload
  through the pipeline `:media_upload` with the real ingest (ASVS 5.2.1,
  2.2.1), the list with its filters and cursor, the single view with its
  uses, the title rules of `PATCH` (ASVS 15.3.3), the deletion with 409
  `asset_in_use`, and the asset view without source digest, store path and
  uploader (ASVS 15.3.3).
  """
  # The upload runs the real ingest, which takes the advisory lock of the
  # quota and writes the shared media store, and the tests change the
  # application environment :media.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import Espalier.LearningFixtures, only: [publish_demo!: 0]

  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.Pack.Importer
  alias Espalier.Catalog.PackImport
  alias Espalier.{Media, MediaFixtures, PackFixtures, Repo, Workbench}
  alias Espalier.Media.{Asset, ProcessWorker, Store}

  @moduletag :tmp_dir

  @view_keys ~w(animated bytes duration_ms ext failure failure_detail has_alpha has_audio height
                id inserted_at kind origin poster_url progress source_name status title updated_at
                url width)

  setup %{conn: conn} do
    author = user_with_role_fixture(:author)
    conn = log_in_user(conn, author)
    %{conn: conn, author: author, token: get_session(conn, :user_token)}
  end

  describe "the pipelines" do
    test "the reads answer 401 without a session and 403 forbidden for a learner" do
      asset = asset!()

      for path <- ["/api/admin/media", "/api/admin/media/#{asset.id}"] do
        conn = get(api_conn(), path)
        assert json_response(conn, 401) == %{"error" => "unauthenticated"}, path
        assert get_resp_header(conn, "cache-control") == ["no-store"]

        conn = api_conn() |> log_in_user(user_fixture()) |> get(path)
        assert json_response(conn, 403) == %{"error" => "forbidden"}, path
        assert get_resp_header(conn, "cache-control") == ["no-store"]
      end
    end

    test "the reads need no recent second factor", %{conn: conn, token: token} do
      asset = asset!()
      assert {1, _} = override_session(token, mfa_at: minutes_ago(11))

      conn = json_request(conn, :get, "/api/admin/media")
      assert %{"items" => [item], "next" => nil} = json_response(conn, 200)
      assert item["id"] == asset.id

      # An unknown id passes the pipeline and reaches the controller.
      conn = json_request(conn, :get, "/api/admin/media/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "a read of a single asset needs no recent second factor", %{conn: conn, token: token} do
      asset = asset!()
      assert {1, _} = override_session(token, mfa_at: minutes_ago(11))

      conn = json_request(conn, :get, "/api/admin/media/#{asset.id}")
      assert json_response(conn, 200)["id"] == asset.id
    end

    test "the changes answer 403 reauth_required without a recent second factor", %{
      conn: conn,
      token: token,
      tmp_dir: tmp_dir
    } do
      asset = asset!()
      assert {1, _} = override_session(token, mfa_at: minutes_ago(11))

      conn = json_request(conn, :patch, "/api/admin/media/#{asset.id}", %{title: "New"})
      assert json_response(conn, 403) == %{"error" => "reauth_required"}

      conn = json_request(conn, :delete, "/api/admin/media/#{asset.id}")
      assert json_response(conn, 403) == %{"error" => "reauth_required"}

      conn = upload(conn, png!(tmp_dir, "red"), "red.png")
      assert json_response(conn, 403) == %{"error" => "reauth_required"}

      assert Repo.get!(Asset, asset.id).title == asset.title
      assert Repo.aggregate(Asset, :count) == 1
    end

    test "the changes answer 403 csrf without the token", %{conn: conn, tmp_dir: tmp_dir} do
      asset = asset!()

      for {method, body} <- [{:patch, %{title: "New"}}, {:delete, nil}] do
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> dispatch(
            @endpoint,
            method,
            "/api/admin/media/#{asset.id}",
            body && JSON.encode!(body)
          )

        assert json_response(response, 403) == %{"error" => "csrf"}, Atom.to_string(method)
      end

      {content_type, body} = multipart(png!(tmp_dir, "red"), "red.png")

      response =
        conn
        |> put_req_header("content-type", content_type)
        |> dispatch(@endpoint, :post, "/api/admin/media", body)

      assert json_response(response, 403) == %{"error" => "csrf"}

      assert Repo.get!(Asset, asset.id).title == asset.title
      assert Repo.aggregate(Asset, :count) == 1
    end

    test "the changes answer 403 forbidden for a learner", %{tmp_dir: tmp_dir} do
      asset = asset!()
      conn = log_in_user(api_conn(), user_fixture())

      conn = json_request(conn, :patch, "/api/admin/media/#{asset.id}", %{title: "New"})
      assert json_response(conn, 403) == %{"error" => "forbidden"}

      conn = json_request(conn, :delete, "/api/admin/media/#{asset.id}")
      assert json_response(conn, 403) == %{"error" => "forbidden"}

      conn = upload(conn, png!(tmp_dir, "red"), "red.png")
      assert json_response(conn, 403) == %{"error" => "forbidden"}

      assert Repo.aggregate(Asset, :count) == 1
    end

    test "an admin without the role author answers 403 forbidden", %{tmp_dir: tmp_dir} do
      conn = log_in_user(api_conn(), user_with_role_fixture(:admin))

      conn = json_request(conn, :get, "/api/admin/media")
      assert json_response(conn, 403) == %{"error" => "forbidden"}

      conn = upload(conn, png!(tmp_dir, "red"), "red.png")
      assert json_response(conn, 403) == %{"error" => "forbidden"}
    end
  end

  describe "POST /api/admin/media" do
    test "answers 201 with the asset view for a new PNG and queues its conversion", %{
      conn: conn,
      author: author,
      tmp_dir: tmp_dir
    } do
      png = png!(tmp_dir, "red")

      conn = upload(conn, png, "Desk photo.png")
      body = json_response(conn, 201)
      on_exit(fn -> File.rm(Store.incoming_path(body["id"])) end)

      assert body |> Map.keys() |> Enum.sort() == @view_keys
      assert get_resp_header(conn, "location") == ["/api/admin/media/#{body["id"]}"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert %{
               "kind" => "image",
               "status" => "queued",
               "failure" => nil,
               "failure_detail" => nil,
               "progress" => 0,
               "title" => "Desk photo",
               "source_name" => "Desk photo.png",
               "origin" => "upload",
               "ext" => nil,
               "bytes" => nil,
               "url" => nil,
               "poster_url" => nil
             } = body

      asset = Repo.get!(Asset, body["id"])
      assert asset.source_sha256 == sha256(png)
      assert asset.incoming_bytes == byte_size(png)
      assert asset.created_by_id == author.id
      assert File.read!(Store.incoming_path(asset.id)) == png

      assert_enqueued(
        worker: ProcessWorker,
        queue: :media,
        args: %{"asset_id" => asset.id, "kind" => "image"}
      )

      assert [%AuditEvent{details: details, subject_id: subject_id}] = events("media.uploaded")
      assert details["kind"] == "image"
      assert subject_id == asset.id

      refute File.exists?(upload_path(conn))
      refute_private(body)
    end

    test "answers 200 with the existing asset for the same file", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      png = png!(tmp_dir, "blue")

      conn = upload(conn, png, "blue.png")
      first = json_response(conn, 201)
      on_exit(fn -> File.rm(Store.incoming_path(first["id"])) end)

      conn = upload(conn, png, "Another name.png")
      second = json_response(conn, 200)

      assert second["id"] == first["id"]
      assert second["title"] == "blue"
      assert get_resp_header(conn, "location") == ["/api/admin/media/#{first["id"]}"]
      assert Repo.aggregate(Asset, :count) == 1
      assert length(all_enqueued(worker: ProcessWorker)) == 1
      assert length(events("media.uploaded")) == 1
      assert File.ls!(Store.incoming_root()) |> Enum.filter(&(&1 == first["id"])) == [first["id"]]
      assert File.read!(Store.incoming_path(first["id"])) == png
      refute File.exists?(upload_path(conn))
    end

    test "answers 200 with the ready asset whose delivery file has the digest of the upload", %{
      conn: conn
    } do
      mapping = MediaFixtures.demo_media!()
      svg = Repo.get!(Asset, mapping["media/release-checks.svg"])
      assert svg.origin == :pack

      content = File.read!(Path.join(PackFixtures.demo_path(), "media/release-checks.svg"))
      conn = upload(conn, content, "diagram.svg")
      body = json_response(conn, 200)

      assert body["id"] == svg.id
      assert body["origin"] == "upload"
      assert body["status"] == "ready"
      assert Repo.get!(Asset, svg.id).origin == :upload
      assert Repo.aggregate(Asset, :count) == 3
      assert all_enqueued(worker: ProcessWorker) == []
      assert events("media.uploaded") == []
      refute File.exists?(upload_path(conn))
      refute File.exists?(Store.incoming_path(svg.id))
    end

    test "an uploaded PNG converts to a ready WebP that the media route serves", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      png = png!(tmp_dir, "green", "40x30")

      conn = upload(conn, png, "green.png")
      %{"id" => id} = json_response(conn, 201)

      assert %Asset{status: :ready} = Media.process_now(Repo.get!(Asset, id))

      # The list renders the same asset view as the single read.
      conn = json_request(conn, :get, "/api/admin/media?status=ready")
      assert %{"items" => [body], "next" => nil} = json_response(conn, 200)
      assert body["id"] == id

      assert %{
               "status" => "ready",
               "progress" => 100,
               "ext" => "webp",
               "width" => 40,
               "height" => 30,
               "animated" => false,
               "poster_url" => nil
             } = body

      asset = Repo.get!(Asset, id)
      assert body["url"] == "/media/#{asset.sha256}.webp"
      assert body["bytes"] == File.stat!(Store.path(asset.sha256, "webp")).size
      refute File.exists?(Store.incoming_path(id))
      refute_private(body)

      conn = conn |> next_request() |> get(body["url"])
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/webp"]
    end

    test "answers 415 unsupported_media_type for a JSON body", %{conn: conn} do
      conn = json_request(conn, :post, "/api/admin/media", %{"file" => "iVBORw0KGgo="})
      assert json_response(conn, 415) == %{"error" => "unsupported_media_type"}
      assert Repo.aggregate(Asset, :count) == 0
    end

    test "answers 413 request_too_large above the parser limit", %{conn: conn} do
      put_media(image_max_mb: 1, video_max_mb: 1)
      assert Media.max_upload_bytes() == 1_048_576

      {content_type, body} = multipart(:binary.copy("x", 1_048_576 + 1), "large.png")
      conn = conn |> with_csrf_token() |> put_req_header("content-type", content_type)

      {413, _headers, resp_body} =
        assert_error_sent(413, fn ->
          dispatch(conn, @endpoint, :post, "/api/admin/media", body)
        end)

      assert JSON.decode!(resp_body) == %{"error" => "request_too_large"}
      assert Repo.aggregate(Asset, :count) == 0
    end

    test "reads the parser limit per request from the larger kind limit", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      put_media(image_max_mb: 1, video_max_mb: 2)
      assert Media.max_upload_bytes() == 2 * 1_048_576

      # Above the image limit and below the parser limit: the context answers.
      content = padded_png!(tmp_dir, 1_048_576 + 100)
      conn = upload(conn, content, "padded.png")

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"file" => ["too_large"]}
             }

      refute File.exists?(upload_path(conn))
    end

    test "answers 422 unsupported_type for a text file and an HLS playlist", %{conn: conn} do
      for {content, name} <- [
            {"just a note, no image\n", "notes.png"},
            {"#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:10,\nfile:///etc/passwd\n", "clip.mp4"},
            {"ffconcat version 1.0\nfile /etc/passwd\n", "list.webm"},
            {"", "empty.png"}
          ] do
        conn = upload(conn, content, name)

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"file" => ["unsupported_type"]}
               },
               name

        refute File.exists?(upload_path(conn)), name
      end

      assert Repo.aggregate(Asset, :count) == 0
      assert all_enqueued(worker: ProcessWorker) == []
    end

    test "answers 422 extension_mismatch for a signature of another kind", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      png = png!(tmp_dir, "yellow")

      for {content, name} <- [
            {png, "photo.mp4"},
            {png, "photo.svg"},
            {png, "photo"},
            {"WEBVTT\n\n00:00.000 --> 00:01.000\nHi\n", "captions.png"},
            {~s(<svg xmlns="http://www.w3.org/2000/svg"/>), "drawing.webp"}
          ] do
        conn = upload(conn, content, name)

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"file" => ["extension_mismatch"]}
               },
               name

        refute File.exists?(upload_path(conn)), name
      end

      assert Repo.aggregate(Asset, :count) == 0
    end

    test "answers 422 too_large above the limit of the kind", %{conn: conn, tmp_dir: tmp_dir} do
      put_media(image_max_mb: 1)
      assert Media.max_upload_bytes() > 2 * 1_048_576

      conn = upload(conn, padded_png!(tmp_dir, 1_048_576 + 1), "padded.png")

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"file" => ["too_large"]}
             }

      refute File.exists?(upload_path(conn))

      # An SVG above svg_max_bytes, below the parser limit.
      svg =
        ~s(<svg xmlns="http://www.w3.org/2000/svg">) <>
          String.duplicate("<!-- padding -->", div(1_048_576, 16) + 1) <> "</svg>"

      conn = upload(conn, svg, "large.svg")

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"file" => ["too_large"]}
             }

      assert Repo.aggregate(Asset, :count) == 0
    end

    test "answers 422 too_many_pixels for a PNG header above max_input_pixels", %{conn: conn} do
      conn = upload(conn, huge_png(10_000, 10_000), "huge.png")

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"file" => ["too_many_pixels"]}
             }

      refute File.exists?(upload_path(conn))
      assert Repo.aggregate(Asset, :count) == 0
    end

    test "answers 422 invalid_type for a text part named file", %{conn: conn} do
      {content_type, body} = text_part("not a file")
      conn = conn |> with_csrf_token() |> put_req_header("content-type", content_type)
      conn = dispatch(conn, @endpoint, :post, "/api/admin/media", body)

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"file" => ["invalid_type"]}
             }

      assert Repo.aggregate(Asset, :count) == 0
    end

    test "answers 422 for a body without the part file", %{conn: conn, tmp_dir: tmp_dir} do
      conn = upload(conn, png!(tmp_dir, "red"), "red.png", field: "upload")
      assert %{"error" => "validation_failed", "fields" => fields} = json_response(conn, 422)
      assert fields == %{"upload" => ["unexpected_field"]}
      assert Repo.aggregate(Asset, :count) == 0
    end

    test "answers 409 storage_full when the upload would exceed the quota", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      put_media(storage_max_gb: 1)
      asset!(bytes: 1024 * 1_048_576 - 10)

      conn = upload(conn, png!(tmp_dir, "red"), "red.png")
      assert json_response(conn, 409) == %{"error" => "storage_full"}
      refute File.exists?(upload_path(conn))
      assert Repo.aggregate(Asset, :count) == 1

      assert File.ls!(Store.incoming_root())
             |> Enum.reject(&String.starts_with?(&1, "."))
             |> Enum.all?(&(&1 not in ids()))

      assert all_enqueued(worker: ProcessWorker) == []
    end
  end

  describe "GET /api/admin/media" do
    test "lists newest first with a cursor in next", %{conn: conn} do
      assets =
        for n <- 1..5 do
          asset!(title: "Asset #{n}", inserted_at: seconds_ago(100 - n))
        end

      newest_first = assets |> Enum.reverse() |> Enum.map(& &1.id)

      conn = json_request(conn, :get, "/api/admin/media")
      body = json_response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert Enum.map(body["items"], & &1["id"]) == newest_first
      assert body["next"] == nil

      for item <- body["items"] do
        assert item |> Map.keys() |> Enum.sort() == @view_keys
        refute_private(item)
      end

      conn = json_request(conn, :get, "/api/admin/media?limit=2")
      page_1 = json_response(conn, 200)
      assert Enum.map(page_1["items"], & &1["id"]) == Enum.slice(newest_first, 0, 2)
      assert is_binary(page_1["next"])

      conn = json_request(conn, :get, "/api/admin/media?limit=2&after=#{page_1["next"]}")
      page_2 = json_response(conn, 200)
      assert Enum.map(page_2["items"], & &1["id"]) == Enum.slice(newest_first, 2, 2)

      conn = json_request(conn, :get, "/api/admin/media?limit=2&after=#{page_2["next"]}")
      page_3 = json_response(conn, 200)
      assert Enum.map(page_3["items"], & &1["id"]) == Enum.slice(newest_first, 4, 1)
      assert page_3["next"] == nil
    end

    test "orders assets of the same second by id", %{conn: conn} do
      at = seconds_ago(10)
      assets = for n <- 1..3, do: asset!(title: "Same #{n}", inserted_at: at)
      expected = assets |> Enum.map(& &1.id) |> Enum.sort(:desc)

      conn = json_request(conn, :get, "/api/admin/media?limit=1")
      page = json_response(conn, 200)
      ids = Enum.map(page["items"], & &1["id"])

      {ids, _next} =
        Enum.reduce(1..2, {ids, page["next"]}, fn _n, {ids, next} ->
          conn = json_request(conn, :get, "/api/admin/media?limit=1&after=#{next}")
          page = json_response(conn, 200)
          {ids ++ Enum.map(page["items"], & &1["id"]), page["next"]}
        end)

      assert ids == expected
    end

    test "filters by kind, status and a case-insensitive part of the title", %{conn: conn} do
      svg = asset!(kind: :svg, ext: "svg", title: "Release Diagram")
      video = asset!(kind: :video, ext: "webm", title: "Demo clip")
      queued = asset!(kind: :image, status: :queued, sha256: nil, ext: nil, title: "Queued photo")
      literal = asset!(kind: :image, title: "50%_off banner")
      plain = asset!(kind: :image, title: "500 off banner")

      assert list_ids(conn, "kind=svg") == [svg.id]
      assert list_ids(conn, "kind=video") == [video.id]

      assert Enum.sort(list_ids(conn, "kind=image")) ==
               Enum.sort([queued.id, literal.id, plain.id])

      assert list_ids(conn, "status=queued") == [queued.id]
      assert list_ids(conn, "q=DIAGRAM") == [svg.id]
      assert list_ids(conn, "q=" <> URI.encode_www_form("%_")) == [literal.id]
      assert Enum.sort(list_ids(conn, "q=banner")) == Enum.sort([literal.id, plain.id])
      assert list_ids(conn, "kind=image&status=queued&q=photo") == [queued.id]
      assert list_ids(conn, "kind=captions") == []
    end

    test "unused leaves out assets of programs, drafts and validated imports", %{
      conn: conn,
      author: author
    } do
      publish_demo!()
      mapping = MediaFixtures.media_for(PackFixtures.demo_path())
      unused = asset!(title: "Unused")
      in_draft = asset!(kind: :svg, ext: "svg", title: "In a draft")
      in_import = asset!(kind: :svg, ext: "svg", title: "In an import")

      scope = author_scope(author)
      {:ok, draft} = Workbench.create_empty(scope, "Media draft")

      {:ok, _draft} =
        Workbench.attach_media(
          scope,
          draft.id,
          %{media_asset_id: in_draft.id, path: "media/diagram.svg"},
          draft.lock_version
        )

      %PackImport{} =
        Repo.insert!(%PackImport{
          status: :validated,
          pack_key: "media-pack",
          payload: %{},
          report: %{},
          media_asset_ids: [in_import.id]
        })

      ids = list_ids(conn, "unused=true")
      assert ids == [unused.id]

      all = list_ids(conn, "unused=false")

      for id <- [unused.id, in_draft.id, in_import.id | Map.values(mapping)],
          do: assert(id in all)
    end

    test "answers 422 for an invalid cursor, limit, kind or status", %{conn: conn} do
      for query <- [
            "after=not-a-cursor",
            "after=" <> Base.url_encode64("2026-01-01T00:00:00Z|no-uuid", padding: false),
            "limit=0",
            "limit=101",
            "limit=many",
            "kind=audio",
            "status=done",
            "unused=maybe",
            "extra=1"
          ] do
        conn = json_request(conn, :get, "/api/admin/media?" <> query)

        assert %{"error" => "validation_failed", "fields" => fields} = json_response(conn, 422),
               query

        assert map_size(fields) == 1, query
      end
    end
  end

  describe "GET /api/admin/media/:id" do
    test "answers the asset with its uses", %{conn: conn, author: author} do
      program = publish_demo!()
      mapping = MediaFixtures.media_for(PackFixtures.demo_path())
      svg_id = mapping["media/release-checks.svg"]

      conn = json_request(conn, :get, "/api/admin/media/#{svg_id}")
      body = json_response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert body |> Map.keys() |> Enum.sort() == Enum.sort(["uses" | @view_keys])
      assert body["kind"] == "svg"
      assert body["status"] == "ready"
      assert body["url"] == "/media/#{Repo.get!(Asset, svg_id).sha256}.svg"

      assert body["uses"] == %{
               "programs" => [%{"slug" => program.slug, "title" => program.title}],
               "drafts" => [],
               "imports" => []
             }

      refute_private(body)

      # A draft and a validated import add their uses.
      scope = author_scope(author)
      {:ok, draft} = Workbench.create_empty(scope, "Media draft")

      {:ok, _draft} =
        Workbench.attach_media(
          scope,
          draft.id,
          %{media_asset_id: svg_id, path: "media/checks/diagram.svg"},
          draft.lock_version
        )

      {:ok, %PackImport{status: :validated} = pack_import} =
        Importer.import(PackFixtures.demo_path(), nil, media: mapping)

      conn = json_request(conn, :get, "/api/admin/media/#{svg_id}")
      uses = json_response(conn, 200)["uses"]

      assert uses["programs"] == [%{"slug" => program.slug, "title" => program.title}]

      assert uses["drafts"] == [
               %{"id" => draft.id, "title" => "Media draft", "path" => "media/checks/diagram.svg"}
             ]

      assert [%{"id" => import_id, "pack_key" => pack_key, "inserted_at" => inserted_at}] =
               uses["imports"]

      assert import_id == pack_import.id
      assert pack_key == pack_import.pack_key
      assert is_binary(inserted_at)
    end

    test "answers 404 for an unknown id and 422 for a malformed id", %{conn: conn} do
      conn = json_request(conn, :get, "/api/admin/media/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}

      conn = json_request(conn, :get, "/api/admin/media/not-a-uuid")

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"id" => ["invalid_format"]}
             }
    end
  end

  describe "PATCH /api/admin/media/:id" do
    test "changes the title and nothing else", %{conn: conn} do
      asset = asset!(title: "Old title")

      conn = json_request(conn, :patch, "/api/admin/media/#{asset.id}", %{title: "New title"})
      body = json_response(conn, 200)
      assert body["title"] == "New title"
      assert body |> Map.keys() |> Enum.sort() == @view_keys

      stored = Repo.get!(Asset, asset.id)
      assert stored.title == "New title"

      assert Map.take(stored, [:kind, :status, :sha256, :source_sha256, :origin, :bytes]) ==
               Map.take(asset, [:kind, :status, :sha256, :source_sha256, :origin, :bytes])

      title = String.duplicate("é", 255)
      conn = json_request(conn, :patch, "/api/admin/media/#{asset.id}", %{title: title})
      assert json_response(conn, 200)["title"] == title
    end

    test "answers 422 for an empty title, 256 characters, U+0000 and an extra member", %{
      conn: conn
    } do
      asset = asset!(title: "Kept")

      for {body, member} <- [
            {%{title: ""}, "title"},
            {%{title: String.duplicate("a", 256)}, "title"},
            {%{title: "a" <> <<0>> <> "b"}, "title"},
            {%{title: nil}, "title"},
            {%{title: 7}, "title"},
            {%{}, "title"},
            {%{title: "Valid", kind: "video"}, "kind"},
            {%{title: "Valid", status: "ready"}, "status"},
            {%{title: "Valid", sha256: MediaFixtures.random_sha256()}, "sha256"}
          ] do
        conn = json_request(conn, :patch, "/api/admin/media/#{asset.id}", body)

        assert %{"error" => "validation_failed", "fields" => fields} = json_response(conn, 422),
               inspect(body)

        assert Map.keys(fields) == [member], inspect(body)
      end

      assert Repo.get!(Asset, asset.id).title == "Kept"
    end

    test "answers 404 for an unknown asset", %{conn: conn} do
      conn = json_request(conn, :patch, "/api/admin/media/#{Ecto.UUID.generate()}", %{title: "X"})
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "DELETE /api/admin/media/:id" do
    test "answers 204, removes the row and its files and writes media.deleted", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      file = Path.join(tmp_dir, "delete-me.svg")

      File.write!(
        file,
        ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4 4"><circle r="2" fill="#b91c1c"/></svg>)
      )

      asset = MediaFixtures.stored_asset!(file, :svg, "svg")
      stored = Store.path(asset.sha256, "svg")
      assert File.regular?(stored)

      conn = json_request(conn, :delete, "/api/admin/media/#{asset.id}")
      assert response(conn, 204) == ""
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert Repo.get(Asset, asset.id) == nil
      refute File.exists?(stored)

      assert [%AuditEvent{details: details, subject_id: subject_id}] = events("media.deleted")
      assert details["kind"] == "svg"
      assert subject_id == asset.id

      conn = json_request(conn, :delete, "/api/admin/media/#{asset.id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "answers 409 asset_in_use with the uses for an asset of a published program", %{
      conn: conn
    } do
      program = publish_demo!()
      mapping = MediaFixtures.media_for(PackFixtures.demo_path())

      for {path, id} <- mapping do
        conn = json_request(conn, :delete, "/api/admin/media/#{id}")

        assert json_response(conn, 409) == %{
                 "error" => "asset_in_use",
                 "uses" => %{
                   "programs" => [%{"slug" => program.slug, "title" => program.title}],
                   "drafts" => [],
                   "imports" => []
                 }
               },
               path

        asset = Repo.get!(Asset, id)
        assert File.regular?(Store.path(asset.sha256, asset.ext))
      end

      assert events("media.deleted") == []
    end

    test "answers 409 asset_in_use for an asset of a draft", %{conn: conn, author: author} do
      asset = asset!(kind: :svg, ext: "svg", title: "Draft diagram")
      scope = author_scope(author)
      {:ok, draft} = Workbench.create_empty(scope, "Media draft")

      {:ok, _draft} =
        Workbench.attach_media(
          scope,
          draft.id,
          %{media_asset_id: asset.id, path: "media/diagram.svg"},
          draft.lock_version
        )

      conn = json_request(conn, :delete, "/api/admin/media/#{asset.id}")

      assert json_response(conn, 409) == %{
               "error" => "asset_in_use",
               "uses" => %{
                 "programs" => [],
                 "drafts" => [
                   %{"id" => draft.id, "title" => "Media draft", "path" => "media/diagram.svg"}
                 ],
                 "imports" => []
               }
             }

      assert Repo.get(Asset, asset.id)
    end

    test "answers 404 for an unknown asset and 422 for a malformed id", %{conn: conn} do
      conn = json_request(conn, :delete, "/api/admin/media/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}

      conn = json_request(conn, :delete, "/api/admin/media/not-a-uuid")

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"id" => ["invalid_format"]}
             }

      assert events("media.deleted") == []
    end

    test "deletes an asset that only a validated import names", %{conn: conn} do
      asset = asset!()

      Repo.insert!(%PackImport{
        status: :validated,
        pack_key: "media-pack",
        payload: %{},
        report: %{},
        media_asset_ids: [asset.id]
      })

      conn = json_request(conn, :delete, "/api/admin/media/#{asset.id}")
      assert response(conn, 204) == ""
      assert Repo.get(Asset, asset.id) == nil
    end
  end

  ## Helpers

  defp author_scope(user), do: %{Scope.for_user(user) | roles: [:learner, :author]}

  defp minutes_ago(minutes), do: DateTime.add(DateTime.utc_now(:second), -minutes, :minute)
  defp seconds_ago(seconds), do: DateTime.add(DateTime.utc_now(:second), -seconds, :second)

  # A ready asset row without a stored file, unless attributes say otherwise.
  defp asset!(attrs \\ []) do
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
          width: 10,
          height: 10,
          incoming_bytes: 0,
          progress: 100,
          origin: :upload
        },
        attrs
      )
    )
  end

  defp ids, do: Repo.all(from a in Asset, select: a.id)

  defp list_ids(conn, query) do
    conn = json_request(conn, :get, "/api/admin/media?" <> query)
    conn |> json_response(200) |> Map.fetch!("items") |> Enum.map(& &1["id"])
  end

  defp events(action) do
    Repo.all(from e in AuditEvent, where: e.action == ^action, order_by: e.inserted_at)
  end

  defp sha256(binary), do: :sha256 |> :crypto.hash(binary) |> Base.encode16(case: :lower)

  # Sets members of the application environment :media for one test.
  defp put_media(changes) do
    previous = Application.fetch_env!(:espalier, :media)
    Application.put_env(:espalier, :media, Keyword.merge(previous, changes))
    on_exit(fn -> Application.put_env(:espalier, :media, previous) end)
  end

  # A PNG from ffmpeg of one colour.
  defp png!(dir, color, size \\ "16x16") do
    file = Path.join(dir, "#{color}-#{size}.png")

    {output, status} =
      System.cmd(
        System.find_executable("ffmpeg"),
        ~w(-nostdin -hide_banner -v error -f lavfi -i color=c=#{color}:s=#{size} -frames:v 1) ++
          ~w(-c:v png -f image2 -y) ++ [file],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.read!(file)
  end

  # A PNG from ffmpeg, padded after IEND to `bytes`.
  defp padded_png!(dir, bytes) do
    png = png!(dir, "orange")
    png <> :binary.copy(<<0>>, bytes - byte_size(png))
  end

  # A PNG of a few bytes whose IHDR names width by height.
  defp huge_png(width, height) do
    chunk = fn type, data ->
      <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
    end

    <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <>
      chunk.("IHDR", <<width::32, height::32, 8, 2, 0, 0, 0>>) <>
      chunk.("IDAT", <<0>>) <> chunk.("IEND", "")
  end

  defp upload(conn, content, filename, opts \\ []) do
    upload_request(conn, "/api/admin/media", content, Keyword.put(opts, :filename, filename))
  end

  # A multipart/form-data body with `content` as the file `filename` in the
  # field file.
  defp multipart(content, filename) do
    boundary = "espalier-test-#{System.unique_integer([:positive])}"

    body =
      IO.iodata_to_binary([
        "--#{boundary}\r\n",
        ~s(Content-Disposition: form-data; name="file"; filename="#{filename}"\r\n),
        "Content-Type: application/octet-stream\r\n\r\n",
        content,
        "\r\n--#{boundary}--\r\n"
      ])

    {"multipart/form-data; boundary=" <> boundary, body}
  end

  # A multipart/form-data body with `content` as a plain form field file.
  defp text_part(content) do
    boundary = "espalier-test-#{System.unique_integer([:positive])}"

    body =
      IO.iodata_to_binary([
        "--#{boundary}\r\n",
        ~s(Content-Disposition: form-data; name="file"\r\n\r\n),
        content,
        "\r\n--#{boundary}--\r\n"
      ])

    {"multipart/form-data; boundary=" <> boundary, body}
  end

  # The temporary file of the part, from the parameters of the request.
  defp upload_path(conn) do
    [conn.body_params, conn.params]
    |> Enum.flat_map(&Map.values/1)
    |> Enum.find_value(fn
      %Plug.Upload{path: path} -> path
      _other -> nil
    end) || flunk("no upload in the request")
  end

  # The view names no source digest, no uploader and no path of the store.
  defp refute_private(view) do
    keys = view |> Map.keys() |> MapSet.new()
    for key <- ~w(source_sha256 created_by_id incoming_bytes path), do: refute(key in keys)
    root = Store.root()

    for {_key, value} <- view, is_binary(value) do
      refute String.contains?(value, root)
      refute String.contains?(value, "/files/")
      refute String.contains?(value, "incoming")
    end
  end
end
