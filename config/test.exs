import Config

# Host and port of the database. The port comes from compose.dev.yaml
# (DATABASE_PORT in .env). DATABASE_HOST serves a CI job that runs in a
# container next to the database service. An empty value counts as unset.
database_host =
  case String.trim(System.get_env("DATABASE_HOST", "")) do
    "" -> "localhost"
    host -> host
  end

database_port =
  case String.trim(System.get_env("DATABASE_PORT", "")) do
    "" -> 5432
    port -> String.to_integer(port)
  end

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :espalier, Espalier.Repo,
  username: "postgres",
  password: "postgres",
  hostname: database_host,
  port: database_port,
  database: "espalier_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :espalier, EspalierWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("t", 64),
  server: false

# In test we don't send emails
config :espalier, Espalier.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Invented keys for test data only. Production keys come from CLOAK_KEY_V<n>
# and CLOAK_HMAC_SECRET (config/runtime.exs).
config :espalier, Espalier.Vault, keys: [{1, Base.encode64(String.duplicate("t", 32))}]
config :espalier, Espalier.Hashed.HMAC, secret: Base.encode64(String.duplicate("s", 32))

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
