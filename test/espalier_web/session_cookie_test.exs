defmodule EspalierWeb.SessionCookieTest do
  use EspalierWeb.ConnCase, async: false

  test "the session cookie of a demo sign-in is __Host-, Secure, HttpOnly and Strict", %{
    conn: conn
  } do
    put_setting(:auth_demo, true)
    conn = conn |> with_csrf_token() |> post("/api/auth/demo", %{slot: 1})
    assert json_response(conn, 200)

    [cookie] =
      conn
      |> get_resp_header("set-cookie")
      |> Enum.filter(&String.starts_with?(&1, "__Host-espalier="))

    attributes = cookie |> String.split(";") |> Enum.map(&String.trim/1) |> tl()
    assert "path=/" in attributes
    assert "secure" in attributes
    assert "HttpOnly" in attributes
    assert "SameSite=Strict" in attributes
    refute Enum.any?(attributes, &String.starts_with?(String.downcase(&1), "domain"))
    refute Enum.any?(attributes, &String.starts_with?(String.downcase(&1), "max-age"))
  end

  test "GET /api/session sets the cookie with the CSRF token", %{conn: conn} do
    conn = get(conn, "/api/session")
    body = json_response(conn, 200)
    assert is_binary(body["csrf_token"])
    assert body["user"] == nil
    assert body["session"] == nil
    assert body["pending"] == nil
    assert body["roles"] == []
    assert body["providers"] == []
    assert body["flags"] == %{"demo" => false, "local_accounts" => true, "signup" => "closed"}
    assert [cookie] = get_resp_header(conn, "set-cookie")
    assert cookie =~ "__Host-espalier="
  end
end
