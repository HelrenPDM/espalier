defmodule EspalierWeb.Me.PasswordController do
  @moduledoc """
  Password change with the current and the new password (ASVS 6.2.2,
  6.2.3). It ends every other session of the user and keeps the calling
  client signed in through a copy of its session row with a new token and a
  new CSRF token.

  In an `enrollment` or `recovery` session the password is set without the
  current one: such a session exists only for a user without a second
  factor, or after a saved recovery code and a link sent by e-mail, so a
  reset never bypasses an enabled second factor (ASVS 6.4.3). The copy keeps
  the strength, `expires_at`, `provider_key` and `idp_sid_hash`.
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
      {attrs, opts} =
        if session.strength in [:enrollment, :recovery],
          do: {Map.take(params, ["password"]), [require_current: false, keep_session: session]},
          else: {Map.take(params, ["current_password", "password"]), [keep_session: session]}

      with {:ok, {_user, token}} <- Accounts.update_user_password(user, attrs, opts) do
        conn
        |> UserAuth.put_reissued_session(token)
        |> SessionController.render_session()
      end
    end
  end
end
