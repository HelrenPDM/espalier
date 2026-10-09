defmodule EspalierWeb.Me.PasskeyController do
  @moduledoc """
  Passkey registration and removal (README sections 6.6 and 8). Registration
  runs in `enrollment`, `recovery` and `mfa` sessions and completes an
  enrollment or a recovery; removal needs an `mfa` session. Both need a
  second factor from the last 10 minutes in an `mfa` session. A failed
  registration answers 422 `registration_failed`.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts
  alias Espalier.Accounts.{Factors, Passkeys}
  alias Espalier.Accounts.Passkeys.Options
  alias EspalierWeb.{FallbackController, WebauthnCeremony}
  alias EspalierWeb.Me.FactorResponse

  action_fallback EspalierWeb.FallbackController

  def options(conn, _params) do
    user = Accounts.ensure_webauthn_user_handle(conn.assigns.current_scope.user)
    challenge = Passkeys.new_registration_challenge()
    {conn, _row} = WebauthnCeremony.start(conn, :registration, user.id, challenge)
    json(conn, Options.creation(user, challenge, Passkeys.list_credentials(user)))
  end

  def create(conn, %{"credential" => %{} = credential} = params) do
    scope = conn.assigns.current_scope
    {conn, challenge} = WebauthnCeremony.finish(conn, :registration, scope.user.id)
    attrs = Map.put(credential, "nickname", params["nickname"])

    with {:ok, row} <- challenge,
         {:ok, passkey} <- Passkeys.register(scope, row, attrs) do
      Factors.notify_change(scope.user, :factor_added, :passkey)
      {conn, codes} = Factors.complete_enrollment(conn, scope, :passkey)

      FactorResponse.render(
        conn,
        %{passkey: passkey_json(passkey)},
        scope.session.strength,
        codes
      )
    else
      {:error, _reason} -> FallbackController.render_error(conn, :registration_failed)
    end
  end

  def create(_conn, _params), do: {:error, :bad_request}

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    with %{} = credential <- Passkeys.get_credential(scope, id) || {:error, :not_found},
         :ok <- Factors.remove(scope, {:passkey, credential}) do
      Factors.notify_change(scope.user, :factor_removed, :passkey)
      FactorResponse.render(conn, %{})
    end
  end

  defp passkey_json(passkey) do
    %{
      id: passkey.id,
      nickname: passkey.nickname,
      inserted_at: passkey.inserted_at,
      last_used_at: passkey.last_used_at,
      backup_eligible: passkey.backup_eligible,
      backed_up: passkey.backed_up,
      transports: passkey.transports
    }
  end
end
