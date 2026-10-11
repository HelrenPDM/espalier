defmodule EspalierWeb.Credentials.IntegrationTest do
  @moduledoc """
  The integration API of task 0013 (spec steps 15, 19 and 24, bullet
  "Routes"): `POST /api/integration/credential-lookups` authenticates a
  machine client by the bearer token alone and runs without session
  cookie, CSRF token and Fetch Metadata (ASVS 3.5.1 and 3.5.2). A missing
  or unknown token answers 401 and logs `authn_login_fail`, a client
  without `credentials:read` answers 403 and logs `authz_fail` (ASVS 8.2.1
  and 16.3.2). The answer holds qualification code, status, unlocked tasks
  and validity of the credentials in force only (ASVS 15.3.1), the address
  travels in the body (ASVS 14.2.1), the response is not stored (ASVS
  14.2.2 and 14.3.2), an extra member answers 422 (ASVS 15.3.3), and the
  log holds neither address nor token (ASVS 16.2.5).
  """
  # Logger.put_module_level/2 changes the level of Phoenix.Logger and
  # Espalier.SecurityLog for the node.
  use EspalierWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Accounts.{ApiClient, UserToken}
  alias Espalier.Repo

  @path "/api/integration/credential-lookups"

  setup do
    program = publish_demo!()
    {_client, token} = api_client_fixture()
    %{program: program, token: token, user: user_fixture()}
  end

  # The request of a machine client: JSON in and out, no cookie, no CSRF
  # token, no Origin and no Fetch Metadata. The real CSRF check stays on, so
  # a CSRF layer in the pipeline would reject the request.
  defp machine_conn(authorization) do
    conn =
      build_conn()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    if authorization,
      do: put_req_header(conn, "authorization", authorization),
      else: conn
  end

  defp bearer(token), do: machine_conn("Bearer " <> token)

  defp lookup(conn, body), do: post(conn, @path, JSON.encode!(body))

  # A token of the format of Accounts.create_api_client/2 for a client row
  # inserted without the changeset, which requires at least one scope.
  defp client_without_scope do
    bytes = UserToken.generate()

    Repo.insert!(%ApiClient{
      name: "client without scope",
      token_hash: UserToken.hash(bytes),
      scopes: []
    })

    Base.url_encode64(bytes, padding: false)
  end

  describe "authentication" do
    test "answers 401 unauthenticated without a token and for an unknown token", %{user: user} do
      ref = attach_security_events()
      unknown = Base.url_encode64(UserToken.generate(), padding: false)

      for authorization <- [nil, "Bearer " <> unknown, "Bearer", "Basic " <> unknown] do
        conn = authorization |> machine_conn() |> lookup(%{email: user.email})

        assert json_response(conn, 401) == %{"error" => "unauthenticated"}, inspect(authorization)
        assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
        assert_received {^ref, %{name: :authn_login_fail, factor: "api_token"}}
      end

      refute_received {^ref, %{name: :authz_fail}}
    end

    test "answers 401 for the session cookie of a signed-in admin without authorization",
         %{user: user} do
      admin = user_with_role_fixture(:admin)
      conn = api_conn() |> log_in_user(admin) |> with_csrf_token()

      # The conn carries the session cookie of a valid admin session and
      # its CSRF token.
      assert conn |> get_req_header("cookie") |> Enum.join("; ") =~ "__Host-espalier="
      assert json_response(get(conn, "/api/session"), 200)["user"]["id"] == admin.id

      ref = attach_security_events()

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(@path, JSON.encode!(%{email: user.email}))

      assert json_response(response, 401) == %{"error" => "unauthenticated"}
      assert_received {^ref, %{name: :authn_login_fail, factor: "api_token"}}
    end

    test "answers 403 forbidden and logs authz_fail for a client without credentials:read",
         %{program: program, user: user} do
      credential_fixture(user, qualification!(program, "basics"))
      token = client_without_scope()
      ref = attach_security_events()

      conn = token |> bearer() |> lookup(%{email: user.email})

      assert json_response(conn, 403) == %{"error" => "forbidden"}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert_received {^ref, %{name: :authz_fail, factor: "api_token", reason: "scope"}}
      refute_received {^ref, %{name: :authn_login_fail}}
    end
  end

  describe "the lookup" do
    test "returns the credentials in force of a known address with four members each",
         %{program: program, token: token, user: user} do
      basics = qualification!(program, "basics")
      workshop = qualification!(program, "workshop")

      credential_fixture(user, basics, %{
        issued_at: ~U[2026-09-01 08:00:00Z],
        valid_until: ~D[2027-09-01]
      })

      credential_fixture(user, workshop, %{
        status: :refresh_due,
        refresh_due_at: ~U[2026-10-01 08:00:00Z]
      })

      conn = token |> bearer() |> lookup(%{email: user.email})

      assert json_response(conn, 200) == %{
               "credentials" => [
                 %{
                   "qualification_code" => "basics",
                   "status" => "active",
                   "unlocks_snapshot" => basics.unlocks,
                   "valid_until" => "2027-09-01"
                 },
                 %{
                   "qualification_code" => "workshop",
                   "status" => "refresh_due",
                   "unlocks_snapshot" => workshop.unlocks,
                   "valid_until" => nil
                 }
               ]
             }

      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "leaves out expired and revoked credentials", %{program: program, token: token} do
      user = user_fixture()

      credential_fixture(user, qualification!(program, "basics"), %{
        status: :expired,
        valid_until: ~D[2026-01-01],
        refresh_due_at: ~U[2025-12-01 08:00:00Z]
      })

      credential_fixture(user, qualification!(program, "workshop"), %{status: :revoked})

      conn = token |> bearer() |> lookup(%{email: user.email})
      assert json_response(conn, 200) == %{"credentials" => []}
    end

    test "returns an empty list for an unknown address", %{program: program, token: token} do
      credential_fixture(user_fixture(), qualification!(program, "basics"))

      conn = token |> bearer() |> lookup(%{email: unique_user_email()})

      assert json_response(conn, 200) == %{"credentials" => []}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "matches the address in any letter case and with surrounding spaces",
         %{program: program, token: token, user: user} do
      credential_fixture(user, qualification!(program, "basics"))

      for email <- [user.email, String.upcase(user.email), "  #{user.email} "] do
        conn = token |> bearer() |> lookup(%{email: email})

        assert [%{"qualification_code" => "basics", "status" => "active"}] =
                 json_response(conn, 200)["credentials"]
      end
    end

    test "answers 422 validation_failed for a body with an extra member",
         %{program: program, token: token, user: user} do
      credential_fixture(user, qualification!(program, "basics"))

      conn = token |> bearer() |> lookup(%{email: user.email, user_id: user.id})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"user_id" => ["unexpected_field"]}
             }

      conn = token |> bearer() |> post(@path, JSON.encode!([%{email: user.email}]))
      assert json_response(conn, 422)["error"] == "validation_failed"

      conn = token |> bearer() |> lookup(%{})
      assert json_response(conn, 422)["fields"] == %{"email" => ["missing_field"]}
    end

    test "works without x-csrf-token, cookie, Origin and sec-fetch-site and sets no cookie",
         %{program: program, token: token, user: user} do
      credential_fixture(user, qualification!(program, "basics"))
      conn = bearer(token)

      for header <- ~w(x-csrf-token cookie origin sec-fetch-site sec-fetch-mode) do
        assert get_req_header(conn, header) == [], header
      end

      conn = lookup(conn, %{email: user.email})

      assert [%{"qualification_code" => "basics"}] = json_response(conn, 200)["credentials"]
      assert get_resp_header(conn, "set-cookie") == []
      assert get_resp_header(conn, "access-control-allow-origin") == []
    end
  end

  test "the log holds neither the looked-up address nor the token",
       %{program: program, token: token, user: user} do
    credential_fixture(user, qualification!(program, "basics"))
    Logger.put_module_level(Phoenix.Logger, :debug)
    Logger.put_module_level(Espalier.SecurityLog, :info)

    on_exit(fn ->
      Logger.delete_module_level(Phoenix.Logger)
      Logger.delete_module_level(Espalier.SecurityLog)
    end)

    unknown = unique_user_email()

    log =
      capture_log([level: :debug], fn ->
        conn = token |> bearer() |> lookup(%{email: user.email})
        assert json_response(conn, 200)["credentials"] != []

        conn = token |> bearer() |> lookup(%{email: unknown})
        assert json_response(conn, 200) == %{"credentials" => []}

        conn = client_without_scope() |> bearer() |> lookup(%{email: user.email})
        assert json_response(conn, 403)

        conn = machine_conn(nil) |> lookup(%{email: user.email})
        assert json_response(conn, 401)
      end)

    assert log =~ "Parameters"
    assert log =~ "[FILTERED]"
    assert log =~ "authn_login_fail"
    refute log =~ user.email
    refute log =~ String.downcase(unknown)
    refute log =~ token
  end
end
