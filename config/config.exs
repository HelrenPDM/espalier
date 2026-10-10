# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :espalier, :scopes,
  user: [
    default: true,
    module: Espalier.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Espalier.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :espalier,
  ecto_repos: [Espalier.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Argon2id. parallelism: 1 keeps the vendored C code off its thread creation
# path (argon2_elixir issue #73) and is encoded into every hash. make
# argon2-bench measures t_cost and m_cost on the production image
# (docs/security/authentication.md).
config :argon2_elixir, argon2_type: 2, parallelism: 1, t_cost: 2, m_cost: 16

config :espalier, Oban,
  engine: Oban.Engines.Basic,
  repo: Espalier.Repo,
  queues: [default: 10, mail: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 86_400},
    {Oban.Plugins.Cron, crontab: [{"0 2 * * *", Espalier.Accounts.PurgeExpiredTokensWorker}]}
  ]

# Rate limit buckets as {scale_ms, limit} (docs/security/authentication.md).
config :espalier, :rate_limits, %{
  auth_ip: {:timer.minutes(1), 30},
  password_account: {:timer.minutes(15), 10},
  invitation_ip: {:timer.minutes(15), 10},
  invitation_target: {:timer.hours(1), 3},
  demo_ip: {:timer.minutes(1), 10},
  account_change: {:timer.minutes(15), 10},
  passkey_options_ip: {:timer.minutes(1), 30},
  passkey_ip: {:timer.minutes(1), 10},
  second_factor_ip: {:timer.minutes(1), 10},
  second_factor_user: {:timer.minutes(1), 10},
  recovery_start_ip: {:timer.minutes(1), 10},
  recovery_start_target: {:timer.hours(1), 3},
  recovery_verify_ip: {:timer.minutes(1), 10},
  recovery_verify_user: {:timer.minutes(15), 10},
  reauth_user: {:timer.minutes(1), 10},
  totp_confirm_user: {:timer.minutes(1), 10},
  oidc_authorize: {:timer.minutes(1), 30},
  oidc_callback: {:timer.minutes(1), 30},
  oidc_intent: {:timer.minutes(1), 10},
  oidc_front_channel: {:timer.minutes(1), 60},
  ldap_ip: {:timer.minutes(1), 20},
  ldap_account: {:timer.minutes(1), 5},
  ldap_subject: {:timer.minutes(1), 5},
  learner_write: {:timer.minutes(1), 120},
  assessment_attempt: {:timer.minutes(10), 10}
}

# Failed directory sign-ins answer no earlier than this many milliseconds
# after the request started (task 0007, step 16).
config :espalier, Espalier.Accounts.LdapSignIn, failure_floor_ms: 1_000

# Passkeys (task 0005). config/dev.exs and config/test.exs set the relying
# party id and the origins, and config/runtime.exs derives them from
# PUBLIC_URL in production. No config :wax_ block exists, because
# Wax.Challenge.new/1 merges that environment into every challenge; every
# option is passed per call.
config :espalier, :webauthn, rp_name: "Espalier"

# Issuer shown by authenticator apps for TOTP factors.
config :espalier, :totp_issuer, "Espalier"

config :espalier, :bootstrap_on_boot, true

# Configure the endpoint
config :espalier, EspalierWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: EspalierWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Espalier.PubSub,
  live_view: [signing_salt: "BGC9pZL+"]

# Configure the mailer. config/dev.exs sends to Mailpit, config/test.exs uses
# the test adapter, and config/runtime.exs configures SMTP for production.
config :espalier, Espalier.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :event]

# Phoenix filters every parameter whose key contains one of these strings,
# also inside nested maps (docs/security/logging.md).
config :phoenix, :filter_parameters, [
  "password",
  "current_password",
  "email",
  "token",
  "code",
  "secret",
  "recovery_code",
  "totp",
  "passkey",
  "credential",
  "response",
  "rawId",
  "state",
  "session_state",
  "ticket",
  "intent",
  "sid",
  "id_token",
  "answer"
]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
