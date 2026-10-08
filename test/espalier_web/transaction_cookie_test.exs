defmodule EspalierWeb.TransactionCookieTest do
  use EspalierWeb.ConnCase, async: false

  alias EspalierWeb.TransactionCookie

  defp with_secret(conn),
    do: %{conn | secret_key_base: EspalierWeb.Endpoint.config(:secret_key_base)}

  defp fresh, do: with_secret(build_conn())

  defp next(conn), do: conn |> recycle() |> with_secret()

  test "put/3 reads back with get/2 and fetch/1 in the next request" do
    conn =
      fresh() |> TransactionCookie.put(:nonce, "n-1") |> TransactionCookie.put("purpose", "link")

    assert TransactionCookie.get(conn, :nonce) == "n-1"

    conn = next(conn)
    assert TransactionCookie.get(conn, :nonce) == "n-1"
    assert TransactionCookie.fetch(conn) == %{"nonce" => "n-1", "purpose" => "link"}
  end

  test "a value written through Plug.Session with session_options/0 reads back" do
    conn =
      fresh()
      |> Plug.Session.call(Plug.Session.init(TransactionCookie.session_options()))
      |> fetch_session()
      |> put_session(:provider_key, "corp")
      |> send_resp(200, "")

    assert TransactionCookie.fetch(next(conn)) == %{"provider_key" => "corp"}
  end

  test "a value written by the helper reads back through Plug.Session" do
    conn = fresh() |> TransactionCookie.put(:state_hash, "h") |> send_resp(200, "")

    conn =
      conn
      |> next()
      |> Plug.Session.call(Plug.Session.init(TransactionCookie.session_options()))
      |> fetch_session()

    assert get_session(conn, :state_hash) == "h"
  end

  test "delete/2 removes one key and clear/1 deletes the cookie" do
    conn = fresh() |> TransactionCookie.put(:a, 1) |> TransactionCookie.put(:b, 2)
    conn = conn |> next() |> TransactionCookie.delete(:a)
    assert TransactionCookie.fetch(next(conn)) == %{"b" => 2}

    conn = conn |> next() |> TransactionCookie.clear()
    assert TransactionCookie.fetch(conn) == %{}
    assert TransactionCookie.fetch(next(conn)) == %{}
  end

  test "a cookie that fails verification reads as empty" do
    conn = put_req_cookie(fresh(), "__Host-espalier_tx", "forged")
    assert TransactionCookie.fetch(conn) == %{}
  end

  test "the cookie is __Host-espalier_tx with Lax, Secure, HttpOnly and 10 minutes" do
    conn = fresh() |> TransactionCookie.put(:nonce, "n") |> send_resp(200, "")
    [cookie] = get_resp_header(conn, "set-cookie")
    [name_value | attributes] = cookie |> String.split(";") |> Enum.map(&String.trim/1)

    assert String.starts_with?(name_value, "__Host-espalier_tx=")
    assert "path=/" in attributes
    assert "secure" in attributes
    assert "HttpOnly" in attributes
    assert "SameSite=Lax" in attributes
    assert "max-age=600" in attributes
    refute Enum.any?(attributes, &String.starts_with?(String.downcase(&1), "domain"))
  end

  test "read_main_session/1 returns the user_token of a demo sign-in", %{conn: conn} do
    put_setting(:auth_demo, true)
    conn = conn |> with_csrf_token() |> post("/api/auth/demo", %{slot: 1})
    token = get_session(conn, :user_token)

    assert %{"user_token" => ^token} = TransactionCookie.read_main_session(next(conn))
    assert TransactionCookie.read_main_session(fresh()) == %{}
  end
end
