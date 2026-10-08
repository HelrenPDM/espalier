defmodule EspalierWeb.SessionControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts

  describe "GET /api/session" do
    setup :register_and_log_in_user

    test "shows the user, the roles and the session", %{conn: conn, user: user} do
      body = conn |> get("/api/session") |> json_response(200)

      assert body["user"] == %{
               "id" => user.id,
               "display_name" => user.display_name,
               "email" => user.email,
               "locale" => "en"
             }

      assert body["roles"] == ["learner"]
      assert body["session"]["strength"] == "mfa"
      assert body["session"]["auth_methods"] == ["password", "totp"]
      assert body["session"]["recent_auth_until"]
      assert body["pending"] == nil
    end
  end

  describe "DELETE /api/session" do
    setup :register_and_log_in_user

    test "deletes the session row and answers 204", %{conn: conn, token: token} do
      ref = attach_security_events()
      conn = conn |> with_csrf_token() |> delete("/api/session")
      assert response(conn, 204)
      assert Accounts.get_session_by_token(token) == {:error, :not_found}
      assert get_session(conn, :user_token) == nil
      assert_received {^ref, %{name: :session_logout}}

      conn = conn |> next_request() |> get("/api/session")
      assert json_response(conn, 200)["user"] == nil
    end
  end
end
