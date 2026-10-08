defmodule EspalierWeb.Me.PasswordController do
  @moduledoc """
  Password change with the current and the new password (ASVS 6.2.2,
  6.2.3). It ends every other session of the user and keeps the calling
  client signed in through a copy of its session row with a new token and a
  new CSRF token.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.{SessionController, UserAuth}

  action_fallback EspalierWeb.FallbackController

  def update(conn, params) do
    %{user: user, session: session} = conn.assigns.current_scope
    conn = RateLimit.check_account(conn, :account_change, user.id)

    if conn.halted do
      conn
    else
      attrs = Map.take(params, ["current_password", "password"])

      with {:ok, {_user, token}} <-
             Accounts.update_user_password(user, attrs, keep_session: session) do
        conn
        |> UserAuth.put_reissued_session(token)
        |> SessionController.render_session()
      end
    end
  end
end
