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

# webhooks delivers the credential events of task 0013, and exports serves
# the exports of task 0016. The credential sweep of task 0013 and the
# retention job of task 0014 run daily.
config :espalier, Oban,
  engine: Oban.Engines.Basic,
  repo: Espalier.Repo,
  queues: [default: 10, mail: 5, webhooks: 5, exports: 1, media: 2, media_video: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 86_400},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 2 * * *", Espalier.Accounts.PurgeExpiredTokensWorker},
       {"0 3 * * *", Espalier.Credentials.SweepWorker},
       {"30 3 * * *", Espalier.Insights.RetentionWorker},
       # Ends the exports of task 0016 whose build was interrupted and
       # applies their retention.
       {"*/15 * * * *", Espalier.Interop.StaleExportWorker},
       # Fails interrupted media jobs and removes leftover media files (task
       # 0018), and deletes imported media that no program, draft or import
       # uses.
       {"*/15 * * * *", Espalier.Media.StaleWorker},
       {"45 3 * * *", Espalier.Media.RetentionWorker}
     ]}
  ]

# The retention of SCORM exports (task 0016, Espalier.Interop.retention/0):
# an export with status done or failed is deleted with its files
# max_age_days after its last change, and of the done exports only the
# newest max_packages keep their package.
config :espalier, :export_retention, max_age_days: 7, max_packages: 100

# The fixed limits of the media store (task 0018, step 4), read through
# Espalier.Media. The runtime settings of README section 6.11 (MEDIA_DIR and
# the MEDIA_* variables) join this list from config/runtime.exs. Sizes are
# bytes, pixels count width times height, and the timeouts are seconds; the
# deadline of a video conversion is max(video_timeout_floor_seconds,
# video_timeout_factor * duration). A running job sets updated_at of its
# asset every heartbeat_seconds, and Espalier.Media.StaleWorker fails an
# asset in processing whose updated_at lies more than
# stale_processing_seconds back, a multiple of heartbeat_seconds.
config :espalier, :media,
  svg_max_bytes: 1_048_576,
  captions_max_bytes: 524_288,
  max_input_pixels: 40_000_000,
  max_video_pixels: 8_294_400,
  max_frames: 1_000,
  image_timeout_seconds: 120,
  video_timeout_factor: 25,
  video_timeout_floor_seconds: 600,
  heartbeat_seconds: 60,
  stale_processing_seconds: 600,
  max_pack_media: 500,
  max_draft_media: 500,
  export_max_mb: 1_024

# Imported media (origin pack) that no program, draft or validated import
# has used for unused_days are deleted (Espalier.Media.RetentionWorker).
config :espalier, :media_retention, unused_days: 30

# The drafts of the pack workbench (task 0016a, Espalier.Workbench): at most
# max_drafts drafts in total, and at most max_parallel_checks checks,
# imports and zip builds of downloads from drafts at once per node. At most
# max_parallel_downloads downloads of drafts run at once per node, one per
# user, from the zip build to the end of the transfer (task 0018). A
# transfer ends at its deadline: the size of the zip at
# download_min_bytes_per_second (256 KiB, about 2 Mbit/s, so 1,024 MB of
# media take about 68 minutes), and at least download_floor_seconds.
config :espalier, :pack_drafts,
  max_drafts: 50,
  max_parallel_checks: 2,
  max_parallel_downloads: 2,
  download_min_bytes_per_second: 262_144,
  download_floor_seconds: 60

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
  assessment_attempt: {:timer.minutes(10), 10},
  insights_write: {:timer.minutes(1), 30}
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
  # No HTTP/2: Espalier serves HTTP/1.1 behind its reverse proxy, and the
  # endpoint accepts no HTTP/2 with prior knowledge over plain TCP. The env
  # files and config/runtime.exs merge their http options into this list.
  http: [http_2_options: [enabled: false]],
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
