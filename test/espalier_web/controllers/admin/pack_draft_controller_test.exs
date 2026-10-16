defmodule EspalierWeb.Admin.PackDraftControllerTest do
  @moduledoc """
  The draft routes of the pack workbench (task 0016a, steps 9 and 14,
  bullet "Routes"): the list, the single view, the four starting points,
  the delete, the check, the import and the download, each with the answers
  of step 9. Task 0018 (step 16) adds the media entries and the captions
  file of the starting points, and the media files of the download, its
  staging directory, 409 `download_too_large` and 429 `checks_busy` for a
  second download of the same author. Served by Bandit on a real socket, a
  download to a client that stops reading frees its slot within the send
  timeout, while the slot of the checks stays free, and a client below the
  minimum rate loses the connection at the deadline.

  Every POST and DELETE request carries a CSRF token of its session
  (`json_request/5` and `upload_request/4` fetch it with
  `with_csrf_token/1`). The parameterized route test of task 0015
  (`admin_routes_test.exs`) covers 401, 403 `forbidden` and 403
  `reauth_required` for every route.
  """
  # put_setting/2 changes the application environment, and the check of
  # the slots uses the one CheckLimiter and the one DownloadLimiter of the
  # node, hence async: false.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import Espalier.PackFixtures, only: [copy_pack!: 1, demo_path: 0, read!: 2, write!: 3]

  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog
  alias Espalier.Catalog.PackImport
  alias Espalier.Interop.PackWriter
  alias Espalier.Media.Store
  alias Espalier.{MediaFixtures, Repo, Workbench, ZipFixtures}
  alias Espalier.Test.FunctionPlug
  alias Espalier.Workbench.{CheckLimiter, DownloadLimiter, PackDraft, PackDraftFile}
  alias EspalierWeb.Admin.{PackDraftController, PackJSON}
  alias EspalierWeb.PackMultipart

  @demo_key "ai-assistant-basics-demo"

  # The media files of the demo pack that a draft holds as media entries;
  # its captions stay a text file (task 0018, step 16).
  @demo_media_files ["media/assistant-demo.webm", "media/release-checks.svg"]

  # The six files of the skeleton for the name "New pack" (step 5).
  @skeleton_paths [
    "modules/01-first-module/items.yaml",
    "modules/01-first-module/lessons/01-first-lesson.md",
    "modules/01-first-module/module.yaml",
    "modules/01-first-module/objectives.yaml",
    "pack.yaml",
    "stations.yaml"
  ]

  setup %{conn: conn} do
    author = user_with_role_fixture(:author)
    conn = log_in_user(conn, author)
    %{conn: conn, author: author, scope: author_scope(author)}
  end

  describe "GET /api/admin/pack-drafts" do
    test "lists the drafts newest change first, with usage and without files", %{
      conn: conn,
      scope: scope
    } do
      older = skeleton!(scope, "Older pack")
      newer = skeleton!(scope, "Newer pack")
      set_updated_at(older, minutes_ago(120))
      set_updated_at(newer, minutes_ago(60))

      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts")
      assert %{"data" => [first, second]} = json_response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert {first["id"], second["id"]} == {newer.id, older.id}
      assert first["title"] == "Newer pack"
      assert first["pack_key"] == "newer-pack"
      assert first["lock_version"] == 1
      assert first["usage"] == %{"files" => 6, "bytes" => stored_bytes(newer.id)}
      assert first["limits"] == limits()
      refute Map.has_key?(first, "files")
      refute Map.has_key?(second, "files")

      # A file change makes the older draft the newest one.
      file = stored_file!(older.id, "stations.yaml")

      conn =
        json_request(conn, :put, ~p"/api/admin/pack-drafts/#{older.id}/files/#{file.id}", %{
          content: file.content <> "\n",
          lock_version: 1
        })

      assert json_response(conn, 200)["lock_version"] == 2

      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts")
      assert [older.id, newer.id] == Enum.map(json_response(conn, 200)["data"], & &1["id"])
    end

    test "answers an empty list without drafts", %{conn: conn} do
      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts")
      assert json_response(conn, 200) == %{"data" => []}
    end
  end

  describe "GET /api/admin/pack-drafts/:id" do
    test "answers the draft with its files, usage and limits", %{conn: conn, scope: scope} do
      draft = skeleton!(scope)

      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{draft.id}")
      body = json_response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert %{
               "id" => id,
               "title" => "New pack",
               "pack_key" => "new-pack",
               "lock_version" => 1,
               "inserted_at" => inserted_at,
               "updated_at" => updated_at,
               "usage" => usage,
               "limits" => limits,
               "files" => files
             } = body

      assert id == draft.id
      assert is_binary(inserted_at) and is_binary(updated_at)
      assert usage == %{"files" => 6, "bytes" => stored_bytes(draft.id)}
      assert limits == limits()

      # Ordered by path, without content.
      assert Enum.map(files, & &1["path"]) == @skeleton_paths

      for file <- files do
        assert file |> Map.keys() |> Enum.sort() == ~w(bytes id path updated_at)
        assert file["bytes"] == byte_size(stored_file!(draft.id, file["path"]).content)
      end
    end

    test "answers 404 for an unknown id and 422 for a malformed id", %{conn: conn} do
      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}

      for path <- [
            "/api/admin/pack-drafts/not-a-uuid",
            "/api/admin/pack-drafts/not-a-uuid/download"
          ] do
        conn = json_request(conn, :get, path)

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"id" => ["invalid_format"]}
               }
      end
    end
  end

  describe "POST /api/admin/pack-drafts" do
    test "starts a draft from the empty skeleton and writes pack_draft.created", %{
      conn: conn,
      author: author
    } do
      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts", %{source: "empty", name: "New pack"})

      assert %{"id" => id} = body = json_response(conn, 201)
      assert get_resp_header(conn, "location") == ["/api/admin/pack-drafts/#{id}"]
      assert body["title"] == "New pack"
      assert body["pack_key"] == "new-pack"
      assert body["lock_version"] == 1
      assert Enum.map(body["files"], & &1["path"]) == @skeleton_paths
      refute Map.has_key?(body, "skipped")

      draft = Repo.get!(PackDraft, id)
      assert draft.created_by_id == author.id

      assert [event] = events("pack_draft.created")

      assert {event.actor_id, event.subject_type, event.subject_id} ==
               {author.id, "PackDraft", id}

      assert event.details == %{"source" => "empty", "pack_key" => "new-pack", "file_count" => 6}
    end

    test "starts a draft from a published program", %{conn: conn, scope: scope, author: author} do
      media = MediaFixtures.media_for(demo_path())
      {:ok, pack_import} = Catalog.import_pack(scope, demo_path(), media: media)
      {:ok, _published} = Catalog.publish_pack(scope, pack_import)
      program = Catalog.get_program_by_slug(@demo_key)
      {:ok, rendered} = PackWriter.render_program(program)

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts", %{
          source: "program",
          program_slug: @demo_key
        })

      assert %{"id" => id} = body = json_response(conn, 201)
      assert get_resp_header(conn, "location") == ["/api/admin/pack-drafts/#{id}"]
      assert body["pack_key"] == @demo_key
      assert body["title"] == program.title

      # The files of the writer and the captions as a text file, and a media
      # entry per image, SVG and video file (task 0018, step 16).
      files = Enum.sort(rendered ++ [demo_captions()])
      paths = Enum.map(body["files"], & &1["path"])
      assert paths == Enum.map(files, &elem(&1, 0))
      # The module directories of the writer (0016 addendum).
      assert "modules/01-how-language-models-work/module.yaml" in paths

      assert stored_pairs(id) == files
      assert media_entries(body) == demo_media_entries(media)

      assert [event] = events("pack_draft.created")
      assert {event.actor_id, event.subject_id} == {author.id, id}

      assert event.details == %{
               "source" => "program",
               "program_slug" => @demo_key,
               "pack_key" => @demo_key,
               "file_count" => length(files)
             }
    end

    test "starts a draft from an import with a payload", %{conn: conn, scope: scope} do
      media = MediaFixtures.media_for(demo_path())

      {:ok, %PackImport{status: :validated} = pack_import} =
        Catalog.import_pack(scope, demo_path(), media: media)

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts", %{
          source: "import",
          pack_import_id: pack_import.id
        })

      assert %{"id" => id} = body = json_response(conn, 201)
      assert get_resp_header(conn, "location") == ["/api/admin/pack-drafts/#{id}"]
      assert body["pack_key"] == @demo_key

      assert stored_pairs(id) ==
               Enum.sort(PackWriter.render(pack_import.payload) ++ [demo_captions()])

      assert media_entries(body) == demo_media_entries(media)

      assert [event] = events("pack_draft.created")

      assert event.details == %{
               "source" => "import",
               "pack_import_id" => pack_import.id,
               "pack_key" => @demo_key,
               "file_count" => length(body["files"])
             }
    end

    test "answers 404 for an unknown program, a program that is not published and an unknown import",
         %{conn: conn, scope: scope} do
      bodies = [
        %{source: "program", program_slug: "no-such-program"},
        %{source: "import", pack_import_id: Ecto.UUID.generate()}
      ]

      for body <- bodies do
        conn = json_request(conn, :post, ~p"/api/admin/pack-drafts", body)
        assert json_response(conn, 404) == %{"error" => "not_found"}
      end

      # A validated import has no published program yet.
      {:ok, %PackImport{status: :validated}} = Catalog.import_pack(scope, demo_path())

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts", %{
          source: "program",
          program_slug: @demo_key
        })

      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert Repo.aggregate(PackDraft, :count) == 0
      assert events("pack_draft.created") == []
    end

    test "answers 409 no_payload for a failed import", %{conn: conn, scope: scope} do
      pack = copy_pack!(demo_path())
      write!(pack, "pack.yaml", read!(pack, "pack.yaml") <> "broken: [unclosed\n")
      {:ok, %PackImport{status: :failed} = failed} = Catalog.import_pack(scope, pack)

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts", %{
          source: "import",
          pack_import_id: failed.id
        })

      assert json_response(conn, 409) == %{"error" => "no_payload"}
      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "answers 409 draft_limit when max_drafts drafts exist", %{conn: conn, scope: scope} do
      put_setting(:pack_drafts, max_drafts: 1, max_parallel_checks: 2)
      skeleton!(scope)

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts", %{source: "empty", name: "Second"})

      assert json_response(conn, 409) == %{"error" => "draft_limit", "max_drafts" => 1}
      assert Repo.aggregate(PackDraft, :count) == 1
      assert length(events("pack_draft.created")) == 1
    end

    test "answers 422 validation_failed for a missing member and a member of another source",
         %{conn: conn} do
      cases = [
        {%{source: "empty"}, %{"name" => ["required"]}},
        {%{source: "empty", name: "A pack", program_slug: @demo_key},
         %{"program_slug" => ["not_allowed"]}},
        {%{source: "program"}, %{"program_slug" => ["required"]}},
        {%{source: "import", name: "A pack"},
         %{"pack_import_id" => ["required"], "name" => ["not_allowed"]}}
      ]

      for {body, fields} <- cases do
        conn = json_request(conn, :post, ~p"/api/admin/pack-drafts", body)

        assert json_response(conn, 422) == %{"error" => "validation_failed", "fields" => fields},
               inspect(body)
      end

      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "answers 422 validation_failed for an unknown source, a long name and an extra member",
         %{conn: conn} do
      cases = [
        {%{source: "upload", name: "A pack"}, %{"source" => ["invalid_enum"]}},
        {%{source: "empty", name: String.duplicate("a", 256)}, %{"name" => ["max_length"]}},
        {%{source: "empty", name: ""}, %{"name" => ["min_length"]}},
        {%{source: "empty", name: "A pack", created_by_id: Ecto.UUID.generate()},
         %{"created_by_id" => ["unexpected_field"]}},
        {%{name: "A pack"}, %{"source" => ["missing_field"]}}
      ]

      for {body, fields} <- cases do
        conn = json_request(conn, :post, ~p"/api/admin/pack-drafts", body)

        assert json_response(conn, 422) == %{"error" => "validation_failed", "fields" => fields},
               inspect(body)
      end

      assert Repo.aggregate(PackDraft, :count) == 0
    end
  end

  describe "POST /api/admin/pack-draft-uploads" do
    test "starts a draft from a zip of the demo pack and lists README.md as skipped", %{
      conn: conn,
      author: author
    } do
      pack = copy_pack!(demo_path())
      write!(pack, "README.md", "# Notes\n")
      archive = ZipFixtures.zip_dir!(pack, root: @demo_key)

      conn = upload_request(conn, ~p"/api/admin/pack-draft-uploads", archive)

      assert %{"id" => id} = body = json_response(conn, 201)
      assert get_resp_header(conn, "location") == ["/api/admin/pack-drafts/#{id}"]
      assert body["skipped"] == %{"paths" => ["README.md"], "omitted" => 0}
      assert body["pack_key"] == @demo_key
      assert body["lock_version"] == 1

      # The captions stay a text file; the other media files become media
      # entries of queued assets at their delivery paths (task 0018, step 16).
      demo = Enum.reject(demo_files(), &(elem(&1, 0) in @demo_media_files))
      assert Enum.map(body["files"], & &1["path"]) == Enum.map(demo, &elem(&1, 0))
      assert stored_pairs(id) == demo

      assert [
               %{"path" => "media/assistant-demo.webm", "asset" => %{"kind" => "video"} = video},
               %{"path" => "media/release-checks.svg", "asset" => %{"kind" => "svg"} = svg}
             ] = body["media"]

      for asset <- [video, svg] do
        assert %{"status" => "queued", "origin" => "pack", "url" => nil} = asset
      end

      assert [event] = events("pack_draft.created")
      assert {event.actor_id, event.subject_id} == {author.id, id}

      assert event.details == %{
               "source" => "upload",
               "pack_key" => @demo_key,
               "file_count" => length(demo)
             }
    end

    test "answers 422 archive_rejected for an upload that is no zip archive", %{conn: conn} do
      conn = upload_request(conn, ~p"/api/admin/pack-draft-uploads", "not a zip archive")

      assert json_response(conn, 422) == %{
               "error" => "archive_rejected",
               "report" => %{
                 "errors" => [
                   %{"file" => ".", "line" => nil, "message" => "the upload is no zip archive"}
                 ],
                 "warnings" => []
               }
             }

      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "answers 422 archive_rejected with an entry at . for a zip without layout files", %{
      conn: conn
    } do
      archive =
        ZipFixtures.build([
          ZipFixtures.entry("README.md", "# Notes\n"),
          ZipFixtures.entry("notes/todo.txt", "nothing\n")
        ])

      conn = upload_request(conn, ~p"/api/admin/pack-draft-uploads", archive)

      assert json_response(conn, 422) == %{
               "error" => "archive_rejected",
               "report" => %{
                 "errors" => [
                   %{
                     "file" => ".",
                     "line" => nil,
                     "message" => "the archive holds no file of the pack layout"
                   }
                 ],
                 "warnings" => []
               }
             }

      assert Repo.aggregate(PackDraft, :count) == 0
      assert events("pack_draft.created") == []
    end

    test "answers 422 validation_failed for a field file that holds text instead of a file", %{
      conn: conn
    } do
      {content_type, body} = text_part("not a file")
      conn = conn |> with_csrf_token() |> put_req_header("content-type", content_type)
      conn = dispatch(conn, @endpoint, :post, ~p"/api/admin/pack-draft-uploads", body)

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"file" => ["invalid_type"]}
             }

      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "answers 415 for a JSON body", %{conn: conn} do
      conn = json_request(conn, :post, ~p"/api/admin/pack-draft-uploads", %{"file" => "UEsDBA=="})
      assert json_response(conn, 415) == %{"error" => "unsupported_media_type"}
      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "answers 413 above PACK_UPLOAD_MAX_MB", %{conn: conn} do
      put_setting(:pack_upload_max_mb, 1)
      assert PackMultipart.max_bytes() == 1_048_576
      {content_type, body} = file_part(:binary.copy("x", 1_048_576 + 1))
      conn = conn |> with_csrf_token() |> put_req_header("content-type", content_type)

      {413, _headers, resp_body} =
        assert_error_sent(413, fn ->
          dispatch(conn, @endpoint, :post, ~p"/api/admin/pack-draft-uploads", body)
        end)

      assert JSON.decode!(resp_body) == %{"error" => "request_too_large"}
      assert Repo.aggregate(PackDraft, :count) == 0
    end
  end

  describe "DELETE /api/admin/pack-drafts/:id" do
    test "answers 204, deletes the files and writes pack_draft.deleted", %{
      conn: conn,
      scope: scope,
      author: author
    } do
      draft = skeleton!(scope)

      conn = json_request(conn, :delete, ~p"/api/admin/pack-drafts/#{draft.id}")
      assert response(conn, 204) == ""
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{draft.id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}

      assert Repo.aggregate(from(f in PackDraftFile, where: f.pack_draft_id == ^draft.id), :count) ==
               0

      assert [event] = events("pack_draft.deleted")

      assert {event.actor_id, event.subject_type, event.subject_id} ==
               {author.id, "PackDraft", draft.id}

      assert event.details == %{"pack_key" => "new-pack", "file_count" => 6}

      conn = json_request(conn, :delete, ~p"/api/admin/pack-drafts/#{draft.id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert length(events("pack_draft.deleted")) == 1
    end
  end

  describe "POST /api/admin/pack-drafts/:id/check" do
    test "answers 200 with the report and the alignment of the skeleton", %{
      conn: conn,
      scope: scope
    } do
      draft = skeleton!(scope)

      conn = json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/check", %{})
      body = json_response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert body["lock_version"] == 1
      assert body["report"] == %{"errors" => [], "warnings" => []}

      assert %{"mode" => "strict", "matrix" => matrix, "errors" => [], "warnings" => []} =
               body["alignment"]

      assert length(matrix) == 12
      assert Enum.all?(matrix, &(&1["module"] == 1))
      assert body |> Map.keys() |> Enum.sort() == ~w(alignment lock_version report)

      # The body is optional: a check without an overlay may send none.
      conn = json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/check")
      assert json_response(conn, 200) == body
    end

    test "an overlay changes the report and leaves the stored draft", %{conn: conn, scope: scope} do
      draft = skeleton!(scope)
      pack_yaml = stored_file!(draft.id, "pack.yaml")
      before = Repo.get!(PackDraft, draft.id)

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/check", %{
          file_id: pack_yaml.id,
          content: pack_yaml.content <> "broken: [unclosed\n"
        })

      body = json_response(conn, 200)
      assert body["lock_version"] == 1
      assert [_ | _] = errors = body["report"]["errors"]
      assert Enum.any?(errors, &(&1["file"] == "pack.yaml"))

      assert body["alignment"] == %{
               "mode" => nil,
               "matrix" => nil,
               "errors" => [],
               "warnings" => []
             }

      assert stored_file!(draft.id, "pack.yaml").content == pack_yaml.content
      after_check = Repo.get!(PackDraft, draft.id)
      assert {after_check.lock_version, after_check.updated_at} == {1, before.updated_at}

      # Without the overlay the stored files check clean.
      conn = json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/check", %{})
      assert json_response(conn, 200)["report"] == %{"errors" => [], "warnings" => []}
    end

    test "answers 422 when only one member of the overlay is given", %{conn: conn, scope: scope} do
      draft = skeleton!(scope)
      file = stored_file!(draft.id, "pack.yaml")
      path = ~p"/api/admin/pack-drafts/#{draft.id}/check"

      conn = json_request(conn, :post, path, %{file_id: file.id})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"content" => ["required"]}
             }

      conn = json_request(conn, :post, path, %{content: "schema: 1\n"})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"file_id" => ["required"]}
             }

      conn = json_request(conn, :post, path, %{file_id: file.id, content: "a\u0000b"})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"content" => ["nul_character"]}
             }
    end

    test "answers 404 for an overlay file of another draft and for an unknown draft", %{
      conn: conn,
      scope: scope
    } do
      draft = skeleton!(scope)
      other = skeleton!(scope, "Other pack")
      foreign = stored_file!(other.id, "pack.yaml")

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/check", %{
          file_id: foreign.id,
          content: "schema: 1\n"
        })

      assert json_response(conn, 404) == %{"error" => "not_found"}

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{Ecto.UUID.generate()}/check", %{})

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "answers 429 checks_busy with retry-after: 5 while every slot is taken", %{
      conn: conn,
      scope: scope
    } do
      put_setting(:pack_drafts, max_drafts: 50, max_parallel_checks: 1)
      draft = skeleton!(scope)
      holder = hold_slot!()

      conn = json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/check", %{})
      assert json_response(conn, 429) == %{"error" => "checks_busy"}
      assert get_resp_header(conn, "retry-after") == ["5"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/imports", %{
          lock_version: 1
        })

      assert json_response(conn, 429) == %{"error" => "checks_busy"}
      assert get_resp_header(conn, "retry-after") == ["5"]
      assert Repo.aggregate(PackImport, :count) == 0

      release_slot!(holder)

      conn = json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/check", %{})
      assert json_response(conn, 200)["report"] == %{"errors" => [], "warnings" => []}
    end

    test "runs without a recent second factor, which a change needs", %{conn: conn, scope: scope} do
      draft = skeleton!(scope)
      token = get_session(conn, :user_token)
      assert {1, _} = override_session(token, mfa_at: minutes_ago(11))

      conn = json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/check", %{})
      assert json_response(conn, 200)["lock_version"] == 1

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/imports", %{
          lock_version: 1
        })

      assert json_response(conn, 403) == %{"error" => "reauth_required"}
    end
  end

  describe "POST /api/admin/pack-drafts/:id/imports" do
    test "answers 201 with the pack view and writes pack.imported with pack_draft_id", %{
      conn: conn,
      scope: scope,
      author: author
    } do
      draft = skeleton!(scope)

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/imports", %{
          lock_version: 1
        })

      assert %{"id" => id, "status" => "validated"} = body = json_response(conn, 201)
      assert get_resp_header(conn, "location") == ["/api/admin/packs/#{id}"]

      pack_import = Repo.get!(PackImport, id)
      assert body == json(PackJSON.show(%{pack_import: pack_import}))
      assert pack_import.pack_key == "new-pack"
      assert pack_import.imported_by_id == author.id

      assert [event] = events("pack.imported")
      assert {event.actor_id, event.subject_id} == {author.id, id}

      assert event.details == %{
               "pack_draft_id" => draft.id,
               "pack_key" => "new-pack",
               "status" => "validated"
             }

      # The draft stays.
      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{draft.id}")
      assert json_response(conn, 200)["lock_version"] == 1
    end

    test "answers 409 stale_draft with the stored version for an old lock_version", %{
      conn: conn,
      scope: scope
    } do
      draft = skeleton!(scope)
      file = stored_file!(draft.id, "stations.yaml")

      conn =
        json_request(conn, :put, ~p"/api/admin/pack-drafts/#{draft.id}/files/#{file.id}", %{
          content: file.content,
          lock_version: 1
        })

      assert json_response(conn, 200)["lock_version"] == 2

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/imports", %{
          lock_version: 1
        })

      assert json_response(conn, 409) == %{"error" => "stale_draft", "lock_version" => 2}
      assert Repo.aggregate(PackImport, :count) == 0
      assert events("pack.imported") == []
    end

    test "answers 404 for an unknown draft and 422 without lock_version", %{
      conn: conn,
      scope: scope
    } do
      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{Ecto.UUID.generate()}/imports", %{
          lock_version: 1
        })

      assert json_response(conn, 404) == %{"error" => "not_found"}

      draft = skeleton!(scope)
      conn = json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/imports", %{})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"lock_version" => ["missing_field"]}
             }

      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/imports", %{
          lock_version: 0
        })

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"lock_version" => ["minimum"]}
             }

      assert Repo.aggregate(PackImport, :count) == 0
    end
  end

  describe "GET /api/admin/pack-drafts/:id/download" do
    test "sends the skeleton as new-pack-draft.zip with exactly the draft files", %{
      conn: conn,
      scope: scope
    } do
      draft = skeleton!(scope)

      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{draft.id}/download")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/zip"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="new-pack-draft.zip")
             ]

      assert unzip!(conn.resp_body) == stored_pairs(draft.id)
      assert Enum.map(unzip!(conn.resp_body), &elem(&1, 0)) == @skeleton_paths
    end

    test "names the archive pack-draft.zip when the key of pack.yaml is not usable", %{
      conn: conn,
      scope: scope
    } do
      draft = skeleton!(scope)
      file = stored_file!(draft.id, "pack.yaml")

      conn =
        json_request(conn, :put, ~p"/api/admin/pack-drafts/#{draft.id}/files/#{file.id}", %{
          content: "schema: 1\nkey: Not a key!\ntitle: New pack\n",
          lock_version: 1
        })

      assert %{"pack_key" => "Not a key!", "lock_version" => 2} = json_response(conn, 200)

      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{draft.id}/download")
      assert conn.status == 200

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="pack-draft.zip")
             ]

      assert unzip!(conn.resp_body) == stored_pairs(draft.id)
    end

    test "answers 404 for an unknown draft", %{conn: conn} do
      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{Ecto.UUID.generate()}/download")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "sends the media files with the text files and removes its staging directory", %{
      conn: conn,
      scope: scope
    } do
      media = MediaFixtures.media_for(demo_path())
      {:ok, pack_import} = Catalog.import_pack(scope, demo_path(), media: media)
      {:ok, draft} = Workbench.create_from_import(scope, pack_import.id)
      staged = staging_dirs()

      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{draft.id}/download")
      assert conn.status == 200

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="#{@demo_key}-draft.zip")
             ]

      media_files = for path <- @demo_media_files, do: {path, read!(demo_path(), path)}
      assert unzip!(conn.resp_body) == Enum.sort(stored_pairs(draft.id) ++ media_files)
      assert staging_dirs() == staged
    end

    test "answers 409 download_too_large above export_max_mb and stages nothing", %{
      conn: conn,
      scope: scope
    } do
      config = Application.fetch_env!(:espalier, :media)
      Application.put_env(:espalier, :media, Keyword.put(config, :export_max_mb, 1))
      on_exit(fn -> Application.put_env(:espalier, :media, config) end)

      draft = skeleton!(scope)
      dir = Path.join(System.tmp_dir!(), "espalier-large-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      file = Path.join(dir, "large.webm")
      File.write!(file, :binary.copy("v", 1_100_000))
      video = MediaFixtures.stored_asset!(file, :video, "webm", %{width: 640, height: 360})

      {:ok, _draft} =
        Workbench.attach_media(
          scope,
          draft.id,
          %{media_asset_id: video.id, path: "media/large.webm"},
          1
        )

      staged = staging_dirs()
      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{draft.id}/download")
      assert json_response(conn, 409) == %{"error" => "download_too_large"}
      assert staging_dirs() == staged
    end

    test "a second download of the same author answers 429 checks_busy and builds nothing", %{
      conn: conn,
      scope: scope
    } do
      draft = skeleton!(scope)
      parent = self()

      transfer =
        Task.async(fn ->
          Workbench.download(scope, draft.id, fn %{dir: dir} ->
            send(parent, {:sending, self(), dir})

            receive do
              :sent -> {:ok, dir}
            end
          end)
        end)

      assert_receive {:sending, pid, dir}, 5_000
      staged = staging_dirs()

      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{draft.id}/download")
      assert json_response(conn, 429) == %{"error" => "checks_busy"}
      assert get_resp_header(conn, "retry-after") == ["5"]
      assert staging_dirs() == staged

      send(pid, :sent)
      assert Task.await(transfer) == {:ok, dir}

      conn = json_request(conn, :get, ~p"/api/admin/pack-drafts/#{draft.id}/download")
      assert conn.status == 200
    end

    # Bandit serves the action on an ephemeral port with a send timeout of
    # two seconds in place of 30 seconds, and a client with a receive buffer
    # of 4096 bytes reads the status line and then nothing more. The zip
    # holds a video of 32 MiB without compression, more than the socket
    # buffers of both ends take.
    test "a client that stops reading frees the slot within the send timeout", %{scope: scope} do
      put_setting(:pack_drafts, max_drafts: 50, max_parallel_checks: 1, max_parallel_downloads: 1)
      send_timeout = 2_000
      draft = skeleton!(scope)
      video = large_video!(32 * 1_048_576)
      attach_video!(scope, draft, video)
      staged = staging_dirs()
      port = serve_download(scope, draft, send_timeout: send_timeout)

      {:ok, socket} =
        :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, recbuf: 4_096], 5_000)

      on_exit(fn -> :gen_tcp.close(socket) end)
      :ok = :gen_tcp.send(socket, "GET /download HTTP/1.1\r\nhost: localhost\r\n\r\n")
      assert {:ok, "HTTP/1.1 200 OK\r\n" <> _rest} = :gen_tcp.recv(socket, 0, 5_000)

      # The download holds the only slot of the downloads while its send
      # waits, and the only slot of the checks is free.
      assert DownloadLimiter.run(Ecto.UUID.generate(), fn -> :free end) == {:error, :checks_busy}
      assert CheckLimiter.run(fn -> :free end) == :free

      # The send of a block ends after the send timeout, and the download
      # removes its staging directory and frees the slot.
      assert_receive {:download_returned, :chunked, _at}, send_timeout + 5_000
      assert DownloadLimiter.run(Ecto.UUID.generate(), fn -> :free end) == :free
      assert staging_dirs() == staged
    end

    # Bandit serves the action with a send buffer of 4096 bytes and the
    # default send timeout of 30 seconds, and a client with a receive buffer
    # of 4096 bytes reads at a quarter of the minimum rate of 1 MiB per
    # second, so the server sends at the pace of the client. The zip holds a
    # video of 3 MiB, so its deadline lies about 3 seconds after the start
    # of the transfer.
    test "a client below the minimum rate loses the connection at the deadline and frees the slot",
         %{scope: scope} do
      min_rate = 1_048_576

      put_setting(:pack_drafts,
        max_drafts: 50,
        max_parallel_downloads: 1,
        download_min_bytes_per_second: min_rate,
        download_floor_seconds: 1
      )

      draft = skeleton!(scope)
      video = large_video!(3 * 1_048_576)
      attach_video!(scope, draft, video)
      staged = staging_dirs()
      port = serve_download(scope, draft, sndbuf: 4_096)

      {:ok, socket} =
        :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, recbuf: 4_096], 5_000)

      on_exit(fn -> :gen_tcp.close(socket) end)
      started = System.monotonic_time(:millisecond)
      :ok = :gen_tcp.send(socket, "GET /download HTTP/1.1\r\nhost: localhost\r\n\r\n")
      {received, reason} = read_paced(socket, div(min_rate, 4), started, 0)

      # The send stopped at the first block after the deadline, and Bandit
      # closed the connection: the client holds less than the zip. The margin
      # of 3 seconds covers a client that a loaded machine wakes late; the
      # whole zip would take 12 seconds at this rate.
      assert_received {:download_returned, :chunked, at}
      assert at - started >= 3_000
      assert at - started < 6_000
      assert reason in [:closed, :econnreset]
      assert received < 3 * 1_048_576
      assert DownloadLimiter.run(Ecto.UUID.generate(), fn -> :free end) == :free
      assert staging_dirs() == staged
    end
  end

  ## Helpers

  defp author_scope(user), do: %{Scope.for_user(user) | roles: [:learner, :author]}

  # A draft from the empty skeleton, started through the context.
  defp skeleton!(scope, name \\ "New pack") do
    {:ok, draft} = Workbench.create_empty(scope, name)
    draft
  end

  defp set_updated_at(draft, at) do
    Repo.update_all(from(d in PackDraft, where: d.id == ^draft.id), set: [updated_at: at])
  end

  defp minutes_ago(minutes), do: DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

  defp limits do
    %{
      "files" => 2_000,
      "file_bytes" => 1_048_576,
      "draft_bytes" => 5 * PackMultipart.max_bytes()
    }
  end

  defp stored_file!(draft_id, path),
    do: Repo.get_by!(PackDraftFile, pack_draft_id: draft_id, path: path)

  # The stored files of a draft as {path, content}, sorted by path.
  defp stored_pairs(draft_id) do
    Repo.all(
      from f in PackDraftFile,
        where: f.pack_draft_id == ^draft_id,
        order_by: f.path,
        select: {f.path, f.content}
    )
  end

  defp stored_bytes(draft_id),
    do: draft_id |> stored_pairs() |> Enum.map(&byte_size(elem(&1, 1))) |> Enum.sum()

  # The regular files of content/demo as {relative path, content}, sorted.
  defp demo_files do
    demo_path()
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&{Path.relative_to(&1, demo_path()), File.read!(&1)})
    |> Enum.sort()
  end

  # The directories below MEDIA_DIR/work, among them the staging directories
  # of the draft downloads.
  defp staging_dirs, do: Store.work_root() |> Path.join("*") |> Path.wildcard() |> Enum.sort()

  # A ready video asset of `bytes` bytes: zeros after 16 random bytes, so
  # that its store file belongs to this test, which removes it on exit.
  defp large_video!(bytes) do
    dir = Path.join(System.tmp_dir!(), "espalier-large-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    file = Path.join(dir, "large.webm")
    File.write!(file, [:crypto.strong_rand_bytes(16), :binary.copy(<<0>>, bytes - 16)])
    video = MediaFixtures.stored_asset!(file, :video, "webm", %{width: 640, height: 360})
    on_exit(fn -> File.rm(Store.path(video.sha256, "webm")) end)
    video
  end

  # Attaches `video` to the skeleton `draft` at media/large.webm.
  defp attach_video!(scope, draft, video) do
    {:ok, _draft} =
      Workbench.attach_media(
        scope,
        draft.id,
        %{media_asset_id: video.id, path: "media/large.webm"},
        1
      )
  end

  # Serves the download of `draft` for `scope` through Bandit; the plug
  # tells the test when the action returned.
  defp serve_download(scope, draft, transport_options) do
    test = self()

    serve(
      fn conn ->
        conn =
          conn
          |> assign(:current_scope, scope)
          |> PackDraftController.download(%{id: draft.id})

        send(test, {:download_returned, conn.state, System.monotonic_time(:millisecond)})
        conn
      end,
      transport_options
    )
  end

  # Reads at `rate` bytes per second until the action returns and then at
  # full speed until the connection ends. Returns the bytes received and
  # the reason of the end.
  defp read_paced(socket, rate, started, received) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        received = received + byte_size(data)
        if not returned?(), do: wait_until(started + div(received * 1_000, rate))
        read_paced(socket, rate, started, received)

      {:error, reason} when reason in [:closed, :econnreset] ->
        {received, reason}

      {:error, reason} ->
        flunk("the connection stayed open: #{inspect(reason)}")
    end
  end

  defp wait_until(at) do
    wait = at - System.monotonic_time(:millisecond)
    if wait > 0, do: Process.sleep(wait)
  end

  # Whether the action has returned, without taking its message.
  defp returned? do
    {:messages, messages} = Process.info(self(), :messages)
    Enum.any?(messages, &match?({:download_returned, _state, _at}, &1))
  end

  # Starts Bandit on an ephemeral port of the loopback interface with `fun`
  # as the plug and returns the port. `send_timeout` replaces the default of
  # ThousandIsland.
  defp serve(fun, transport_options) do
    options = [
      plug: {FunctionPlug, fun},
      ip: :loopback,
      port: 0,
      startup_log: false,
      thousand_island_options: [transport_options: transport_options]
    ]

    pid = start_supervised!({Bandit, options})
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    port
  end

  # The captions of the demo pack as {path, content}.
  defp demo_captions do
    path = "media/assistant-demo-en.vtt"
    {path, read!(demo_path(), path)}
  end

  # The media entries of a draft view as {path, asset id}.
  defp media_entries(body), do: Enum.map(body["media"], &{&1["path"], &1["asset"]["id"]})

  # The media entries that a draft of the demo pack holds for the mapping
  # of MediaFixtures.
  defp demo_media_entries(media), do: for(path <- @demo_media_files, do: {path, media[path]})

  defp unzip!(archive) do
    {:ok, entries} = :zip.unzip(archive, [:memory])
    entries |> Enum.map(fn {name, content} -> {List.to_string(name), content} end) |> Enum.sort()
  end

  # A process that takes a slot of CheckLimiter and holds it until
  # release_slot!/1.
  defp hold_slot! do
    parent = self()

    holder =
      Task.async(fn ->
        CheckLimiter.run(fn ->
          send(parent, {:holding, self()})

          receive do
            :release -> :released
          end
        end)
      end)

    assert_receive {:holding, _pid}
    holder
  end

  defp release_slot!(holder) do
    send(holder.pid, :release)
    assert Task.await(holder) == :released
  end

  # A multipart/form-data body with `content` as a plain form field named
  # `file`, without a filename.
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

  # A multipart/form-data body with `content` as the file `pack.zip` in the
  # field `file`.
  defp file_part(content) do
    boundary = "espalier-test-#{System.unique_integer([:positive])}"

    body =
      IO.iodata_to_binary([
        "--#{boundary}\r\n",
        ~s(Content-Disposition: form-data; name="file"; filename="pack.zip"\r\n),
        "Content-Type: application/zip\r\n\r\n",
        content,
        "\r\n--#{boundary}--\r\n"
      ])

    {"multipart/form-data; boundary=" <> boundary, body}
  end

  defp events(action) do
    Repo.all(from e in AuditEvent, where: e.action == ^action, order_by: e.inserted_at)
  end

  defp json(value), do: value |> JSON.encode!() |> JSON.decode!()
end
