import Config

# Force using SSL in production. This also sets the "strict-security-transport" header,
# known as HSTS. If you have a health check endpoint, you may want to exclude it below.
# Note `:force_ssl` is required to be set at compile-time.
config :espalier, EspalierWeb.Endpoint,
  force_ssl: [
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

# ecto_sql logs the cast parameters of a query, which hold the plaintext of
# encrypted and hashed fields before dump. Its query log stays off, and
# Espalier.Telemetry.QueryLog logs queries without parameters. Telemetry
# events are still emitted with `log: false`.
config :espalier, Espalier.Repo, log: false
config :espalier, Espalier.Telemetry.QueryLog, enabled: true

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
