defmodule EspalierWeb.ProviderControllerTest do
  use EspalierWeb.ConnCase, async: false

  @entry %{
    key: "corp",
    type: "oidc",
    kind: "redirect",
    label: "Company account",
    start_url: "/auth/oidc/corp"
  }

  test "GET /auth/providers lists no provider in this task", %{conn: conn} do
    assert conn |> get("/auth/providers") |> json_response(200) == %{"providers" => []}
  end

  test "a configured public entry appears in /auth/providers and in the session payload", %{
    conn: conn
  } do
    put_setting(:auth_providers, [@entry])
    expected = [Map.new(@entry, fn {key, value} -> {Atom.to_string(key), value} end)]

    assert conn |> get("/auth/providers") |> json_response(200) == %{"providers" => expected}

    assert conn |> get("/api/session") |> json_response(200) |> Map.fetch!("providers") ==
             expected
  end

  test "GET /auth/providers fetches no session and sets no cookie", %{conn: conn} do
    conn = get(conn, "/auth/providers")
    assert get_resp_header(conn, "set-cookie") == []
  end
end
