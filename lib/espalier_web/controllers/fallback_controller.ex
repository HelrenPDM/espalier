defmodule EspalierWeb.FallbackController do
  @moduledoc """
  Translates controller errors into the JSON error body `{"error": code}`
  (README section 6.10). The answers carry a code and no internals.

  Task 0005 adds `authentication_failed` (401) for every failed second
  factor, passkey sign-in, recovery and re-authentication,
  `registration_failed` (422) for a failed passkey registration,
  `invalid_code` (422) for a wrong TOTP confirmation, and the conflicts
  (409) of the factor rules.

  Task 0006 adds `ticket_invalid` (401) for a failed finish step,
  `unknown_provider` (404), `step_up_not_available` (422), and the link
  conflicts `identity_in_use` and `provider_already_linked` (409).
  """
  use EspalierWeb, :controller

  @statuses %{
    invalid_credentials: :unauthorized,
    authentication_failed: :unauthorized,
    unauthenticated: :unauthorized,
    invalid_token: :bad_request,
    bad_request: :bad_request,
    forbidden: :forbidden,
    not_found: :not_found,
    registration_failed: :unprocessable_entity,
    invalid_code: :unprocessable_entity,
    last_factor: :conflict,
    admin_passkey_required: :conflict,
    totp_already_enabled: :conflict,
    password_required: :conflict,
    ticket_invalid: :unauthorized,
    unknown_provider: :not_found,
    step_up_not_available: :unprocessable_entity,
    identity_in_use: :conflict,
    provider_already_linked: :conflict
  }

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "validation_failed",
      fields: EspalierWeb.ChangesetJSON.error_codes(changeset)
    })
  end

  def call(conn, {:error, code}) when is_map_key(@statuses, code) do
    render_error(conn, code)
  end

  @doc """
  Renders the error body of `code` on `conn`. Controllers that change the
  session before a failure (WebAuthn ceremonies, the pending second factor)
  call it with their own conn, because the fallback receives the conn that
  entered the action.
  """
  def render_error(conn, code) when is_map_key(@statuses, code) do
    conn
    |> put_status(Map.fetch!(@statuses, code))
    |> json(%{error: Atom.to_string(code)})
  end
end
