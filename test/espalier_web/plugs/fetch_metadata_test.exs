defmodule EspalierWeb.Plugs.FetchMetadataTest do
  use EspalierWeb.ConnCase, async: true

  alias EspalierWeb.Plugs.FetchMetadata

  @oidc_options FetchMetadata.init(
                  allow_cross_site_navigation: [
                    ["auth", "oidc", :provider, "callback"],
                    ["auth", "oidc", :provider, "front-channel-logout"]
                  ]
                )

  defp bare_conn(method, path, headers) do
    Enum.reduce(headers, Phoenix.ConnTest.build_conn(method, path), fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
  end

  test "a cross-site POST answers 403 cross_site_request and logs malicious_csrf", %{conn: conn} do
    ref = attach_security_events()

    conn =
      conn
      |> put_req_header("sec-fetch-site", "cross-site")
      |> post("/api/auth/password", %{email: "a@example.org", password: "x"})

    assert json_response(conn, 403) == %{"error" => "cross_site_request"}
    assert_received {^ref, %{name: :malicious_csrf}}
  end

  test "without sec-fetch-site, a POST with a foreign or missing Origin answers 403" do
    for headers <- [[{"origin", "https://evil.example.net"}], []] do
      conn = bare_conn(:post, "/api/auth/password", headers) |> EspalierWeb.Endpoint.call([])
      assert json_response(conn, 403) == %{"error" => "cross_site_request"}
    end
  end

  test "without sec-fetch-site, a POST with the right Origin reaches the CSRF check" do
    conn =
      bare_conn(:post, "/api/auth/password", [{"origin", FetchMetadata.public_origin()}])
      |> put_private(:plug_skip_csrf_protection, false)
      |> EspalierWeb.Endpoint.call([])

    assert json_response(conn, 403) == %{"error" => "csrf"}
  end

  test "same-origin, same-site and none pass; GET and HEAD without the header pass" do
    for site <- ["same-origin", "same-site", "none"] do
      conn = bare_conn(:post, "/api/session", [{"sec-fetch-site", site}])
      refute FetchMetadata.call(conn, []).halted
    end

    for method <- [:get, :head] do
      refute FetchMetadata.call(bare_conn(method, "/api/session", []), []).halted
    end
  end

  test "a cross-site navigation GET to the OIDC callback passes" do
    conn =
      bare_conn(:get, "/auth/oidc/x/callback", [
        {"sec-fetch-site", "cross-site"},
        {"sec-fetch-mode", "navigate"},
        {"sec-fetch-dest", "document"}
      ])

    refute FetchMetadata.call(conn, @oidc_options).halted
  end

  test "a cross-site navigation in an iframe to the front-channel logout passes, embed does not" do
    headers = [{"sec-fetch-site", "cross-site"}, {"sec-fetch-mode", "navigate"}]

    iframe =
      bare_conn(
        :get,
        "/auth/oidc/x/front-channel-logout",
        headers ++ [{"sec-fetch-dest", "iframe"}]
      )

    refute FetchMetadata.call(iframe, @oidc_options).halted

    embed =
      bare_conn(
        :get,
        "/auth/oidc/x/front-channel-logout",
        headers ++ [{"sec-fetch-dest", "embed"}]
      )

    conn = FetchMetadata.call(embed, @oidc_options)
    assert conn.halted
    assert conn.status == 403
  end

  test "a cross-site request that is no navigation, or to another path, is rejected" do
    no_navigation =
      bare_conn(:get, "/auth/oidc/x/callback", [
        {"sec-fetch-site", "cross-site"},
        {"sec-fetch-mode", "cors"}
      ])

    other_path =
      bare_conn(:get, "/auth/oidc/x/other", [
        {"sec-fetch-site", "cross-site"},
        {"sec-fetch-mode", "navigate"}
      ])

    post =
      bare_conn(:post, "/auth/oidc/x/callback", [
        {"sec-fetch-site", "cross-site"},
        {"sec-fetch-mode", "navigate"}
      ])

    for conn <- [no_navigation, other_path, post] do
      assert FetchMetadata.call(conn, @oidc_options).halted
    end
  end
end
