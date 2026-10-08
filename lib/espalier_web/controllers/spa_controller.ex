defmodule EspalierWeb.SpaController do
  use EspalierWeb, :controller

  # Paths below these prefixes belong to Phoenix and never receive the SPA.
  @reserved ~w(api auth health)

  def index(conn, %{"path" => [first | _rest]}) when first in @reserved do
    conn
    |> put_status(:not_found)
    |> json(EspalierWeb.ErrorJSON.render("404.json", %{}))
  end

  def index(conn, _params) do
    index_html = Application.app_dir(:espalier, "priv/static/spa/index.html")

    if File.exists?(index_html) do
      conn
      |> put_resp_content_type("text/html")
      |> send_file(200, index_html)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "SPA not built. Run make run or make docker-build.")
    end
  end
end
