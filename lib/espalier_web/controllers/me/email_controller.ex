defmodule EspalierWeb.Me.EmailController do
  @moduledoc """
  E-mail change: the request always answers 202, and the confirmation link
  goes to the new address (ASVS 6.3.8, 6.5.5).
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.SessionController

  action_fallback EspalierWeb.FallbackController

  def update(conn, %{"email" => email}) when is_binary(email) do
    user = conn.assigns.current_scope.user
    conn = RateLimit.check_account(conn, :account_change, user.id)

    if conn.halted do
      conn
    else
      :ok = Accounts.request_email_change(user, email)

      conn
      |> put_status(:accepted)
      |> json(%{status: "accepted"})
    end
  end

  def update(_conn, _params), do: {:error, :bad_request}

  def confirm(conn, %{"token" => token}) when is_binary(token) do
    scope = conn.assigns.current_scope

    with {:ok, user} <- Accounts.confirm_email_change(scope.user, token) do
      conn
      |> assign(:current_scope, %{scope | user: user})
      |> SessionController.render_session()
    end
  end

  def confirm(_conn, _params), do: {:error, :invalid_token}
end
