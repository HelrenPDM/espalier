defmodule EspalierWeb.Admin.PackDraftFileControllerTest do
  @moduledoc """
  The file routes of the pack workbench (task 0016a, steps 9 and 14): the
  read of a file with its content, and the create, update, rename and
  delete of a file with the `lock_version` of the draft, each with the
  answers of step 9.

  - A path outside the pack layout answers 422 `validation_failed` with
    `fields.path` `["invalid_path"]`, and a path that the draft holds
    already answers 409 `path_taken` (ASVS 2.2.1, 5.2.2 and 5.3.2).
  - A content with U+0000 answers 422 with `fields.content`
    `["nul_character"]`, a content above 1,048,576 bytes 422 with
    `["too_large"]`, and a content above 1,048,576 characters 422 from the
    request schema (ASVS 5.2.1 and 15.3.3).
  - A change sent with a `lock_version` that differs from the stored one
    answers 409 `stale_draft` with the stored version (ASVS 2.3.2).
  - No file route writes an audit event (step 10).

  Every POST, PUT, PATCH and DELETE request carries a CSRF token of its
  session (`json_request/5` fetches it with `with_csrf_token/1`).
  """
  # The creation of a draft takes a transaction-scoped advisory lock, which
  # the sandbox transaction of a test holds until the test ends, so the
  # modules that create drafts run one after the other.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias Espalier.{Repo, Workbench}
  alias Espalier.Workbench.{PackDraft, PackDraftFile}

  @max_file_bytes 1_048_576

  setup %{conn: conn} do
    author = user_with_role_fixture(:author)
    scope = %{Scope.for_user(author) | roles: [:learner, :author]}
    {:ok, draft} = Workbench.create_empty(scope, "New pack")
    %{conn: log_in_user(conn, author), scope: scope, draft: draft}
  end

  describe "GET /api/admin/pack-drafts/:id/files/:file_id" do
    test "answers the file with its content, bytes and the lock_version of the draft", %{
      conn: conn,
      draft: draft
    } do
      file = stored_file!(draft, "pack.yaml")

      conn = json_request(conn, :get, files_path(draft, file))
      body = json_response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert %{
               "id" => id,
               "path" => "pack.yaml",
               "content" => content,
               "bytes" => bytes,
               "updated_at" => updated_at,
               "lock_version" => 1
             } = body

      assert id == file.id
      assert content == file.content
      assert content =~ "key: new-pack"
      assert bytes == byte_size(file.content)
      assert is_binary(updated_at)

      assert body |> Map.keys() |> Enum.sort() ==
               ~w(bytes content id lock_version path updated_at)
    end

    test "answers 404 for a file of another draft and for an unknown file", %{
      conn: conn,
      scope: scope,
      draft: draft
    } do
      {:ok, other} = Workbench.create_empty(scope, "Other pack")
      foreign = stored_file!(other, "pack.yaml")

      conn = json_request(conn, :get, files_path(draft, foreign))
      assert json_response(conn, 404) == %{"error" => "not_found"}

      conn = json_request(conn, :get, files_path(draft, Ecto.UUID.generate()))
      assert json_response(conn, 404) == %{"error" => "not_found"}

      conn = json_request(conn, :get, "/api/admin/pack-drafts/#{draft.id}/files/not-a-uuid")

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"file_id" => ["invalid_format"]}
             }
    end
  end

  describe "POST /api/admin/pack-drafts/:id/files" do
    test "answers 201 with the draft and the new lock_version", %{conn: conn, draft: draft} do
      conn = create_file(conn, draft, %{path: "sources.yaml", content: "[]\n", lock_version: 1})

      body = json_response(conn, 201)
      assert body["id"] == draft.id
      assert body["lock_version"] == 2
      assert "sources.yaml" in Enum.map(body["files"], & &1["path"])
      assert body["usage"]["files"] == 7

      assert %PackDraftFile{content: "[]\n"} = stored_file!(draft, "sources.yaml")
      assert Repo.get!(PackDraft, draft.id).lock_version == 2
    end

    test "answers 422 invalid_path for a path outside the pack layout", %{
      conn: conn,
      draft: draft
    } do
      for path <- ["README.md", "../pack.yaml", "modules/a/notes.yaml", "modules/A/module.yaml"] do
        conn = create_file(conn, draft, %{path: path, content: "", lock_version: 1})

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"path" => ["invalid_path"]}
               },
               path
      end

      assert_unchanged(draft)
    end

    test "answers 409 path_taken for a path that the draft holds", %{conn: conn, draft: draft} do
      conn = create_file(conn, draft, %{path: "stations.yaml", content: "[]\n", lock_version: 1})
      assert json_response(conn, 409) == %{"error" => "path_taken"}
      assert_unchanged(draft)
    end

    test "answers 422 nul_character for a content with U+0000", %{conn: conn, draft: draft} do
      conn =
        create_file(conn, draft, %{path: "sources.yaml", content: "a\u0000b", lock_version: 1})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"content" => ["nul_character"]}
             }

      assert_unchanged(draft)
    end

    test "answers 422 too_large for a content of more than 1,048,576 bytes", %{
      conn: conn,
      draft: draft
    } do
      # Two bytes per character: within maxLength of the schema, above the
      # byte limit of the context.
      content = String.duplicate("ä", div(@max_file_bytes, 2) + 1)
      assert String.length(content) <= @max_file_bytes
      assert byte_size(content) > @max_file_bytes

      conn = create_file(conn, draft, %{path: "sources.yaml", content: content, lock_version: 1})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"content" => ["too_large"]}
             }

      assert_unchanged(draft)
    end

    test "stores a content of exactly 1,048,576 bytes", %{conn: conn, draft: draft} do
      content = String.duplicate("a", @max_file_bytes)
      conn = create_file(conn, draft, %{path: "sources.yaml", content: content, lock_version: 1})

      assert json_response(conn, 201)["lock_version"] == 2
      assert byte_size(stored_file!(draft, "sources.yaml").content) == @max_file_bytes
    end

    test "answers 422 from the schema for a content above 1,048,576 characters", %{
      conn: conn,
      draft: draft
    } do
      content = String.duplicate("a", @max_file_bytes + 1)
      conn = create_file(conn, draft, %{path: "sources.yaml", content: content, lock_version: 1})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"content" => ["max_length"]}
             }

      assert_unchanged(draft)
    end

    test "answers 422 for a path above 527 characters and an extra member", %{
      conn: conn,
      draft: draft
    } do
      long = "modules/" <> String.duplicate("a", 520) <> "/module.yaml"
      conn = create_file(conn, draft, %{path: long, content: "", lock_version: 1})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"path" => ["max_length"]}
             }

      conn =
        create_file(conn, draft, %{
          path: "sources.yaml",
          content: "",
          lock_version: 1,
          pack_draft_id: Ecto.UUID.generate()
        })

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"pack_draft_id" => ["unexpected_field"]}
             }

      assert_unchanged(draft)
    end

    test "answers 409 stale_draft with the stored lock_version", %{conn: conn, draft: draft} do
      conn = create_file(conn, draft, %{path: "sources.yaml", content: "[]\n", lock_version: 5})
      assert json_response(conn, 409) == %{"error" => "stale_draft", "lock_version" => 1}
      assert_unchanged(draft)
    end

    test "answers 404 for an unknown draft", %{conn: conn} do
      conn =
        json_request(conn, :post, ~p"/api/admin/pack-drafts/#{Ecto.UUID.generate()}/files", %{
          path: "sources.yaml",
          content: "[]\n",
          lock_version: 1
        })

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "PUT /api/admin/pack-drafts/:id/files/:file_id" do
    test "answers 200 with the new lock_version", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "stations.yaml")
      content = file.content <> "\n"

      conn =
        json_request(conn, :put, files_path(draft, file), %{content: content, lock_version: 1})

      body = json_response(conn, 200)
      assert body["lock_version"] == 2
      assert Enum.find(body["files"], &(&1["id"] == file.id))["bytes"] == byte_size(content)
      assert stored_file!(draft, "stations.yaml").content == content
    end

    test "two saves with the same lock_version give 200 and 409 stale_draft", %{
      conn: conn,
      draft: draft
    } do
      file = stored_file!(draft, "stations.yaml")

      conn =
        json_request(conn, :put, files_path(draft, file), %{content: "first\n", lock_version: 1})

      assert json_response(conn, 200)["lock_version"] == 2

      conn =
        json_request(conn, :put, files_path(draft, file), %{content: "second\n", lock_version: 1})

      assert json_response(conn, 409) == %{"error" => "stale_draft", "lock_version" => 2}
      assert stored_file!(draft, "stations.yaml").content == "first\n"
      assert Repo.get!(PackDraft, draft.id).lock_version == 2
    end

    test "a save of pack.yaml updates title and pack_key", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "pack.yaml")
      content = String.replace(file.content, "key: new-pack", "key: renamed-pack")
      content = String.replace(content, "title: New pack", "title: Renamed pack")

      conn =
        json_request(conn, :put, files_path(draft, file), %{content: content, lock_version: 1})

      assert %{"title" => "Renamed pack", "pack_key" => "renamed-pack", "lock_version" => 2} =
               json_response(conn, 200)
    end

    test "answers 422 for a content with U+0000 and 404 for a file of another draft", %{
      conn: conn,
      scope: scope,
      draft: draft
    } do
      file = stored_file!(draft, "stations.yaml")

      conn =
        json_request(conn, :put, files_path(draft, file), %{content: "\u0000", lock_version: 1})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"content" => ["nul_character"]}
             }

      {:ok, other} = Workbench.create_empty(scope, "Other pack")
      foreign = stored_file!(other, "stations.yaml")

      conn =
        json_request(conn, :put, files_path(draft, foreign), %{content: "x\n", lock_version: 1})

      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert_unchanged(draft)
      assert stored_file!(other, "stations.yaml").content == foreign.content
    end
  end

  describe "PATCH /api/admin/pack-drafts/:id/files/:file_id" do
    test "answers 200 with the new path", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "stations.yaml")

      conn =
        json_request(conn, :patch, files_path(draft, file), %{
          path: "sources.yaml",
          lock_version: 1
        })

      body = json_response(conn, 200)
      assert body["lock_version"] == 2
      paths = Enum.map(body["files"], & &1["path"])
      assert "sources.yaml" in paths
      refute "stations.yaml" in paths
      assert Repo.get!(PackDraftFile, file.id).path == "sources.yaml"
    end

    test "answers 409 path_taken and leaves lock_version unchanged", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "stations.yaml")

      conn =
        json_request(conn, :patch, files_path(draft, file), %{path: "pack.yaml", lock_version: 1})

      assert json_response(conn, 409) == %{"error" => "path_taken"}
      assert_unchanged(draft)
      assert Repo.get!(PackDraftFile, file.id).path == "stations.yaml"
    end

    test "answers 422 invalid_path for a path outside the pack layout", %{
      conn: conn,
      draft: draft
    } do
      file = stored_file!(draft, "stations.yaml")

      conn =
        json_request(conn, :patch, files_path(draft, file), %{path: "README.md", lock_version: 1})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"path" => ["invalid_path"]}
             }

      assert_unchanged(draft)
    end

    test "answers 409 stale_draft with the stored lock_version", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "stations.yaml")

      conn =
        json_request(conn, :patch, files_path(draft, file), %{
          path: "sources.yaml",
          lock_version: 2
        })

      assert json_response(conn, 409) == %{"error" => "stale_draft", "lock_version" => 1}
      assert_unchanged(draft)
    end

    test "a rename away from pack.yaml clears pack_key", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "pack.yaml")

      conn =
        json_request(conn, :patch, files_path(draft, file), %{
          path: "sources.yaml",
          lock_version: 1
        })

      assert %{"pack_key" => nil, "title" => "New pack", "lock_version" => 2} =
               json_response(conn, 200)
    end
  end

  describe "DELETE /api/admin/pack-drafts/:id/files/:file_id" do
    test "answers 200 with the draft without the file", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "stations.yaml")

      conn = json_request(conn, :delete, delete_path(draft, file, 1))

      body = json_response(conn, 200)
      assert body["lock_version"] == 2
      refute "stations.yaml" in Enum.map(body["files"], & &1["path"])
      assert body["usage"]["files"] == 5
      assert Repo.get(PackDraftFile, file.id) == nil
    end

    test "answers 422 without lock_version", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "stations.yaml")

      conn = json_request(conn, :delete, files_path(draft, file))

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"lock_version" => ["missing_field"]}
             }

      assert Repo.get(PackDraftFile, file.id) != nil
      assert_unchanged(draft)
    end

    test "answers 409 stale_draft with the stored lock_version", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "stations.yaml")

      conn = json_request(conn, :delete, delete_path(draft, file, 3))

      assert json_response(conn, 409) == %{"error" => "stale_draft", "lock_version" => 1}
      assert Repo.get(PackDraftFile, file.id) != nil
      assert_unchanged(draft)
    end

    test "a delete of pack.yaml clears pack_key", %{conn: conn, draft: draft} do
      file = stored_file!(draft, "pack.yaml")

      conn = json_request(conn, :delete, delete_path(draft, file, 1))
      assert %{"pack_key" => nil, "lock_version" => 2} = json_response(conn, 200)
    end
  end

  describe "the limits of a draft" do
    test "stores a lesson whose path holds more than 255 bytes", %{conn: conn, draft: draft} do
      path =
        "modules/" <>
          String.duplicate("d", 200) <> "/lessons/" <> String.duplicate("k", 200) <> ".md"

      conn = create_file(conn, draft, %{path: path, content: "", lock_version: 1})

      assert %{"lock_version" => 2} = json_response(conn, 201)
      assert stored_file!(draft, path).content == ""
    end

    test "answers 422 invalid_path for a component of more than 255 bytes", %{
      conn: conn,
      draft: draft
    } do
      path = "modules/" <> String.duplicate("d", 256) <> "/module.yaml"
      conn = create_file(conn, draft, %{path: path, content: "", lock_version: 1})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"path" => ["invalid_path"]}
             }
    end

    test "a file beyond max_files answers 409 too_many_files", %{conn: conn, draft: draft} do
      fill!(draft, Workbench.max_files() - 6, fn n -> {"modules/a/lessons/l#{n}.md", "x"} end)

      conn = create_file(conn, draft, %{path: "sources.yaml", content: "[]\n", lock_version: 1})

      assert json_response(conn, 409) == %{"error" => "too_many_files"}
      assert Repo.get!(PackDraft, draft.id).lock_version == 1
    end

    test "a save beyond max_draft_bytes answers 409 draft_too_large", %{conn: conn, draft: draft} do
      put_setting(:pack_upload_max_mb, 1)
      big = :binary.copy("x", @max_file_bytes)
      fill!(draft, 4, fn n -> {"modules/a/lessons/l#{n}.md", big} end)
      file = stored_file!(draft, "stations.yaml")

      conn = json_request(conn, :put, files_path(draft, file), %{content: big, lock_version: 1})

      assert json_response(conn, 409) == %{"error" => "draft_too_large"}
      assert stored_file!(draft, "stations.yaml").content == file.content
    end
  end

  describe "the audit log" do
    test "no file route writes an audit event", %{conn: conn, draft: draft} do
      before = Repo.all(from e in AuditEvent, select: e.action)
      assert "pack_draft.created" in before

      conn = create_file(conn, draft, %{path: "sources.yaml", content: "[]\n", lock_version: 1})
      %{"files" => files} = json_response(conn, 201)
      sources = Enum.find(files, &(&1["path"] == "sources.yaml"))

      conn =
        json_request(conn, :put, files_path(draft, sources["id"]), %{
          content: "[]\n\n",
          lock_version: 2
        })

      assert json_response(conn, 200)["lock_version"] == 3

      conn =
        json_request(conn, :patch, files_path(draft, sources["id"]), %{
          path: "glossary.yaml",
          lock_version: 3
        })

      assert json_response(conn, 200)["lock_version"] == 4

      conn = json_request(conn, :get, files_path(draft, sources["id"]))
      assert json_response(conn, 200)["path"] == "glossary.yaml"

      conn = json_request(conn, :delete, delete_path(draft, sources["id"], 4))
      assert json_response(conn, 200)["lock_version"] == 5

      assert Repo.all(from e in AuditEvent, select: e.action) == before
    end
  end

  ## Helpers

  defp files_path(draft, %PackDraftFile{id: id}), do: files_path(draft, id)

  defp files_path(draft, file_id) when is_binary(file_id),
    do: ~p"/api/admin/pack-drafts/#{draft.id}/files/#{file_id}"

  defp delete_path(draft, file, lock_version),
    do: files_path(draft, file) <> "?" <> URI.encode_query(%{lock_version: lock_version})

  defp create_file(conn, draft, body),
    do: json_request(conn, :post, ~p"/api/admin/pack-drafts/#{draft.id}/files", body)

  defp stored_file!(draft, path),
    do: Repo.get_by!(PackDraftFile, pack_draft_id: draft.id, path: path)

  # Adds `count` files to the draft directly, as {path, content} of `file`.
  defp fill!(draft, count, file) do
    now = DateTime.utc_now(:second)

    rows =
      for n <- 1..count do
        {path, content} = file.(n)

        %{
          id: Ecto.UUID.generate(),
          pack_draft_id: draft.id,
          path: path,
          content: content,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(PackDraftFile, rows)
  end

  # The draft keeps lock_version 1 and the six files of the skeleton.
  defp assert_unchanged(draft) do
    assert Repo.get!(PackDraft, draft.id).lock_version == 1

    assert Repo.aggregate(from(f in PackDraftFile, where: f.pack_draft_id == ^draft.id), :count) ==
             6
  end
end
