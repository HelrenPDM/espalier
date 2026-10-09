defmodule EspalierWeb.Auth.RecoveryController do
  @moduledoc """
  Recovery of a local account with a link sent by e-mail and a saved
  recovery code (README sections 6.2 and 6.6, ASVS 6.4.3, 6.4.4, 6.6.2 and
  6.6.3). The start always answers 202 with the same body. The verification
  opens a `recovery` session, which reaches only the enrollment routes; every
  failure answers 401 `authentication_failed`. With `LOCAL_ACCOUNTS=false`
  both routes answer 404.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts
  alias Espalier.Accounts.{Factors, Recovery}
  alias EspalierWeb.{FallbackController, SessionController, UserAuth}
  alias EspalierWeb.Plugs.RateLimit

  action_fallback EspalierWeb.FallbackController

  plug :require_local_accounts
  plug RateLimit, [bucket: :recovery_start_ip] when action in [:start]
  plug RateLimit, [bucket: :recovery_verify_ip] when action in [:verify]

  def start(conn, %{"email" => email}) when is_binary(email) do
    conn = RateLimit.check_account(conn, :recovery_start_target, Accounts.normalize_email(email))

    if conn.halted do
      conn
    else
      :ok = Recovery.start(email)

      conn
      |> put_status(:accepted)
      |> json(%{status: "accepted"})
    end
  end

  def start(_conn, _params), do: {:error, :bad_request}

  def verify(conn, %{"token" => token, "recovery_code" => code})
      when is_binary(token) and is_binary(code) do
    case Recovery.resolve_token(token) do
      {:ok, user} ->
        conn = RateLimit.check_account(conn, :recovery_verify_user, user.id)
        if conn.halted, do: conn, else: verify_code(conn, user, code)

      :error ->
        Factors.log_failure(%{ip: conn.remote_ip, factor: :recovery_code}, :invalid_token)
        {:error, :authentication_failed}
    end
  end

  def verify(_conn, _params), do: {:error, :bad_request}

  defp verify_code(conn, user, code) do
    case Recovery.verify(user, code, %{ip: conn.remote_ip}) do
      {:ok, _remaining} ->
        conn
        |> UserAuth.log_in_user(user,
          auth_methods: [:recovery_code, :email_code],
          strength: :recovery
        )
        |> SessionController.render_session()

      {:error, _reason} ->
        {:error, :authentication_failed}
    end
  end

  defp require_local_accounts(conn, _opts) do
    if Application.get_env(:espalier, :local_accounts, true),
      do: conn,
      else: conn |> FallbackController.render_error(:not_found) |> halt()
  end
end
