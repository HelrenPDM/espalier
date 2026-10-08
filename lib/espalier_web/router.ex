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

  scope "/api", EspalierWeb do
    pipe_through :api

    get "/session", SessionController, :show
    delete "/session", SessionController, :delete

    post "/auth/password", Auth.PasswordController, :create
    post "/auth/invitations", Auth.InvitationController, :create
    post "/auth/invitations/accept", Auth.InvitationController, :accept
    post "/auth/demo", Auth.DemoController, :create
  end

  scope "/api/me", EspalierWeb.Me do
    pipe_through [:api, :authenticated]

    get "/sessions", SessionController, :index
  end

  scope "/api/me", EspalierWeb.Me do
    pipe_through [:api, :authenticated, :recent_auth]

    delete "/sessions/:id", SessionController, :delete
    put "/password", PasswordController, :update
    put "/email", EmailController, :update
    post "/email/confirm", EmailController, :confirm
  end

  # The SPA catch-all stays the last route.
  scope "/", EspalierWeb do
    get "/*path", SpaController, :index
  end
end
