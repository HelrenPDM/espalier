defmodule EspalierWeb.Router do
  use EspalierWeb, :router

  import EspalierWeb.UserAuth

  @api_session EspalierWeb.TransactionCookie.main_session_options()
  @transaction_session EspalierWeb.TransactionCookie.session_options()

  # The function plug :protect_api_from_forgery checks the x-csrf-token header on every mutating request.
  # sobelow_skip ["Config.CSRF"]
  pipeline :api do
    plug :accepts, ["json"]
    plug EspalierWeb.Plugs.FetchMetadata
    plug Plug.Session, @api_session
    plug :fetch_session
    plug :protect_api_from_forgery
    plug :fetch_current_scope_for_user
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  pipeline :recent_auth do
    plug :require_recent_auth
  end

  pipeline :enrollment do
    plug :require_enrollment_session
  end

  pipeline :facilitator do
    plug :require_authenticated_user
    plug :require_role, :facilitator
  end

  pipeline :author do
    plug :require_authenticated_user
    plug :require_role, :author
  end

  pipeline :registrar do
    plug :require_authenticated_user
    plug :require_role, :registrar
  end

  pipeline :analyst do
    plug :require_authenticated_user
    plug :require_role, :analyst
  end

  pipeline :admin do
    plug :require_authenticated_user
    plug :require_role, :admin
  end

  # This pipeline serves GET navigations only; state, nonce and PKCE bind each OIDC flow (task 0006).
  # sobelow_skip ["Config.CSRF"]
  pipeline :oidc_transaction do
    plug EspalierWeb.Plugs.FetchMetadata,
      allow_cross_site_navigation: [
        ["auth", "oidc", :provider, "callback"],
        ["auth", "oidc", :provider, "front-channel-logout"]
      ]

    plug Plug.Session, @transaction_session
    plug :fetch_session
  end

  pipeline :auth_bare do
    plug :accepts, ["json"]
    plug EspalierWeb.Plugs.FetchMetadata
  end

  scope "/", EspalierWeb do
    get "/health", HealthController, :index
  end

  scope "/auth", EspalierWeb do
    pipe_through :auth_bare

    get "/providers", ProviderController, :index
  end

  # The only OIDC entry points (task 0006, docs/security/authentication.md).
  scope "/auth/oidc", EspalierWeb do
    pipe_through :oidc_transaction

    get "/:provider", OidcController, :authorize
    get "/:provider/callback", OidcController, :callback
    get "/:provider/front-channel-logout", OidcController, :front_channel_logout
  end

  scope "/api", EspalierWeb do
    pipe_through :api

    get "/session", SessionController, :show
    delete "/session", SessionController, :delete

    post "/auth/password", Auth.PasswordController, :create
    post "/auth/invitations", Auth.InvitationController, :create
    post "/auth/invitations/accept", Auth.InvitationController, :accept
    post "/auth/demo", Auth.DemoController, :create

    post "/auth/passkey/options", Auth.PasskeyAuthController, :options
    post "/auth/passkey", Auth.PasskeyAuthController, :create
    post "/auth/second-factor", Auth.SecondFactorController, :create
    post "/auth/recovery/start", Auth.RecoveryController, :start
    post "/auth/recovery/verify", Auth.RecoveryController, :verify
    post "/auth/finish", Auth.FinishController, :create
  end

  scope "/api/auth/oidc", EspalierWeb do
    pipe_through [:api, :authenticated]

    post "/:provider/intents", OidcIntentController, :create
  end

  # Enrollment, recovery and mfa sessions (task 0005). A route with
  # :recent_auth names :enrollment first, so a request without a session and
  # a demo session halt before the recent-auth check.
  scope "/api/me", EspalierWeb.Me do
    pipe_through [:api, :enrollment]

    get "/security", SecurityController, :show
  end

  scope "/api/me", EspalierWeb.Me do
    pipe_through [:api, :enrollment, :recent_auth]

    post "/passkeys/options", PasskeyController, :options
    post "/passkeys", PasskeyController, :create
    post "/totp", TotpController, :create
    post "/totp/confirm", TotpController, :confirm
    put "/password", PasswordController, :update
  end

  scope "/api/me", EspalierWeb.Me do
    pipe_through [:api, :authenticated]

    get "/sessions", SessionController, :index
    post "/reauth", ReauthController, :create
  end

  scope "/api/me", EspalierWeb.Me do
    pipe_through [:api, :authenticated, :recent_auth]

    delete "/sessions/:id", SessionController, :delete
    put "/email", EmailController, :update
    post "/email/confirm", EmailController, :confirm
    delete "/passkeys/:id", PasskeyController, :delete
    delete "/totp", TotpController, :delete
    post "/recovery-codes", RecoveryCodeController, :create
  end

  # The SPA catch-all stays the last route.
  scope "/", EspalierWeb do
    get "/*path", SpaController, :index
  end
end
