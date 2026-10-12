defmodule EspalierWeb.Admin.AuditControllerTest do
  @moduledoc """
  The audit log of the admin area (task 0015, steps 8 and 19):
  `GET /api/admin/audit` returns pages of `Espalier.Audit.list_events/2`,
  newest first, filtered by action and actor id, and names each actor by
  display name. `list_events/2` takes the filter `:actor_id` and pages 50
  events with `desc: :id` as the last ordering key, so events within one
  second keep one order across pages.
  """
  use EspalierWeb.ConnCase, async: true

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 2]
  import OpenApiSpex.TestAssertions

  alias Espalier.{Accounts, Audit, Repo}
  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias EspalierWeb.ApiSpec

  setup %{conn: conn} do
    admin = user_with_role_fixture(:admin, %{display_name: "Acting Admin"})
    {_authenticator, _passkey} = passkey_fixture(admin)
    {_token, session} = session_fixture(admin)
    scope = Scope.for_session(admin, session, Accounts.list_role_grants(admin))

    %{
      admin: admin,
      scope: scope,
      conn: log_in_user(conn, admin),
      spec: ApiSpec.spec()
    }
  end

  defp admin_scope(user) do
    {:ok, _grant} = Accounts.grant_role(Scope.system(), user, :admin)
    {_token, session} = session_fixture(user)
    Scope.for_session(user, session, Accounts.list_role_grants(user))
  end

  # Inserts `count` events of `action` with one `at` and one `inserted_at`,
  # as events written within one second carry them. Returns their ids.
  defp same_second_events!(action, count, actor_id \\ nil) do
    at = DateTime.utc_now(:second)

    rows =
      for _ <- 1..count do
        %{
          id: Ecto.UUID.generate(),
          action: action,
          actor_id: actor_id,
          details: %{},
          at: at,
          inserted_at: at,
          updated_at: at
        }
      end

    {^count, _} = Repo.insert_all(AuditEvent, rows)
    Enum.map(rows, & &1.id)
  end

  defp ids({:ok, events}), do: Enum.map(events, & &1.id)

  describe "Audit.list_events/2" do
    test "the filter actor_id returns only the events of that actor", %{scope: scope} do
      other = admin_scope(user_fixture())
      subject = user_fixture()

      {:ok, mine} = Audit.record(scope, "user.disabled", subject)
      {:ok, theirs} = Audit.record(other, "user.disabled", subject)
      {:ok, _system} = Audit.record(Scope.system(), "user.disabled", subject)

      assert ids(Audit.list_events(scope, %{actor_id: scope.user.id})) == [mine.id]

      assert ids(Audit.list_events(scope, %{actor_id: other.user.id, action: "user.disabled"})) ==
               [theirs.id]
    end

    test "events with the same at keep one order across two pages", %{scope: scope} do
      expected = "test.same_second" |> same_second_events!(57) |> Enum.sort(:desc)
      _other = same_second_events!("test.other_action", 3)

      page = fn n ->
        ids(Audit.list_events(scope, %{action: "test.same_second", page: n}))
      end

      first = page.(1)
      second = page.(2)

      assert length(first) == Audit.per_page()
      assert length(second) == 7
      assert page.(3) == []

      # Every event appears exactly once, in the order of desc: :id.
      assert first ++ second == expected

      for _ <- 1..3 do
        assert page.(1) == first
        assert page.(2) == second
      end
    end

    test "orders newest first and caps an unpaged list at :limit", %{scope: scope} do
      older = DateTime.add(DateTime.utc_now(:second), -60)

      Repo.insert_all(AuditEvent, [
        %{
          id: Ecto.UUID.generate(),
          action: "test.order",
          details: %{},
          at: older,
          inserted_at: older,
          updated_at: older
        }
      ])

      _newer = same_second_events!("test.order", 3)

      assert {:ok, events} = Audit.list_events(scope, %{action: "test.order"})
      assert length(events) == 4
      assert List.last(events).at == older
      assert hd(events).at != older

      assert {:ok, [_one, _two]} = Audit.list_events(scope, %{action: "test.order", limit: 2})
    end

    test "answers {:error, :forbidden} for a scope without admin" do
      learner = Scope.for_user(user_fixture())

      assert Audit.list_events(learner) == {:error, :forbidden}
      assert Audit.list_events(learner, %{page: 1}) == {:error, :forbidden}
    end
  end

  describe "GET /api/admin/audit" do
    test "filters by actor id and names the actor", %{
      conn: conn,
      admin: admin,
      scope: scope,
      spec: spec
    } do
      other = admin_scope(user_fixture(%{display_name: "Other Admin"}))
      subject = user_fixture()

      {:ok, mine} = Audit.record(scope, "user.disabled", subject)
      {:ok, _theirs} = Audit.record(other, "user.disabled", subject)

      body =
        conn
        |> json_request(:get, "/api/admin/audit?actor_id=#{admin.id}")
        |> json_response(200)

      assert_schema(body, "AdminAuditEventList", spec)
      assert %{"page" => 1, "per_page" => 50} = body
      assert [event] = body["events"]

      assert event["id"] == mine.id
      assert event["action"] == "user.disabled"
      assert event["actor_id"] == admin.id
      assert event["actor_display_name"] == "Acting Admin"
      assert event["subject_type"] == "User"
      assert event["subject_id"] == subject.id

      body =
        conn
        |> json_request(:get, "/api/admin/audit?actor_id=#{other.user.id}")
        |> json_response(200)

      assert [%{"actor_display_name" => "Other Admin"}] = body["events"]
    end

    test "filters by action", %{conn: conn, scope: scope, spec: spec} do
      subject = user_fixture()
      {:ok, disabled} = Audit.record(scope, "user.disabled", subject)
      {:ok, _invited} = Audit.record(scope, "user.invited", subject)

      body =
        conn
        |> json_request(:get, "/api/admin/audit?action=user.disabled")
        |> json_response(200)

      assert_schema(body, "AdminAuditEventList", spec)
      assert Enum.map(body["events"], & &1["id"]) == [disabled.id]
    end

    test "an event of the system scope has no actor name", %{conn: conn} do
      {:ok, event} = Audit.record(Scope.system(), "test.system", nil)

      body =
        conn
        |> json_request(:get, "/api/admin/audit?action=test.system")
        |> json_response(200)

      assert [%{"id" => id, "actor_id" => nil, "actor_display_name" => nil}] = body["events"]
      assert id == event.id
    end

    test "two pages hold events of the same second exactly once, in a stable order",
         %{conn: conn, admin: admin} do
      expected = "test.same_second" |> same_second_events!(53, admin.id) |> Enum.sort(:desc)

      page = fn n ->
        conn
        |> json_request(:get, "/api/admin/audit?action=test.same_second&page=#{n}")
        |> json_response(200)
        |> Map.fetch!("events")
        |> Enum.map(& &1["id"])
      end

      first = page.(1)
      second = page.(2)

      assert length(first) == 50
      assert first ++ second == expected
      assert page.(1) == first
      assert page.(2) == second
    end

    test "answers 422 validation_failed for a malformed actor id and page", %{conn: conn} do
      for query <- ["actor_id=not-a-uuid", "page=0"] do
        response = json_request(conn, :get, "/api/admin/audit?" <> query)
        assert json_response(response, 422)["error"] == "validation_failed", query
      end
    end

    test "carries cache-control: no-store", %{conn: conn} do
      conn = json_request(conn, :get, "/api/admin/audit")
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  test "the events of admin changes name actor and subject", %{conn: conn, admin: admin} do
    user = user_fixture()

    conn = json_request(conn, :post, "/api/admin/users/#{user.id}/disable")
    assert json_response(conn, 200)["status"] == "disabled"

    body =
      conn
      |> json_request(:get, "/api/admin/audit?action=user.disabled&actor_id=#{admin.id}")
      |> json_response(200)

    assert [%{"actor_id" => actor_id, "subject_id" => subject_id}] = body["events"]
    assert actor_id == admin.id
    assert subject_id == user.id
  end
end
