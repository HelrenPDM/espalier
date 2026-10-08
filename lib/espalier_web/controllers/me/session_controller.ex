defmodule EspalierWeb.Me.SessionController do
  @moduledoc """
  Lists the sessions of the signed-in user and ends one of them after
  re-authentication (ASVS 7.5.2).
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts

  action_fallback EspalierWeb.FallbackController

  def index(conn, _params) do
    scope = conn.assigns.current_scope

    sessions =
      for session <- Accounts.list_sessions(scope.user) do
        %{
          id: session.id,
          current: session.id == scope.session.id,
          device: session.device_summary,
          strength: session.strength,
          auth_methods: session.auth_methods,
          authenticated_at: session.authenticated_at,
          last_seen_at: session.last_seen_at,
          expires_at: session.expires_at
        }
      end

    json(conn, %{sessions: sessions})
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- Accounts.delete_session(conn.assigns.current_scope.user, id) do
      send_resp(conn, :no_content, "")
    end
  end
end
