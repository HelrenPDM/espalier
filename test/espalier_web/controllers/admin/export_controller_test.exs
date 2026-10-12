defmodule EspalierWeb.Admin.ExportControllerTest do
  @moduledoc """
  The export routes of task 0016 (step 10; step 13, bullet "Controller").

  - Without a session all three routes answer 401 `unauthenticated`, and a
    learner gets 403 `forbidden` (ASVS 8.2.1).
  - `POST /api/admin/exports` answers 403 `reauth_required` when the
    session's last second factor lies 11 minutes back and 202 with one now
    (README section 6.4, ASVS 7.5.1).
  - An unknown `scorm_version` and a body with an extra member answer 422
    `validation_failed` (ASVS 2.2.1 and 15.3.3); an archived module answers
    404.
  - The download answers 409 `export_not_ready` before the job ran, and 200
    with the zip, `cache-control: no-store` and the generated file name
    after it (ASVS 5.4.1 and 5.4.2).

  Every POST carries a CSRF token of its session. The packages go to the
  shared `EXPORT_DIR` of the tests under the unique id of each export, and
  each test removes them.
  """
  use EspalierWeb.ConnCase, async: true

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Program
  alias Espalier.{Interop, LearningFixtures, Repo}
  alias Espalier.Interop.{Export, ExportWorker}

  setup %{conn: conn} do
    program = LearningFixtures.publish_demo!()
    author = user_with_role_fixture(:author)
    conn = log_in_user(conn, author)

    %{
      conn: conn,
      author: author,
      token: get_session(conn, :user_token),
      program: program,
      module: LearningFixtures.module!(program, 1)
    }
  end

  defp request(conn, module, version \\ "scorm12") do
    json_request(conn, :post, ~p"/api/admin/exports", %{
      module_id: module.id,
      scorm_version: version
    })
  end

  # Runs the job of the export `id` and removes its package when the test
  # exits.
  defp run_job!(id) do
    on_exit(fn -> File.rm(Path.join(Interop.export_dir(), "#{id}.zip")) end)
    assert perform_job(ExportWorker, %{export_id: id}) == :ok
  end

  defp minutes_ago(minutes), do: DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

  describe "the role checks" do
    test "every route answers 401 without a session and 403 forbidden to a learner",
         %{module: module} do
      id = Ecto.UUID.generate()

      cases = [
        {api_conn(), 401, %{"error" => "unauthenticated"}},
        {log_in_user(api_conn(), user_fixture()), 403, %{"error" => "forbidden"}}
      ]

      for {conn, status, body} <- cases do
        response = request(conn, module)
        assert json_response(response, status) == body

        response = json_request(conn, :get, ~p"/api/admin/exports/#{id}")
        assert json_response(response, status) == body

        response = json_request(conn, :get, ~p"/api/admin/exports/#{id}/download")
        assert json_response(response, status) == body
      end

      assert Repo.aggregate(Export, :count) == 0
    end

    test "POST needs a second factor from the last 10 minutes",
         %{conn: conn, token: token, module: module} do
      assert {1, _} = override_session(token, mfa_at: minutes_ago(11))
      response = request(conn, module)
      assert json_response(response, 403) == %{"error" => "reauth_required"}
      assert Repo.aggregate(Export, :count) == 0

      assert {1, _} = override_session(token, mfa_at: DateTime.utc_now(:second))
      response = request(conn, module)
      assert %{"status" => "queued"} = json_response(response, 202)
    end
  end

  describe "POST /api/admin/exports" do
    test "answers 202 with the queued export, its job and the audit event",
         %{conn: conn, author: author, program: program, module: module} do
      response = request(conn, module, "scorm2004")

      assert %{"id" => id} = body = json_response(response, 202)
      assert get_resp_header(response, "location") == ["/api/admin/exports/#{id}"]
      assert get_resp_header(response, "cache-control") == ["no-store"]

      assert body == %{
               "id" => id,
               "module" => %{
                 "id" => module.id,
                 "number" => 1,
                 "title" => module.title,
                 "program" => %{"slug" => program.slug, "title" => program.title}
               },
               "scorm_version" => "scorm2004",
               "status" => "queued",
               "error" => nil,
               "inserted_at" => body["inserted_at"],
               "download_path" => nil
             }

      assert_enqueued(worker: ExportWorker, args: %{export_id: id}, queue: :exports)
      assert Repo.get!(Export, id).requested_by_id == author.id

      assert [event] = Repo.all(from e in AuditEvent, where: e.action == "export.requested")
      assert {event.actor_id, event.subject_id} == {author.id, id}
    end

    test "answers 422 validation_failed for an unknown version and an extra member",
         %{conn: conn, module: module} do
      response = request(conn, module, "scorm3")

      assert json_response(response, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"scorm_version" => ["invalid_enum"]}
             }

      response =
        json_request(conn, :post, ~p"/api/admin/exports", %{
          module_id: module.id,
          scorm_version: "scorm12",
          path: "../../etc/passwd"
        })

      assert json_response(response, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"path" => ["unexpected_field"]}
             }

      response = json_request(conn, :post, ~p"/api/admin/exports", %{scorm_version: "scorm12"})
      assert json_response(response, 422)["error"] == "validation_failed"

      assert Repo.aggregate(Export, :count) == 0
      refute_enqueued(worker: ExportWorker)
    end

    test "answers 404 for an archived or unknown module and a program that is not published",
         %{conn: conn, program: program, module: module} do
      module_2 = LearningFixtures.module!(program, 2)
      now = DateTime.utc_now(:second)

      Repo.update_all(from(m in CatalogModule, where: m.id == ^module_2.id),
        set: [archived_at: now]
      )

      response = request(conn, module_2)
      assert json_response(response, 404) == %{"error" => "not_found"}

      response = request(conn, %{id: Ecto.UUID.generate()})
      assert json_response(response, 404) == %{"error" => "not_found"}

      Repo.update_all(from(p in Program, where: p.id == ^program.id), set: [status: :draft])
      response = request(conn, module)
      assert json_response(response, 404) == %{"error" => "not_found"}

      assert Repo.aggregate(Export, :count) == 0
    end
  end

  describe "GET /api/admin/exports/:id and the download" do
    test "the download answers 409 before the job ran and 200 with the zip after it",
         %{conn: conn, program: program, module: module} do
      %{"id" => id} = conn |> request(module) |> json_response(202)

      response = json_request(conn, :get, ~p"/api/admin/exports/#{id}/download")
      assert json_response(response, 409) == %{"error" => "export_not_ready"}
      assert get_resp_header(response, "cache-control") == ["no-store"]

      run_job!(id)

      response = json_request(conn, :get, ~p"/api/admin/exports/#{id}")

      assert %{"status" => "done", "error" => nil, "download_path" => path} =
               json_response(response, 200)

      assert path == "/api/admin/exports/#{id}/download"

      response = json_request(conn, :get, path)
      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["application/zip"]
      assert get_resp_header(response, "cache-control") == ["no-store"]

      assert get_resp_header(response, "content-disposition") == [
               ~s(attachment; filename="#{program.slug}-module-1-scorm12.zip")
             ]

      assert {:ok, entries} = :zip.list_dir(response.resp_body)
      names = for {:zip_file, name, _, _, _, _} <- entries, do: List.to_string(name)
      assert "imsmanifest.xml" in names
      assert "LICENSE" in names and "NOTICE" in names
    end

    test "a failed export answers 409 on the download and shows its error",
         %{conn: conn, module: module} do
      %{"id" => id} = conn |> request(module) |> json_response(202)

      Repo.get!(Export, id)
      |> Export.status_changeset(%{status: :failed, error: "The module is no longer published."})
      |> Repo.update!()

      response = json_request(conn, :get, ~p"/api/admin/exports/#{id}")

      assert %{
               "status" => "failed",
               "error" => "The module is no longer published.",
               "download_path" => nil
             } = json_response(response, 200)

      response = json_request(conn, :get, ~p"/api/admin/exports/#{id}/download")
      assert json_response(response, 409) == %{"error" => "export_not_ready"}
    end

    test "an unknown id answers 404 and a malformed id 422", %{conn: conn} do
      id = Ecto.UUID.generate()

      for path <- [~p"/api/admin/exports/#{id}", ~p"/api/admin/exports/#{id}/download"] do
        assert json_response(json_request(conn, :get, path), 404) == %{"error" => "not_found"}
      end

      for path <- ["/api/admin/exports/not-a-uuid", "/api/admin/exports/not-a-uuid/download"] do
        assert json_response(json_request(conn, :get, path), 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"id" => ["invalid_format"]}
               }
      end
    end
  end
end
