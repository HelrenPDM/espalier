defmodule EspalierWeb.Auth.InvitationController do
  @moduledoc """
  Invitation requests (`SIGNUP=invite` or `domain`) and the acceptance of an
  invitation link, which opens an enrollment session only (README section
  6.2, rule 1).
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.{SessionController, UserAuth}

  action_fallback EspalierWeb.FallbackController

  plug :require_signup when action in [:create]
  plug :require_local_accounts
  plug RateLimit, [bucket: :invitation_ip] when action in [:create]
  plug RateLimit, [bucket: :auth_ip] when action in [:accept]

  def create(conn, %{"email" => email}) when is_binary(email) do
    conn = RateLimit.check_account(conn, :invitation_target, Accounts.normalize_email(email))

    if conn.halted do
      conn
    else
      :ok = Accounts.request_invitation(email)

      conn
      |> put_status(:accepted)
      |> json(%{status: "accepted"})
    end
  end

  def create(_conn, _params), do: {:error, :bad_request}

  def accept(conn, %{"token" => token}) when is_binary(token) do
    with {:ok, user} <- Accounts.accept_invitation(token) do
      conn
      |> UserAuth.log_in_user(user, auth_methods: [:email_code], strength: :enrollment)
      |> SessionController.render_session()
    end
  end

  def accept(_conn, _params), do: {:error, :invalid_token}

  defp require_signup(conn, _opts) do
    if Application.get_env(:espalier, :signup, :closed) == :closed,
      do: not_found(conn),
      else: conn
  end

  defp require_local_accounts(conn, _opts) do
    if Application.get_env(:espalier, :local_accounts, true), do: conn, else: not_found(conn)
  end

  defp not_found(conn) do
    conn |> put_status(:not_found) |> json(%{error: "not_found"}) |> halt()
  end
end
