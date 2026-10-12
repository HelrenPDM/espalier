defmodule EspalierWeb.Admin.RoleGrantControllerTest do
  @moduledoc """
  Role grants of the admin area (task 0015, steps 3 and 19; README section
  6.5): the list names the users with a grant beyond `learner` and the
  role, source and provider key of each grant, a new `manual` grant ends
  every session of the user and writes `role.granted`, a demo user answers
  409 `demo_user`, a `manual` grant is revoked with 204 and `role.revoked`,
  and an `idp_claim` grant answers 409 `idp_claim` on delete.
  """
  use EspalierWeb.ConnCase, async: true

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import OpenApiSpex.TestAssertions

  alias Espalier.Accounts
  alias Espalier.Accounts.{Demo, RoleGrant, UserToken}
  alias Espalier.Audit.AuditEvent
  alias Espalier.Repo
  alias EspalierWeb.ApiSpec

  setup %{conn: conn} do
    admin = user_with_role_fixture(:admin)
    {_authenticator, _passkey} = passkey_fixture(admin)
    %{admin: admin, conn: log_in_user(conn, admin), spec: ApiSpec.spec()}
  end

  defp session_rows(user) do
    Repo.aggregate(
      from(t in UserToken, where: t.user_id == ^user.id and t.context == :session),
      :count
    )
  end

  defp assert_audit(action, actor, subject) do
    assert [%AuditEvent{} = event] =
             Repo.all(
               from e in AuditEvent, where: e.action == ^action and e.subject_id == ^subject.id
             )

    assert event.actor_id == actor.id
    assert event.subject_type == "User"
    event
  end

  describe "GET /api/admin/role-grants" do
    test "lists the users with a grant beyond learner, with role, source and provider key",
         %{conn: conn, admin: admin, spec: spec} do
      author = user_with_role_fixture(:author)
      claimed = user_fixture()
      {:ok, :changed} = Accounts.replace_idp_role_grants(claimed, "test", [:analyst])
      learner = user_fixture()

      body = conn |> json_request(:get, "/api/admin/role-grants") |> json_response(200)

      users = Map.new(body["users"], &{&1["id"], &1})

      assert Map.keys(users) |> Enum.sort() == Enum.sort([admin.id, author.id, claimed.id])
      refute Map.has_key?(users, learner.id)

      assert [%{"role" => "author", "source" => "manual", "provider_key" => nil}] =
               users[author.id]["grants"]

      assert [%{"role" => "analyst", "source" => "idp_claim", "provider_key" => "test"}] =
               users[claimed.id]["grants"]

      assert Enum.sort(users[claimed.id]["roles"]) == ["analyst", "learner"]
      assert_schema(body, "AdminGrantHolderList", spec)
    end
  end

  describe "POST /api/admin/role-grants" do
    test "grants a manual role, ends the user's sessions and records role.granted",
         %{conn: conn, admin: admin, spec: spec} do
      user = user_fixture()
      {_token, _session} = session_fixture(user)
      {_token, _session} = session_fixture(user)
      assert session_rows(user) == 2

      conn =
        json_request(conn, :post, "/api/admin/role-grants", %{user_id: user.id, role: "author"})

      body = json_response(conn, 201)
      assert_schema(body, "AdminRoleGrant", spec)

      assert %{
               "user_id" => user_id,
               "role" => "author",
               "source" => "manual",
               "provider_key" => nil
             } = body

      assert user_id == user.id
      assert %RoleGrant{source: :manual, role: :author} = Repo.get!(RoleGrant, body["id"])
      assert session_rows(user) == 0
      assert session_rows(admin) == 1

      event = assert_audit("role.granted", admin, user)
      assert event.details == %{"role" => "author"}
    end

    test "answers 409 demo_user for a demo user", %{conn: conn} do
      user = user_fixture()
      external_identity_fixture(user, %{provider_key: Demo.provider_key()})

      conn =
        json_request(conn, :post, "/api/admin/role-grants", %{user_id: user.id, role: "admin"})

      assert json_response(conn, 409) == %{"error" => "demo_user"}
      assert Accounts.list_role_grants(user) == []

      assert Repo.all(
               from e in AuditEvent,
                 where: e.action == "role.granted" and e.subject_id == ^user.id
             ) == []
    end

    test "answers 404 not_found for an unknown user", %{conn: conn} do
      conn =
        json_request(conn, :post, "/api/admin/role-grants", %{
          user_id: Ecto.UUID.generate(),
          role: "author"
        })

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "answers 422 validation_failed for the role learner and for an extra member",
         %{conn: conn} do
      user = user_fixture()

      for body <- [
            %{user_id: user.id, role: "learner"},
            %{user_id: user.id, role: "author", source: "idp_claim"}
          ] do
        response = json_request(conn, :post, "/api/admin/role-grants", body)
        assert json_response(response, 422)["error"] == "validation_failed"
      end

      assert Accounts.list_role_grants(user) == []
    end
  end

  describe "DELETE /api/admin/role-grants/:id" do
    test "revokes a manual grant, ends the user's sessions and records role.revoked",
         %{conn: conn, admin: admin} do
      user = user_with_role_fixture(:facilitator)
      [grant] = Accounts.list_role_grants(user)
      {_token, _session} = session_fixture(user)

      conn = json_request(conn, :delete, "/api/admin/role-grants/#{grant.id}")

      assert response(conn, 204) == ""
      assert Repo.get(RoleGrant, grant.id) == nil
      assert session_rows(user) == 0

      event = assert_audit("role.revoked", admin, user)
      assert event.details == %{"role" => "facilitator"}
    end

    test "answers 409 idp_claim for a grant of an identity provider", %{conn: conn} do
      user = user_fixture()
      {:ok, :changed} = Accounts.replace_idp_role_grants(user, "test", [:author])
      [grant] = Accounts.list_role_grants(user)
      {_token, _session} = session_fixture(user)

      conn = json_request(conn, :delete, "/api/admin/role-grants/#{grant.id}")

      assert json_response(conn, 409) == %{"error" => "idp_claim"}
      assert Repo.get(RoleGrant, grant.id)
      assert session_rows(user) == 1
      assert Repo.all(from e in AuditEvent, where: e.action == "role.revoked") == []
    end

    test "answers 404 not_found for an unknown id", %{conn: conn} do
      conn = json_request(conn, :delete, "/api/admin/role-grants/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end
end
