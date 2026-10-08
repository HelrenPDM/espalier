defmodule EspalierWeb.Auth.PasswordController do
  @moduledoc """
  Password sign-in up to the pending second-factor state. A password alone
  never opens a session (ASVS 6.3.4). Known and unknown addresses receive
  the same answer.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.UserAuth

  action_fallback EspalierWeb.FallbackController

  plug :require_local_accounts
  plug RateLimit, [bucket: :auth_ip] when action in [:create]

  def create(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    conn = RateLimit.check_account(conn, :password_account, Accounts.normalize_email(email))

    if conn.halted do
      conn
    else
      case Accounts.authenticate_password(email, password, %{ip: conn.remote_ip}) do
        {:ok, user} ->
          conn
          |> UserAuth.put_pending_second_factor(user, auth_methods: [:password])
          |> json(%{next: "second_factor"})

        {:error, :invalid_credentials} = error ->
          error
      end
    end
  end

  def create(_conn, _params), do: {:error, :bad_request}

  defp require_local_accounts(conn, _opts) do
    if Application.get_env(:espalier, :local_accounts, true) do
      conn
    else
      conn |> put_status(:not_found) |> json(%{error: "not_found"}) |> halt()
    end
  end
end
