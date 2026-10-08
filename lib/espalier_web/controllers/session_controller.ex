defmodule EspalierWeb.SessionController do
  use EspalierWeb, :controller

  alias EspalierWeb.UserAuth

  def show(conn, _params) do
    render_session(conn)
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> send_resp(:no_content, "")
  end

  @doc "Renders the session payload for the scope and the pending state of `conn`."
  def render_session(conn, status \\ :ok) do
    pending =
      case UserAuth.fetch_pending_second_factor(conn) do
        {:ok, pending} -> pending
        :error -> nil
      end

    conn
    |> put_status(status)
    |> put_view(json: EspalierWeb.SessionJSON)
    |> render(:show, scope: conn.assigns[:current_scope], pending: pending)
  end
end
