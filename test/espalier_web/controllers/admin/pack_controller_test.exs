defmodule EspalierWeb.Admin.PackControllerTest do
  # put_setting/2 changes the application environment, hence async: false.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  import Espalier.PackFixtures,
    only: [copy_pack!: 1, demo_path: 0, line_of!: 3, read!: 2, read_yaml!: 2, write!: 3]

  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.{Alignment, PackImport, Program}
  alias Espalier.Catalog.Pack.Importer
  alias Espalier.{Repo, ZipFixtures}

  @key "ai-assistant-basics-demo"
  @items1 "modules/01-basics/items.yaml"
  @assessment1 "modules/01-basics/assessment.yaml"
  @objectives2 "modules/02-checking/objectives.yaml"

  setup %{conn: conn} do
    author = user_with_role_fixture(:author)
    %{conn: log_in_user(conn, author), author: author}
  end

  describe "POST /api/admin/packs" do
    test "imports the demo pack and answers 201 with the pack view", %{conn: conn, author: author} do
      conn = upload_request(conn, ~p"/api/admin/packs", ZipFixtures.zip_dir!(demo_path()))

      assert %{"id" => id, "status" => "validated"} = body = json_response(conn, 201)
      assert get_resp_header(conn, "location") == ["/api/admin/packs/#{id}"]
      assert body["pack_key"] == @key
      assert body["pack_version"] == "1.0.0"
      assert body["report"] == %{"errors" => [], "warnings" => []}
      assert %{"key" => @key, "alignment" => "strict"} = body["payload"]

      pack_import = Repo.get!(PackImport, id)
      assert pack_import.status == :validated
      assert pack_import.imported_by_id == author.id

      assert [event] = events("pack.imported")
      assert event.actor_id == author.id
      assert event.subject_id == id
      assert event.details == %{"pack_key" => @key, "status" => "validated"}
    end

    test "accepts a pack in one top-level directory of the archive", %{conn: conn} do
      archive = ZipFixtures.zip_dir!(demo_path(), root: "ai-assistant-basics-demo")
      conn = upload_request(conn, ~p"/api/admin/packs", archive)

      assert %{"status" => "validated", "pack_key" => @key} = json_response(conn, 201)
    end

    test "answers 413 above PACK_UPLOAD_MAX_MB", %{conn: conn} do
      put_setting(:pack_upload_max_mb, 1)
      {content_type, body} = multipart(:binary.copy("x", 1_048_576 + 1))
      conn = conn |> with_csrf_token() |> put_req_header("content-type", content_type)

      {413, _headers, resp_body} =
        assert_error_sent(413, fn ->
          dispatch(conn, @endpoint, :post, ~p"/api/admin/packs", body)
        end)

      assert JSON.decode!(resp_body) == %{"error" => "request_too_large"}
      assert Repo.aggregate(PackImport, :count) == 0
    end

    test "reads an upload just below PACK_UPLOAD_MAX_MB", %{conn: conn} do
      put_setting(:pack_upload_max_mb, 1)
      archive = ZipFixtures.zip_dir!(demo_path())
      assert byte_size(archive) < 1_048_576

      conn = upload_request(conn, ~p"/api/admin/packs", archive)
      assert %{"status" => "validated"} = json_response(conn, 201)
    end

    test "answers 415 for a JSON body and for a bare zip body", %{conn: conn} do
      conn = json_request(conn, :post, ~p"/api/admin/packs", %{"file" => "UEsDBA=="})
      assert json_response(conn, 415) == %{"error" => "unsupported_media_type"}

      conn =
        upload_request(conn, ~p"/api/admin/packs", ZipFixtures.zip_dir!(demo_path()),
          content_type: "application/zip"
        )

      assert json_response(conn, 415) == %{"error" => "unsupported_media_type"}
      assert Repo.aggregate(PackImport, :count) == 0
    end

    test "answers 422 for a body without the field file", %{conn: conn} do
      conn =
        upload_request(conn, ~p"/api/admin/packs", ZipFixtures.zip_dir!(demo_path()),
          field: "archive"
        )

      assert %{"error" => "validation_failed"} = json_response(conn, 422)
      assert Repo.aggregate(PackImport, :count) == 0
    end

    test "answers 422 for a field file that holds text instead of a file", %{conn: conn} do
      # A form field without a filename reaches the controller as a string,
      # which the binary format of the request schema also accepts.
      {content_type, body} = multipart("not a file", filename: nil)
      conn = conn |> with_csrf_token() |> put_req_header("content-type", content_type)
      conn = dispatch(conn, @endpoint, :post, ~p"/api/admin/packs", body)

      assert %{"error" => "validation_failed"} = json_response(conn, 422)
      assert Repo.aggregate(PackImport, :count) == 0
    end

    test "answers 422 archive_rejected for an entry ../../etc/passwd", %{conn: conn} do
      archive =
        ZipFixtures.build([
          ZipFixtures.entry("pack.yaml", "schema: 1\n"),
          ZipFixtures.entry("../../etc/passwd", "root::0:0::/:/bin/sh\n")
        ])

      conn = upload_request(conn, ~p"/api/admin/packs", archive)

      assert json_response(conn, 422) == %{
               "error" => "archive_rejected",
               "report" => %{
                 "errors" => [
                   %{
                     "file" => "../../etc/passwd",
                     "line" => nil,
                     "message" => "the name contains a .. component"
                   }
                 ],
                 "warnings" => []
               }
             }

      assert Repo.aggregate(PackImport, :count) == 0
      assert events("pack.imported") == []
    end

    test "answers 422 archive_rejected for a symlink entry", %{conn: conn} do
      archive =
        ZipFixtures.build([
          ZipFixtures.entry("pack.yaml", "schema: 1\n"),
          ZipFixtures.symlink_entry("modules", "/etc")
        ])

      conn = upload_request(conn, ~p"/api/admin/packs", archive)

      assert json_response(conn, 422) == %{
               "error" => "archive_rejected",
               "report" => %{
                 "errors" => [
                   %{
                     "file" => "modules",
                     "line" => nil,
                     "message" => "the entry is a symbolic link"
                   }
                 ],
                 "warnings" => []
               }
             }

      assert Repo.aggregate(PackImport, :count) == 0
    end
  end

  describe "pack alignment" do
    test "the demo pack: strict, 24 matrix rows and no finding", %{conn: conn} do
      pack = copy_pack!(demo_path())
      {conn, id} = upload!(conn, pack)

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{id}")
      body = json_response(conn, 200)

      assert body["status"] == "validated"
      alignment = body["alignment"]
      assert alignment["mode"] == "strict"
      assert alignment["errors"] == []
      assert alignment["warnings"] == []

      assert length(alignment["matrix"]) == 24
      assert alignment["matrix"] == json(Alignment.matrix(Repo.get!(PackImport, id).payload))

      assert alignment["matrix"] |> Enum.map(& &1["module"]) |> Enum.frequencies() == %{
               1 => 12,
               2 => 12
             }
    end

    test "strict: an exam item without objectives fails with one check 2 error", %{conn: conn} do
      pack = copy_pack!(demo_path())
      key = changed_exam_item(pack)
      line = line_of!(pack, @items1, "- key: #{key}")
      drop_objectives!(pack, @items1, key)

      {conn, id} = upload!(conn, pack, "failed")

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{id}")
      body = json_response(conn, 200)

      assert body["status"] == "failed"
      assert body["payload"] == nil

      assert [
               %{
                 "check" => 2,
                 "module" => 1,
                 "key" => ^key,
                 "file" => @items1,
                 "line" => ^line,
                 "message" => message
               } = finding
             ] = body["alignment"]["errors"]

      assert is_binary(message) and message != ""
      assert body["alignment"]["warnings"] == []
      # The importer stores no payload for a failed import.
      assert body["alignment"]["mode"] == nil
      assert body["alignment"]["matrix"] == nil
      # The report keeps the entry next to the alignment section.
      assert finding in body["report"]["errors"]

      conn = json_request(conn, :post, ~p"/api/admin/packs/#{id}/publish")
      assert json_response(conn, 409) == %{"error" => "not_publishable"}
      assert Repo.aggregate(Program, :count) == 0
    end

    test "warn: the same pack is validated, lists the warning and publishes", %{
      conn: conn,
      author: author
    } do
      pack = copy_pack!(demo_path())
      key = changed_exam_item(pack)
      line = line_of!(pack, @items1, "- key: #{key}")
      drop_objectives!(pack, @items1, key)
      write!(pack, "pack.yaml", read!(pack, "pack.yaml") <> "alignment: warn\n")

      {conn, id} = upload!(conn, pack)

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{id}")
      body = json_response(conn, 200)

      assert body["status"] == "validated"
      assert body["alignment"]["mode"] == "warn"
      assert body["alignment"]["errors"] == []

      assert [
               %{
                 "check" => 2,
                 "module" => 1,
                 "key" => ^key,
                 "file" => @items1,
                 "line" => ^line
               }
             ] = body["alignment"]["warnings"]

      assert length(body["alignment"]["matrix"]) == 24

      conn = json_request(conn, :post, ~p"/api/admin/packs/#{id}/publish")
      assert %{"id" => ^id, "status" => "published"} = json_response(conn, 200)
      assert %Program{status: :published} = Repo.get_by(Program, slug: @key)

      assert [event] = events("pack.published")
      assert event.actor_id == author.id
      assert event.subject_id == id
    end

    test "a pack whose only finding comes from check 4 is validated and publishes", %{
      conn: conn
    } do
      pack = copy_pack!(demo_path())
      line = line_of!(pack, @objectives2, "- key: m2-method-release-check")

      # Its only evidence is the checklist_drill item, which fits no `know`.
      edit_entry!(pack, @objectives2, "m2-method-release-check", fn lines ->
        Enum.map(lines, &String.replace(&1, ~r/^  depth: .*$/, "  depth: know"))
      end)

      assert %{"depth" => "know"} =
               pack
               |> read_yaml!(@objectives2)
               |> Enum.find(&(&1["key"] == "m2-method-release-check"))

      {conn, id} = upload!(conn, pack)

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{id}")
      body = json_response(conn, 200)

      assert body["status"] == "validated"
      assert body["alignment"]["errors"] == []

      assert [
               %{
                 "check" => 4,
                 "module" => 2,
                 "key" => "m2-method-release-check",
                 "file" => @objectives2,
                 "line" => ^line
               }
             ] = body["alignment"]["warnings"]

      conn = json_request(conn, :post, ~p"/api/admin/packs/#{id}/publish")
      assert %{"status" => "published"} = json_response(conn, 200)
    end

    test "a YAML syntax error answers mode and matrix as null", %{conn: conn} do
      pack = copy_pack!(demo_path())
      write!(pack, "pack.yaml", read!(pack, "pack.yaml") <> "broken: [unclosed\n")

      {conn, id} = upload!(conn, pack, "failed")

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{id}")
      body = json_response(conn, 200)

      assert body["status"] == "failed"
      assert [_ | _] = body["report"]["errors"]
      assert Enum.any?(body["report"]["errors"], &(&1["file"] == "pack.yaml"))

      assert body["alignment"] == %{
               "mode" => nil,
               "matrix" => nil,
               "errors" => [],
               "warnings" => []
             }
    end

    test "a validated import whose payload fails the checks answers 409 alignment_errors", %{
      conn: conn,
      author: author
    } do
      key = changed_exam_item(copy_pack!(demo_path()))

      payload =
        update_items(demo_payload(), fn items -> Enum.map(items, &without_objectives(&1, key)) end)

      pack_import =
        Repo.insert!(%PackImport{
          pack_key: @key,
          pack_version: payload["version"],
          status: :validated,
          report: %{"errors" => [], "warnings" => []},
          payload: payload,
          imported_by_id: author.id
        })

      conn = json_request(conn, :post, ~p"/api/admin/packs/#{pack_import.id}/publish")

      assert %{
               "error" => "alignment_errors",
               "findings" => [
                 %{
                   "check" => 2,
                   "module" => 1,
                   "file" => "items.yaml",
                   "key" => ^key,
                   "message" => message
                 } = finding
               ]
             } = json_response(conn, 409)

      assert is_binary(message)
      assert finding |> Map.keys() |> Enum.sort() == ~w(check file key message module)
      assert Repo.aggregate(Program, :count) == 0
      assert Repo.get!(PackImport, pack_import.id).status == :validated
      assert events("pack.published") == []
    end
  end

  describe "GET /api/admin/packs/:id" do
    test "returns the payload for a validated import only", %{conn: conn} do
      {conn, validated} = upload!(conn, copy_pack!(demo_path()))

      failed_pack = copy_pack!(demo_path())
      write!(failed_pack, "pack.yaml", read!(failed_pack, "pack.yaml") <> "broken: [unclosed\n")
      {conn, failed} = upload!(conn, failed_pack, "failed")

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{validated}")
      assert %{"modules" => [_, _]} = json_response(conn, 200)["payload"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{failed}")
      assert json_response(conn, 200)["payload"] == nil

      conn = json_request(conn, :post, ~p"/api/admin/packs/#{validated}/publish")
      assert json_response(conn, 200)["status"] == "published"

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{validated}")
      assert %{"status" => "published", "payload" => nil} = json_response(conn, 200)

      # A published import is no longer validated.
      conn = json_request(conn, :post, ~p"/api/admin/packs/#{validated}/publish")
      assert json_response(conn, 409) == %{"error" => "not_publishable"}
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      unknown = Ecto.UUID.generate()

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{unknown}")
      assert json_response(conn, 404) == %{"error" => "not_found"}

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{unknown}/diff")
      assert json_response(conn, 404) == %{"error" => "not_found"}

      conn = json_request(conn, :post, ~p"/api/admin/packs/#{unknown}/publish")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "GET /api/admin/packs/:id/diff" do
    test "lists an archived key after an item is removed from the payload", %{
      conn: conn,
      author: author
    } do
      {conn, id} = upload!(conn, copy_pack!(demo_path()))
      conn = json_request(conn, :post, ~p"/api/admin/packs/#{id}/publish")
      assert json_response(conn, 200)["status"] == "published"

      payload =
        update_items(demo_payload(), fn items ->
          Enum.reject(items, &(&1["key"] == "m1-fluent-figure"))
        end)

      pack_import =
        Repo.insert!(%PackImport{
          pack_key: @key,
          pack_version: payload["version"],
          status: :validated,
          report: %{"errors" => [], "warnings" => []},
          payload: payload,
          imported_by_id: author.id
        })

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{pack_import.id}/diff")
      diff = json_response(conn, 200)

      assert diff["items"]["archived"] == ["m1-fluent-figure"]
      assert diff["items"]["added"] == []

      assert diff |> Map.keys() |> Enum.sort() ==
               Enum.sort(~w(modules lessons learning_objectives items rules assessments
                            qualifications formats sources segments glossary_terms))

      assert %{"added" => [], "archived" => [], "changed" => changed, "changed_fields" => fields} =
               diff["learning_objectives"]

      # The objective of the removed item loses it from its evidence.
      assert changed == ["m1-subject-next-word"]
      assert fields == %{"m1-subject-next-word" => ["items"]}
    end

    test "answers 409 not_publishable for an import without payload", %{conn: conn} do
      pack = copy_pack!(demo_path())
      write!(pack, "pack.yaml", read!(pack, "pack.yaml") <> "broken: [unclosed\n")
      {conn, id} = upload!(conn, pack, "failed")

      conn = json_request(conn, :get, ~p"/api/admin/packs/#{id}/diff")
      assert json_response(conn, 409) == %{"error" => "not_publishable"}
    end
  end

  ## Helpers

  # Zips `pack` with :zip.create/3, uploads it and asserts 201 with `status`.
  defp upload!(conn, pack, status \\ "validated") do
    conn = upload_request(conn, ~p"/api/admin/packs", ZipFixtures.zip_dir!(pack))
    assert %{"id" => id, "status" => ^status} = json_response(conn, 201)
    {conn, id}
  end

  # A multipart/form-data body with `content` in the field `file`; with
  # `filename: nil` the part is a plain form field.
  defp multipart(content, opts \\ []) do
    boundary = "espalier-test-#{System.unique_integer([:positive])}"

    disposition =
      case Keyword.get(opts, :filename, "pack.zip") do
        nil ->
          ~s(Content-Disposition: form-data; name="file"\r\n\r\n)

        name ->
          ~s(Content-Disposition: form-data; name="file"; filename="#{name}"\r\n) <>
            "Content-Type: application/zip\r\n\r\n"
      end

    body =
      IO.iodata_to_binary([
        "--#{boundary}\r\n",
        disposition,
        content,
        "\r\n--#{boundary}--\r\n"
      ])

    {"multipart/form-data; boundary=" <> boundary, body}
  end

  # The changed exam item of task 0015, step 19: the first item in the
  # `items` list of `module-1-exam` whose objective a second evidence item
  # also names, another item of the exam or a practice item of module 1
  # other than the poll.
  defp changed_exam_item(pack) do
    %{"items" => exam_keys} =
      pack |> read_yaml!(@assessment1) |> Enum.find(&(&1["key"] == "module-1-exam"))

    items = read_yaml!(pack, @items1)

    key =
      Enum.find(exam_keys, fn key ->
        objectives = items |> Enum.find(&(&1["key"] == key)) |> Map.get("objectives", [])

        Enum.any?(items, fn other ->
          other["key"] != key and other["kind"] != "poll" and
            Enum.any?(Map.get(other, "objectives", []), &(&1 in objectives))
        end)
      end)

    assert is_binary(key), "the demo pack holds no changed exam item"
    key
  end

  # Removes the `objectives` line of the entry `key` in the YAML list `rel`,
  # so that every other line keeps its number.
  defp drop_objectives!(pack, rel, key) do
    edit_entry!(pack, rel, key, fn lines ->
      kept = Enum.reject(lines, &String.starts_with?(&1, "  objectives:"))
      assert length(kept) == length(lines) - 1, "the entry #{key} has no objectives line"
      kept
    end)
  end

  # Applies `fun` to the lines of the entry `key` in the YAML list `rel`
  # after its `- key:` line, up to the next entry.
  defp edit_entry!(pack, rel, key, fun) do
    lines = pack |> read!(rel) |> String.split("\n")
    start = Enum.find_index(lines, &(&1 == "- key: #{key}"))
    assert is_integer(start), "#{rel} holds no entry #{key}"

    {before, [first | tail]} = Enum.split(lines, start)
    {body, others} = Enum.split_while(tail, &(not String.starts_with?(&1, "- ")))
    write!(pack, rel, Enum.join(before ++ [first | fun.(body)] ++ others, "\n"))
  end

  defp demo_payload do
    {:ok, %PackImport{status: :validated, payload: payload}} = Importer.import(demo_path(), nil)
    payload
  end

  # Applies `fun` to the items list of every module of `payload`.
  defp update_items(payload, fun) do
    update_in(payload["modules"], fn modules ->
      Enum.map(modules, &Map.update!(&1, "items", fun))
    end)
  end

  defp without_objectives(%{"key" => key} = item, key), do: Map.put(item, "objectives", [])
  defp without_objectives(item, _key), do: item

  defp events(action) do
    Repo.all(from e in AuditEvent, where: e.action == ^action, order_by: e.inserted_at)
  end

  defp json(value), do: value |> JSON.encode!() |> JSON.decode!()
end
