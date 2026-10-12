defmodule EspalierWeb.Admin.ApiClientControllerTest do
  @moduledoc """
  Machine clients of the admin area (task 0015, step 3): a new client
  answers 201 with its token once, and the token works against the
  integration API of task 0013; the list carries neither the token nor its
  hash (ASVS 14.3.2); a deleted client's token answers 401. Every change
  writes its `audit_events` row with actor and subject.
  """
  use EspalierWeb.ConnCase, async: true

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1, api_client_fixture: 0]
  import OpenApiSpex.TestAssertions

  alias Espalier.Accounts.{ApiClient, UserToken}
  alias Espalier.Audit.AuditEvent
  alias Espalier.Repo
  alias EspalierWeb.ApiSpec

  setup %{conn: conn} do
    admin = user_with_role_fixture(:admin)
    {_authenticator, _passkey} = passkey_fixture(admin)
    %{admin: admin, conn: log_in_user(conn, admin), spec: ApiSpec.spec()}
  end

  # A lookup of the integration API with the bearer token alone.
  defp integration_lookup(token) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
    |> post("/api/integration/credential-lookups", JSON.encode!(%{email: unique_user_email()}))
  end

  defp assert_audit(action, actor, client_id) do
    assert [%AuditEvent{} = event] =
             Repo.all(
               from e in AuditEvent, where: e.action == ^action and e.subject_id == ^client_id
             )

    assert event.actor_id == actor.id
    assert event.subject_type == "ApiClient"
    event
  end

  describe "POST /api/admin/api-clients" do
    test "answers 201 with the token once, and the token works against the integration API",
         %{conn: conn, admin: admin, spec: spec} do
      conn =
        json_request(conn, :post, "/api/admin/api-clients", %{
          name: "Registry sync",
          scopes: ["credentials:read"]
        })

      body = json_response(conn, 201)
      assert_schema(body, "AdminApiClientCreated", spec)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert %{
               "client" => %{
                 "id" => id,
                 "name" => "Registry sync",
                 "scopes" => ["credentials:read"],
                 "last_used_at" => nil
               },
               "token" => token
             } = body

      # The table stores the SHA-256 hash of the token, never the token.
      client = Repo.get!(ApiClient, id)
      {:ok, bytes} = Base.url_decode64(token, padding: false)
      assert client.token_hash == UserToken.hash(bytes)
      refute client.token_hash == token

      assert json_response(integration_lookup(token), 200) == %{"credentials" => []}

      event = assert_audit("api_client.created", admin, id)
      assert event.details == %{"scopes" => ["credentials:read"]}
    end

    test "answers 422 validation_failed for an unknown scope, no name and an extra member",
         %{conn: conn} do
      for body <- [
            %{name: "client", scopes: ["credentials:write"]},
            %{name: "", scopes: ["credentials:read"]},
            %{name: "client", scopes: ["credentials:read"], token: "chosen"}
          ] do
        response = json_request(conn, :post, "/api/admin/api-clients", body)
        assert json_response(response, 422)["error"] == "validation_failed", inspect(body)
      end

      assert Repo.aggregate(ApiClient, :count) == 0
    end
  end

  describe "GET /api/admin/api-clients" do
    test "lists the clients without token and token hash", %{conn: conn, spec: spec} do
      {client, token} = api_client_fixture()

      conn = json_request(conn, :get, "/api/admin/api-clients")
      raw = response(conn, 200)
      body = json_response(conn, 200)

      assert_schema(body, "AdminApiClientList", spec)
      assert [entry] = body["clients"]

      assert Map.keys(entry) |> Enum.sort() == ~w(id inserted_at last_used_at name scopes)
      assert entry["id"] == client.id
      assert entry["name"] == client.name
      assert entry["scopes"] == ["credentials:read"]

      refute raw =~ token
      refute raw =~ Base.encode64(client.token_hash)
      refute raw =~ Base.url_encode64(client.token_hash, padding: false)
      refute raw =~ Base.encode16(client.token_hash, case: :lower)
      refute raw =~ "token"
    end
  end

  describe "DELETE /api/admin/api-clients/:id" do
    test "deletes the client, whose token then answers 401", %{conn: conn, admin: admin} do
      {client, token} = api_client_fixture()
      assert json_response(integration_lookup(token), 200)

      conn = json_request(conn, :delete, "/api/admin/api-clients/#{client.id}")

      assert response(conn, 204) == ""
      assert Repo.get(ApiClient, client.id) == nil
      assert json_response(integration_lookup(token), 401) == %{"error" => "unauthenticated"}
      assert_audit("api_client.deleted", admin, client.id)
    end

    test "answers 404 not_found for an unknown id", %{conn: conn} do
      conn = json_request(conn, :delete, "/api/admin/api-clients/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end
end
