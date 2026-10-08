defmodule EspalierWeb.Me.SessionControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts

  setup do
    %{user: user_fixture()}
  end

  test "lists the sessions of the user and marks the calling one", %{conn: conn, user: user} do
    conn = log_in_user(conn, user)
    {_other, other_session} = session_fixture(user)

    sessions = conn |> get("/api/me/sessions") |> json_response(200) |> Map.fetch!("sessions")
    assert length(sessions) == 2
    assert [%{"current" => true} = current] = Enum.filter(sessions, & &1["current"])
    assert Enum.find(sessions, &(&1["id"] == other_session.id))["current"] == false
    assert current["strength"] == "mfa"
    assert current["auth_methods"] == ["password", "totp"]

    for key <-
          ~w(id current device strength auth_methods authenticated_at last_seen_at expires_at) do
      assert Map.has_key?(current, key)
    end
  end

  test "ending a session needs a recent second factor", %{conn: conn, user: user} do
    {_other, other_session} = session_fixture(user)

    stale = DateTime.add(DateTime.utc_now(:second), -11, :minute)
    conn = conn |> log_in_user(user, %{mfa_at: stale}) |> with_csrf_token()
    conn = delete(conn, "/api/me/sessions/#{other_session.id}")
    assert json_response(conn, 403) == %{"error" => "reauth_required"}
  end

  test "ends one of the user's sessions and answers 404 for others", %{conn: conn, user: user} do
    {other, other_session} = session_fixture(user)
    {_foreign, foreign_session} = session_fixture(user_fixture())
    conn = conn |> log_in_user(user) |> with_csrf_token()

    assert conn |> delete("/api/me/sessions/#{other_session.id}") |> response(204)
    assert Accounts.get_session_by_token(other) == {:error, :not_found}

    conn = delete(conn, "/api/me/sessions/#{foreign_session.id}")
    assert json_response(conn, 404) == %{"error" => "not_found"}
  end

  test "answers 401 without a session", %{conn: conn} do
    assert conn |> get("/api/me/sessions") |> json_response(401) == %{
             "error" => "unauthenticated"
           }
  end
end
