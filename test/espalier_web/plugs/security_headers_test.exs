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

  # Task 0013 step 15 (ASVS 14.2.2 and 14.3.2): the routes that return
  # personal data outside /api/session, /api/auth and /api/me; GET
  # /api/policies carries the user's own acknowledgements.
  test "answers of facilitator, registrar, integration, attendance and policy routes are not stored",
       %{conn: conn} do
    format_id = Ecto.UUID.generate()

    for {method, path} <- [
          {"POST", "/api/facilitator/user-lookups"},
          {"GET", "/api/registrar/credentials?qualification=basics"},
          {"POST", "/api/integration/credential-lookups"},
          {"POST", "/api/formats/#{format_id}/attendance"},
          {"GET", "/api/policies"}
        ] do
      response = dispatch(conn, @endpoint, method, path, nil)
      assert get_resp_header(response, "cache-control") == ["no-store"], "#{method} #{path}"
    end

    refute get_resp_header(get(conn, "/health"), "cache-control") == ["no-store"]
  end

  test "the plug sets no-store under each prefix of task 0013 and not on /health" do
    no_store? = fn path ->
      conn =
        :get
        |> Phoenix.ConnTest.build_conn(path)
        |> SecurityHeaders.call([])
        |> send_resp(200, "")

      get_resp_header(conn, "cache-control") == ["no-store"]
    end

    for path <- [
          "/api/facilitator/user-lookups",
          "/api/facilitator/any",
          "/api/registrar/credentials",
          "/api/registrar/any",
          "/api/integration/credential-lookups",
          "/api/integration/any",
          "/api/formats/#{Ecto.UUID.generate()}/attendance",
          "/api/policies"
        ] do
      assert no_store?.(path), path
    end

    refute no_store?.("/health")
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
