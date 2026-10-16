defmodule EspalierWeb.Plugs.SecurityHeadersMediaTest do
  @moduledoc """
  The CSP of the application with the media allowlists (task 0018, step 14;
  ASVS 3.4.3): `SecurityHeaders.csp/2` as a pure function with and without
  hosts, `put_csp/2` with the header of a normal response, the base CSP of
  README section 6.5 on `/`, `/api/session` and `/health` in the test
  configuration, and the media CSP for a conn with the private flag
  `:espalier_media` (step 13).
  """
  # put_csp/2 changes a :persistent_term that every response reads.
  use EspalierWeb.ConnCase, async: false

  alias Espalier.Media
  alias EspalierWeb.Plugs.SecurityHeaders

  @base "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; " <>
          "object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"

  @media_csp "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; " <>
               "frame-ancestors 'none'; sandbox"

  @csp_key {SecurityHeaders, :csp}

  describe "csp/2" do
    test "with empty lists is the base CSP byte for byte" do
      assert SecurityHeaders.csp([], []) == @base

      assert SecurityHeaders.headers()
             |> List.keyfind("content-security-policy", 0) == {"content-security-policy", @base}
    end

    test "appends media-src with 'self' and the external hosts in their order" do
      assert SecurityHeaders.csp([{"cdn.example.org", nil}], []) ==
               @base <> "; media-src 'self' https://cdn.example.org"

      assert SecurityHeaders.csp(
               [{"videos.example.net", nil}, {"cdn.example.org", 8443}, {"a.example.com", nil}],
               []
             ) ==
               @base <>
                 "; media-src 'self' https://videos.example.net https://cdn.example.org:8443 " <>
                 "https://a.example.com"
    end

    test "appends frame-src with the embed hosts in their order" do
      assert SecurityHeaders.csp([], [{"player.example.org", nil}]) ==
               @base <> "; frame-src https://player.example.org"

      assert SecurityHeaders.csp([], [{"z.example.org", 8080}, {"player.example.org", nil}]) ==
               @base <> "; frame-src https://z.example.org:8080 https://player.example.org"
    end

    test "appends media-src before frame-src when both lists hold hosts" do
      csp =
        SecurityHeaders.csp(
          [{"cdn.example.org", nil}],
          [{"player.example.org", nil}, {"embed.example.net", 444}]
        )

      assert csp ==
               @base <>
                 "; media-src 'self' https://cdn.example.org" <>
                 "; frame-src https://player.example.org https://embed.example.net:444"

      # The base directives stay, object-src and base-uri among them.
      assert String.starts_with?(csp, @base)
      assert csp =~ "object-src 'none'"
      assert csp =~ "base-uri 'none'"
      assert csp |> String.split("; ") |> Enum.count(&String.starts_with?(&1, "media-src")) == 1
      assert csp |> String.split("; ") |> Enum.count(&String.starts_with?(&1, "frame-src")) == 1
    end

    test "names no http source and no wildcard" do
      csp = SecurityHeaders.csp([{"cdn.example.org", 80}], [{"player.example.org", nil}])
      refute csp =~ "http://"
      refute csp =~ "*"
      assert csp =~ "https://cdn.example.org:80"
    end
  end

  describe "put_csp/2" do
    setup do
      previous = :persistent_term.get(@csp_key, nil)

      on_exit(fn ->
        if previous,
          do: :persistent_term.put(@csp_key, previous),
          else: :persistent_term.erase(@csp_key)
      end)

      :ok
    end

    test "changes the CSP of a normal response and keeps the other headers", %{conn: conn} do
      :ok = SecurityHeaders.put_csp([{"cdn.example.org", nil}], [{"player.example.org", 8443}])

      expected =
        @base <>
          "; media-src 'self' https://cdn.example.org; frame-src https://player.example.org:8443"

      for path <- ["/health", "/api/session", "/"] do
        response = get(conn, path)
        assert get_resp_header(response, "content-security-policy") == [expected], path
        assert get_resp_header(response, "x-content-type-options") == ["nosniff"], path
        assert get_resp_header(response, "cross-origin-resource-policy") == ["same-origin"], path
      end

      :ok = SecurityHeaders.put_csp([], [])

      for path <- ["/health", "/api/session", "/"] do
        assert get_resp_header(get(conn, path), "content-security-policy") == [@base], path
      end
    end

    test "leaves the media CSP of the media route unchanged", %{conn: conn} do
      :ok = SecurityHeaders.put_csp([{"cdn.example.org", nil}], [{"player.example.org", nil}])

      response = get(conn, "/media/#{String.duplicate("0", 64)}.webp")
      assert response.status == 401
      assert get_resp_header(response, "content-security-policy") == [@media_csp]
    end
  end

  describe "the configured CSP" do
    test "/, /api/session and /health carry the base CSP in the test configuration", %{
      conn: conn
    } do
      assert Media.external_hosts() == []
      assert Media.embed_hosts() == []

      for path <- ["/", "/api/session", "/health"] do
        assert get_resp_header(get(conn, path), "content-security-policy") == [@base], path
      end
    end
  end

  describe "the media flag" do
    test "a conn with :espalier_media gets the media CSP, the other headers and no no-store" do
      for path <- ["/media/x.webp", "/api/admin/media", "/api/session"] do
        conn =
          :get
          |> Phoenix.ConnTest.build_conn(path)
          |> put_private(:espalier_media, true)
          |> SecurityHeaders.call([])
          |> put_resp_content_type("image/svg+xml", nil)
          |> send_resp(200, "")

        assert get_resp_header(conn, "content-security-policy") == [@media_csp], path
        assert get_resp_header(conn, "cache-control") != ["no-store"], path
        assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
        assert get_resp_header(conn, "cross-origin-resource-policy") == ["same-origin"]
        assert get_resp_header(conn, "cross-origin-opener-policy") == ["same-origin"]
        assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
        assert get_resp_header(conn, "content-type") == ["image/svg+xml; charset=utf-8"]
        assert get_resp_header(conn, "vary") == ["Sec-Fetch-Site, Sec-Fetch-Mode, Sec-Fetch-Dest"]
      end
    end

    test "a conn without the flag keeps the application CSP and no-store under /api/admin" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/api/admin/media")
        |> SecurityHeaders.call([])
        |> send_resp(200, "")

      assert get_resp_header(conn, "content-security-policy") == [@base]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "the charset callback completes text/vtt and leaves video/webm and image/webp" do
      for {type, expected} <- [
            {"text/vtt", "text/vtt; charset=utf-8"},
            {"image/svg+xml", "image/svg+xml; charset=utf-8"},
            {"video/webm", "video/webm"},
            {"image/webp", "image/webp"}
          ] do
        conn =
          :get
          |> Phoenix.ConnTest.build_conn("/media/x")
          |> put_private(:espalier_media, true)
          |> SecurityHeaders.call([])
          |> put_resp_content_type(type, nil)
          |> send_resp(200, "")

        assert get_resp_header(conn, "content-type") == [expected], type
      end
    end

    test "media_csp/0 is the media CSP" do
      assert SecurityHeaders.media_csp() == @media_csp
    end
  end
end
