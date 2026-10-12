defmodule EspalierWeb.Admin.WebhookControllerTest do
  @moduledoc """
  The webhook routes of the admin area (task 0015, steps 2 and 19):
  `/api/admin/webhooks` lists, reads, creates, changes and deletes webhooks
  for a signed-in admin with a passkey, in the nested body and answer
  shapes of `mix phx.gen.json`. An unknown id answers 404, and every change
  writes its audit event with actor and subject (ASVS 8.2.1).

  A webhook admits an `https` URL of a host in `WEBHOOK_ALLOWED_HOSTS` of at
  most 255 characters and a `secret_env` with the prefix `WEBHOOK_SECRET_`
  that names a set variable. Every other body answers 422, with
  `host_not_allowed` on `url` for a host outside the list and
  `secret_env_unset` for an unset or empty variable.
  """
  # put_setting/2 changes :webhook_allowed_hosts and :webhook_allow_http,
  # and System.put_env/2 the environment of the node.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.CredentialsFixtures

  alias Espalier.Audit.AuditEvent
  alias Espalier.Credentials.Webhook
  alias Espalier.Repo

  @path "/api/admin/webhooks"
  @url "https://hooks.example.org/espalier"

  setup do
    put_setting(:webhook_allowed_hosts, [{"hooks.example.org", nil}])
    secret_env = put_secret_env!("a-test-secret")
    admin = user_with_role_fixture(:admin)
    _passkey = passkey_fixture(admin)

    %{
      admin: admin,
      conn: log_in_user(api_conn(), admin),
      secret_env: secret_env,
      attrs: %{
        url: @url,
        events: ["credential.issued", "credential.revoked"],
        secret_env: secret_env,
        active: true
      }
    }
  end

  # Sets a WEBHOOK_SECRET_* variable that no other test uses and removes it
  # when the test exits.
  defp put_secret_env!(value) do
    name = unset_secret_env()
    System.put_env(name, value)
    on_exit(fn -> System.delete_env(name) end)
    name
  end

  defp unset_secret_env, do: "WEBHOOK_SECRET_ADMIN_TEST_#{System.unique_integer([:positive])}"

  defp audit_events(action),
    do: Repo.all(from e in AuditEvent, where: e.action == ^action)

  defp assert_audit(action, admin, subject_id, details) do
    assert [event] = audit_events(action)
    assert event.actor_id == admin.id
    assert event.subject_type == "Webhook"
    assert event.subject_id == subject_id
    assert event.details == details
  end

  defp assert_nothing_created do
    assert Repo.aggregate(Webhook, :count) == 0
    assert audit_events("webhook.created") == []
  end

  describe "index" do
    test "lists the webhooks ordered by URL, with no-store", %{conn: conn} do
      second = webhook_fixture(url: "https://hooks.example.org/b", active: false)
      first = webhook_fixture(url: "https://hooks.example.org/a", events: ["credential.issued"])

      conn = json_request(conn, :get, @path)

      assert json_response(conn, 200)["data"] == [
               %{
                 "id" => first.id,
                 "url" => "https://hooks.example.org/a",
                 "events" => ["credential.issued"],
                 "secret_env" => "WEBHOOK_SECRET_TEST",
                 "active" => true
               },
               %{
                 "id" => second.id,
                 "url" => "https://hooks.example.org/b",
                 "events" => Webhook.events(),
                 "secret_env" => "WEBHOOK_SECRET_TEST",
                 "active" => false
               }
             ]

      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "show" do
    test "returns one webhook", %{conn: conn} do
      webhook = webhook_fixture()

      conn = json_request(conn, :get, "#{@path}/#{webhook.id}")

      assert json_response(conn, 200)["data"] == %{
               "id" => webhook.id,
               "url" => @url,
               "events" => Webhook.events(),
               "secret_env" => "WEBHOOK_SECRET_TEST",
               "active" => true
             }
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      conn = json_request(conn, :get, "#{@path}/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "create" do
    test "creates a webhook and writes webhook.created without the URL",
         %{conn: conn, admin: admin, attrs: attrs, secret_env: secret_env} do
      conn = json_request(conn, :post, @path, %{webhook: Map.delete(attrs, :active)})

      assert %{"id" => id} = data = json_response(conn, 201)["data"]

      assert data == %{
               "id" => id,
               "url" => @url,
               "events" => ["credential.issued", "credential.revoked"],
               "secret_env" => secret_env,
               "active" => true
             }

      assert get_resp_header(conn, "location") == ["#{@path}/#{id}"]
      assert %Webhook{url: @url, active: true} = Repo.get!(Webhook, id)

      assert_audit("webhook.created", admin, id, %{
        "events" => ["credential.issued", "credential.revoked"],
        "secret_env" => secret_env
      })

      conn = json_request(conn, :get, "#{@path}/#{id}")
      assert json_response(conn, 200)["data"] == data
    end

    test "answers 422 for secret_env CLOAK_KEY_V1", %{conn: conn, attrs: attrs} do
      conn = json_request(conn, :post, @path, %{webhook: %{attrs | secret_env: "CLOAK_KEY_V1"}})

      # The request schema rejects the name before the controller reads any
      # variable.
      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"webhook" => ["invalid_format"]}
             }

      assert_nothing_created()
    end

    test "answers 422 secret_env_unset for an unset or empty variable",
         %{conn: conn, attrs: attrs} do
      for secret_env <- [unset_secret_env(), put_secret_env!("")] do
        conn = json_request(conn, :post, @path, %{webhook: %{attrs | secret_env: secret_env}})
        assert json_response(conn, 422) == %{"error" => "secret_env_unset"}
      end

      assert_nothing_created()
    end

    test "answers 422 for an http URL of an admitted host while http is off",
         %{conn: conn, attrs: attrs} do
      put_setting(:webhook_allow_http, false)

      conn =
        json_request(conn, :post, @path, %{
          webhook: %{attrs | url: "http://hooks.example.org/espalier"}
        })

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"url" => ["scheme"]}
             }

      assert_nothing_created()
    end

    test "answers 422 for a URL longer than 255 characters", %{conn: conn, attrs: attrs} do
      url = "https://hooks.example.org/" <> String.duplicate("a", 230)
      assert String.length(url) == 256

      conn = json_request(conn, :post, @path, %{webhook: %{attrs | url: url}})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"webhook" => ["max_length"]}
             }

      assert_nothing_created()
    end

    test "answers 422 with host_not_allowed for a host or port outside the list",
         %{conn: conn, attrs: attrs} do
      for url <- [
            "https://other.example.org/espalier",
            "https://hooks.example.org:8443/espalier",
            "https://hooks.example.org.attacker.example/espalier"
          ] do
        conn = json_request(conn, :post, @path, %{webhook: %{attrs | url: url}})

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"url" => ["host_not_allowed"]}
               }
      end

      assert_nothing_created()
    end

    test "answers 422 for other bodies that do not fit the schema",
         %{conn: conn, attrs: attrs} do
      for body <- [
            %{webhook: %{attrs | events: []}},
            %{webhook: %{attrs | events: ["credential.deleted"]}},
            %{webhook: %{attrs | secret_env: "WEBHOOK_SECRET_lower"}},
            %{webhook: Map.delete(attrs, :url)},
            %{webhook: Map.put(attrs, :extra, true)},
            attrs
          ] do
        conn = json_request(conn, :post, @path, body)
        assert %{"error" => "validation_failed"} = json_response(conn, 422)
      end

      assert_nothing_created()
    end
  end

  describe "update" do
    test "PUT changes every field and writes webhook.updated", %{conn: conn, admin: admin} do
      webhook = webhook_fixture()
      secret_env = put_secret_env!("another-secret")

      conn =
        json_request(conn, :put, "#{@path}/#{webhook.id}", %{
          webhook: %{
            url: "https://hooks.example.org/v2",
            events: ["credential.expired"],
            secret_env: secret_env,
            active: false
          }
        })

      assert json_response(conn, 200)["data"] == %{
               "id" => webhook.id,
               "url" => "https://hooks.example.org/v2",
               "events" => ["credential.expired"],
               "secret_env" => secret_env,
               "active" => false
             }

      assert %Webhook{active: false, secret_env: ^secret_env} = Repo.get!(Webhook, webhook.id)

      assert_audit("webhook.updated", admin, webhook.id, %{
        "events" => ["credential.expired"],
        "secret_env" => secret_env
      })
    end

    test "PATCH changes the given fields only", %{conn: conn, secret_env: secret_env} do
      webhook = webhook_fixture(secret_env: secret_env)

      conn = json_request(conn, :patch, "#{@path}/#{webhook.id}", %{webhook: %{active: false}})

      assert %{"url" => @url, "secret_env" => ^secret_env, "active" => false} =
               json_response(conn, 200)["data"]
    end

    test "answers 422 for an unset variable, a host outside the list and a bad body",
         %{conn: conn, secret_env: secret_env} do
      webhook = webhook_fixture(secret_env: secret_env)

      conn =
        json_request(conn, :patch, "#{@path}/#{webhook.id}", %{
          webhook: %{secret_env: unset_secret_env()}
        })

      assert json_response(conn, 422) == %{"error" => "secret_env_unset"}

      conn =
        json_request(conn, :patch, "#{@path}/#{webhook.id}", %{
          webhook: %{url: "https://other.example.org/espalier"}
        })

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"url" => ["host_not_allowed"]}
             }

      conn =
        json_request(conn, :patch, "#{@path}/#{webhook.id}", %{
          webhook: %{secret_env: "CLOAK_KEY_V1"}
        })

      assert %{"error" => "validation_failed"} = json_response(conn, 422)

      assert Repo.get!(Webhook, webhook.id) == webhook
      assert audit_events("webhook.updated") == []
    end

    test "switches off a webhook whose variable is gone, and keeps it off while the variable stays unset",
         %{conn: conn} do
      webhook = webhook_fixture(secret_env: unset_secret_env())

      conn = json_request(conn, :patch, "#{@path}/#{webhook.id}", %{webhook: %{active: false}})
      assert %{"active" => false} = json_response(conn, 200)["data"]

      conn = json_request(conn, :patch, "#{@path}/#{webhook.id}", %{webhook: %{active: true}})
      assert json_response(conn, 422) == %{"error" => "secret_env_unset"}
      assert %Webhook{active: false} = Repo.get!(Webhook, webhook.id)
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      conn =
        json_request(conn, :patch, "#{@path}/#{Ecto.UUID.generate()}", %{
          webhook: %{active: false}
        })

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "delete" do
    test "deletes a webhook and writes webhook.deleted", %{conn: conn, admin: admin} do
      webhook = webhook_fixture()
      other = webhook_fixture(url: "https://hooks.example.org/other")

      conn = json_request(conn, :delete, "#{@path}/#{webhook.id}")

      assert response(conn, 204) == ""
      assert Repo.get(Webhook, webhook.id) == nil
      assert Repo.get(Webhook, other.id)

      assert_audit("webhook.deleted", admin, webhook.id, %{
        "events" => Webhook.events(),
        "secret_env" => "WEBHOOK_SECRET_TEST"
      })

      conn = json_request(conn, :get, "#{@path}/#{webhook.id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "answers 404 for an unknown id", %{conn: conn} do
      conn = json_request(conn, :delete, "#{@path}/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert audit_events("webhook.deleted") == []
    end
  end
end
