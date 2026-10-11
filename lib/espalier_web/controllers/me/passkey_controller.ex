defmodule EspalierWeb.Me.PasskeyController do
  @moduledoc """
  Passkey registration and removal (README sections 6.6 and 8). Registration
  runs in `enrollment`, `recovery` and `mfa` sessions and completes an
  enrollment or a recovery; removal needs an `mfa` session. Both need a
  second factor from the last 10 minutes in an `mfa` session. A failed
  registration answers 422 `registration_failed`.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses

  alias EspalierWeb.Schemas.{
    FactorChange,
    Fields,
    PasskeyCreationOptions,
    PasskeyRegistrationRequest,
    PasskeyRegistrationResult
  }

  # OpenAPI operations of task 0011 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0005.
  tags ["Account"]
  security Responses.session_and_csrf()

  alias Espalier.Accounts
  alias Espalier.Accounts.{Factors, Passkeys}
  alias Espalier.Accounts.Passkeys.Options
  alias EspalierWeb.{FallbackController, WebauthnCeremony}
  alias EspalierWeb.Me.FactorResponse

  action_fallback EspalierWeb.FallbackController

  operation :options,
    summary: "Start a passkey registration",
    description:
      "Stores a single-use challenge for 300 seconds and answers the creation options. " <>
        "Needs a second factor within the last 10 minutes in an `mfa` session.",
    responses:
      Map.merge(
        %{200 => {"The creation options", "application/json", PasskeyCreationOptions}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["forbidden", "reauth_required", "csrf", "cross_site_request"]}
        ])
      )

  def options(conn, _params) do
    user = Accounts.ensure_webauthn_user_handle(conn.assigns.current_scope.user)
    challenge = Passkeys.new_registration_challenge()
    {conn, _row} = WebauthnCeremony.start(conn, :registration, user.id, challenge)
    json(conn, Options.creation(user, challenge, Passkeys.list_credentials(user)))
  end

  operation :create,
    summary: "Register a passkey",
    description:
      "Completes an enrollment or a recovery, which then answers ten new `recovery_codes` " <>
        "and the `session` payload with a new CSRF token.",
    request_body:
      {"The result of startRegistration", "application/json", PasskeyRegistrationRequest,
       required: true},
    responses:
      Map.merge(
        %{200 => {"The passkey", "application/json", PasskeyRegistrationResult}},
        Responses.errors([
          {400, ["bad_request"]},
          {401, ["unauthenticated"]},
          {403, ["forbidden", "reauth_required", "csrf", "cross_site_request"]},
          {422, ["registration_failed"]}
        ])
      )

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

  operation :delete,
    summary: "Remove a passkey",
    description:
      "Needs a second factor within the last 10 minutes. The last remaining second factor " <>
        "and, with `ADMIN_REQUIRE_PASSKEY=true`, the last passkey of an admin stay.",
    parameters: [
      id: [in: :path, required: true, description: "The passkey id.", schema: Fields.uuid()]
    ],
    responses:
      Map.merge(
        %{200 => {"Removed", "application/json", FactorChange}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "reauth_required", "csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {409, ["last_factor", "admin_passkey_required"]}
        ])
      )

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
