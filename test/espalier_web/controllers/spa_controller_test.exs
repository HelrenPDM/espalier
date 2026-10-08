defmodule EspalierWeb.SpaControllerTest do
  use EspalierWeb.ConnCase, async: true

  for path <- ["/api/unknown", "/auth/unknown", "/health/unknown"] do
    test "GET #{path} answers 404 with a JSON body", %{conn: conn} do
      conn = get(conn, unquote(path))

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end
end
