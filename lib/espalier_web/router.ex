defmodule EspalierWeb.Router do
  use EspalierWeb, :router

  import EspalierWeb.UserAuth
  import EspalierWeb.PackMultipart, only: [require_multipart: 2]

  @api_session EspalierWeb.TransactionCookie.main_session_options()
  @transaction_session EspalierWeb.TransactionCookie.session_options()

  # The function plug :protect_api_from_forgery checks the x-csrf-token header
  # on every mutating request.
  # sobelow_skip ["Config.CSRF"]
  pipeline :api do
    plug :accepts, ["json"]
    plug EspalierWeb.Plugs.FetchMetadata
    plug Plug.Session, @api_session
    plug :fetch_session
    plug :protect_api_from_forgery
    plug :fetch_current_scope_for_user
    plug OpenApiSpex.Plug.PutApiSpec, module: EspalierWeb.ApiSpec
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

  # Task 0015: the passkey gate runs after the role check (README section
  # 6.11), and the write pipelines also require a second factor from the
  # last 10 minutes (README section 6.4, ASVS 7.5.1).
  pipeline :admin do
    plug :require_authenticated_user
    plug :require_role, :admin
    plug EspalierWeb.Plugs.RequireAdminPasskey
  end

  pipeline :admin_write do
    plug :require_authenticated_user
    plug :require_role, :admin
    plug EspalierWeb.Plugs.RequireAdminPasskey
    plug :require_recent_auth
  end

  pipeline :author_write do
    plug :require_authenticated_user
    plug :require_role, :author
    plug :require_recent_auth
  end

  # The pack upload (task 0015, step 7). The endpoint parses no multipart
  # body, so the server reads an upload only here, behind :author_write and
  # up to PACK_UPLOAD_MAX_MB (ASVS 5.2.1).
  pipeline :pack_upload do
    plug :require_multipart
    plug Plug.Parsers, parsers: [EspalierWeb.PackMultipart], pass: []
  end

  # The media upload (task 0018, step 15): read only here, behind
  # :author_write and up to the largest per-kind limit (ASVS 5.2.1).
  pipeline :media_upload do
    plug :require_multipart
    plug Plug.Parsers, parsers: [EspalierWeb.MediaMultipart], pass: []
  end

  # The media route (task 0018, step 13). The flag comes first, so that
  # EspalierWeb.Plugs.SecurityHeaders sets the media CSP on every answer of
  # the route, also on the 401 and 404 answers before the controller. The
  # Fetch Metadata plug runs without a cross-site allowlist, and the session
  # check answers 401 without a session and 403 for an enrollment session.
  # The pipeline serves GET requests only, which change nothing.
  # sobelow_skip ["Config.CSRF"]
  pipeline :media do
    plug :put_media_flag
    plug EspalierWeb.Plugs.FetchMetadata
    plug Plug.Session, @api_session
    plug :fetch_session
    plug :fetch_current_scope_for_user
    plug :require_authenticated_user
  end

  # REGISTRAR_ENABLED (task 0013): runs before the role check of :registrar,
  # so a disabled list answers 404 to every caller.
  pipeline :registrar_enabled do
    plug EspalierWeb.Plugs.RegistrarEnabled
  end

  # The integration API for machine clients (task 0013, README section 11).
  # A bearer token in the authorization header is the only credential, so
  # the pipeline holds no session, no CSRF layer and no Fetch Metadata plug:
  # a browser never sends a bearer token by itself, and authorization is no
  # CORS-safelisted header (row 3.5.1 of docs/security/asvs-l2.md).
  # sobelow_skip ["Config.CSRF"]
  pipeline :integration do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: EspalierWeb.ApiSpec
    plug EspalierWeb.Plugs.ApiClientAuth, scope: "credentials:read"
  end

  # This pipeline serves GET navigations only; state, nonce and PKCE bind each
  # OIDC flow (task 0006).
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

  # The SPA route /auth/finish (task 0011). The redirect chain from the
  # provider makes it a cross-site navigation; the route reads no session
  # and serves index.html only.
  pipeline :spa_navigation do
    plug EspalierWeb.Plugs.FetchMetadata, allow_cross_site_navigation: [["auth", "finish"]]
  end

  pipeline :auth_bare do
    plug :accepts, ["json"]
    plug EspalierWeb.Plugs.FetchMetadata
  end

  scope "/", EspalierWeb do
    get "/health", HealthController, :index
  end

  scope "/media", EspalierWeb do
    pipe_through :media

    get "/:file", MediaController, :show
  end

  scope "/auth", EspalierWeb do
    pipe_through :auth_bare

    get "/providers", ProviderController, :index
  end

  # The finish step of an OIDC flow: the SPA posts the ticket of the
  # fragment same-origin to POST /api/auth/finish (README section 6.5).
  scope "/auth", EspalierWeb do
    pipe_through :spa_navigation

    get "/finish", SpaController, :index
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
    post "/auth/ldap/:provider", Auth.LdapController, :create
  end

  # The OpenAPI document (task 0009). It describes the routes of the
  # published source code and holds no data of the instance.
  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  # Learner routes (task 0009). Person-linked rows are read and written only
  # through the scope of the signed-in user.
  scope "/api", EspalierWeb do
    pipe_through [:api, :authenticated]

    get "/programs", ProgramController, :index
    get "/programs/:slug", ProgramController, :show
    get "/programs/:slug/glossary", ProgramController, :glossary
    get "/programs/:slug/handbook", ProgramController, :handbook
    get "/modules/:id", ModuleController, :show
    post "/modules/:id/completion", ModuleCompletionController, :create
    post "/enrollments", EnrollmentController, :create
    patch "/enrollments/:id", EnrollmentController, :update
    post "/items/:id/responses", ItemResponseController, :create
    post "/assessments/:id/attempts", AttemptController, :create
    get "/me/progress", Me.ProgressController, :show
  end

  # Learner routes of task 0013: policies, acknowledgements, requirements
  # and credentials.
  scope "/api", EspalierWeb do
    pipe_through [:api, :authenticated]

    get "/policies", PolicyController, :index
    post "/policy-versions/:id/acknowledgements", AcknowledgementController, :create
    get "/approved-tools", PolicyController, :approved_tools
    get "/me/requirements", Me.RequirementController, :show
    get "/me/credentials", Me.CredentialController, :index
    get "/me/credentials/:id", Me.CredentialController, :show
  end

  # Anonymous insights of learners (task 0014): the answer is stored without
  # the person, and a participation marker lets each person count once.
  scope "/api", EspalierWeb do
    pipe_through [:api, :authenticated]

    post "/self-assessments", SelfAssessmentController, :create
    post "/formats/:id/votes", FormatVoteController, :create
    post "/feedback", FeedbackController, :create
    get "/me/participation", Me.ParticipationController, :show
  end

  # Reports for analysts (task 0014, README section 10).
  scope "/api/insights", EspalierWeb do
    pipe_through [:api, :analyst]

    get "/self-assessment", ReportController, :self_assessment
    get "/items", ReportController, :items
    get "/competence", ReportController, :competence
    get "/formats", ReportController, :formats
    get "/feedback", ReportController, :feedback
    get "/credentials", ReportController, :credentials
  end

  # Attendance and the user lookup of facilitators (task 0013). The lookup
  # takes the address in the JSON body (ASVS 14.2.1).
  scope "/api", EspalierWeb do
    pipe_through [:api, :facilitator]

    post "/formats/:id/attendance", AttendanceController, :create
    post "/facilitator/user-lookups", Facilitator.UserLookupController, :create
  end

  scope "/api/registrar", EspalierWeb.Registrar do
    pipe_through [:api, :registrar_enabled, :registrar]

    get "/credentials", CredentialController, :index
  end

  scope "/api/integration", EspalierWeb.Integration do
    pipe_through [:integration]

    post "/credential-lookups", CredentialLookupController, :create
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
    post "/identities/ldap/:provider", LdapIdentityController, :create
  end

  # The admin area (task 0015, README section 8). Every GET route runs
  # :admin or :author; every POST, PUT, PATCH and DELETE route runs
  # :admin_write or :author_write, apart from the user lookup, which changes
  # no state and carries the address in its body (ASVS 14.2.1), and the
  # check of a pack draft (task 0016a).
  scope "/api/admin", EspalierWeb.Admin do
    pipe_through [:api, :admin]

    resources "/policies", PolicyController, only: [:index, :show]
    resources "/approved-tools", ApprovedToolController, only: [:index, :show]
    resources "/webhooks", WebhookController, only: [:index, :show]
    resources "/policy-versions", PolicyVersionController, only: [:index, :show]
    get "/role-grants", RoleGrantController, :index
    get "/api-clients", ApiClientController, :index
    get "/users", UserAdminController, :index
    post "/user-lookups", UserAdminController, :lookup
    get "/audit", AuditController, :index
  end

  scope "/api/admin", EspalierWeb.Admin do
    pipe_through [:api, :admin_write]

    resources "/policies", PolicyController, only: [:create, :update, :delete]
    resources "/approved-tools", ApprovedToolController, only: [:create, :update, :delete]
    resources "/webhooks", WebhookController, only: [:create, :update, :delete]
    resources "/policy-versions", PolicyVersionController, only: [:create, :update]
    post "/policy-versions/:id/publish", PolicyVersionController, :publish
    post "/role-grants", RoleGrantController, :create
    delete "/role-grants/:id", RoleGrantController, :delete
    post "/api-clients", ApiClientController, :create
    delete "/api-clients/:id", ApiClientController, :delete
    post "/users", UserAdminController, :create
    post "/users/:id/invitation", UserAdminController, :resend_invitation
    post "/users/:id/disable", UserAdminController, :disable
    delete "/users/:id/sessions", UserAdminController, :end_sessions
    delete "/sessions", UserAdminController, :end_all_sessions
    post "/users/:id/reset-factors", UserAdminController, :reset_factors
    post "/users/:id/reset-failure-counters", UserAdminController, :reset_failure_counters
    post "/credentials/:id/revoke", CredentialAdminController, :revoke
  end

  # The check of a draft (task 0016a) writes and removes a temporary
  # directory and changes no state, so it runs in :author like the reads; it
  # carries a content in its body, which a query string cannot hold.
  scope "/api/admin", EspalierWeb.Admin do
    pipe_through [:api, :author]

    get "/packs/:id", PackController, :show
    get "/packs/:id/diff", PackController, :diff
    get "/exports/:id", ExportController, :show
    get "/exports/:id/download", ExportController, :download
    get "/pack-drafts", PackDraftController, :index
    get "/pack-drafts/:id", PackDraftController, :show
    get "/pack-drafts/:id/download", PackDraftController, :download
    post "/pack-drafts/:id/check", PackDraftController, :check
    get "/pack-drafts/:id/files/:file_id", PackDraftFileController, :show
    get "/media", MediaController, :index
    get "/media/:id", MediaController, :show
  end

  scope "/api/admin", EspalierWeb.Admin do
    pipe_through [:api, :author_write]

    post "/packs/:id/publish", PackController, :publish
    post "/exports", ExportController, :create
    post "/pack-drafts", PackDraftController, :create
    delete "/pack-drafts/:id", PackDraftController, :delete
    post "/pack-drafts/:id/imports", PackDraftController, :create_import
    post "/pack-drafts/:id/files", PackDraftFileController, :create
    put "/pack-drafts/:id/files/:file_id", PackDraftFileController, :update
    patch "/pack-drafts/:id/files/:file_id", PackDraftFileController, :rename
    delete "/pack-drafts/:id/files/:file_id", PackDraftFileController, :delete
    post "/pack-drafts/:id/media", PackDraftMediaController, :create
    patch "/pack-drafts/:id/media/:media_id", PackDraftMediaController, :rename
    delete "/pack-drafts/:id/media/:media_id", PackDraftMediaController, :delete
    patch "/media/:id", MediaController, :update
    delete "/media/:id", MediaController, :delete
  end

  scope "/api/admin", EspalierWeb.Admin do
    pipe_through [:api, :author_write, :media_upload]

    post "/media", MediaController, :create
  end

  scope "/api/admin", EspalierWeb.Admin do
    pipe_through [:api, :author_write, :pack_upload]

    post "/packs", PackController, :create
    post "/pack-draft-uploads", PackDraftController, :upload
  end

  # Seeding routes of the end-to-end tests (task 0011). Only config/dev.exs
  # sets dev_routes, and only dev and test compile the controller.
  if Application.compile_env(:espalier, :dev_routes) do
    scope "/api/dev/e2e", EspalierWeb do
      pipe_through :api

      post "/invitations", DevE2EController, :invitations
      post "/reset", DevE2EController, :reset
      post "/reset-demo", DevE2EController, :reset_demo
      post "/age-recent-auth", DevE2EController, :age_recent_auth
      post "/role-grants", DevE2EController, :role_grants
      get "/demo-pack.zip", DevE2EController, :demo_pack
    end
  end

  # The SPA catch-all stays the last route.
  scope "/", EspalierWeb do
    get "/*path", SpaController, :index
  end

  defp put_media_flag(conn, _opts), do: put_private(conn, :espalier_media, true)
end
