defmodule EspalierWeb.Me.EmailController do
  @moduledoc """
  E-mail change: the request always answers 202, and the confirmation link
  goes to the new address (ASVS 6.3.8, 6.5.5).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Accepted, EmailChangeRequest, EmailConfirmRequest, SessionPayload}

  # OpenAPI operations of task 0009 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0004.
  tags ["Account"]
  security Responses.session_and_csrf()

  alias Espalier.Accounts
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.SessionController

  action_fallback EspalierWeb.FallbackController

  operation :update,
    summary: "Request an e-mail change",
    description:
      "Sends a confirmation link to the new address; the answer is the same for every " <>
        "address. Needs a second factor within the last 10 minutes.",
    request_body: {"The new address", "application/json", EmailChangeRequest, required: true},
    responses:
      Map.merge(
        %{202 => {"Accepted", "application/json", Accepted}},
        Responses.errors([
          {400, ["bad_request"]},
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "reauth_required", "csrf", "cross_site_request"]},
          {429, ["rate_limited"]}
        ])
      )

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

  operation :confirm,
    summary: "Confirm an e-mail change",
    request_body:
      {"The confirmation token", "application/json", EmailConfirmRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The session payload", "application/json", SessionPayload}},
        Responses.errors([
          {400, ["invalid_token"]},
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "reauth_required", "csrf", "cross_site_request"]}
        ])
      )

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
