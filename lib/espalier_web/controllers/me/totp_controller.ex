defmodule EspalierWeb.Me.TotpController do
  @moduledoc """
  TOTP enrollment, confirmation and removal (README sections 6.6 and 8).
  TOTP is a second factor only, so an enrollment or recovery session needs
  a password or an external identity first (409 `password_required`). A
  wrong or locked confirmation answers 422 `invalid_code`.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts
  alias Espalier.Accounts.{Factors, Totp}
  alias EspalierWeb.FallbackController
  alias EspalierWeb.Me.FactorResponse
  alias EspalierWeb.Plugs.RateLimit

  action_fallback EspalierWeb.FallbackController

  def create(conn, _params) do
    %{user: user, session: session} = scope = conn.assigns.current_scope

    if session.strength in [:enrollment, :recovery] and not first_factor?(user) do
      {:error, :password_required}
    else
      with {:ok, payload} <- Totp.start_enrollment(scope), do: json(conn, payload)
    end
  end

  def confirm(conn, %{"code" => code}) when is_binary(code) do
    %{user: user} = scope = conn.assigns.current_scope
    conn = RateLimit.check_account(conn, :totp_confirm_user, user.id)

    if conn.halted, do: conn, else: confirm_code(conn, scope, code)
  end

  def confirm(_conn, _params), do: {:error, :bad_request}

  defp confirm_code(conn, %{user: user, session: session} = scope, code) do
    # A recovery replaces a TOTP factor that 50 failures disabled.
    opts = [events: false, allow_disabled: session.strength == :recovery]
    verify = fn -> Totp.confirm(scope, code) end

    case Factors.verify(user, :totp, verify, %{ip: conn.remote_ip}, opts) do
      {:ok, factor} ->
        Factors.notify_change(user, :factor_added, :totp)
        {conn, codes} = Factors.complete_enrollment(conn, scope, :totp)
        totp = %{enabled: true, enabled_at: factor.enabled_at}
        FactorResponse.render(conn, %{totp: totp}, session.strength, codes)

      {:error, _reason} ->
        FallbackController.render_error(conn, :invalid_code)
    end
  end

  def delete(conn, _params) do
    scope = conn.assigns.current_scope

    with :ok <- Factors.removable?(scope.user, :totp),
         :ok <- Totp.disable(scope) do
      Factors.notify_change(scope.user, :factor_removed, :totp)
      FactorResponse.render(conn, %{})
    end
  end

  defp first_factor?(user),
    do: is_binary(user.hashed_password) or Accounts.external_identity?(user)
end
