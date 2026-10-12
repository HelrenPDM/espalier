defmodule EspalierWeb.Admin.ApprovedToolControllerTest do
  @moduledoc """
  The approved tool routes of the admin area (task 0015, steps 2 and 19):
  `/api/admin/approved-tools` lists, reads, creates, changes and deletes
  entries of the approved tool list for a signed-in admin with a passkey,
  in the nested body and answer shapes of `mix phx.gen.json`. An unknown id
  answers 404 (`Policies.get_approved_tool!/1`), and every change writes
  its audit event with actor and subject (ASVS 8.2.1).
  """
  use EspalierWeb.ConnCase, async: true

  import Ecto.Query
  import Espalier.CredentialsFixtures

  alias Espalier.Audit.AuditEvent
  alias Espalier.Policies.ApprovedTool
  alias Espalier.Repo

  @create_attrs %{
    name: "Drafting assistant",
    vendor: "Example vendor",
    status: "approved",
    conditions: "Internal drafts only.",
    reviewed_on: "2026-10-11",
    position: 42
  }

  @update_attrs %{
    name: "Drafting assistant, revised",
    vendor: "Another vendor",
    status: "restricted",
    conditions: "No personal data.",
    reviewed_on: "2026-10-12",
    position: 43
  }

  setup do
    admin = user_with_role_fixture(:admin)
    _passkey = passkey_fixture(admin)
    %{admin: admin, conn: log_in_user(api_conn(), admin)}
  end

  defp audit_events(action),
    do: Repo.all(from e in AuditEvent, where: e.action == ^action)

  defp assert_audit(action, admin, subject_id, name) do
    assert [event] = audit_events(action)
    assert event.actor_id == admin.id
    assert event.subject_type == "ApprovedTool"
    assert event.subject_id == subject_id
    assert event.details == %{"name" => name}
  end

  # get_approved_tool!/1 raises Ecto.NoResultsError, which the endpoint
  # renders as 404. assert_error_sent/2 reads the first response that the
  # test process receives, so the CSRF token is fetched before it runs.
  defp assert_not_found(conn, method, path, body \\ nil) do
    conn = if conn.state == :unset, do: conn, else: next_request(conn)
    conn = with_csrf_token(conn)

    {conn, body} =
      if body,
        do: {put_req_header(conn, "content-type", "application/json"), JSON.encode!(body)},
        else: {conn, nil}

    {404, _headers, resp_body} =
      assert_error_sent(404, fn -> dispatch(conn, @endpoint, method, path, body) end)

    assert JSON.decode!(resp_body) == %{"error" => "not_found"}
  end

  describe "index" do
    test "lists the tools ordered by position and name, with no-store", %{conn: conn} do
      third = approved_tool_fixture(%{name: "Zeta", position: 1})
      second = approved_tool_fixture(%{name: "Beta", position: 1})
      first = approved_tool_fixture(%{name: "Omega", position: 0, conditions: nil})

      conn = json_request(conn, :get, ~p"/api/admin/approved-tools")

      assert [entry | _rest] = data = json_response(conn, 200)["data"]
      assert Enum.map(data, & &1["id"]) == [first.id, second.id, third.id]

      assert entry == %{
               "id" => first.id,
               "name" => "Omega",
               "vendor" => "Example vendor",
               "status" => "approved",
               "conditions" => nil,
               "reviewed_on" => "2026-09-01",
               "position" => 0
             }

      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "show" do
    test "returns one tool", %{conn: conn} do
      tool = approved_tool_fixture(%{name: "Drafting assistant", status: :not_approved})

      conn = json_request(conn, :get, ~p"/api/admin/approved-tools/#{tool}")

      assert %{"id" => id, "name" => "Drafting assistant", "status" => "not_approved"} =
               json_response(conn, 200)["data"]

      assert id == tool.id
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      assert_not_found(conn, :get, ~p"/api/admin/approved-tools/#{Ecto.UUID.generate()}")
    end
  end

  describe "create" do
    test "creates a tool and writes approved_tool.created", %{conn: conn, admin: admin} do
      conn =
        json_request(conn, :post, ~p"/api/admin/approved-tools", %{approved_tool: @create_attrs})

      assert %{"id" => id} = data = json_response(conn, 201)["data"]

      assert data == %{
               "id" => id,
               "name" => "Drafting assistant",
               "vendor" => "Example vendor",
               "status" => "approved",
               "conditions" => "Internal drafts only.",
               "reviewed_on" => "2026-10-11",
               "position" => 42
             }

      assert get_resp_header(conn, "location") == ["/api/admin/approved-tools/#{id}"]

      assert %ApprovedTool{status: :approved, reviewed_on: ~D[2026-10-11]} =
               Repo.get!(ApprovedTool, id)

      assert_audit("approved_tool.created", admin, id, "Drafting assistant")

      conn = json_request(conn, :get, ~p"/api/admin/approved-tools/#{id}")
      assert json_response(conn, 200)["data"] == data
    end

    test "conditions and reviewed_on are optional", %{conn: conn} do
      attrs = Map.drop(@create_attrs, [:conditions, :reviewed_on])

      conn = json_request(conn, :post, ~p"/api/admin/approved-tools", %{approved_tool: attrs})

      assert %{"conditions" => nil, "reviewed_on" => nil} = json_response(conn, 201)["data"]
    end

    test "answers 422 for a body that does not fit the schema", %{conn: conn} do
      for body <- [
            %{approved_tool: Map.delete(@create_attrs, :name)},
            %{approved_tool: Map.put(@create_attrs, :status, "banned")},
            %{approved_tool: Map.put(@create_attrs, :position, -1)},
            %{approved_tool: Map.put(@create_attrs, :reviewed_on, "yesterday")},
            %{approved_tool: Map.put(@create_attrs, :name, String.duplicate("a", 256))},
            %{approved_tool: Map.put(@create_attrs, :extra, true)},
            @create_attrs
          ] do
        conn = json_request(conn, :post, ~p"/api/admin/approved-tools", body)
        assert %{"error" => "validation_failed"} = json_response(conn, 422)
      end

      assert Repo.aggregate(ApprovedTool, :count) == 0
      assert audit_events("approved_tool.created") == []
    end

    test "answers 422 with unique on name for a name in use", %{conn: conn} do
      approved_tool_fixture(%{name: "Drafting assistant"})

      conn =
        json_request(conn, :post, ~p"/api/admin/approved-tools", %{approved_tool: @create_attrs})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"name" => ["unique"]}
             }

      assert audit_events("approved_tool.created") == []
    end
  end

  describe "update" do
    test "PUT changes every field and writes approved_tool.updated",
         %{conn: conn, admin: admin} do
      tool = approved_tool_fixture()

      conn =
        json_request(conn, :put, ~p"/api/admin/approved-tools/#{tool}", %{
          approved_tool: @update_attrs
        })

      assert json_response(conn, 200)["data"] == %{
               "id" => tool.id,
               "name" => "Drafting assistant, revised",
               "vendor" => "Another vendor",
               "status" => "restricted",
               "conditions" => "No personal data.",
               "reviewed_on" => "2026-10-12",
               "position" => 43
             }

      assert %ApprovedTool{status: :restricted, position: 43} = Repo.get!(ApprovedTool, tool.id)
      assert_audit("approved_tool.updated", admin, tool.id, "Drafting assistant, revised")
    end

    test "PATCH changes the given fields only", %{conn: conn} do
      tool = approved_tool_fixture(%{name: "Drafting assistant", position: 3})

      conn =
        json_request(conn, :patch, ~p"/api/admin/approved-tools/#{tool}", %{
          approved_tool: %{status: "not_approved", conditions: nil}
        })

      assert %{
               "name" => "Drafting assistant",
               "status" => "not_approved",
               "conditions" => nil,
               "position" => 3
             } = json_response(conn, 200)["data"]
    end

    test "answers 422 for a body that does not fit the schema", %{conn: conn} do
      tool = approved_tool_fixture(%{status: :approved})

      for body <- [
            %{approved_tool: %{status: "banned"}},
            %{approved_tool: %{name: ""}},
            %{approved_tool: %{extra: 1}},
            %{status: "restricted"}
          ] do
        conn = json_request(conn, :patch, ~p"/api/admin/approved-tools/#{tool}", body)
        assert %{"error" => "validation_failed"} = json_response(conn, 422)
      end

      assert Repo.get!(ApprovedTool, tool.id) == tool
      assert audit_events("approved_tool.updated") == []
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      assert_not_found(conn, :put, ~p"/api/admin/approved-tools/#{Ecto.UUID.generate()}", %{
        approved_tool: @update_attrs
      })
    end
  end

  describe "delete" do
    test "deletes a tool and writes approved_tool.deleted", %{conn: conn, admin: admin} do
      tool = approved_tool_fixture(%{name: "Drafting assistant"})
      other = approved_tool_fixture()

      conn = json_request(conn, :delete, ~p"/api/admin/approved-tools/#{tool}")

      assert response(conn, 204) == ""
      assert Repo.get(ApprovedTool, tool.id) == nil
      assert Repo.get(ApprovedTool, other.id)
      assert_audit("approved_tool.deleted", admin, tool.id, "Drafting assistant")

      assert_not_found(conn, :get, ~p"/api/admin/approved-tools/#{tool}")
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      assert_not_found(conn, :delete, ~p"/api/admin/approved-tools/#{Ecto.UUID.generate()}")
      assert audit_events("approved_tool.deleted") == []
    end
  end
end
