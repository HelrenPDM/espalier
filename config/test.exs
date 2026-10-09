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

# Cheap Argon2 parameters for the test suite only; the timing test sets the
# production values for its own run.
config :argon2_elixir, t_cost: 1, m_cost: 8, parallelism: 1

# Jobs run only through Oban.Testing (perform_job/3, drain_queue/2).
config :espalier, Oban, testing: :manual

config :espalier, :bootstrap_on_boot, false

# Every ConnTest request comes from 127.0.0.1 and the ETS table is global to
# the node, so the suite runs with limits no test reaches. The rate limit
# tests restore a real limit with put_rate_limit/2.
config :espalier, :rate_limits, %{
  auth_ip: {:timer.minutes(1), 1_000_000},
  password_account: {:timer.minutes(1), 1_000_000},
  invitation_ip: {:timer.minutes(1), 1_000_000},
  invitation_target: {:timer.minutes(1), 1_000_000},
  demo_ip: {:timer.minutes(1), 1_000_000},
  account_change: {:timer.minutes(1), 1_000_000},
  passkey_options_ip: {:timer.minutes(1), 1_000_000},
  passkey_ip: {:timer.minutes(1), 1_000_000},
  second_factor_ip: {:timer.minutes(1), 1_000_000},
  second_factor_user: {:timer.minutes(1), 1_000_000},
  recovery_start_ip: {:timer.minutes(1), 1_000_000},
  recovery_start_target: {:timer.minutes(1), 1_000_000},
  recovery_verify_ip: {:timer.minutes(1), 1_000_000},
  recovery_verify_user: {:timer.minutes(1), 1_000_000},
  reauth_user: {:timer.minutes(1), 1_000_000},
  totp_confirm_user: {:timer.minutes(1), 1_000_000},
  oidc_authorize: {:timer.minutes(1), 1_000_000},
  oidc_callback: {:timer.minutes(1), 1_000_000},
  oidc_intent: {:timer.minutes(1), 1_000_000},
  oidc_front_channel: {:timer.minutes(1), 1_000_000}
}

# Passkeys: the SPA origin of PUBLIC_URL (task 0005).
config :espalier, :webauthn, rp_id: "localhost", origins: ["http://localhost:5173"]

# Requests from the tests stub the Pwned Passwords API.
config :espalier, Espalier.Accounts.BreachedPasswords,
  req_options: [plug: {Req.Test, Espalier.Accounts.BreachedPasswords}, retry: false]

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Invented keys for test data only. Production keys come from CLOAK_KEY_V<n>
# and CLOAK_HMAC_SECRET (config/runtime.exs).
config :espalier, Espalier.Vault, keys: [{1, Base.encode64(String.duplicate("t", 32))}]
config :espalier, Espalier.Hashed.HMAC, secret: Base.encode64(String.duplicate("s", 32))

# Mock OIDC provider of test/support/dev_oidc/ (task 0006, `make dev-oidc`).
# The fixture secret works only against the mock, and the tenant id is
# invented. allow_unsafe_http admits the http:// end-session endpoint of the
# mock on localhost; no other configuration sets it.
oidc_public_url =
  case String.trim(System.get_env("PUBLIC_URL", "")) do
    "" -> "http://localhost:5173"
    url -> url |> String.trim("\"") |> String.trim_trailing("/")
  end

config :espalier, :dev_children, [{Espalier.DevOidc, port: 4011}]

config :espalier, Espalier.DevOidc,
  client_id: "espalier-dev",
  client_secret: "dev-oidc-fixture-secret",
  tenant_id: "3f0c2a9e-7b1d-4e5a-8c6f-2d9b0e4a1c7d",
  redirect_uris:
    for(key <- ["entra", "google", "oidc"], do: "#{oidc_public_url}/auth/oidc/#{key}/callback"),
  post_logout_redirect_uris: ["#{oidc_public_url}/signed-out"]

# The OIDC tests start Espalier.Identity.Oidc.Supervisor themselves, with
# short retry intervals.
config :espalier, Espalier.Identity.Oidc,
  allow_unsafe_http: true,
  start_supervisor: false,
  backoff_min: 100,
  backoff_max: 500

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
