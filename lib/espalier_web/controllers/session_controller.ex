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

  @doc """
  Renders the session payload for the scope and the pending state of
  `conn`, merged with `extra` (such as `recent_auth_until`).
  """
  def render_session(conn, status \\ :ok, extra \\ %{}) do
    conn
    |> put_status(status)
    |> json(Map.merge(session_payload(conn), extra))
  end

  @doc "Returns the session payload of `conn` as a map."
  def session_payload(conn) do
    pending =
      case UserAuth.fetch_pending_second_factor(conn) do
        {:ok, pending} -> pending
        :error -> nil
      end

    EspalierWeb.SessionJSON.show(%{scope: conn.assigns[:current_scope], pending: pending})
  end
end
