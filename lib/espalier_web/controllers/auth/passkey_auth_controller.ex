defmodule EspalierWeb.Auth.PasskeyAuthController do
  @moduledoc """
  Passkey options for the sign-in, the second factor and the
  re-authentication, and the discoverable passkey sign-in of local accounts
  (README sections 6.2 and 6.6).

  A failed sign-in assertion never counts against the owner of the
  credential; only the IP bucket `passkey_ip` limits it, so passkey sign-in
  stays available while another factor of the account is locked
  (ASVS 6.1.1). Every failure answers 401 `authentication_failed`.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts.{Factors, Passkeys, Scope, UserToken}
  alias Espalier.Accounts.Passkeys.Options
  alias EspalierWeb.{FallbackController, SessionController, UserAuth, WebauthnCeremony}
  alias EspalierWeb.Plugs.RateLimit

  action_fallback EspalierWeb.FallbackController

  plug :require_local_accounts when action in [:create]
  plug RateLimit, [bucket: :passkey_options_ip] when action in [:options]
  plug RateLimit, [bucket: :passkey_ip] when action in [:create]

  def options(conn, params) do
    case Map.get(params, "purpose", "sign_in") do
      "sign_in" -> sign_in_options(conn)
      "second_factor" -> second_factor_options(conn)
      "reauth" -> reauth_options(conn)
      _ -> {:error, :bad_request}
    end
  end

  defp sign_in_options(conn) do
    if local_accounts?(), do: start(conn, :sign_in, nil, []), else: not_found(conn)
  end

  defp second_factor_options(conn) do
    case UserAuth.fetch_pending_second_factor(conn) do
      {:ok, %{user: user}} -> start(conn, :second_factor, user, Passkeys.list_credentials(user))
      :error -> {:error, :authentication_failed}
    end
  end

  defp reauth_options(conn) do
    case conn.assigns[:current_scope] do
      %Scope{user: user, session: %UserToken{strength: :mfa}} ->
        start(conn, :reauth, user, Passkeys.list_credentials(user))

      _ ->
        {:error, :authentication_failed}
    end
  end

  defp start(conn, purpose, user, allow) do
    challenge = Passkeys.new_authentication_challenge()
    {conn, _row} = WebauthnCeremony.start(conn, purpose, user && user.id, challenge)
    json(conn, Options.request(challenge, allow))
  end

  def create(conn, params) do
    {conn, challenge} = WebauthnCeremony.finish(conn, :sign_in, nil)
    log = %{ip: conn.remote_ip, factor: :passkey}

    with {:ok, row} <- challenge,
         {:ok, result} <- Passkeys.authenticate(row, params, nil) do
      user = result.user
      Factors.record_success(user, :passkey, result, Map.put(log, :user_id, user.id))

      conn
      |> UserAuth.log_in_user(user,
        auth_methods: [:passkey],
        strength: :mfa,
        mfa_at: DateTime.utc_now(:second)
      )
      |> SessionController.render_session()
    else
      {:error, reason} ->
        Factors.log_failure(log, reason)
        FallbackController.render_error(conn, :authentication_failed)
    end
  end

  defp require_local_accounts(conn, _opts) do
    if local_accounts?(), do: conn, else: conn |> not_found() |> halt()
  end

  defp local_accounts?, do: Application.get_env(:espalier, :local_accounts, true)

  defp not_found(conn), do: FallbackController.render_error(conn, :not_found)
end
