import Config

# Force using SSL in production. If you have a health check endpoint, you may want to exclude it below.
# Note `:force_ssl` is required to be set at compile-time.
# HSTS comes from the reverse proxy alone (README section 6.5, the Caddyfile
# of docs/guides/examples): with `hsts: true`, Plug.SSL would add a second
# Strict-Transport-Security header with another max-age to every proxied
# response for a host other than localhost (task 0017, step 5).
config :espalier, EspalierWeb.Endpoint,
  force_ssl: [
    hsts: false,
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      # paths: ["/health"],
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

# Configure Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Production logs go to standard output as JSON lines
# (docs/security/logging.md). The `formatter` key of the default handler
# replaces the default formatter (`h Logger`, Elixir 1.20.4).
config :logger, :default_handler,
  formatter:
    {Espalier.Logger.JSONFormatter,
     %{
       metadata: [
         :request_id,
         :event,
         :user_id,
         :session_id,
         :ip,
         :factor,
         :provider,
         :reason,
         :count,
         :account_hash,
         :risk_signal,
         :credential_ref,
         :change,
         :exception,
         :purpose,
         :trigger
       ]
     }}

# ecto_sql logs the cast parameters of a query, which hold the plaintext of
# encrypted and hashed fields before dump. Its query log stays off, and
# Espalier.Telemetry.QueryLog logs queries without parameters. Telemetry
# events are still emitted with `log: false`.
config :espalier, Espalier.Repo, log: false
config :espalier, Espalier.Telemetry.QueryLog, enabled: true

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
