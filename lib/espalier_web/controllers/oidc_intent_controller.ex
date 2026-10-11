defmodule EspalierWeb.OidcIntentController do
  @moduledoc """
  `POST /api/auth/oidc/:provider/intents` with `{"purpose": "link" |
  "step_up"}` (task 0006, step 11). The answer `{"url": ...}` names the
  authorize route with a single-use intent, which the SPA opens as a
  same-origin top-level navigation. The intent works for 5 minutes and only
  together with the session row that created it (README section 6.7).

  Only sessions of strength `mfa` create intents. A link needs a second
  factor within the last 10 minutes (ASVS 7.5.1); a step-up needs an
  identity of the provider and `idp_trusted` mode.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Fields, OidcIntent, OidcIntentRequest}

  # OpenAPI operations of task 0011 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0006.
  tags ["Session"]
  security Responses.session_and_csrf()

  alias Espalier.{Accounts, Identity, SecurityLog}
  alias Espalier.Accounts.Scope
  alias EspalierWeb.FallbackController
  alias EspalierWeb.Plugs.RateLimit

  operation :create,
    summary: "Create an OIDC intent",
    description:
      "Only `mfa` sessions. `link` needs a second factor within the last 10 minutes; " <>
        "`step_up` needs an identity of the provider and `idp_trusted` mode.",
    parameters: [
      provider: [
        in: :path,
        required: true,
        description: "The provider key.",
        schema: Fields.string()
      ]
    ],
    request_body: {"The purpose", "application/json", OidcIntentRequest, required: true},
    responses:
      Map.merge(
        %{201 => {"The intent URL", "application/json", OidcIntent}},
        Responses.errors([
          {400, ["bad_request"]},
          {401, ["unauthenticated"]},
          {403,
           ["forbidden", "enrollment_required", "reauth_required", "csrf", "cross_site_request"]},
          {404, ["unknown_provider"]},
          {409, ["provider_already_linked"]},
          {422, ["step_up_not_available"]},
          {429, ["rate_limited"]}
        ])
      )

  def create(conn, %{"provider" => key} = params) do
    scope = conn.assigns.current_scope
    conn = RateLimit.check_account(conn, :oidc_intent, scope.user.id)

    if conn.halted, do: conn, else: create_intent(conn, scope, key, params["purpose"])
  end

  defp create_intent(conn, scope, key, purpose) do
    case Identity.fetch_oidc_provider(key) do
      {:ok, _provider} when scope.session.strength != :mfa ->
        deny(conn, scope, "forbidden")

      {:ok, provider} when purpose in ["link", "step_up"] ->
        with :ok <- check(conn, scope, provider, purpose) do
          token = Accounts.create_oidc_intent(scope, provider, purpose)

          conn
          |> put_status(:created)
          |> json(%{url: "/auth/oidc/#{provider.key}?intent=#{token}"})
        end

      {:ok, _provider} ->
        FallbackController.render_error(conn, :bad_request)

      :error ->
        FallbackController.render_error(conn, :unknown_provider)
    end
  end

  defp check(conn, scope, provider, "link") do
    cond do
      not Scope.recent_auth?(scope) -> deny(conn, scope, "reauth_required")
      linked?(scope, provider) -> FallbackController.render_error(conn, :provider_already_linked)
      true -> :ok
    end
  end

  # Users of local providers step up with POST /api/me/reauth (task 0005).
  defp check(conn, scope, provider, "step_up") do
    if provider.mfa == :idp_trusted and linked?(scope, provider),
      do: :ok,
      else: FallbackController.render_error(conn, :step_up_not_available)
  end

  defp linked?(scope, provider), do: Accounts.provider_linked?(scope.user.id, provider.key)

  defp deny(conn, scope, code) do
    SecurityLog.event(:authz_fail, %{user_id: scope.user.id, ip: conn.remote_ip, reason: code})

    conn
    |> put_status(:forbidden)
    |> json(%{error: code})
  end
end
