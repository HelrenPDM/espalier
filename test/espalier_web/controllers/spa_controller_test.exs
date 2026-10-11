defmodule EspalierWeb.SpaControllerTest do
  use EspalierWeb.ConnCase, async: true

  for path <- ["/api/unknown", "/auth/unknown", "/health/unknown"] do
    test "GET #{path} answers 404 with a JSON body", %{conn: conn} do
      conn = get(conn, unquote(path))

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "GET /auth/finish (task 0011)" do
    test "admits the cross-site navigation at the end of an OIDC redirect chain", %{conn: conn} do
      conn =
        conn
        |> put_req_header("sec-fetch-site", "cross-site")
        |> put_req_header("sec-fetch-mode", "navigate")
        |> put_req_header("sec-fetch-dest", "document")
        |> get("/auth/finish")

      refute conn.status == 403
      assert conn.status in [200, 404]
      refute get_resp_header(conn, "content-type") |> Enum.any?(&(&1 =~ "json"))
      refute Map.has_key?(conn.private, :plug_session)
    end

    test "rejects a cross-site request that is no navigation", %{conn: conn} do
      conn =
        conn
        |> put_req_header("sec-fetch-site", "cross-site")
        |> put_req_header("sec-fetch-mode", "cors")
        |> get("/auth/finish")

      assert json_response(conn, 403) == %{"error" => "cross_site_request"}
    end

    test "rejects a cross-site navigation to another path below /auth/finish", %{conn: conn} do
      conn =
        conn
        |> put_req_header("sec-fetch-site", "cross-site")
        |> put_req_header("sec-fetch-mode", "navigate")
        |> get("/auth/finish/other")

      assert conn.status in [403, 404]
      refute conn.status == 200
    end
  end
end
