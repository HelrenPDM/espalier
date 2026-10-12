defmodule EspalierWeb.Admin.PolicyControllerTest do
  @moduledoc """
  The policy routes of the admin area (task 0015, steps 2 and 19):
  `/api/admin/policies` lists, reads, creates, changes and deletes policies
  for a signed-in admin with a passkey, in the nested body and answer
  shapes of `mix phx.gen.json`. An unknown id answers 404. A policy with a
  published version keeps its key and cannot be deleted (409
  `policy_in_use`); a policy whose versions are drafts is deleted together
  with its drafts. Every change writes its audit event with actor and
  subject (ASVS 8.2.1).
  """
  use EspalierWeb.ConnCase, async: true

  import Ecto.Query
  import Espalier.CredentialsFixtures

  alias Espalier.Audit.AuditEvent
  alias Espalier.Policies.{Policy, PolicyVersion}
  alias Espalier.Repo

  setup do
    admin = user_with_role_fixture(:admin)
    _passkey = passkey_fixture(admin)
    %{admin: admin, conn: log_in_user(api_conn(), admin)}
  end

  defp audit_events(action),
    do: Repo.all(from e in AuditEvent, where: e.action == ^action)

  defp versions(policy),
    do: Repo.all(from v in PolicyVersion, where: v.policy_id == ^policy.id)

  defp assert_audit(action, admin, subject_id, details) do
    assert [event] = audit_events(action)
    assert event.actor_id == admin.id
    assert event.subject_type == "Policy"
    assert event.subject_id == subject_id
    assert event.details == details
  end

  # get_policy!/1 raises Ecto.NoResultsError, which the endpoint renders as
  # 404. assert_error_sent/2 reads the first response that the test process
  # receives, so the CSRF token is fetched before it runs.
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
    test "lists the policies ordered by key, with no-store", %{conn: conn} do
      second = policy_fixture(%{key: "b-policy", title: "Second"})
      first = policy_fixture(%{key: "a-policy", title: "First"})

      conn = json_request(conn, :get, ~p"/api/admin/policies")

      assert json_response(conn, 200)["data"] == [
               %{"id" => first.id, "key" => "a-policy", "title" => "First"},
               %{"id" => second.id, "key" => "b-policy", "title" => "Second"}
             ]

      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "show" do
    test "returns one policy", %{conn: conn} do
      policy = policy_fixture(%{key: "usage-policy", title: "Usage"})

      conn = json_request(conn, :get, ~p"/api/admin/policies/#{policy}")

      assert json_response(conn, 200)["data"] == %{
               "id" => policy.id,
               "key" => "usage-policy",
               "title" => "Usage"
             }
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      assert_not_found(conn, :get, ~p"/api/admin/policies/#{Ecto.UUID.generate()}")
    end
  end

  describe "create" do
    test "creates a policy and writes policy.created", %{conn: conn, admin: admin} do
      conn =
        json_request(conn, :post, ~p"/api/admin/policies", %{
          policy: %{key: "usage-policy", title: "Usage policy"}
        })

      assert %{"id" => id, "key" => "usage-policy", "title" => "Usage policy"} =
               json_response(conn, 201)["data"]

      assert get_resp_header(conn, "location") == ["/api/admin/policies/#{id}"]
      assert %Policy{key: "usage-policy", title: "Usage policy"} = Repo.get!(Policy, id)
      assert_audit("policy.created", admin, id, %{"key" => "usage-policy"})

      conn = json_request(conn, :get, ~p"/api/admin/policies/#{id}")
      assert json_response(conn, 200)["data"]["key"] == "usage-policy"
    end

    test "answers 422 for a body that does not fit the schema", %{conn: conn} do
      for body <- [
            %{policy: %{key: "usage-policy"}},
            %{policy: %{key: "Usage Policy", title: "Usage"}},
            %{policy: %{key: "usage-policy", title: ""}},
            %{policy: %{key: "usage-policy", title: "Usage", extra: true}},
            %{key: "usage-policy", title: "Usage"}
          ] do
        conn = json_request(conn, :post, ~p"/api/admin/policies", body)
        assert %{"error" => "validation_failed"} = json_response(conn, 422)
      end

      assert Repo.aggregate(Policy, :count) == 0
      assert audit_events("policy.created") == []
    end

    test "answers 422 with unique on key for a key in use", %{conn: conn} do
      policy_fixture(%{key: "usage-policy"})

      conn =
        json_request(conn, :post, ~p"/api/admin/policies", %{
          policy: %{key: "usage-policy", title: "Another"}
        })

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"key" => ["unique"]}
             }

      assert audit_events("policy.created") == []
    end
  end

  describe "update" do
    test "PUT and PATCH change the policy and write policy.updated",
         %{conn: conn, admin: admin} do
      policy = policy_fixture(%{key: "usage-policy", title: "Usage"})

      conn =
        json_request(conn, :put, ~p"/api/admin/policies/#{policy}", %{
          policy: %{key: "usage-policy-v2", title: "Usage, revised"}
        })

      assert json_response(conn, 200)["data"] == %{
               "id" => policy.id,
               "key" => "usage-policy-v2",
               "title" => "Usage, revised"
             }

      assert_audit("policy.updated", admin, policy.id, %{"key" => "usage-policy-v2"})

      conn =
        json_request(conn, :patch, ~p"/api/admin/policies/#{policy}", %{
          policy: %{title: "Usage, third"}
        })

      assert json_response(conn, 200)["data"]["title"] == "Usage, third"

      assert %Policy{key: "usage-policy-v2", title: "Usage, third"} =
               Repo.get!(Policy, policy.id)

      assert length(audit_events("policy.updated")) == 2
    end

    test "a policy whose versions are drafts may change its key", %{conn: conn} do
      policy = policy_fixture(%{key: "usage-policy"})
      draft_version_fixture(policy)

      conn =
        json_request(conn, :patch, ~p"/api/admin/policies/#{policy}", %{
          policy: %{key: "renamed-policy"}
        })

      assert json_response(conn, 200)["data"]["key"] == "renamed-policy"
    end

    test "a policy with a published version answers 409 policy_in_use to a new key",
         %{conn: conn} do
      policy = policy_fixture(%{key: "usage-policy", title: "Usage"})
      published_version_fixture(policy)

      conn =
        json_request(conn, :put, ~p"/api/admin/policies/#{policy}", %{
          policy: %{key: "renamed-policy", title: "Renamed"}
        })

      assert json_response(conn, 409) == %{"error" => "policy_in_use"}
      assert %Policy{key: "usage-policy", title: "Usage"} = Repo.get!(Policy, policy.id)
      assert audit_events("policy.updated") == []

      # The title changes while the key stays.
      conn =
        json_request(conn, :patch, ~p"/api/admin/policies/#{policy}", %{
          policy: %{key: "usage-policy", title: "Renamed"}
        })

      assert json_response(conn, 200)["data"] == %{
               "id" => policy.id,
               "key" => "usage-policy",
               "title" => "Renamed"
             }
    end

    test "answers 422 for a body that does not fit the schema", %{conn: conn} do
      policy = policy_fixture(%{key: "usage-policy", title: "Usage"})

      for body <- [
            %{policy: %{title: ""}},
            %{policy: %{key: "Not A Key"}},
            %{policy: %{title: "Usage", extra: 1}}
          ] do
        conn = json_request(conn, :patch, ~p"/api/admin/policies/#{policy}", body)
        assert %{"error" => "validation_failed"} = json_response(conn, 422)
      end

      assert %Policy{key: "usage-policy", title: "Usage"} = Repo.get!(Policy, policy.id)
      assert audit_events("policy.updated") == []
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      assert_not_found(conn, :put, ~p"/api/admin/policies/#{Ecto.UUID.generate()}", %{
        policy: %{title: "Usage"}
      })
    end
  end

  describe "delete" do
    test "deletes a policy together with its drafts and writes policy.deleted",
         %{conn: conn, admin: admin} do
      policy = policy_fixture(%{key: "usage-policy"})
      draft_version_fixture(policy)
      draft_version_fixture(policy)
      other = policy_fixture()
      other_draft = draft_version_fixture(other)

      conn = json_request(conn, :delete, ~p"/api/admin/policies/#{policy}")

      assert response(conn, 204) == ""
      assert Repo.get(Policy, policy.id) == nil
      assert versions(policy) == []
      assert Repo.get(PolicyVersion, other_draft.id)
      assert_audit("policy.deleted", admin, policy.id, %{"key" => "usage-policy", "drafts" => 2})

      assert_not_found(conn, :get, ~p"/api/admin/policies/#{policy}")
    end

    test "a policy with a published version answers 409 policy_in_use", %{conn: conn} do
      policy = policy_fixture(%{key: "usage-policy"})
      published = published_version_fixture(policy)
      draft = draft_version_fixture(policy)

      conn = json_request(conn, :delete, ~p"/api/admin/policies/#{policy}")

      assert json_response(conn, 409) == %{"error" => "policy_in_use"}
      assert Repo.get(Policy, policy.id)

      assert versions(policy) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([published.id, draft.id])

      assert audit_events("policy.deleted") == []
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      assert_not_found(conn, :delete, ~p"/api/admin/policies/#{Ecto.UUID.generate()}")
    end
  end
end
