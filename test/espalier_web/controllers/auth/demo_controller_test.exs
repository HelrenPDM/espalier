defmodule EspalierWeb.Auth.DemoControllerTest do
  # Switches AUTH_DEMO for the whole node.
  use EspalierWeb.ConnCase, async: false

  alias Espalier.Accounts
  alias Espalier.Accounts.UserToken

  describe "with AUTH_DEMO=true" do
    setup do
      put_setting(:auth_demo, true)
      :ok
    end

    test "signs in to a demo session", %{conn: conn} do
      conn = conn |> with_csrf_token() |> post("/api/auth/demo", %{slot: 1})
      body = json_response(conn, 200)
      assert body["user"]["display_name"] == "Test person 1"
      assert body["flags"]["demo"] == true

      conn = conn |> next_request() |> get("/api/session")
      body = json_response(conn, 200)
      assert body["user"]["display_name"] == "Test person 1"
      assert body["user"]["email"] == nil
      assert body["roles"] == ["learner"]
      assert body["session"]["strength"] == "demo"
      assert body["session"]["auth_methods"] == ["demo"]
      assert body["session"]["provider_key"] == nil
      assert body["session"]["recent_auth_until"] == nil
      assert body["session"]["idle_timeout_minutes"] == 60

      token = get_session(conn, :user_token)
      assert %UserToken{provider_key: nil, strength: :demo} = session_row(token)
    end

    test "the security events carry the provider demo", %{conn: conn} do
      ref = attach_security_events()
      conn |> with_csrf_token() |> post("/api/auth/demo", %{slot: 3})
      assert_received {^ref, %{name: :session_created, provider: "demo"}}
      assert_received {^ref, %{name: :authn_login_success, provider: "demo", factor: "demo"}}
    end

    test "a second sign-in in the same conn leaves the first token without a row", %{conn: conn} do
      conn = conn |> with_csrf_token() |> post("/api/auth/demo", %{slot: 1})
      first = get_session(conn, :user_token)
      csrf = json_response(conn, 200)["csrf_token"]

      conn =
        conn
        |> next_request()
        |> put_req_header("x-csrf-token", csrf)
        |> post("/api/auth/demo", %{slot: 2})

      second = get_session(conn, :user_token)
      assert json_response(conn, 200)["user"]["display_name"] == "Test person 2"
      assert first != second
      assert Accounts.get_session_by_token(first) == {:error, :not_found}
      assert {:ok, _user, _session} = Accounts.get_session_by_token(second)
    end

    test "the sign-in rotates the CSRF token", %{conn: conn} do
      conn = with_csrf_token(conn)
      [before] = get_req_header(conn, "x-csrf-token")
      conn = post(conn, "/api/auth/demo", %{slot: 4})
      assert json_response(conn, 200)["csrf_token"] != before

      # The token of the anonymous session no longer passes.
      conn =
        conn |> next_request() |> put_req_header("x-csrf-token", before) |> delete("/api/session")

      assert json_response(conn, 403) == %{"error" => "csrf"}
    end

    test "a demo sign-in with a user-agent shows its summary as device", %{conn: conn} do
      conn =
        conn
        |> with_csrf_token()
        |> put_req_header(
          "user-agent",
          "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0"
        )

      conn = post(conn, "/api/auth/demo", %{slot: 5})
      assert json_response(conn, 200)

      sessions = conn |> next_request() |> get("/api/me/sessions") |> json_response(200)
      assert [%{"device" => "Firefox on Linux", "current" => true}] = sessions["sessions"]
    end

    test "an invalid slot answers 400 bad_request", %{conn: conn} do
      conn = conn |> with_csrf_token() |> post("/api/auth/demo", %{slot: 21})
      assert json_response(conn, 400) == %{"error" => "bad_request"}
    end
  end

  test "answers 404 with AUTH_DEMO=false", %{conn: conn} do
    put_setting(:auth_demo, false)
    conn = conn |> with_csrf_token() |> post("/api/auth/demo", %{slot: 1})
    assert json_response(conn, 404) == %{"error" => "not_found"}
  end
end
