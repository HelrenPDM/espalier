defmodule EspalierWeb.Plugs.SecurityHeadersTest do
  use EspalierWeb.ConnCase, async: true

  alias EspalierWeb.Plugs.SecurityHeaders

  @expected %{
    "content-security-policy" =>
      "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; " <>
        "object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    "content-security-policy-report-only" => "require-trusted-types-for 'script'",
    "cross-origin-opener-policy" => "same-origin",
    "cross-origin-resource-policy" => "same-origin",
    "referrer-policy" => "strict-origin-when-cross-origin",
    "x-content-type-options" => "nosniff",
    "permissions-policy" =>
      "camera=(), microphone=(), geolocation=(), payment=(), usb=(), " <>
        "publickey-credentials-create=(self), publickey-credentials-get=(self)",
    "vary" => "Sec-Fetch-Site, Sec-Fetch-Mode, Sec-Fetch-Dest"
  }

  for path <- ["/health", "/api/session", "/"] do
    test "#{path} carries every security header and no CORS header", %{conn: conn} do
      conn = get(conn, unquote(path))

      for {name, value} <- @expected do
        assert get_resp_header(conn, name) == [value], name
      end

      assert get_resp_header(conn, "access-control-allow-origin") == []
    end
  end

  test "/api/session carries cache-control: no-store and a JSON content type", %{conn: conn} do
    conn = get(conn, "/api/session")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/json"
  end

  test "/api/auth and /api/me answers are not stored, /health may be", %{conn: conn} do
    assert get_resp_header(post(conn, "/api/auth/password", %{}), "cache-control") == ["no-store"]
    assert get_resp_header(get(conn, "/api/me/sessions"), "cache-control") == ["no-store"]
    refute get_resp_header(get(conn, "/health"), "cache-control") == ["no-store"]
  end

  test "a vary header of another plug is merged" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> SecurityHeaders.call([])
      |> put_resp_header("vary", "Accept-Encoding")
      |> send_resp(200, "")

    assert get_resp_header(conn, "vary") == [
             "Accept-Encoding, Sec-Fetch-Site, Sec-Fetch-Mode, Sec-Fetch-Dest"
           ]
  end
end
