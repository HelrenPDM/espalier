defmodule EspalierWeb.ErrorJSONTest do
  use EspalierWeb.ConnCase, async: true

  alias EspalierWeb.ErrorJSON

  test "renders a code without internals" do
    assert ErrorJSON.render("400.json", %{}) == %{error: "bad_request"}
    assert ErrorJSON.render("403.json", %{}) == %{error: "forbidden"}
    assert ErrorJSON.render("404.json", %{}) == %{error: "not_found"}
    assert ErrorJSON.render("406.json", %{}) == %{error: "bad_request"}

    assert ErrorJSON.render("500.json", %{reason: %RuntimeError{message: "secret"}}) ==
             %{error: "internal_error"}

    assert ErrorJSON.render("503.json", %{}) == %{error: "internal_error"}
  end

  test "an unmatched mutating route answers 404 not_found", %{conn: conn} do
    conn = conn |> with_csrf_token() |> post("/api/unknown", %{})
    assert json_response(conn, 404) == %{"error" => "not_found"}
  end
end
