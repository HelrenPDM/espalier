defmodule EspalierWeb.Admin.PolicyVersionControllerTest do
  @moduledoc """
  The policy version routes of the admin area (task 0015, steps 3 and 19):
  `GET /api/admin/policy-versions?policy_id=` lists the versions of a
  policy, the highest number first; `GET /api/admin/policy-versions/:id`
  returns a version with `refresh_due_count`; `POST` creates a draft, `PUT`
  and `PATCH` change a draft, and `POST /:id/publish` stores
  `requires_refresher` and publishes in one transaction (ASVS 2.3.3).

  A published version answers 409 `published` to every change. A draft
  whose policy has a published version with a higher number answers the
  publish with 409 `superseded` and keeps `published_at`,
  `requires_refresher` and the credentials of the qualifications that
  require the policy unchanged. An unknown id answers 404, and every change
  writes its audit event with actor and subject.
  """
  use EspalierWeb.ConnCase, async: true

  import Ecto.Query
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Accounts.MailWorker
  alias Espalier.Audit.AuditEvent
  alias Espalier.Credentials.Credential
  alias Espalier.Policies.PolicyVersion
  alias Espalier.Repo

  @path "/api/admin/policy-versions"

  setup do
    admin = user_with_role_fixture(:admin)
    _passkey = passkey_fixture(admin)
    %{admin: admin, conn: log_in_user(api_conn(), admin)}
  end

  # The demo program, whose qualification `basics` requires the policy
  # `usage-policy`, with that policy.
  defp demo_policy do
    program = publish_demo!()
    %{basics: qualification!(program, "basics"), policy: policy_fixture(%{key: "usage-policy"})}
  end

  defp admin_events(action, admin),
    do: Repo.all(from e in AuditEvent, where: e.action == ^action and e.actor_id == ^admin.id)

  defp reload(%PolicyVersion{id: id}), do: Repo.get!(PolicyVersion, id)
  defp reload(%Credential{id: id}), do: Repo.get!(Credential, id)

  defp refresh_due_mails do
    for %{args: %{"kind" => "credential_refresh_due"} = args} <-
          all_enqueued(worker: MailWorker),
        do: args["credential_id"]
  end

  defp assert_audit(action, admin, version) do
    assert [event] = admin_events(action, admin)
    assert event.subject_type == "PolicyVersion"
    assert event.subject_id == version.id
    event
  end

  # get_policy!/1 raises Ecto.NoResultsError, which the endpoint renders as
  # 404. assert_error_sent/2 reads the first response that the test process
  # receives, so the CSRF token is fetched before it runs.
  defp assert_not_found_raised(conn, method, path, body \\ nil) do
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
    test "lists the versions of a policy, the highest number first", %{conn: conn} do
      policy = policy_fixture(%{key: "usage-policy", title: "Usage"})
      first = published_version_fixture(policy, %{body: "First."})
      second = draft_version_fixture(policy)
      third = draft_version_fixture(policy, %{requires_refresher: true})
      _other = draft_version_fixture(policy_fixture())

      conn = json_request(conn, :get, "#{@path}?policy_id=#{policy.id}")

      assert %{"versions" => versions} = json_response(conn, 200)
      assert Enum.map(versions, & &1["id"]) == [third.id, second.id, first.id]
      assert Enum.map(versions, & &1["number"]) == [3, 2, 1]

      assert List.last(versions) == %{
               "id" => first.id,
               "policy_id" => policy.id,
               "policy_key" => "usage-policy",
               "policy_title" => "Usage",
               "number" => 1,
               "body" => "First.",
               "effective_from" => "2026-01-01",
               "published_at" => DateTime.to_iso8601(first.published_at),
               "requires_refresher" => false
             }

      assert %{"published_at" => nil, "requires_refresher" => true} = hd(versions)
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "answers 404 for an unknown policy and 422 without policy_id", %{conn: conn} do
      assert_not_found_raised(conn, :get, "#{@path}?policy_id=#{Ecto.UUID.generate()}")

      conn = json_request(conn, :get, @path)
      assert %{"error" => "validation_failed"} = json_response(conn, 422)
    end
  end

  describe "show" do
    test "returns the version with refresh_due_count of its policy", %{conn: conn} do
      %{basics: basics, policy: policy} = demo_policy()
      draft = draft_version_fixture(policy, %{body: "Draft.", requires_refresher: true})
      _active = for _n <- 1..2, do: credential_fixture(user_fixture(), basics)
      _due = credential_fixture(user_fixture(), basics, %{status: :refresh_due})
      _revoked = credential_fixture(user_fixture(), basics, %{status: :revoked})

      conn = json_request(conn, :get, "#{@path}/#{draft.id}")

      assert json_response(conn, 200) == %{
               "id" => draft.id,
               "policy_id" => policy.id,
               "policy_key" => "usage-policy",
               "policy_title" => "A policy",
               "number" => 1,
               "body" => "Draft.",
               "effective_from" => "2026-01-01",
               "published_at" => nil,
               "requires_refresher" => true,
               "refresh_due_count" => 2
             }

      other = draft_version_fixture(policy_fixture())
      conn = json_request(conn, :get, "#{@path}/#{other.id}")
      assert json_response(conn, 200)["refresh_due_count"] == 0
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      conn = json_request(conn, :get, "#{@path}/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "create" do
    test "creates a draft with the next number and writes policy_version.created",
         %{conn: conn, admin: admin} do
      policy = policy_fixture(%{key: "usage-policy"})
      published_version_fixture(policy)

      conn =
        json_request(conn, :post, @path, %{
          policy_id: policy.id,
          body: "The second text.",
          effective_from: "2026-11-01",
          requires_refresher: true
        })

      assert %{"id" => id} = data = json_response(conn, 201)

      assert %{
               "policy_id" => policy_id,
               "policy_key" => "usage-policy",
               "number" => 2,
               "body" => "The second text.",
               "effective_from" => "2026-11-01",
               "published_at" => nil,
               "requires_refresher" => true,
               "refresh_due_count" => 0
             } = data

      assert policy_id == policy.id
      assert get_resp_header(conn, "location") == ["#{@path}/#{id}"]

      assert %PolicyVersion{number: 2, published_at: nil, effective_from: ~D[2026-11-01]} =
               version = Repo.get!(PolicyVersion, id)

      event = assert_audit("policy_version.created", admin, version)
      assert event.details == %{"policy_key" => "usage-policy", "number" => 2}
    end

    test "requires_refresher defaults to false", %{conn: conn} do
      policy = policy_fixture()

      conn =
        json_request(conn, :post, @path, %{
          policy_id: policy.id,
          body: "Text.",
          effective_from: "2026-11-01"
        })

      assert %{"number" => 1, "requires_refresher" => false} = json_response(conn, 201)
    end

    test "answers 404 for an unknown policy", %{conn: conn} do
      assert_not_found_raised(conn, :post, @path, %{
        policy_id: Ecto.UUID.generate(),
        body: "Text.",
        effective_from: "2026-11-01"
      })
    end

    test "answers 422 for a body that does not fit the schema", %{conn: conn, admin: admin} do
      policy = policy_fixture()
      attrs = %{policy_id: policy.id, body: "Text.", effective_from: "2026-11-01"}

      for body <- [
            Map.delete(attrs, :body),
            %{attrs | body: ""},
            %{attrs | effective_from: "soon"},
            %{attrs | policy_id: "not-a-uuid"},
            Map.put(attrs, :number, 7),
            Map.put(attrs, :published_at, "2026-11-01T00:00:00Z")
          ] do
        conn = json_request(conn, :post, @path, body)
        assert %{"error" => "validation_failed"} = json_response(conn, 422)
      end

      assert Repo.aggregate(PolicyVersion, :count) == 0
      assert admin_events("policy_version.created", admin) == []
    end
  end

  describe "update" do
    test "PUT and PATCH change a draft and write policy_version.updated",
         %{conn: conn, admin: admin} do
      policy = policy_fixture(%{key: "usage-policy"})
      draft = draft_version_fixture(policy)

      conn =
        json_request(conn, :put, "#{@path}/#{draft.id}", %{
          body: "The changed text.",
          effective_from: "2026-12-01",
          requires_refresher: true
        })

      assert %{
               "id" => id,
               "number" => 1,
               "body" => "The changed text.",
               "effective_from" => "2026-12-01",
               "published_at" => nil,
               "requires_refresher" => true,
               "refresh_due_count" => 0
             } = json_response(conn, 200)

      assert id == draft.id

      assert %PolicyVersion{
               body: "The changed text.",
               effective_from: ~D[2026-12-01],
               requires_refresher: true,
               published_at: nil
             } = reload(draft)

      event = assert_audit("policy_version.updated", admin, draft)
      assert event.details == %{"policy_key" => "usage-policy", "number" => 1}

      conn = json_request(conn, :patch, "#{@path}/#{draft.id}", %{body: "Third."})

      assert %{"body" => "Third.", "effective_from" => "2026-12-01", "requires_refresher" => true} =
               json_response(conn, 200)

      assert length(admin_events("policy_version.updated", admin)) == 2
    end

    test "a published version answers 409 published", %{conn: conn, admin: admin} do
      published = published_version_fixture(policy_fixture(), %{body: "Published."})

      for method <- [:put, :patch] do
        conn =
          json_request(conn, method, "#{@path}/#{published.id}", %{
            body: "Changed.",
            requires_refresher: true
          })

        assert json_response(conn, 409) == %{"error" => "published"}
      end

      assert %PolicyVersion{body: "Published.", requires_refresher: false} = reload(published)
      assert admin_events("policy_version.updated", admin) == []
    end

    test "answers 422 for a body that does not fit the schema", %{conn: conn, admin: admin} do
      draft = draft_version_fixture(policy_fixture())
      before = reload(draft)

      for body <- [
            %{body: ""},
            %{effective_from: "soon"},
            %{requires_refresher: "yes"},
            %{published_at: "2026-11-01T00:00:00Z"},
            %{number: 7}
          ] do
        conn = json_request(conn, :patch, "#{@path}/#{draft.id}", body)
        assert %{"error" => "validation_failed"} = json_response(conn, 422)
      end

      assert reload(draft) == before
      assert admin_events("policy_version.updated", admin) == []
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      conn = json_request(conn, :patch, "#{@path}/#{Ecto.UUID.generate()}", %{body: "Text."})
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "publish" do
    test "publishes a draft without a refresher and leaves the credentials active",
         %{conn: conn, admin: admin} do
      %{basics: basics, policy: policy} = demo_policy()
      draft = draft_version_fixture(policy, %{requires_refresher: true})
      credential = credential_fixture(user_fixture(), basics)

      conn =
        json_request(conn, :post, "#{@path}/#{draft.id}/publish", %{requires_refresher: false})

      assert %{"id" => id, "published_at" => published_at, "requires_refresher" => false} =
               json_response(conn, 200)

      assert id == draft.id
      assert {:ok, _at, 0} = DateTime.from_iso8601(published_at)
      assert %PolicyVersion{published_at: %DateTime{}, requires_refresher: false} = reload(draft)
      assert reload(credential).status == :active
      assert refresh_due_mails() == []

      event = assert_audit("policy_version.published", admin, draft)

      assert event.details == %{
               "policy_key" => "usage-policy",
               "number" => 1,
               "requires_refresher" => false,
               "refresh_due_count" => 0
             }
    end

    test "with requires_refresher moves the active credentials to refresh_due",
         %{conn: conn, admin: admin} do
      %{basics: basics, policy: policy} = demo_policy()
      published_version_fixture(policy)
      draft = draft_version_fixture(policy, %{requires_refresher: false})
      credential = credential_fixture(user_fixture(), basics)

      conn = json_request(conn, :get, "#{@path}/#{draft.id}")
      assert json_response(conn, 200)["refresh_due_count"] == 1

      conn =
        json_request(conn, :post, "#{@path}/#{draft.id}/publish", %{requires_refresher: true})

      assert %{"number" => 2, "requires_refresher" => true, "refresh_due_count" => 0} =
               json_response(conn, 200)

      assert %PolicyVersion{published_at: %DateTime{}, requires_refresher: true} = reload(draft)
      assert %Credential{status: :refresh_due, refresh_due_at: %DateTime{}} = reload(credential)
      assert refresh_due_mails() == [credential.id]

      assert_audit("policy_version.updated", admin, draft)
      event = assert_audit("policy_version.published", admin, draft)
      assert %{"requires_refresher" => true, "refresh_due_count" => 1} = event.details
    end

    test "a published version answers 409 published", %{conn: conn, admin: admin} do
      published = published_version_fixture(policy_fixture())

      conn =
        json_request(conn, :post, "#{@path}/#{published.id}/publish", %{requires_refresher: true})

      assert json_response(conn, 409) == %{"error" => "published"}

      assert %PolicyVersion{requires_refresher: false, published_at: published_at} =
               reload(published)

      assert published_at == published.published_at
      assert admin_events("policy_version.updated", admin) == []
      assert admin_events("policy_version.published", admin) == []
    end

    test "a draft below a published version answers 409 superseded and changes nothing",
         %{conn: conn, admin: admin} do
      %{basics: basics, policy: policy} = demo_policy()
      first = draft_version_fixture(policy, %{requires_refresher: false})
      second = published_version_fixture(policy)
      credential = credential_fixture(user_fixture(), basics)

      assert {first.number, second.number} == {1, 2}

      conn =
        json_request(conn, :post, "#{@path}/#{first.id}/publish", %{requires_refresher: true})

      assert json_response(conn, 409) == %{"error" => "superseded"}
      assert %PolicyVersion{published_at: nil, requires_refresher: false} = reload(first)
      assert %Credential{status: :active, refresh_due_at: nil} = reload(credential)
      assert refresh_due_mails() == []
      assert admin_events("policy_version.updated", admin) == []
      assert admin_events("policy_version.published", admin) == []

      conn = json_request(conn, :get, "#{@path}/#{first.id}")
      assert json_response(conn, 200)["refresh_due_count"] == 1
    end

    test "answers 404 for an unknown id and 422 without requires_refresher", %{conn: conn} do
      conn =
        json_request(conn, :post, "#{@path}/#{Ecto.UUID.generate()}/publish", %{
          requires_refresher: false
        })

      assert json_response(conn, 404) == %{"error" => "not_found"}

      draft = draft_version_fixture(policy_fixture())

      for body <- [%{}, %{requires_refresher: "yes"}, %{requires_refresher: true, extra: 1}] do
        conn = json_request(conn, :post, "#{@path}/#{draft.id}/publish", body)
        assert %{"error" => "validation_failed"} = json_response(conn, 422)
      end

      assert reload(draft).published_at == nil
    end
  end
end
