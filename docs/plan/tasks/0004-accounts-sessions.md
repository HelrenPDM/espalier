# 0004: Accounts and sessions from phx.gen.auth

> Milestone: M1 Accounts, Depends on: 0002, 0003

## Context to read first
- Read `docs/plan/README.md`, sections 5 (session, cookies and CSRF; scopes), 6.1, 6.2, 6.4, 6.5, 6.9 (encrypted fields), 6.10, 6.11, 6.12 (shared interfaces between the account tasks), 8 (API outline), 12 (Makefile), 13 (quality gates) and 15 (decision D12).
- Read `docs/architecture/session-lifecycle.puml`, `auth-local.puml` (invitation, password with second factor), `auth-oidc.puml` (pending state after `POST /api/auth/finish`), `domain-records.puml` (package Accounts and authentication, `AuditEvent`) and `domain-values.puml` (packages Authentication and Identity and policies).
- Read `docs/plan/tasks/0003-encryption-at-rest.md` for `Espalier.Vault`, `Espalier.Encrypted.Binary` and `Espalier.Hashed.HMAC` (README section 6.12). Read its steps 11, 13, 16 and 18 as well: they define the rotation-only schemas `Espalier.Crypto.Rotation.<Table>` in `lib/espalier/crypto/rotation/`, the tests under `test/espalier/crypto/` that this task must keep green, the rows of `docs/security/crypto-inventory.md` that this task completes, and the layout of `docs/security/asvs-l2.md`.
- Read `docs/plan/tasks/0005-second-factors.md`, step 12, for the clauses that 0005 adds to the strength check of `create_session/2`.
- Read the Notes of `docs/plan/tasks/0002-quality-ci-oss.md` for the Sobelow check `Config.CSRF` and the way an accepted finding is recorded in code (step 32 of this task).
- Read the output of `nix-shell --run "mix help phx.gen.auth"` (Phoenix 1.8.15) and, once step 2 has run, the reference project in `tmp/auth-reference/espalier/`.

## Goal
The API project holds the account core of `phx.gen.auth`, generated in a
reference project and ported to JSON. User records keep e-mail address, display
name and org unit encrypted. Sessions are server-side rows behind an encrypted
`__Host-` cookie, with idle and absolute timeouts checked on the server, and
every mutating request passes the CSRF token check, the Fetch Metadata check and
the `Strict` cookie. A password alone yields only a pending second-factor state,
and an invitation link yields only an enrollment session. Throttling, durable
failure counters, security event logging, audit events, roles, the demo sign-in
and the ASVS 5.0.0 Level 2 matrix are in place for the tasks that follow.

## Scope
- In: The task adds the `make auth-reference` target and ports the context layer, the session plugs, the fixtures and the tests of `phx.gen.auth` into the API project.
- In: It changes the `users` and `users_tokens` tables for Cloak, hashed session tokens, session metadata, timeouts and the concurrent session limit, and it adds Oban with the daily purge job.
- In: It adds both cookie configurations in the router, the CSRF layers, the security header plug, trusted proxy handling, throttling with Hammer and the durable failure counters.
- In: It adds password sign-in up to the pending second-factor state, invitations and `SIGNUP`, e-mail and password change, listing and ending sessions, the demo sign-in, roles and role grants, the bootstrap admin, API clients, external identity rows, security event logging, audit events, mail through Oban with Mailpit in development, and the extension of the ASVS matrix that 0003 creates.
- In: It adds the rotation-only schemas of its encrypted columns and completes their rows in the cryptographic inventory of 0003, the helper `EspalierWeb.TransactionCookie` for the `__Host-espalier_tx` cookie, the device summary of each session row, and the base of `Espalier.Identity.Config` with `public_entry/1` and `GET /auth/providers` (`ProviderController`, pipeline `:auth_bare`), which 0006 and 0007 extend with their provider types.
- In: It holds the ownership table of `docs/security/asvs-l2.md` (step 42), which assigns every row of the matrix to one owning task and names the tasks that extend it.
- Out: Passkeys, TOTP, recovery codes, `POST /api/auth/second-factor`, the step-up endpoint `POST /api/me/reauth`, the enrollment routes, the recovery pathway with `/recover#token=`, the real implementation of `Accounts.enrolled?/1`, `Accounts.Factors.complete_enrollment/3` and `ADMIN_REQUIRE_PASSKEY` belong to 0005.
- Out: OIDC routes, the OIDC provider types of `Espalier.Identity.Config`, the sign-in ticket, `POST /api/auth/finish`, `POST /api/auth/oidc/:provider/intents`, `Accounts.sign_in_external/2`, `link_external_identity/3`, RP-initiated logout with the post-logout page `/signed-out`, front-channel logout and the identity resolution rules belong to 0006. LDAP belongs to 0007, which also makes `failure_counters.user_id` nullable for directory counters.
- Out: OpenAPI operations for the routes of this task belong to 0009 (README section 6.12), the SPA pages to 0010 and 0011, the admin routes to 0015, and HSTS, the reverse proxy example and the checks against the running container to 0017.

## Security requirements
- 3.2.1: API responses are JSON with `content-type: application/json` and `x-content-type-options: nosniff`, and the Fetch Metadata plug rejects cross-site requests that are no allowlisted navigation.
- 3.3.1: `__Host-espalier` and `__Host-espalier_tx` carry `Secure`.
- 3.3.2: the session cookie carries `SameSite=Strict`, and the OIDC transaction cookie carries `SameSite=Lax`.
- 3.3.3: both cookie names carry the `__Host-` prefix, with `Path=/` and no `Domain`.
- 3.3.4: both cookies carry `HttpOnly`, and the session token travels only in `Set-Cookie`.
- 3.4.2: no response carries `Access-Control-Allow-Origin`, because the SPA and the API share one origin.
- 3.4.3: every response carries the CSP of README section 6.5 with `object-src 'none'` and `base-uri 'none'`.
- 3.4.4: every response carries `X-Content-Type-Options: nosniff`.
- 3.4.5: every response carries `Referrer-Policy: strict-origin-when-cross-origin`.
- 3.4.6: the CSP of every response contains `frame-ancestors 'none'`.
- 3.4.8 (selected Level 3 item): every response carries `Cross-Origin-Opener-Policy: same-origin`.
- 3.5.1: every mutating request under `/api` must carry the CSRF token in the `x-csrf-token` header.
- 3.5.2: the CSRF defense holds without a CORS preflight, because a mutating request without the `x-csrf-token` header, which is no CORS-safelisted header, fails the CSRF check, and the Fetch Metadata plug checks `Origin` when `Sec-Fetch-Site` is missing.
- 3.5.3: no GET route changes state.
- 3.5.8 (selected Level 3 item): the Fetch Metadata plug rejects cross-site requests, and every response carries `Cross-Origin-Resource-Policy: same-origin`.
- 6.1.1: the rate limits, the failure counters and the protection against malicious lockout are documented.
- 6.1.2: the context-word list is documented.
- 6.1.3: the pathways of this task are documented with their session strength.
- 6.2.1: a password has at least 15 code points, counted after NFC normalization.
- 6.2.2 and 6.2.3: users change their password with the current and the new password.
- 6.2.4: the bundled common-password list holds at least 3000 entries that satisfy the length rule.
- 6.2.5: no composition rule exists.
- 6.2.8 (deviation, README section 15, decision D12): `PasswordPolicy.prepare/1` normalizes every password to Unicode NFC before the length check, the blocklist checks, the breached-password check, the Argon2id hash and the verification. The matrix records the row with the status `deviation` and the reason from NIST SP 800-63B-4 section 3.1.1.2: a password verifies in the same way on keyboards and devices that produce different Unicode forms of the same characters.
- 6.2.9: passwords of up to 128 code points, counted after NFC normalization, are accepted.
- 6.2.10: no periodic password change exists.
- 6.2.11: the context-word list is checked.
- 6.2.12: the password is checked against breached passwords (bundled list, optional range API).
- 6.3.1: throttling and failure counters are implemented as documented.
- 6.3.2: no default account exists.
- 6.3.4: a password alone never opens a session, and every pathway ends in `log_in_user/3` with a strength check.
- 6.3.5 (selected Level 3 item): the user is notified of a sign-in after repeated failures.
- 6.3.7 (selected Level 3 item): the user is notified of a password change and of an e-mail change at the old address.
- 6.3.8 (selected Level 3 item): sign-in, invitation request and e-mail change answer with the same body, status and timing for known and unknown accounts.
- 6.4.1: invitation tokens have 256 bits from a CSPRNG, live 10 minutes and work once.
- 6.4.2: no password hint and no secret question exists.
- 6.5.5: invitation and e-mail change links expire after 10 minutes.
- 7.1.1 and 7.1.2: idle timeout, absolute lifetime and the concurrent session limit are documented with their behaviour.
- 7.2.1: the session token is verified on the server against the database.
- 7.2.2: session tokens are generated per sign-in, and no static secret grants access.
- 7.2.3: session tokens carry 256 bits from `:crypto.strong_rand_bytes/1`.
- 7.2.4: sign-in and reissue create a new token, and the previous row is deleted, including the row whose token the cookie held before a sign-in.
- 7.3.1 and 7.3.2: the server enforces 60 minutes of inactivity and 24 hours of absolute lifetime.
- 7.4.1: logout deletes the session row.
- 7.4.2: disabling a user ends all sessions of that user.
- 7.4.3: a password change ends every other session of the user.
- 7.4.5: context functions end the sessions of one user or of all users.
- 7.5.1: e-mail and password changes require a second factor from the last 10 minutes.
- 7.5.2: users list their sessions and end them after re-authentication.
- 7.6.2: a session starts only after an explicit POST of the user.
- 8.1.1: the roles and their checks are documented.
- 8.2.1: role pipelines check every role-bound route on the server.
- 8.3.1: authorization runs in plugs and contexts on the server.
- 11.4.2: passwords are hashed with Argon2id and parameters benchmarked on the production image.
- 11.5.1: every token comes from `:crypto.strong_rand_bytes(32)`, and no UUID serves as a secret.
- 12.3.1: production mail goes out over SMTP with TLS.
- 16.1.1: the log inventory is documented.
- 16.2.1: security events record when, where, who and what.
- 16.2.2: timestamps are UTC.
- 16.2.3: logs go to standard output only, which is the one destination that `docs/security/logging.md` documents.
- 16.2.4: production logs are JSON lines.
- 16.2.5: logs contain no password, code or token; sessions appear by row id.
- 16.3.1: every authentication operation is logged with factor and provider.
- 16.3.2: failed authorization is logged as `authz_fail`.
- 16.3.3: rate limit and CSRF rejections are logged.
- 16.3.4: unexpected errors, a failed mail delivery and an unreachable breached-password API are logged.
- 16.4.1: JSON encoding prevents log injection.
- 16.5.1: error responses carry a code and no internals.

## Steps

### Reference project and port

1. Add the target `auth-reference` to the `Makefile`, next to a variable for the installer version:
   ```make
   PHX_NEW_VERSION ?= 1.8.15

   auth-reference: ## Regenerate the phx.gen.auth reference project in tmp/auth-reference
   	rm -rf tmp/auth-reference.previous
   	if [ -d tmp/auth-reference ]; then mv tmp/auth-reference tmp/auth-reference.previous; fi
   	mkdir -p tmp/auth-reference
   	$(NIX) "mix archive.install hex phx_new $(PHX_NEW_VERSION) --force"
   	$(NIX) "cd tmp/auth-reference && mix phx.new espalier --module Espalier --binary-id --no-assets --no-dashboard --no-install"
   	$(NIX) "cd tmp/auth-reference/espalier && mix deps.get && printf 'Y\n' | mix phx.gen.auth Accounts User users --no-live --hashing-lib argon2"
   	test -f tmp/auth-reference/espalier/lib/espalier_web/user_auth.ex
   ```
   The reference is a full HTML project, because `mix phx.gen.auth` raises `mix phx.gen.auth requires phoenix_html` in a project generated with `--no-html`. The generator asks once, `Warning: did not find phoenix_html in your app.js. [...] Continue? [Yn]`, because the reference has no assets; the piped `Y` answers it. When the generator meets a further prompt, it reads the end of input, takes it as no and halts with exit status 0; the final `test -f` line then fails the target. Check that `.gitignore` contains `/tmp/` (generated by `phx.new`) and add it if it is missing.
2. Run `make auth-reference`. The reference contains, among the HTML files, `priv/repo/migrations/<timestamp>_create_users_auth_tables.exs`, `lib/espalier/accounts.ex`, `lib/espalier/accounts/{user,user_token,scope,user_notifier}.ex`, `lib/espalier_web/user_auth.ex`, `test/espalier/accounts_test.exs`, `test/espalier_web/user_auth_test.exs`, `test/support/fixtures/accounts_fixtures.ex`, and injected blocks in `test/support/conn_case.ex`, `config/config.exs`, `config/test.exs` and `mix.exs`.
3. Copy into the API project:

   | Reference file | Treatment |
   |---|---|
   | `priv/repo/migrations/*_create_users_auth_tables.exs` | copy, edit in step 10 before it ever runs |
   | `lib/espalier/accounts.ex` | copy, adapt in steps 13 to 27 |
   | `lib/espalier/accounts/user.ex`, `user_token.ex`, `scope.ex`, `user_notifier.ex` | copy, adapt |
   | `lib/espalier_web/user_auth.ex` | port to JSON in step 33 |
   | `test/espalier/accounts_test.exs`, `test/espalier_web/user_auth_test.exs` | copy, adapt to the ported behaviour |
   | `test/support/fixtures/accounts_fixtures.ex` | copy, adapt |
   | block injected into `test/support/conn_case.ex` | merge, adapt in step 44 |
   | `config :espalier, :scopes, user: [...]` from `config/config.exs` | merge unchanged |
   | `config :argon2_elixir, t_cost: 1, m_cost: 8` from `config/test.exs` | merge, add `parallelism: 1` |
   | `{:argon2_elixir, "~> 4.0"}` from `mix.exs` | add as `~> 4.1` in step 6 |

   Do not copy the `*_html.ex` modules, the `*.html.heex` templates, `user_registration_controller.ex`, `user_session_controller.ex`, `user_settings_controller.ex`, their tests, the router injection, the `root.html.heex` injection or the `AGENTS.md` injection. The session and settings controllers of the reference serve as the model for the JSON controllers of step 35.
4. Start every copied or ported file, including tests and the migration, with the line `# Derived from phx.gen.auth (Phoenix 1.8.15).` After a Phoenix upgrade, run `make auth-reference` once with the old `PHX_NEW_VERSION` and once with the new one, then read `diff -ru tmp/auth-reference.previous/espalier tmp/auth-reference/espalier` for fixes to port.
5. Port the generated `Accounts` functions as follows, and keep the generator's names where the table keeps them:

   | Generated | Ported |
   |---|---|
   | `get_user_by_email/1` | kept; looks up `email_hash` with `normalize_email/1` |
   | `get_user_by_email_and_password/2` | `authenticate_password/3` (step 16) |
   | `register_user/1` | removed; `invite_user/2` and `request_invitation/1` (step 19) |
   | `sudo_mode?/2` | `Scope.recent_auth?/1` (step 22) |
   | `get_user_by_magic_link_token/1`, `login_user_by_magic_link/1`, `deliver_login_instructions/2` | removed; `accept_invitation/1` keeps the two-step consumption, the token wipe and the pre-stuffing guard (step 19) |
   | `deliver_user_update_email_instructions/3`, `update_user_email/2` | `request_email_change/2`, `confirm_email_change/2` (step 20) |
   | `change_user_password/3` | kept |
   | `update_user_password/2` | `update_user_password/3` with the current-password check and the option `require_current` (step 21) |
   | `generate_user_session_token/1`, `get_user_by_session_token/1` | `create_session/2`, `get_session_by_token/2` (step 18) |
   | `delete_user_session_token/1` | kept |

### Dependencies, Oban and mail

6. In `mix.exs`, add `{:argon2_elixir, "~> 4.1"}`, `{:hammer, "~> 7.5"}`, `{:gen_smtp, "~> 1.1"}` and `{:oban, "~> 2.<minor>"}` with the current minor from `nix-shell --run "mix hex.info oban"`. Change `{:swoosh, "~> 1.16"}` to `~> 1.28` and `{:req, "~> 0.5"}` to `~> 0.7`. Run `make init`.
7. In `config/config.exs`, set `config :argon2_elixir, argon2_type: 2, parallelism: 1, t_cost: 2, m_cost: 16`. `parallelism: 1` keeps the vendored C code off its thread creation path, which upstream issue #73 reports failing on this OTP version, and it is encoded into every hash, so every stored hash uses it from the start. Step 46 confirms or lowers `t_cost` and `m_cost` on the production image; `m_cost` never goes below 15 with `t_cost: 2`, which stays above the OWASP minimum of 19 MiB.
8. Install Oban as its installation guide for the resolved release describes:
   - Run `nix-shell --run "mix ecto.gen.migration add_oban_jobs_table"` and write `def up, do: Oban.Migration.up(version: <N>)` and `def down, do: Oban.Migration.down(version: 1)`, where `<N>` is the migration version the guide names for that release. The guide of Oban 2.24.1 uses the module `Oban.Migration` and `version: 14`. Open the installation guide of the resolved release (`https://oban.hexdocs.pm/installation.html` serves the current one) and use the module name and the version it shows.
   - `config/config.exs` receives:
     ```elixir
     config :espalier, Oban,
       engine: Oban.Engines.Basic,
       repo: Espalier.Repo,
       queues: [default: 10, mail: 5],
       plugins: [
         {Oban.Plugins.Pruner, max_age: 86_400},
         {Oban.Plugins.Cron, crontab: [{"0 2 * * *", Espalier.Accounts.PurgeExpiredTokensWorker}]}
       ]
     ```
   - `config/test.exs` sets `config :espalier, Oban, testing: :manual`.
   - `Espalier.Application` starts `{Oban, Application.fetch_env!(:espalier, Oban)}` after the Repo.
   - `DataCase` and `ConnCase` receive `use Oban.Testing, repo: Espalier.Repo`.
   Task 0013 reuses this installation and adds its queues; 0014 adds its job to the same crontab.
9. Mail in development: add to `compose.dev.yaml`
   ```yaml
     mailpit:
       image: axllent/mailpit:v1.31.4
       ports:
         - "127.0.0.1:1025:1025"
         - "127.0.0.1:8025:8025"
   ```
   Both ports are published on the loopback interface only, because the UI and the API on port 8025 show every development mail, including invitation and e-mail change links, to anyone who reaches the port. Set in `config/dev.exs`
   ```elixir
   config :espalier, Espalier.Mailer,
     adapter: Swoosh.Adapters.SMTP,
     relay: "localhost",
     port: 1025,
     ssl: false,
     tls: :never,
     auth: :never,
     no_mx_lookups: true,
     retries: 1
   ```
   Delete the `/dev` scope with the `Plug.Swoosh.MailboxPreview` forward from the router; Mailpit at `http://localhost:8025` replaces it, and that scope relies on the endpoint session that step 28 removes. In `config/runtime.exs` for `:prod`, configure `Swoosh.Adapters.SMTP` from `SMTP_HOST`, `SMTP_PORT` (default 587), `SMTP_USERNAME`, `SMTP_PASSWORD` with `tls: :always` and `auth: :always`, and verify in the documentation of `Swoosh.Adapters.SMTP` 1.28 how certificate verification options reach `gen_smtp`; set `verify: :verify_peer` with `cacerts: :public_key.cacerts_get()` and server name indication through that option. `MAIL_FROM` sets the sender in every environment.

### Schemas and migrations

10. Edit the copied migration before it runs for the first time. Remove the `citext` extension line. The tables become:
    ```elixir
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :binary
      add :email_hash, :binary
      add :display_name, :binary
      add :org_unit, :binary
      add :locale, :string, null: false, default: "en"
      add :status, :string, null: false, default: "active"
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :last_login_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email_hash])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :context, :string, null: false
      add :sent_to_hash, :binary
      add :new_email, :binary
      add :authenticated_at, :utc_datetime
      add :auth_methods, {:array, :string}, null: false, default: []
      add :strength, :string
      add :mfa_at, :utc_datetime
      add :provider_key, :string
      add :idp_sid_hash, :binary
      add :device_summary, :string, size: 64
      add :last_seen_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token_hash])
    create index(:users_tokens, [:expires_at])
    create index(:users_tokens, [:idp_sid_hash], where: "idp_sid_hash IS NOT NULL")
    ```
    `email` stays nullable, because demo users have no address. `device_summary` holds the browser and system family of step 18. The full `User-Agent` string is never stored.
11. Generate the remaining schemas, each command through `nix-shell --run "..."`. With the default scope from step 3, `phx.gen.schema` adds the owning user itself: the migration line `add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)` with an index on `user_id`, the schema field `field :user_id, :binary_id`, and a third changeset argument `user_scope` from which the changeset puts `user_id` (Phoenix 1.8.15, `priv/templates/phx.gen.schema/migration.exs.eex` and `schema.ex.eex`). The commands for tables with a user therefore name no `user_id`; a command that names `user_id:references:users` together with the default scope raises `Reference :user_id has the same name as the scope schema key` (`lib/mix/phoenix/schema.ex`). Tables without a user take `--no-scope`. Edit the migrations as listed:
    - Run `nix-shell --run "mix phx.gen.schema Accounts.RoleGrant role_grants role:enum:learner:facilitator:author:registrar:analyst:admin source:enum:idp_claim:manual provider_key:string"`. Add `null: false` to the generated `user_id` line and replace the generated index on `user_id` with a unique index on `(user_id, role, source)`, whose first column serves lookups by user. Remove `provider_key` from `validate_required`, because `manual` grants carry none.
    - Run `nix-shell --run "mix phx.gen.schema Accounts.ExternalIdentity external_identities provider_key:string issuer:string tenant_id:string subject:binary subject_hash:binary"`. Add `null: false` to the generated `user_id` line, set `null: false` on `provider_key`, `issuer`, `subject` and `subject_hash`, keep the generated index on `user_id`, and add a unique index on `(provider_key, subject_hash)`. Remove `tenant_id` from `validate_required`, because only Entra ID identities carry it. In the schema, `subject` uses `Espalier.Encrypted.Binary` and `subject_hash` uses `Espalier.Hashed.HMAC`, both with `redact: true`.
      The hash input is fixed here, because this task writes the first identities (the demo identities of step 25). Write `Espalier.Accounts.ExternalIdentity.hash_input(issuer, tenant_id, subject)`, which returns `Enum.join([issuer, tenant_id || "", subject], <<0>>)`. Remove `subject_hash` from the `cast/3` list of the generated changeset. `changeset/3` puts `hash_input/3` of the cast `issuer`, `tenant_id` and `subject` into `subject_hash` with `put_change/3` before `validate_required/2`, so a caller never passes `subject_hash`, and the HMAC type stores the keyed hash. The same `subject` at two issuers thereby yields two keys. A lookup passes the result of `hash_input/3` as the value of `subject_hash`, and Ecto hashes it through the field type (cloak_ecto 1.3.0, `lib/cloak_ecto/types/hmac.ex`, `dump/1`). 0006 and 0007 reuse `hash_input/3` and the changeset for their identities.
    - Run `nix-shell --run "mix phx.gen.schema Accounts.FailureCounter failure_counters authenticator:enum:password:totp:recovery_code:passkey:ldap consecutive_failures:integer locked_until:utc_datetime disabled_at:utc_datetime"`. Add `null: false` to the generated `user_id` line, set `null: false` on `authenticator`, give `consecutive_failures` `null: false, default: 0`, and replace the generated index on `user_id` with a unique index on `(user_id, authenticator)`. PostgreSQL treats NULL values as distinct in a unique index, so a nullable `user_id` or `authenticator` would let the upsert of step 17 insert duplicate counters. 0007 drops the `null: false` on `user_id` for directory counters in its own migration (README section 6.12).
    - Run `nix-shell --run "mix phx.gen.schema Accounts.ApiClient api_clients name:string token_hash:binary scopes:array:string last_used_at:utc_datetime --no-scope"` and add a unique index on `token_hash`. A machine client belongs to no user.
    - Run `nix-shell --run "mix phx.gen.schema Audit.AuditEvent audit_events actor_id:references:users action:string subject_type:string subject_id:uuid details:map at:utc_datetime --no-scope"`. An audit event belongs to no user; its actor is a reference of its own. Set `on_delete: :nilify_all` on `actor_id` and add indexes on `at` and `action`. `details` holds role names, provider keys and counts. It holds no personal data. The column stays `jsonb`, so that the admin area of 0015 can filter on it in SQL.
    - The three schemas with a user keep the generated `changeset/3`. Its scope argument names the user who owns the row, so the context passes `Scope.for_user(user)` for the grantee of a role, for the owner of an external identity and for the owner of a failure counter, also when an admin or the system scope acts.
12. Schemas:
    - In `User`, the fields `email`, `display_name` and `org_unit` use `Espalier.Encrypted.Binary` and `email_hash` uses `Espalier.Hashed.HMAC`, all with `redact: true`. `status` is `Ecto.Enum, values: [:active, :disabled]`, and the schema has `has_many` associations to tokens, role grants, external identities and failure counters.
    - In `UserToken`, `token_hash` is `:binary` and `context` is `Ecto.Enum, values: [:session, :invite, :change_email, :recovery_email, :login_ticket]`. `sent_to_hash` uses `Espalier.Hashed.HMAC`, and `new_email` uses `Espalier.Encrypted.Binary`; both carry `redact: true`, which `schema_rules_test.exs` of 0003 requires for every encrypted and hashed field. `idp_sid_hash` is a plain `:binary` field with `redact: true` (next item). `auth_methods` is `{:array, Ecto.Enum}` with `values: [:passkey, :password, :totp, :recovery_code, :email_code, :oidc, :ldap, :idp_mfa, :demo]`, and `strength` is `Ecto.Enum, values: [:mfa, :recovery, :enrollment, :demo]`. `device_summary` is `:string`. The remaining columns follow step 10. The enum values are those of `domain-values.puml`, apart from the context `:oidc_intent`, which 0006 adds together with its intent rows.
    - `idp_sid_hash` holds the keyed hash of the identity provider's `sid`. `UserToken.hash_idp_sid(sid)` computes it once from the raw `sid`: it returns `nil` for `nil` and otherwise the binary of `{:ok, mac} = Espalier.Hashed.HMAC.dump(sid)`, which is HMAC-SHA256 under `CLOAK_HMAC_SECRET`, the value that `encrypted_types_test.exs` of 0003 asserts for the HMAC type. Every later step carries the stored bytes unchanged: the sign-in ticket of 0006, the pending state of step 33, the enrollment completion of 0005, `reissue_session/2` (step 18) and the password change of step 35. `delete_sessions_by_idp_sid/2` of 0006 compares the column with `hash_idp_sid(sid)`. The field type is `:binary`, because `Cloak.Ecto.HMAC` hashes every value that `dump/1` receives and `load/1` returns the stored hash (cloak_ecto 1.3.0, `lib/cloak_ecto/types/hmac.ex`). With that type, each copy from row to row would hash the hash again, and front-channel logout would miss every session that passed a ticket, a pending state, an enrollment, a step-up or a password change.
    - Rotation-only schemas (0003 step 11): write `Espalier.Crypto.Rotation.Users` in `lib/espalier/crypto/rotation/users.ex` on the table `users` with the fields `email`, `display_name` and `org_unit`, `Espalier.Crypto.Rotation.UsersTokens` in `lib/espalier/crypto/rotation/users_tokens.ex` on `users_tokens` with `new_email`, and `Espalier.Crypto.Rotation.ExternalIdentities` in `lib/espalier/crypto/rotation/external_identities.ex` on `external_identities` with `subject`. Each schema has `@primary_key {:id, :binary_id, autogenerate: false}` and only these fields, each with its `Espalier.Encrypted.Binary` type and `redact: true`; it has no timestamps, no enum fields and no HMAC fields, so that `Rotation.validate!/1` accepts it. Add the three modules to the list that `Espalier.Crypto.Rotation.schemas/0` returns. Without them, the assertion of `rotation_test.exs` that `uncovered(SchemaRules.app_schemas(), Rotation.schemas())` returns `[]` fails as soon as the schemas of this step exist.
    - Check that `docs/architecture/domain-records.puml` shows the fields of this step: `new_email : encrypted` and `device_summary : string` on `UserToken`, `details : map` on `AuditEvent` (the association `actor` stands for `actor_id`), `provider_key : string` on `RoleGrant` and `last_used_at : datetime` on `ApiClient`. Run `make docs` and check that the diagram renders.

### Accounts context

13. E-mail handling: `Espalier.Accounts.normalize_email/1` is `email |> String.trim() |> String.downcase()`. Every write puts the normalized address into `email` and into `email_hash`, and every lookup queries `email_hash` with the normalized input, because the HMAC is case-sensitive. Replace the generated `unsafe_validate_unique(:email, ...)` with `unsafe_validate_unique(:email_hash, Repo, error_key: :email)` and keep `unique_constraint(:email, name: :users_email_hash_index)`. Keep the generated format and length checks (at most 160 characters).
14. Password policy in `Espalier.Accounts.PasswordPolicy`, called from `User.password_changeset/3` before hashing:
    - Normalization (README section 6.4, the password row of the table, and section 15, decision D12): `PasswordPolicy.prepare(password)` returns `String.normalize(password, :nfc)`. `User.password_changeset/3` applies it directly after `cast/4` with `update_change(:password, &PasswordPolicy.prepare/1)`, so the length check, the common-password and context-word checks, the breached-password check of step 15 and the Argon2id hash all receive the NFC form. `User.valid_password?/2` calls `Argon2.verify_pass(PasswordPolicy.prepare(password), hashed_password)`, which covers the sign-in of step 16 and the current-password check of step 21. Inside `lib/`, only `Espalier.Accounts.User` calls `Argon2.hash_pwd_salt/1` and `Argon2.verify_pass/2`. NIST SP 800-63B-4 section 3.1.1.2 asks verifiers that accept Unicode to apply NFC before hashing, so that a password verifies in the same way on keyboards and devices that produce different Unicode forms of the same characters. ASVS 5.0.0 6.2.8 asks for verification exactly as received, so step 42 records the row 6.2.8 as a deviation with this reason, and `docs/security/authentication.md` (step 43) names both sources. The platform stores no password hash before this rule applies, so no rehash migration exists. Directory passwords never pass through `prepare/1` and go to the LDAP server unchanged (0007 step 8).
    - Length: `validate_length(:password, min: 15, max: 128, count: :codepoints)` on the normalized value. NIST counts each code point as one character; Ecto counts graphemes by default, and `String.length/1` counts graphemes as well, so neither default is used. NFC composes a base letter and a combining mark into one code point where Unicode defines a composed character, and a few characters such as U+0344 expand to two code points, so the count of a password as received can differ from the count that the check uses.
    - Delete the commented composition rules of the generated changeset.
    - Common passwords: `priv/security/common-passwords.txt`, one lowercase entry per line in NFC, at least 3000 entries with 15 or more code points. Take them from a published list whose license allows redistribution, and record source URL, license, retrieval date and the filter command, which normalizes each entry to NFC and lowercases it, in `priv/security/README.md`. The check compares `String.downcase/1` of the normalized password with the list.
    - Context words: `priv/security/context-words.txt` (product name, words of the domain such as `espalier`, `learning`, `credential`, `qualification`, `password`, `passphrase`) plus the comma-separated `PASSWORD_CONTEXT_WORDS`, where an operator adds the organization's own words. The check rejects a password when its lowercase letters alone (digits, whitespace and punctuation removed) equal a context word, and when it contains the lowercase local part of the user's address or the display name, each when 4 or more code points long. The context words, the local part and the display name pass through `String.normalize(&1, :nfc)` before they are lowercased, so both sides of each comparison have the same Unicode form.
    - `Espalier.Application.start/2` loads both lists into `:persistent_term`.
    - Error codes on the `:password` field: `too_short`, `too_long`, `common`, `context`, `breached`.
15. Breached passwords in `Espalier.Accounts.BreachedPasswords.check/1`, used only when `PASSWORD_BREACH_CHECK=hibp`: compute `:crypto.hash(:sha, password) |> Base.encode16()` over the normalized password that the changeset holds after step 14, send the first five characters with
    ```elixir
    Req.get("https://api.pwnedpasswords.com/range/" <> prefix,
      headers: [{"add-padding", "true"}, {"user-agent", "Espalier"}],
      receive_timeout: 3_000,
      max_retries: 2
    )
    ```
    merged with `Application.get_env(:espalier, __MODULE__, [])[:req_options]`, parse the `SUFFIX:COUNT` lines, ignore entries with count 0 (padding), and return `{:ok, :breached}`, `{:ok, :unlisted}` or `{:error, :unavailable}`. On `:unavailable`, the password change proceeds with the bundled lists, and the module logs a warning with the event `breach_check_unavailable`. The password never leaves the server in any other form.
16. Password sign-in in `Accounts.authenticate_password(email, password, meta)`. `meta` carries `ip` and an optional `now` (default `DateTime.utc_now()`), which the calls of step 17 receive, so that tests can sign in after a lock has passed:
    1. Look up an active local user by `email_hash` (status `active`, `confirmed_at` set, no external identity).
    2. For an unknown address, a password longer than 128 code points after `PasswordPolicy.prepare/1`, a user without `hashed_password`, or a failure counter that is locked or disabled, call `Argon2.no_user_verify()` and return `{:error, :invalid_credentials}`.
    3. Otherwise call `User.valid_password?/2`, which verifies the normalized password of step 14 and wraps `Argon2.verify_pass/2` in `try`/`rescue ArgumentError`. `verify_pass/2` raises for strings that are not Argon2 hashes and for NIF errors such as `Threading failure`; both count as a failed verification and are logged at error level without the input.
    4. On failure, record a failure for the authenticator `:password` (step 17) and return `{:error, :invalid_credentials}`.
    5. On success, reset the counter. When the counter stood at 5 or more, enqueue the mail `failed_attempts` (step 27) and log `authn_login_successafterfail`. Return `{:ok, user}`.
    Every branch logs `authn_login_fail` or the success event through `Espalier.SecurityLog` (step 39) with factor `password` and provider `local`, and an unknown address appears in the log only as `account_hash` with the value of `Espalier.RateLimit.account_hash/1` (step 34).
17. `Espalier.Accounts.FailureCounters` implements README section 6.10 for every `AuthenticatorKind`:
    - `check(user, kind, now)` returns `:ok`, `{:locked, until}` or `:disabled`. An attempt that meets `:locked` or `:disabled` is rejected without verification and without counting.
    - `record_failure(user, kind, now)` increments atomically with `Repo.insert(%FailureCounter{...}, on_conflict: [inc: [consecutive_failures: 1]], conflict_target: [:user_id, :authenticator], returning: true)`. With `n` failures after the increment, `n >= 5` sets `locked_until` to `now + min(30 * 2^(n - 5), 3600)` seconds, and `n >= 50` sets `disabled_at`. Reaching 5 logs `authn_login_fail_max`; reaching 50 logs `authn_login_lock`.
    - `reset(user, kind)` sets the count to 0 and clears `locked_until`. `disabled_at` is cleared only by a completed recovery (0005) or by an admin through the admin user routes of 0015 (README section 8, decision D11).
    The limit of 50 stays below the NIST limit of 100. A locked password leaves passkey sign-in (0005) available, which is the documented protection against malicious lockout.
18. Sessions in `Accounts` and `UserToken`:
    - `create_session(user, attrs)` takes `auth_methods`, `strength`, `mfa_at`, `provider_key`, `idp_sid_hash` (the bytes of `UserToken.hash_idp_sid/1`, stored as given, step 12), `device_summary` and the optional `replaces` (the raw token of the session that the cookie held before this sign-in). It raises `ArgumentError` unless `UserToken.strength_valid?(strength, auth_methods, attrs)` holds. The clauses of this task are: `:mfa` with `:passkey` in the list, with `:idp_mfa` in the list, or with `:totp` together with one of `:password`, `:oidc` or `:ldap`; `:enrollment` with exactly `[:email_code]`; `:demo` with exactly `[:demo]`; `:recovery` with `:recovery_code` and `:email_code`. 0005 step 12 adds the clauses for a recovery code as second factor, for the completion of an enrollment or a recovery (attribute `completes:`), and for the enrollment sessions `[:oidc]` and `[:ldap]` of a federated user without a local factor (0006, 0007), so that every pathway of README section 6.2 and every call of 0005 to 0007 matches a clause. The function generates 32 bytes with `:crypto.strong_rand_bytes/1`, stores `:crypto.hash(:sha256, token)` in `token_hash`, sets `authenticated_at` and `last_seen_at` to now and `expires_at` to now plus `SESSION_MAX_HOURS` (enrollment and recovery sessions: now plus 30 minutes), and returns `{token, session}`.
    - Replaced session: when the attribute `replaces` names a session row, `create_session/2` deletes that row inside its `Repo.transact/1` before it counts the live sessions, whichever user the row belongs to. It logs `session_renewed` when the row belongs to the same user and `session_logout` when it belongs to another user. A sign-in in a browser that already holds a session therefore leaves no second valid token behind, and the earlier row does not count toward `SESSION_MAX_CONCURRENT`.
    - Concurrent sessions: inside the same `Repo.transact/1`, lock the user row with `lock: "FOR UPDATE"`, count the user's live session rows, and delete the oldest rows so that at most `SESSION_MAX_CONCURRENT` remain after the insert. Each deletion logs `excess_sessions_exceeded`.
    - `get_session_by_token(token, now \\ DateTime.utc_now())` hashes the token and returns `{:ok, user, session}` only for context `:session`, an active user, `expires_at > now` and `last_seen_at > now - SESSION_IDLE_MINUTES`. A row that exists but fails a timeout is deleted, logged as `session_expired` with the reason `idle` or `absolute`, and returned as `{:error, :expired}`; a missing row returns `{:error, :not_found}`. Cookie expiry is never the only check.
    - `touch_session(session, now)` updates `last_seen_at` with `Repo.update_all` only when the stored value is older than one minute.
    - `reissue_session(token, changes)` inserts a new row that copies every column of the previous row except `id`, `token_hash` and `inserted_at`, applies `changes` (for example a new `mfa_at` at step-up in 0005), deletes the previous row in the same transaction, keeps `expires_at`, and returns the new token. Columns that 0005 to 0007 add to `users_tokens` travel along without a change to this function. The copy writes the loaded values, so `idp_sid_hash` keeps its bytes (step 12). A field of the type `Espalier.Hashed.HMAC` would be hashed a second time, so the function raises `ArgumentError` when such a field (`sent_to_hash`, and any HMAC field that a later task adds) holds a value on the previous row. It logs `session_renewed`.
    - `delete_user_session_token/1` deletes one session row by token. `list_sessions(user)` returns id, `authenticated_at`, `last_seen_at`, `expires_at`, `auth_methods`, `strength` and `device_summary` of every live session of the user. `delete_session(user, session_id)` deletes one session row of that user.
    - `Espalier.Accounts.DeviceSummary.from_user_agent/1` turns a `User-Agent` value into the browser and system family (README section 6.5). It checks fixed tokens in this order: `Edg/` (Edge), `Firefox/`, `Chrome/` and `Safari/` for the browser, and `iPhone` or `iPad` (iOS), `Android`, `Windows`, `Mac OS X` (macOS) and `Linux` for the system. The order matters, because an Edge value also contains `Chrome/`, a Chrome value also contains `Safari/`, an iPhone value also contains `Mac OS X`, and an Android value also contains `Linux`. It returns `"<browser> on <system>"`, the one family that matched when only one matches, and `nil` for `nil` or when nothing matches. The full value is never stored or logged.
    - `Espalier.Accounts.PurgeExpiredTokensWorker` (queue `default`, cron from step 8) deletes every row with `expires_at <= now` and every session row with `last_seen_at <= now - SESSION_IDLE_MINUTES`, and logs the counts.
19. Invitations and sign-up, with token context `:invite`, 10 minutes validity and the link `PUBLIC_URL <> "/invite#token=" <> token`. The token sits in the URL fragment, so it reaches neither the server log nor the `Referer` header.
    - `invite_user(scope, attrs)` (`email`, optional `display_name`, optional `locale`) requires the role `admin` in the scope and returns `{:error, :forbidden}` otherwise. It returns `{:error, :user_exists}` for an address that has an account. When `display_name` is missing or blank, it takes the local part of the normalized address. `User.invite_changeset/2` therefore requires `email` only and validates `display_name` with `validate_length(:display_name, min: 1, max: 200, count: :codepoints)`. The same rule fills the display name on the paths that know only an address: `Espalier.Release.invite_user/1`, `Espalier.Accounts.Bootstrap` and the `signup` job. The function creates the user, enqueues the mail `invitation`, writes the audit event `user.invited` and logs `user_created`.
    - `resend_invitation(scope, user)` enqueues a new invitation for an active local user that has no external identity and for which `enrolled?/1` is false, and returns `{:error, :not_invitable}` otherwise.
    - `enrolled?(user)` returns `false` in this task. Task 0005 implements it as "holds a passkey or an active TOTP factor", and its `Accounts.Factors.complete_enrollment/3` deletes every `:invite` row of the user when a factor is enrolled. Invitations never go to enrolled users or to users with an external identity, so an e-mail link cannot add a factor to an account that already has one. The rule is checked at three points: when an invitation is requested, when the `MailWorker` inserts the invite row (step 27), and when the token is accepted. A job enqueued before an enrollment and run after it therefore sends nothing, and a link mailed before an enrollment fails after it.
    - `request_invitation(email)` serves `POST /api/auth/invitations`. With `SIGNUP=invite`, it sends a fresh invitation when the address belongs to an invitable user (as above). With `SIGNUP=domain`, it also enqueues the job `signup` for an unknown address whose domain is listed in `SIGNUP_DOMAINS`; the worker creates the user and sends the invitation. In every other case it enqueues the no-op job `none`. Every request thereby causes one lookup and one job insert, so that known and unknown addresses lead to the same database work and the same response. With `SIGNUP=closed` or `LOCAL_ACCOUNTS=false`, the route answers 404.
    - `accept_invitation(token)` decodes the token, hashes it and finds a row with context `:invite`, `expires_at > now`, an active user and `sent_to_hash` equal to that user's `email_hash`. It returns `{:error, :invalid_token}` when the user holds an external identity or `enrolled?/1` holds for the user. It raises, as the generator does, when the user has `confirmed_at` unset and a `hashed_password` set (pre-stuffing guard). Otherwise it sets `confirmed_at`, deletes every token row of the user (the generator's wipe on first confirmation), and returns `{:ok, user}`. Every failure returns `{:error, :invalid_token}`. The `enrolled?/1` branch takes effect once 0005 replaces the stub; the external identity branch takes effect in this task.
20. E-mail change, with token context `:change_email` and 10 minutes validity:
    - `request_email_change(user, new_email)` normalizes the address. When it belongs to no other account, it deletes the user's earlier `:change_email` rows and enqueues the mail `change_email` with the new address encrypted in the job arguments; the worker inserts the row with `sent_to_hash` and the encrypted `new_email` and sends `PUBLIC_URL <> "/account/email/confirm#token=" <> token` to the new address. `/account/email/confirm` is the route of the account UI in 0011. When the address belongs to another account, it enqueues the job `none`. It always returns `:ok`.
    - `confirm_email_change(user, token)` finds the row by `token_hash`, context `:change_email`, `user_id` of the signed-in user and `expires_at > now`, updates `email` and `email_hash` from `new_email`, deletes every `:change_email` row of the user, enqueues the mail `email_changed` to the old address, and logs `user_updated`. The generator binds this token to the old address through the context string `change:<email>`. The port binds it to the account through `user_id`, because the address is encrypted.
21. Password change: `update_user_password(user, attrs, opts)` requires `current_password` and verifies it like step 16 (a wrong value counts as a password failure) when the user has a password and `opts[:require_current]` is true (the default). 0005 calls it with `require_current: false` during enrollment. It applies the normalization and the policy of steps 14 and 15, hashes the normalized password with `Argon2.hash_pwd_salt/1` inside `User.password_changeset/3`, deletes every token row of the user in the same transaction as the generator does, enqueues the mail `password_changed`, and logs `authn_password_change` (on rejection `authn_password_change_fail`).
22. Roles and scope:
    - `Espalier.Accounts.Scope` becomes `defstruct user: nil, roles: [], session: nil, system: false`. Keep `for_user/1` (roles `[:learner]`). Add `for_session(user, session, grants)`, which always includes `:learner` in `roles`; `has_role?(scope, role)`; `admin?(scope)`; `recent_auth?(scope)`, which is true when `session.mfa_at` lies within the last 10 minutes; and `system/0`, a scope with `system: true` and the role `admin` for release functions and the boot task. `system/0` is never reachable from a request.
    - `roles_for(user)` returns `[:learner | granted roles]` without duplicates. Every signed-in user holds `learner` without a stored grant.
    - `grant_role(scope, user, role)` and `revoke_role(scope, user, role)` change `manual` grants, require the role `admin`, write the audit events `role.granted` and `role.revoked`, log `privilege_permissions_changed`, and delete every session row of the affected user in the same transaction. A role change thereby always leads to a new sign-in and a new token (README section 6.5).
    - `replace_idp_role_grants(user, provider_key, roles)` compares the set of the user's `idp_claim` roles with `roles`. When the sets are equal, it writes nothing and returns `{:ok, :unchanged}`. Otherwise, in one transaction, it deletes every `idp_claim` grant of the user, inserts the given ones with `provider_key`, writes the audit event `role.synced` through `Espalier.Audit.record(Scope.system(), "role.synced", user, %{provider_key: provider_key, added: added, removed: removed})` with role names only, logs `privilege_permissions_changed`, and deletes every session row of the user, as `grant_role/3` does. It returns `{:ok, :changed}`. `manual` grants stay. 0006 and 0007 call it at every sign-in before `log_in_user/3`, so a changed provider role ends the user's other sessions, and the sign-in that follows issues a new token (README section 6.5).
23. Administrative functions for 0015, each with the scope as first argument, each returning `{:error, :forbidden}` without the role `admin`, each writing an audit event and a security event:
    - `disable_user(scope, user)` sets `status: :disabled` and deletes every token row of the user in one transaction (`user.disabled`, `user_updated`).
    - `end_user_sessions(scope, user)` deletes every session row of the user (`sessions.ended`, `session_expired` with reason `admin`).
    - `end_all_sessions(scope)` deletes every session row (`sessions.ended_all`).
    - `create_api_client(scope, %{name: name, scopes: scopes})` accepts the scopes `["credentials:read"]`, generates 32 bytes with `:crypto.strong_rand_bytes/1`, returns `{:ok, {client, token}}` with the token as `Base.url_encode64(bytes, padding: false)` exactly once, and stores `:crypto.hash(:sha256, bytes)` in `token_hash`. `get_api_client_by_token(token)` decodes and hashes the presented token the same way. `list_api_clients(scope)` and `delete_api_client(scope, client)` complete the set (`api_client.created`, `api_client.deleted`).
24. Bootstrap admin and release functions:
    - `Espalier.Accounts.Bootstrap` runs as a `Task` child with `restart: :temporary` after Oban when `config :espalier, :bootstrap_on_boot` is true (false in `config/test.exs`). For every address in `BOOTSTRAP_ADMIN_EMAILS`, it uses `Scope.system()`. An unknown address becomes a local user with a `manual` grant `admin` and an invitation. A known local account (status `active`, no external identity, which also excludes demo users) without that grant receives it. Every other known account, a disabled one or one that holds an external identity, receives no grant: Bootstrap logs a warning that names the user id and skips it. 0006 writes the e-mail claim of an identity provider into `users.email` of a federated account, so a grant by address to such an account would be authorization through an e-mail claim, which README section 6.2, rule 3, excludes. An operator grants `admin` to a federated account with `Espalier.Release.grant_role/2`, which is an explicit operator action. With `LOCAL_ACCOUNTS=false`, unknown addresses are skipped with a warning. Bootstrap runs at every boot, so a local admin whose grant was revoked receives it again at the next boot while the address stays in `BOOTSTRAP_ADMIN_EMAILS`; `docs/security/authentication.md` states this.
    - Extend `Espalier.Release` with `grant_role(role, email)` (README section 6.11), `invite_user(email)` (invites a new address or calls `resend_invitation/2`) and `end_all_sessions()`. Each function first calls the generated `load_app/0`, as the functions of 0003 do, then sets `Application.put_env(:espalier, Oban, Keyword.merge(Application.fetch_env!(:espalier, Oban), queues: false, plugins: false))` and `Application.put_env(:espalier, :bootstrap_on_boot, false)`, and then calls `Application.ensure_all_started(:espalier)`. An `eval` node thereby inserts jobs without processing them and does not run Bootstrap. The order matters: `fetch_env!/2` can raise before the application is loaded, and loading can replace a value that was set before it. `grant_role/2` validates the role against `Ecto.Enum.values(RoleGrant, :role)` and prints `{:ok, grant}`, `{:error, :unknown_role}` or `{:error, :not_found}`.
25. Demo accounts in `Espalier.Accounts.Demo.get_or_create_user(slot)` for `slot` 1 to 20: the user has no address, the display name `Test person <slot>`, locale `en`, and an `ExternalIdentity` with `provider_key: "demo"`, `issuer: "demo"`, no `tenant_id` and `subject: "slot-<slot>"`, whose `subject_hash` holds the keyed hash of `ExternalIdentity.hash_input("demo", nil, "slot-<slot>")` (step 11).
    - The function looks up the identity by `provider_key: "demo"` and `subject_hash: ExternalIdentity.hash_input("demo", nil, "slot-<slot>")` and returns its user. The encrypted `subject` cannot be queried, so the lookup always goes through `subject_hash`.
    - Without a match, it creates the user and the identity (through `ExternalIdentity.changeset/3`) in one `Repo.transact/1`. When a concurrent request has created the identity first, the unique index on `(provider_key, subject_hash)` rejects the insert, the transaction rolls back, and the function repeats the lookup once.
    - A demo user thereby keeps its user id and its records across sign-ins and restarts, which 0012 relies on.
    - Demo users hold only `learner`; `grant_role/3` returns `{:error, :demo_user}` for them.
26. Mail notifier: adapt the copied `UserNotifier` to plain-text mails with the sender from `MAIL_FROM`: `deliver_invitation/2`, `deliver_change_email/2`, `deliver_email_changed/1` (to the old address), `deliver_password_changed/1`, `deliver_failed_attempts/2`. Links are built from `PUBLIC_URL`: `deliver_invitation/2` links to `/invite#token=<token>`, and `deliver_change_email/2` links to `/account/email/confirm#token=<token>`. Mails are in English; localized mails can follow with the UI languages.
27. `Espalier.Accounts.MailWorker` (Oban, queue `mail`, `max_attempts: 5`) handles the kinds `invitation`, `signup`, `change_email`, `email_changed`, `password_changed`, `failed_attempts` and `none`. Oban stores job arguments as plain JSON in `oban_jobs`, so the arguments carry only the kind, the user id, a count, and addresses encrypted with `Espalier.Vault.encrypt!/1` and Base64. The worker generates every e-mail token itself (`invitation`, `signup`, `change_email`), inserts its hashed row with `sent_to_hash` and sends the link, so a raw token never reaches the database or the job table. For `signup`, it creates the user first and skips the job when the address has gained an account in the meantime. For `invitation`, it loads the user and skips the job when the user is no longer active, holds an external identity or is enrolled (`enrolled?/1`), so that a job enqueued before an enrollment inserts no invite row after it. A skipped job returns `:ok` and logs nothing about the address. The kind `none` returns `:ok` without work. When `Espalier.Mailer.deliver/1` returns `{:error, reason}`, the worker logs a warning with the job id and the mail kind, without the address and without `reason` (an SMTP error can quote the recipient), and returns the error so that Oban retries the job.

### Web layer

28. Endpoint (`lib/espalier_web/endpoint.ex`): delete `@session_options`, the commented `socket "/live"` lines that refer to it, `plug Plug.Session, @session_options` and `plug Plug.MethodOverride` (the JSON API has no HTML forms). Insert `plug EspalierWeb.Plugs.TrustedProxy` and `plug EspalierWeb.Plugs.SecurityHeaders` before `Plug.Static`, so that the SPA, the static assets, `/health` and the API all receive the headers.
29. `EspalierWeb.Plugs.TrustedProxy` replaces `conn.remote_ip` with the rightmost address of `X-Forwarded-For` only when the peer address lies in `TRUSTED_PROXIES` (comma-separated addresses or CIDR ranges, parsed at boot, empty by default). It parses the entry with `:inet.parse_strict_address/1` and keeps the peer address when parsing fails. `Plug.RewriteOn` is not used for this, because it takes the leftmost entry, which a client controls behind an appending proxy.
30. `EspalierWeb.Plugs.SecurityHeaders` registers a `before_send` callback that sets these headers on every response:
    ```text
    content-security-policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'
    content-security-policy-report-only: require-trusted-types-for 'script'
    cross-origin-opener-policy: same-origin
    cross-origin-resource-policy: same-origin
    referrer-policy: strict-origin-when-cross-origin
    x-content-type-options: nosniff
    permissions-policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), publickey-credentials-create=(self), publickey-credentials-get=(self)
    vary: Sec-Fetch-Site, Sec-Fetch-Mode, Sec-Fetch-Dest
    ```
    The callback merges the `vary` values into a `vary` header that another plug has set. On `/api/session`, `/api/auth/*` and `/api/me/*` it also sets `cache-control: no-store`. HSTS comes from the reverse proxy (0017).
31. `EspalierWeb.Plugs.FetchMetadata` with the option `allow_cross_site_navigation` (a list of `path_info` patterns, `:provider` matching one segment):
    - With a `sec-fetch-site` header: `same-origin`, `same-site` and `none` pass. `cross-site` passes only for a GET with `sec-fetch-mode: navigate` on an allowlisted pattern and a `sec-fetch-dest` other than `object` and `embed`. Everything else is rejected.
    - Without the header: GET and HEAD pass. Every other method needs an `Origin` header equal to the origin of `PUBLIC_URL` (scheme, host and port, default ports omitted), and is rejected otherwise, also when `Origin` is missing.
    - A rejection answers 403 with `{"error":"cross_site_request"}`, halts and logs `malicious_csrf`.
32. Router (`lib/espalier_web/router.ex`), with salts generated by `nix-shell --run "mix phx.gen.secret 32"` (salts are no secrets; the keys derive from `SECRET_KEY_BASE`). The options of both session cookies live in `EspalierWeb.TransactionCookie` (below), and the router reads them from there:
    ```elixir
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
    ```
    Add one pipeline per role, `:facilitator`, `:author`, `:registrar`, `:analyst` and `:admin`, each with `plug :require_authenticated_user` and `plug :require_role, <role>`. The `:oidc_transaction` pipeline has no route in this task. 0006 adds the `/auth/oidc` routes to it, among them the callback and the front-channel logout, which its allowlist admits as cross-site navigations; the front-channel logout arrives in an iframe (README section 6.5). The `:auth_bare` pipeline fetches no session and serves `GET /auth/providers` (step 35).

    Sobelow's check `Config.CSRF` reports every `pipeline` block that lists `plug :fetch_session` and no plug named `:protect_from_forgery`, whatever the pipeline accepts; it compares plug names only (Sobelow 0.16.0, `lib/sobelow/config.ex`, `vuln_pipeline?/2`). The `:api` pipeline checks the token with the function plug `:protect_api_from_forgery` (step 33), and `Plug.CSRFProtection` checks no GET request, so a token check in `:oidc_transaction` would have no effect on its routes. Sobelow reports both pipelines with confidence `high`, and `mix sobelow --config --exit` fails until each carries, as shown above, the comment that states the reason, followed by the `# sobelow_skip ["Config.CSRF"]` comment as the last line above `pipeline`, as 0002 prescribes for an accepted finding. The skip takes effect because `.sobelow-conf` of 0002 sets `skip: true`. Sobelow rewrites the skip comment into a `@sobelow_skip` attribute before it parses the file and parses without comments, so the attribute binds the skip to the pipeline statement that directly follows it in the same block, and the reason comment above the skip line plays no part in the parse (`lib/sobelow/parse/source.ex` and `lib/sobelow/parse/metadata.ex`). The Sobelow result is no CSRF proof for these pipelines. The router-wide tests of step 45 provide it: every mutating `/api` route rejects a request without `x-csrf-token`, and every route in `:oidc_transaction` is a GET.

    A pipeline has one session store, so the Plug session of every `/api` route is the `__Host-espalier` cookie. It holds `user_token` after sign-in, `_csrf_token` from `Plug.CSRFProtection`, during sign-in `pending_second_factor`, and during a WebAuthn ceremony the ceremony id that 0005 stores with `put_session/3` (README section 6.5). It holds no personal data, and `encryption_salt` makes its content unreadable to the browser. Check that the row "Session cookie" of README section 6.5 names these entries.

    The transaction cookie `__Host-espalier_tx` holds the data of one OIDC flow (the nonce, the PKCE verifier, a hash of `state`, the peer IP and the user agent as stored by `oidcc_plug`, plus the provider key, the purpose and the user id) and the ticket binding until `POST /api/auth/finish` deletes the cookie (0006, README section 6.5). The intent token is consumed at the authorization request and is not stored in the cookie. Routes in the `:oidc_transaction` pipeline read and write it as their Plug session. Routes under `/api` reach it, and routes in `:oidc_transaction` reach the main session, through `EspalierWeb.TransactionCookie` in `lib/espalier_web/transaction_cookie.ex`. It is the only module that reads or writes `__Host-espalier_tx` outside `Plug.Session`:
    - `main_session_options/0` returns `[store: :cookie, key: "__Host-espalier", signing_salt: "<generated>", encryption_salt: "<generated>", same_site: "Strict", secure: true, http_only: true, path: "/"]`.
    - `session_options/0` returns `[store: :cookie, key: "__Host-espalier_tx", signing_salt: "<generated>", encryption_salt: "<generated>", same_site: "Lax", secure: true, http_only: true, path: "/", max_age: 600]`.
    - `fetch(conn)` fetches the request cookies, decodes the value of `__Host-espalier_tx` with `Plug.Session.COOKIE.get/3` and the store configuration from `Plug.Session.COOKIE.init/1` on `session_options/0`, and returns the stored map, or `%{}` when the cookie is missing, expired or fails verification.
    - `get(conn, key)` returns `Map.get(fetch(conn), key)`.
    - `put(conn, key, value)` stores `Map.put(fetch(conn), key, value)`, encodes it with `Plug.Session.COOKIE.put/4` and writes it with `Plug.Conn.put_resp_cookie/4` and the attributes `same_site`, `secure`, `http_only`, `path` and `max_age` of `session_options/0`.
    - `delete(conn, key)` removes one key and rewrites the cookie, and `clear(conn)` deletes the cookie with `Plug.Conn.delete_resp_cookie/3` and the same attributes.
    - `read_main_session(conn)` decodes the `__Host-espalier` cookie of the request in the same way with `main_session_options/0` and returns its session map, or `%{}` when the cookie is missing or fails verification. It never writes. A route in the `:oidc_transaction` pipeline uses it to find the signed-in session, for example when a same-origin navigation starts a link or a step-up flow (0006). A cross-site navigation carries no `Strict` cookie, so the function returns `%{}` there.
    The helper writes the same format as `Plug.Session` with the same options, so a value that the `:oidc_transaction` pipeline stores is readable in `/api` and the other way round. Check the callback signatures of `Plug.Session.COOKIE` in `deps/plug/lib/plug/session/cookie.ex` (Plug 1.20.3) before writing the module. A route in the `:oidc_transaction` pipeline uses `get_session/2` and `put_session/3` for the transaction cookie. It calls none of `put/3`, `delete/2` and `clear/1`, because `Plug.Session` in that pipeline writes the cookie from its own session map whenever the route changes the session, which would overwrite a value that the helper wrote.
33. Port `EspalierWeb.UserAuth` to JSON:
    - `log_in_user(conn, user, attrs)` takes the attributes of `create_session/2`, among them `auth_methods:` and `strength:` (README section 6.12). It reads `get_session(conn, :user_token)` first and passes it as `replaces` to `Accounts.create_session/2`, which deletes that row in the same transaction (step 18). It also passes `device_summary: DeviceSummary.from_user_agent(user_agent)` with the first `user-agent` request header. It then calls `renew_session/1` (`delete_csrf_token()`, `configure_session(renew: true)`, `clear_session()`, always, also for the same user), puts `:user_token`, updates `last_login_at`, and logs `session_created` and `authn_login_success` with the methods and the provider. It returns the conn; the controller renders the session payload of step 35, which carries the new CSRF token.
    - `put_pending_second_factor(conn, user, attrs)` reads `get_session(conn, :user_token)` first and, when it is present, deletes that row with `Accounts.delete_user_session_token/1` and logs `session_logout`, because the renewal drops the token from the cookie. It then renews the session and stores `pending_second_factor` as `%{"user_id", "auth_methods", "provider_key", "idp_sid_hash", "expires_at"}` with `expires_at` five minutes ahead (Unix seconds; `idp_sid_hash` as the Base64 encoding of the bytes it receives, step 12). `fetch_pending_second_factor(conn)` returns `{:ok, pending}` with the loaded user and `idp_sid_hash` decoded back to the same bytes, or `:error` for a missing or expired state, which it deletes. 0005 completes the state with `log_in_user/3`, and 0006 and 0007 create it after their first step.
    - `log_out_user(conn)` deletes the row, renews the session and logs `session_logout`.
    - `fetch_current_scope_for_user/2` reads `:user_token`, calls `get_session_by_token/2` and `touch_session/2`, loads the grants and assigns `current_scope` with `Scope.for_session/3`. On `{:error, :expired}` it drops `:user_token` from the session.
    - `require_authenticated_user/2` passes the strengths `:mfa` and `:demo`. Without a session it answers 401 `{"error":"unauthenticated"}`; for `:enrollment` and `:recovery` it answers 403 `{"error":"enrollment_required"}`.
    - `require_enrollment_session/2` passes `:enrollment`, `:recovery` and `:mfa` (used by 0005). Without a session it answers 401 `{"error":"unauthenticated"}`. For the strength `:demo` it answers 403 `{"error":"forbidden"}` and logs `authz_fail`, so a demo session never reaches an enrollment route.
    - `require_recent_auth/2` (port of `require_sudo_mode/2`) answers 403 `{"error":"reauth_required"}` unless `Scope.recent_auth?/1` holds. 0005 adds `POST /api/me/reauth`, which renews `mfa_at` through `reissue_session/2`.
    - `require_role(conn, role)` answers 403 `{"error":"forbidden"}`.
    - `protect_api_from_forgery(conn, _opts)` calls `Phoenix.Controller.protect_from_forgery(conn, [])` inside `try`, rescues `Plug.CSRFProtection.InvalidCSRFTokenError`, answers 403 `{"error":"csrf"}` (README section 6.10), halts and logs `malicious_csrf`. `Plug.CSRFProtection` reads the token from the `x-csrf-token` header.
    - Every 403 of these plugs logs `authz_fail` with the reason.
    - Remove `redirect_if_user_is_authenticated/2`, `signed_in_path/1`, `maybe_store_return_to/1`, the remember-me cookie functions, `maybe_reissue_user_session_token/3`, every `put_flash` and every `redirect`.
34. Throttling: `Espalier.RateLimit` with `use Hammer, backend: :ets, algorithm: :fix_window_per_key`, started as `{Espalier.RateLimit, clean_period: :timer.minutes(1)}`. Check in the Hammer 7.5 documentation that `:algorithm` is a `use` option; if it is a start option, pass it in the child spec. `hit(key, scale_ms, limit)` returns `{:allow, count}` or `{:deny, retry_after_ms}`. Buckets in `config/config.exs`:
    ```elixir
    config :espalier, :rate_limits, %{
      auth_ip: {:timer.minutes(1), 30},
      password_account: {:timer.minutes(15), 10},
      invitation_ip: {:timer.minutes(15), 10},
      invitation_target: {:timer.hours(1), 3},
      demo_ip: {:timer.minutes(1), 10},
      account_change: {:timer.minutes(15), 10}
    }
    ```
    - `Espalier.RateLimit` reads the scale and the limit of a bucket with `Application.fetch_env!(:espalier, :rate_limits)` at every check, so that tests can change them at runtime.
    - The ETS table is global to the node, and every `Phoenix.ConnTest` request comes from `127.0.0.1`, so test runs would share buckets. `config/test.exs` therefore sets every bucket of the map above to `{:timer.minutes(1), 1_000_000}`. Only the rate limit tests of step 45 restore a real limit, through the helper `put_rate_limit/2` of step 44, and they send their requests from addresses of `unique_ip/0`.
    - IP keys are `{bucket, ip}`, with IPv6 addresses reduced to their /64 prefix.
    - Account keys are `{bucket, :crypto.mac(:hmac, :sha256, key, normalized_identifier)}`, with `key` derived once at boot by `Plug.Crypto.KeyGenerator.generate(secret_key_base, "espalier rate limit", length: 32)` and kept in `:persistent_term`, so the limiter never holds an address.
    - `Espalier.RateLimit.account_hash(identifier)` returns the first eight lowercase hex characters of that HMAC over the normalized identifier. Security events carry it as `account_hash` for an identifier that matches no account (step 16, and the LDAP usernames of 0007).
    - `EspalierWeb.Plugs.RateLimit` (option `bucket:`) applies IP buckets in controllers with `plug ... when action in [...]`; account buckets run in the controller after parameter parsing through `Espalier.RateLimit.check_account(bucket, identifier)`.
    - A denial answers 429 with `retry-after` set to `max(div(ms + 999, 1000), 1)` and `{"error":"rate_limited"}`, and logs `excess_rate_limit_exceeded`. Known and unknown identifiers share the same buckets, so a 429 reveals nothing about an account.
    - The ETS backend counts per node. The compose files run one application node; several nodes would need a shared backend such as `hammer_backend_redis` 7.2, which requires Redis 7.0 or later.
35. Controllers and routes (all under `pipe_through :api`, except `GET /auth/providers`, which uses `pipe_through :auth_bare`):

    | Route | Controller | Request body | Extra pipelines | Behaviour |
    |---|---|---|---|---|
    | `GET /auth/providers` | `ProviderController.index` | none | | 200 `{"providers": [...]}` with the entries of `:auth_providers` (step 41) in configured order, each with `key`, `type`, `kind`, `label` and `start_url`; `[]` in this task, because 0006 and 0007 add the provider types |
    | `GET /api/session` | `SessionController.show` | none | | session payload |
    | `DELETE /api/session` | `SessionController.delete` | none | | `log_out_user/1`, 204 |
    | `POST /api/auth/password` | `Auth.PasswordController.create` | `email`, `password` | | buckets `auth_ip`, `password_account`; 200 `{"next":"second_factor"}` with the pending state, or 401 `{"error":"invalid_credentials"}`; 404 with `LOCAL_ACCOUNTS=false` |
    | `POST /api/auth/invitations` | `Auth.InvitationController.create` | `email` | | buckets `invitation_ip`, `invitation_target`; always 202 `{"status":"accepted"}`; 404 with `SIGNUP=closed` |
    | `POST /api/auth/invitations/accept` | `Auth.InvitationController.accept` | `token` | | bucket `auth_ip`; enrollment session (`auth_methods: [:email_code]`, `strength: :enrollment`), 200 session payload, or 400 `{"error":"invalid_token"}` |
    | `POST /api/auth/demo` | `Auth.DemoController.create` | `slot` (1 to 20) | | bucket `demo_ip`; `Demo.get_or_create_user/1` (step 25), then a demo session (`auth_methods: [:demo]`, `strength: :demo`) whose row carries no `provider_key`; the security events of the sign-in carry the provider `demo`; 200 session payload; 404 unless `AUTH_DEMO=true` |
    | `GET /api/me/sessions` | `Me.SessionController.index` | none | `:authenticated` | 200 `{"sessions": [...]}`, each with `id`, `current` (true on the calling one), `device` (from `device_summary`, or `null`), `strength`, `auth_methods`, `authenticated_at`, `last_seen_at` and `expires_at` |
    | `DELETE /api/me/sessions/:id` | `Me.SessionController.delete` | none | `:authenticated`, `:recent_auth` | 204 |
    | `PUT /api/me/password` | `Me.PasswordController.update` | `current_password`, `password` | `:authenticated`, `:recent_auth` | bucket `account_change`; step 21, then a new session row for the calling client that copies the loaded values of every column of the deleted row except `id`, `token_hash` and `inserted_at`, with the same copy function and the same `ArgumentError` guard as `reissue_session/2` (`auth_methods`, `strength`, `mfa_at`, `provider_key`, the bytes of `idp_sid_hash`, `device_summary`, `expires_at` and the columns that 0005 to 0007 add), puts its token into the session after `renew_session/1`, and answers 200 with the session payload, which carries the new CSRF token |
    | `PUT /api/me/email` | `Me.EmailController.update` | `email` | `:authenticated`, `:recent_auth` | bucket `account_change`; always 202 |
    | `POST /api/me/email/confirm` | `Me.EmailController.confirm` | `token` | `:authenticated`, `:recent_auth` | 200 or 400 `{"error":"invalid_token"}` |

    The session payload (`EspalierWeb.SessionJSON`) is
    ```json
    {
      "user": {"id": "...", "display_name": "...", "email": "...", "locale": "en"},
      "roles": ["learner"],
      "session": {"strength": "mfa", "auth_methods": ["password", "totp"], "provider_key": null, "recent_auth_until": "2026-10-07T10:10:00Z", "expires_at": "2026-10-08T10:00:00Z", "idle_timeout_minutes": 60},
      "pending": {"next": "second_factor", "expires_at": "2026-10-07T10:05:00Z"},
      "csrf_token": "...",
      "providers": [],
      "flags": {"demo": false, "local_accounts": true, "signup": "closed"}
    }
    ```
    with `user`, `session` and `pending` as `null` when absent, `session.provider_key` as the `provider_key` of the session row (`null` for local and demo sessions, whose rows carry none), `recent_auth_until` as `null` outside the 10-minute window, and `providers` as the entries of `Application.get_env(:espalier, :auth_providers, [])` with every key of an entry (`key`, `type`, `kind`, `label`, `start_url`). Step 41 sets that key, and 0006 and 0007 add the provider types that fill it. `flags.demo` mirrors `AUTH_DEMO`, so the SPA shows the demo banner on every page. `Espalier.Application.start/2` logs a warning at boot when `AUTH_DEMO=true`. The answers of `POST /api/auth/finish` (0006) and of the LDAP sign-in (0007) reuse this payload for a full session (README section 6.12).

    Check that the rows "Session", "Local sign-in", "Invitation and recovery", "External sign-in" and "Account" of README section 8 list the routes of this table, among them `POST /api/auth/invitations` and `PUT /api/me/password` with `current_password` and `password`.
36. Errors: `EspalierWeb.ErrorJSON` renders `{"error": code}` with `not_found`, `forbidden`, `bad_request` and `internal_error` and no internals. `EspalierWeb.FallbackController` maps `{:error, :forbidden}`, `{:error, :not_found}`, `{:error, :invalid_token}`, `{:error, :invalid_credentials}` and `{:error, %Ecto.Changeset{}}`; the last answers 422 `{"error":"validation_failed","fields":{"password":["too_short"]}}` with the error codes of step 14 and Ecto's validation names for the other fields. An unhandled exception answers 500 `{"error":"internal_error"}`, and the HTTP server is expected to log the exception at error level. Check in the documentation of the resolved Bandit release which statuses its HTTP option `log_exceptions_with_status_codes` covers by default, set it in the endpoint configuration if 500 is missing, and record the result in `docs/security/logging.md` (ASVS 16.3.4).
37. In `config/config.exs`, set `config :phoenix, :filter_parameters, ["password", "current_password", "email", "token", "code", "secret", "recovery_code"]`. Phoenix filters every parameter whose key contains one of these strings, also inside nested maps. The entries serve the categories of README section 6.10: `password` and `current_password` the password routes, `email` the addresses in `email` and `new_email`, `token` the invitation, e-mail change and recovery tokens, `code` and `recovery_code` the TOTP and recovery codes, and `secret` every parameter named after a secret. 0005 adds the keys of its TOTP fields and WebAuthn payloads, 0006 the keys of the OIDC flow and 0009 the key `answer`, each to the same list. A logging test of step 45 asserts the entries of this step.

### Logging and audit

38. `Espalier.Audit.record(scope, action, subject, details \\ %{})` inserts an `AuditEvent` with `actor_id` from the scope (nil for `Scope.system/0`), `subject_type` and `subject_id` from the subject struct and `at` set to now. `list_events(scope, filters)` requires the role `admin` (used by 0015). Audit events are append-only; the context has no update or delete function apart from the retention job of 0014.
39. `Espalier.SecurityLog.event(name, attrs, opts \\ [])` (README section 6.12) accepts only names of the OWASP Logging Vocabulary used in this plan (`authn_login_success`, `authn_login_successafterfail`, `authn_login_fail`, `authn_login_fail_max`, `authn_login_lock`, `authn_password_change`, `authn_password_change_fail`, `authn_token_created`, `authn_token_revoked`, `authz_fail`, `authz_change`, `privilege_permissions_changed`, `excess_rate_limit_exceeded`, `excess_sessions_exceeded`, `malicious_csrf`, `session_created`, `session_renewed`, `session_expired`, `session_logout`, `session_use_after_expire`, `user_created`, `user_updated`) plus the operational event `breach_check_unavailable`, and raises `ArgumentError` for any other name. `attrs` may carry `user_id`, `session_id` (the id of the session row), `ip`, `factor`, `provider`, `reason`, `count` and `account_hash`. No attribute carries a token. The function emits `:telemetry.execute([:espalier, :security, :event], %{count: 1}, Map.put(attrs, :name, name))` and writes one line through `Logger.log/3` with these keys as metadata. The level is `info` for successes and `warning` for failures and rejections; the option `level:` overrides it. 0005 to 0007 add their event names and attribute keys to the allowlists of this module.
40. `Espalier.Logger.JSONFormatter` implements the `:logger` formatter callback `format(log_event, config)`: it builds a map with `time` (ISO 8601 UTC from `meta.time`, which holds microseconds), `level`, `message` (from `{:string, chardata}`, `{:report, report}` or `{format, args}`), and the metadata keys allowlisted in `config.metadata` (`request_id`, `event`, `user_id`, `session_id`, `ip`, `factor`, `provider`, `reason`, `count`, `account_hash`), converts other values with `inspect/1`, and returns `[JSON.encode!(map), ?\n]` with Elixir's built-in `JSON` module. In `config/prod.exs`, set `config :logger, :default_handler, formatter: {Espalier.Logger.JSONFormatter, %{metadata: [...]}}`; check against `h Logger` (section on the default handler) in Elixir 1.20.4, read in `nix-shell --run "iex -S mix"`, that this key replaces the formatter. Development and test keep the text formatter.

### Configuration

41. `config/runtime.exs` (all environments) parses and validates, raising at boot on invalid values: `SESSION_IDLE_MINUTES` (default 60), `SESSION_MAX_HOURS` (default 24, a warning at boot above 24 names decision D9), `SESSION_MAX_CONCURRENT` (default 5), `LOCAL_ACCOUNTS` (default `true`), `SIGNUP` (`closed`, `invite` or `domain`; default `closed`), `SIGNUP_DOMAINS`, `PASSWORD_BREACH_CHECK` (`off` or `hibp`; default `off`), `PASSWORD_CONTEXT_WORDS`, `AUTH_DEMO` (default `false`), `BOOTSTRAP_ADMIN_EMAILS`, `TRUSTED_PROXIES`, `PUBLIC_URL` and `MAIL_FROM`. Add each with a placeholder or its default to `.env.example`, together with `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME` and `SMTP_PASSWORD` (empty), and `AUTH_PROVIDERS=` (empty).
    - Write `Espalier.Identity.Config` in `lib/espalier/identity/config.ex` and the exception `Espalier.Identity.ConfigError` (`defexception [:message]`) in `lib/espalier/identity/config_error.ex`. `parse!(env, config_env)` takes the map of `System.get_env()` and returns the external providers as a list of structs in the order of `AUTH_PROVIDERS`; every struct carries at least `key`, `type`, `kind`, `label` and `start_url`. `kind` tells the SPA whether the sign-in starts with a browser redirect or with a form (0006 uses `redirect` and 0007 `credentials`), and `start_url` is the path where the sign-in starts. An unset or blank `AUTH_PROVIDERS` returns `[]`. Otherwise the function splits the value at commas and trims each key. A key that does not match `^[a-z][a-z0-9_]{0,31}$`, or a key that appears twice, raises `ConfigError` with a message that names `AUTH_PROVIDERS`. For each key, `<KEY>` is its upper-case form, and a missing `AUTH_<KEY>_TYPE` raises `ConfigError` with the message `AUTH_<KEY>_TYPE is required`. The function dispatches on the type value; this task knows no type, so every value raises `ConfigError` with the message `AUTH_<KEY>_TYPE=<value> is not supported`. 0006 adds the types `entra`, `google` and `oidc`, and 0007 adds `ldap`. No message contains the value of a secret variable.
    - `public_entry(provider)` returns `%{key: key, type: type, kind: kind, label: label, start_url: start_url}` from the struct fields of the same names. The entry holds no client secret, bind password or other configuration value, so the session payload and `GET /auth/providers` can render it.
    - In `config/runtime.exs` (all environments), set
      ```elixir
      providers = Espalier.Identity.Config.parse!(System.get_env(), config_env())
      config :espalier, :identity_providers, providers
      config :espalier, :auth_providers, Enum.map(providers, &Espalier.Identity.Config.public_entry/1)
      ```
      `:identity_providers` holds the full structs for the sign-in code of 0006 and 0007, and `:auth_providers` holds the public entries (README section 6.12). `LOCAL_ACCOUNTS` stays a separate key, and 0017 adds the boot check for `LOCAL_ACCOUNTS=false` without any provider.

### Security documentation

42. Extend `docs/security/asvs-l2.md`, which 0003 step 18 creates in the layout below; create the file in that layout only if it is missing. The layout is a short header (ASVS 5.0.0, tag `v5.0.0_release` of the OWASP ASVS repository, Level 2 target, selected Level 3 items of README section 6.1), the status values `open`, `implemented`, `verified`, `deviation` and `not applicable`, one table per chapter with the columns `ID`, `Level`, `Requirement` (a few words), `Task`, `Status`, `Code`, `Test` and `Notes`, and a section `Deviations`. Keep every row that 0003 has written.

    The table below is the ownership table of the matrix (README section 6.1). Each entry assigns a row to one owning task, named first. The tasks after `extended by` add their code and test to the same row. The `Task` column of the matrix lists the owner first and then the extending tasks. The section "Security requirements" of every task spec lists exactly the rows that this table names for that task, as owner or as extending task. Add the missing rows with status `open`. A row stays `open` until every task it names has added its code and test, and `Notes` states what each task delivers and what remains. A row whose tasks have all done so has the status `verified`. In the rows that 0003 owns and this task extends (11.5.1 and 16.2.5), add the code and the test of this task.

    | Chapter | Rows |
    |---|---|
    | V1 | 1.2.6 (0007, LDAP injection) |
    | V3 | 3.2.1 (0004); 3.2.2 (0010, extended by 0011); 3.3.1 to 3.3.4 (0004, extended by 0017); 3.4.1 (0017); 3.4.2 (0004); 3.4.3 to 3.4.6 (0004, extended by 0017); 3.5.1 (0004, extended by 0010 and 0011); 3.5.2 and 3.5.3 (0004); 3.5.4 (0017); 3.5.5 (0010); 3.7.2 (0006, extended by 0010); Level 3: 3.4.8 (0004, extended by 0017), 3.5.8 (0004) |
    | V6 | 6.1.1 (0004, extended by 0005 and 0007); 6.1.2 (0004); 6.1.3 (0004, extended by 0005, 0006 and 0007); 6.2.1 (0004); 6.2.2 and 6.2.3 (0004, extended by 0011); 6.2.4 and 6.2.5 (0004); 6.2.8 (0004, deviation: NFC normalization, README section 15, decision D12); 6.2.6 and 6.2.7 (0011); 6.2.9 (0004, extended by 0011); 6.2.10 to 6.2.12 (0004); 6.3.1 (0004, extended by 0005 and 0007); 6.3.2 (0004); 6.3.3 (0005, extended by 0006, 0007 and 0011); 6.3.4 (0004, extended by 0005 and 0006); 6.4.1 (0004, extended by 0015); 6.4.2 (0004); 6.4.3 and 6.4.4 (0005); 6.5.1 to 6.5.4 (0005); 6.5.5 (0004, extended by 0005); 6.6.2 and 6.6.3 (0005); 6.8.1, 6.8.2 and 6.8.4 (0006, extended by 0007); Level 3: 6.3.5 (0004, extended by 0005), 6.3.7 (0004, extended by 0005 and 0007), 6.3.8 (0004, extended by 0005, 0007 and 0011), 6.5.6 (0005, extended by 0011) |
    | V7 | 7.1.1 and 7.1.2 (0004); 7.1.3 (0006); 7.2.1 to 7.2.3 (0004); 7.2.4 (0004, extended by 0005 and 0006); 7.3.1 and 7.3.2 (0004); 7.4.1 (0004); 7.4.2 (0004, extended by 0015); 7.4.3 (0004, extended by 0005 and 0011); 7.4.4 (0010, extended by 0011); 7.4.5 (0004, extended by 0015); 7.5.1 (0004, extended by 0005, 0006, 0011 and 0015); 7.5.2 (0004, extended by 0011); 7.6.1 (0006, extended by 0011); 7.6.2 (0004, extended by 0006 and 0011) |
    | V8 | 8.1.1 (0004); 8.1.2 (0009); 8.2.1 (0004, extended by 0013, 0014 and 0015); 8.2.2 (0009, extended by 0013); 8.2.3 (0009); 8.3.1 (0004, extended by 0013 and 0015); 8.4.1 not applicable (one organization per instance, README section 1) |
    | V9 | 9.1.1 to 9.1.3 and 9.2.1 to 9.2.3 (0006, ID tokens) |
    | V10 | 10.1.1, 10.1.2, 10.2.1, 10.2.2 and 10.5.1 to 10.5.4 (0006); 10.5.5 (0006, not applicable: no back-channel logout, README section 6.7); sections 10.3, 10.4, 10.6 and 10.7 not applicable (no resource server for external tokens, no authorization server) |
    | V11 | 11.1.1 and 11.1.2 (0003, extended by 0017); 11.2.1 to 11.2.3, 11.3.2, 11.3.3 and 11.4.1 (0003); 11.4.2 (0004); 11.5.1 (0003, extended by 0004 and 0005) |
    | V12 | 12.1.1 (0017, extended by 0007); 12.3.1 (0004 for SMTP, extended by 0007 for LDAP and 0017 for the database); 12.3.2 (0006, extended by 0007); 12.3.4 (0007) |
    | V13 | 13.2.1 and 13.2.2 (0007); 13.2.4 and 13.2.5 (0006); 13.3.1 (0003, extended by 0006, 0007, 0013 and 0017); 13.3.2 (0003); 13.4.1, 13.4.2, 13.4.4 and 13.4.5 (0017) |
    | V14 | 14.1.1, 14.1.2 and 14.2.4 (0003); 14.2.1 and 14.3.1 (0011); 14.3.3 (0011, extended by 0012 and 0014) |
    | V15 | 15.1.1, 15.1.2 and 15.2.1 (0017) |
    | V16 | 16.1.1 (0004); 16.2.1 to 16.2.4 (0004); 16.2.5 (0003, extended by 0004, 0005, 0006, 0007 and 0013); 16.3.1 (0004, extended by 0005, 0006 and 0007); 16.3.2 (0004, extended by 0013 and 0015); 16.3.3 (0004, extended by 0005); 16.3.4 (0004, extended by 0007); 16.4.1 (0004); 16.4.2 and 16.4.3 (0017); 16.5.1 (0004, extended by 0005 and 0007); 16.5.2 (0006, extended by 0007); 16.5.3 (0003, extended by 0006 and 0007) |

    The row 6.2.8 takes the status `deviation` once the code of step 14 and the normalization tests of step 45 exist. Its `Code` column names `Espalier.Accounts.PasswordPolicy.prepare/1` and `Espalier.Accounts.User`, its `Test` column names `test/espalier/accounts/password_policy_test.exs`, and its `Notes` point to the section `Deviations`. The entry there states the rule: every password is normalized to Unicode NFC with `String.normalize(password, :nfc)` before the length check, the blocklist checks, the breached-password check, the Argon2id hash and the verification. It states the reason: NIST SP 800-63B-4 section 3.1.1.2 asks verifiers that accept Unicode to apply NFC before hashing, so that verification stays consistent across keyboards and devices that produce different Unicode forms of the same characters. ASVS 6.2.8 asks for verification exactly as received, and README section 15, decision D12, follows NIST. The entry also states that directory passwords go to the LDAP server unchanged (0007 step 8).

    Then open the chapter files V1 to V16 at tag `v5.0.0_release` of the OWASP ASVS repository, from `5.0/en/0x10-V1-Encoding-and-Sanitization.md` through `5.0/en/0x24-V15-Secure-Coding-and-Architecture.md` and `5.0/en/0x25-V16-Security-Logging-and-Error-Handling.md`, and add every Level 1 and Level 2 requirement that the lists above lack, with the owning task or `not applicable` and a reason. The chapters without an entry above (V2, V4 and V5) are part of this scan. Chapter V17 (`0x26-V17-WebRTC.md`) is `not applicable`, because the platform uses no WebRTC; the matrix records it in one line with that reason. Fill the rows this task implements with code and test.
43. Create `docs/security/authentication.md` with: the pathways of this task with their strength and a pointer to README section 6.2 (6.1.3); session settings, the fields of the session row with the device summary of step 18, the concurrent session limit and what happens at the limit, the termination rules (7.1.1, 7.1.2); the bucket table of step 34, the failure counter rules of step 17 and the protection against malicious lockout (6.1.1); the password policy, the NFC normalization of step 14 with NIST SP 800-63B-4 section 3.1.1.2 as its source and the deviation from ASVS 6.2.8, the rule that directory passwords go to the LDAP server unchanged, the list sources and the context-word list (6.1.2); the enumeration measures; the notifications; the bootstrap admin rules of step 24, including the regrant at boot and `Espalier.Release.grant_role/2` for federated admins; and the Argon2 parameters with the measurements of step 46. Create `docs/security/logging.md` with the log inventory (16.1.1): destination (standard output as JSON lines in production, and no other destination, 16.2.3), each event name with its fields, the logged failures of 16.3.4 (unhandled exceptions, failed mail deliveries, `breach_check_unavailable`), what is never logged, the `audit_events` table, and the note that log retention is the operator's decision.
    - Complete the rows of this task in `docs/security/crypto-inventory.md` (0003 step 16). Set the status to `done` and name the module in each row. The encrypted rows `users.email`, `users.display_name` and `users.org_unit` name `Espalier.Accounts.User` and the rotation through `Espalier.Crypto.Rotation.Users`, `users_tokens.new_email` names `Espalier.Accounts.UserToken` and the rotation through `Espalier.Crypto.Rotation.UsersTokens`, and `external_identities.subject` names `Espalier.Accounts.ExternalIdentity` and the rotation through `Espalier.Crypto.Rotation.ExternalIdentities`. The keyed-hash rows `users.email_hash` (`Espalier.Accounts.User`), `users_tokens.sent_to_hash` (`Espalier.Accounts.UserToken`) and `external_identities.subject_hash` (`Espalier.Accounts.ExternalIdentity`) use `Espalier.Hashed.HMAC`, which the first version does not rotate (README section 6.9). The row `external_identities.subject_hash` names the input `ExternalIdentity.hash_input/3` of step 11 and the writers 0004 (demo identities, step 25), 0006 and 0007. The row `users_tokens.idp_sid_hash` names `Espalier.Accounts.UserToken`, the plain `:binary` field and `UserToken.hash_idp_sid/1` (HMAC-SHA256 under `CLOAK_HMAC_SECRET`, computed once and carried unchanged, step 12). The rows `users.hashed_password` (`Espalier.Accounts.User` with `argon2_elixir`, with the parameters of step 46), `users_tokens.token_hash` (`Espalier.Accounts.UserToken`) and `api_clients.token_hash` (`Espalier.Accounts.ApiClient`) complete the list, together with `oban_jobs.args` in the section "Values encrypted outside Ecto types" (`Espalier.Accounts.MailWorker` and `request_email_change/2`). Add a row for any further encrypted or hashed field of this task that the inventory lacks, because `inventory_test.exs` of 0003 fails on a missing `table.column`.

### Tests and checks

44. ConnCase and fixtures: `user_fixture/1` creates an active, confirmed local user; `register_and_log_in_user/1` and `log_in_user(conn, user, attrs \\ %{})` create a session row with `strength: :mfa`, `auth_methods: [:password, :totp]` and `mfa_at` now (overridable) and put `user_token` into a test session; `api_conn/0` sets `sec-fetch-site: same-origin` and `origin` to the `PUBLIC_URL` of the test config; `with_csrf_token(conn)` performs `GET /api/session`, recycles the conn and sets `x-csrf-token` from the response. `override_session(token, attrs)` replaces the generated `override_token_authenticated_at/2` and sets `mfa_at`, `last_seen_at` or `expires_at` for timeout tests. `unique_ip/0` returns an address `{10, a, b, c}` derived from `System.unique_integer([:positive])`, which a test sets with `%{conn | remote_ip: unique_ip()}`. `put_rate_limit(bucket, {scale_ms, limit})` sets one bucket of `:rate_limits` with `Application.put_env/3` and restores the previous map in `on_exit/1`; a test module that calls it sets `async: false`.
45. Write at least these ExUnit tests:
    - Session tests assert that the stored `token_hash` equals `:crypto.hash(:sha256, token)` and differs from the token, that a session expires after 60 idle minutes and after 24 hours (with an explicit `now`), that an expired row is deleted and logged, that a reissue deletes the previous row and keeps `expires_at`, that the sixth session deletes the oldest, that the purge worker removes expired rows and keeps live ones, and that two demo sign-ins in one conn leave the first token without a row (`get_session_by_token/2` returns `{:error, :not_found}`). A unit test feeds `DeviceSummary.from_user_agent/1` an Edge value on Windows, a Chrome value on Android, a Safari value on an iPhone, a Firefox value on Linux, a Chrome value on macOS, `nil` and an unknown value. A controller test signs in with a `user-agent` header and asserts that `GET /api/me/sessions` shows its summary as `device`, and that a reissue keeps `device_summary`. A table-driven test covers each clause of step 18: `create_session/2` accepts `[:password, :totp]`, `[:oidc, :totp]`, `[:ldap, :totp]`, `[:passkey]` and `[:oidc, :idp_mfa]` with `:mfa`, `[:email_code]` with `:enrollment`, `[:demo]` with `:demo` and `[:recovery_code, :email_code]` with `:recovery`, and it raises for `[:password]` and `[:email_code]` with `:mfa`, for `[:password]` with `:enrollment` and for `[:password]` with `:demo`. 0005 adds the rows of its clauses to the same table.
    - `idp_sid_hash` tests assert that `UserToken.hash_idp_sid("sid-1")` equals `:crypto.mac(:hmac, :sha256, secret, "sid-1")` with the HMAC secret of the test config and `nil` for `nil`. A session created with `idp_sid_hash: UserToken.hash_idp_sid("sid-1")` and `provider_key: "x"` keeps the same bytes after `reissue_session/2`, after `PUT /api/me/password` and after a round trip through `put_pending_second_factor/3`, `fetch_pending_second_factor/1` and `log_in_user/3`; after each of these steps, a query on `provider_key: "x"` and `idp_sid_hash: UserToken.hash_idp_sid("sid-1")` finds exactly the new row. `reissue_session/2` raises `ArgumentError` on a row whose `sent_to_hash` holds a value.
    - Sign-in tests assert that a correct password answers 200 `{"next":"second_factor"}` and sets the pending state, after which `GET /api/session` shows `pending` and `user: null`. They assert that the pending state expires after five minutes, that a password sign-in in a conn that holds a session deletes that session row, and that a wrong password, an unknown address, an ASCII password of 129 code points, a locked counter and a stored value that is no Argon2 hash all answer the identical 401 body. Each sign-in test uses an address from `user_fixture/1` or a fresh unknown address, so the high test limits of step 34 keep every bucket open.
    - Password normalization tests in `test/espalier/accounts/password_policy_test.exs` use `nfc = "Crème brûlée au café du matin"` (29 code points) and `nfd = String.normalize(nfc, :nfd)` (33 code points) and first assert `nfc != nfd`. They assert that `PasswordPolicy.prepare(nfd)` equals `nfc`. For a user whose password was set to `nfd` with `Accounts.update_user_password(user, %{password: nfd}, require_current: false)`, `Argon2.verify_pass(nfc, user.hashed_password)` returns true, which shows that the stored hash covers the NFC form, and `User.valid_password?/2` returns true for both spellings. For a user whose password was set to `nfc`, `Accounts.authenticate_password/3` returns `{:ok, user}` for `nfd`. Length tests with combining characters write their inputs with explicit escapes, so that no editor can normalize them, and first assert the code points as received with `length(String.codepoints(v))`. They then assert that `"Lernpfad Cafe\u0301!"` (15 code points as received, 14 after NFC) fails with `too_short`, that `"Lernpfad Cafe\u0301!!"` (16 and 15) is accepted, and that `String.duplicate("x", 127) <> "e\u0301"` (129 and 128) is accepted and signs in. A password that contains the display name `Chloë` in its NFD spelling fails with `context` for a user whose display name is stored in NFC. With the `Req.Test` stub of the change tests and the breach check set to `hibp`, the range request for `nfd` carries the first five characters of `:crypto.hash(:sha, nfc) |> Base.encode16()`.
    - Failure counter tests call `FailureCounters.record_failure/3` and `check/3` with an explicit `now`, because over HTTP a locked counter rejects attempts without counting them. They assert that the fifth failure locks for 30 seconds, the sixth (recorded after the first lock has passed) for 60, the tenth for 960 and the twelfth for 3600 (the cap), and that the fiftieth disables the authenticator. Context tests call `Accounts.authenticate_password/3` with `now` in `meta`: a success after five failures, 31 seconds after the fifth, resets the counter and enqueues `failed_attempts`, and an attempt during a lock leaves the count unchanged.
    - Invitation tests assert that a token works once and only within 10 minutes, that a token fails after the address changed, and that acceptance creates an `enrollment` session, which receives 403 `enrollment_required` on `GET /api/me/sessions`. They assert that `accept_invitation/1` returns `{:error, :invalid_token}` for a user who received an `ExternalIdentity` after the invitation was sent, and that an `invitation` job run with `perform_job/3` for such a user inserts no `:invite` row and sends no mail; 0005 adds the same two cases for an enrolled user. For a known invitable address, an unknown address and (with `SIGNUP=domain`) an address of a listed domain, `POST /api/auth/invitations` answers the same 202 body and enqueues exactly one job; with `SIGNUP=closed` it answers 404. No job argument contains a plain address or a token. `Espalier.Release.invite_user("ada@example.org")` creates a user with the display name `ada`.
    - Change tests assert that e-mail and password change answer 403 `reauth_required` when `mfa_at` is older than 10 minutes. An e-mail change mails the new address with a link that contains `/account/email/confirm#token=`, and the confirmation updates `email_hash` and mails the old address. A password change needs the current password; it rejects a common password, a context word and, with a `Req.Test` stub, a breached password; it falls back to the lists and logs `breach_check_unavailable` when the stub returns a transport error; it deletes the other sessions, keeps the calling client signed in with the `device_summary` of its previous row, and answers with a new CSRF token. A request body without `password` answers 422 `validation_failed`.
    - Plug tests run `fetch_current_scope_for_user/2` and then `require_enrollment_session/2` on test conns, because the `:enrollment` pipeline has no route in this task. With sessions from `log_in_user/3` of step 44 (strength and methods overridden per case), they assert that the plug passes `:enrollment` (`[:email_code]`), `:recovery` (`[:recovery_code, :email_code]`) and `:mfa`. A conn without `user_token` answers 401 `{"error":"unauthenticated"}` and halts. A `:demo` session (`[:demo]`) answers 403 `{"error":"forbidden"}`, halts and emits the telemetry event `authz_fail`.
    - Role tests assert that `replace_idp_role_grants/3` keeps `manual` grants, that a changed set writes the audit event `role.synced` and deletes the user's session rows, that an unchanged set returns `{:ok, :unchanged}` and leaves the session rows, that `grant_role/3` writes an audit event and ends the user's sessions, that role pipelines answer 403 `forbidden`, and that `Espalier.Release.grant_role("admin", email)` grants the role and returns `{:error, :unknown_role}` for `"owner"`.
    - Bootstrap tests run `Espalier.Accounts.Bootstrap` with a configured address list and assert that an unknown address becomes a local user with the `admin` grant and one `invitation` job, that a matching local user receives the grant, and that a matching user with an `ExternalIdentity` receives no grant while a warning is logged.
    - `test/espalier/identity/config_test.exs` asserts that `Espalier.Identity.Config.parse!/2` returns `[]` for a map without `AUTH_PROVIDERS` and raises `Espalier.Identity.ConfigError` for `AUTH_PROVIDERS=Bad`, for a repeated key, for a key without `AUTH_<KEY>_TYPE` and for an unknown type, each with a message that names the variable. It asserts that `public_entry/1` on a test struct with the five public fields and a field `client_secret` returns a map with exactly `key`, `type`, `kind`, `label` and `start_url`. A controller test asserts that `GET /auth/providers` answers 200 `{"providers":[]}`, and, with one public entry put into `:auth_providers` through `Application.put_env/3`, that the answer and `providers` of `GET /api/session` list that entry with its five keys.
    - `test/espalier_web/transaction_cookie_test.exs` asserts that a value written with `TransactionCookie.put/3` reads back with `get/2` and `fetch/1` in the next request, that a value written through `Plug.Session` with `session_options/0`, as the `:oidc_transaction` pipeline writes it, reads back through `fetch/1`, that `delete/2` removes one key, that `clear/1` deletes the cookie, and that the `set-cookie` header names `__Host-espalier_tx` with `path=/`, `secure`, `HttpOnly`, `SameSite=Lax` and `max-age=600` and without `domain`. It asserts that `read_main_session/1` returns the `user_token` that a demo sign-in through the `:api` pipeline wrote into `__Host-espalier`, and `%{}` for a request without that cookie.
    - Demo tests assert that with `AUTH_DEMO=true`, `POST /api/auth/demo {"slot": 1}` followed by `GET /api/session` shows `Test person 1`, roles `["learner"]`, strength `demo` and `session.provider_key` `null`, and that the route answers 404 with `AUTH_DEMO=false`. They assert that two calls of `Demo.get_or_create_user(1)` return the same user id and leave one demo identity for slot 1, that `Repo.get_by(ExternalIdentity, provider_key: "demo", subject_hash: ExternalIdentity.hash_input("demo", nil, "slot-1"))` finds that identity, and that the session row of a demo sign-in has `provider_key` `nil`.
    - `ExternalIdentity` tests assert that `hash_input("demo", nil, "slot-1")` returns `"demo" <> <<0, 0>> <> "slot-1"`, that the same subject at two issuers yields two `subject_hash` values, and that the changeset fills `subject_hash` from `issuer`, `tenant_id` and `subject` and ignores a `subject_hash` in the attributes.
    - `test/espalier_web/csrf_coverage_test.exs` takes every route of `Phoenix.Router.routes(EspalierWeb.Router)` with the verb POST, PUT, PATCH or DELETE, replaces path parameters by a UUID, and asserts that a request through `api_conn/0` with a session and without `x-csrf-token` answers 403 `{"error":"csrf"}`. Its exemption list is empty, and any entry would need a row in the ASVS matrix. A second test asserts with `Phoenix.Router.route_info/4` that the `pipe_through` of every `/api` route contains `:api`. A third test asserts that every route whose `pipe_through` contains `:oidc_transaction` uses the verb GET, which backs the reason of the Sobelow skip of step 32. The pipeline has no route in this task, so the test guards the routes that 0006 adds.
    - Fetch Metadata tests assert that `cross-site` on `POST /api/auth/password` answers 403, that a POST without the header and with a foreign or missing `Origin` answers 403, that a POST without the header and with the right `Origin` reaches the CSRF check, and (as unit tests on the plug with the `:oidc_transaction` options) that a cross-site navigation GET to `/auth/oidc/x/callback` passes, that a cross-site navigation GET with `sec-fetch-dest: iframe` to `/auth/oidc/x/front-channel-logout` passes, and that the same request with `sec-fetch-dest: embed` answers 403.
    - Header tests assert that `/health`, `/api/session` and `/` carry every header of step 30 with the exact values, that `/api/session` carries `cache-control: no-store`, and that no response carries `access-control-allow-origin`.
    - A cookie test asserts that the `set-cookie` header of a demo sign-in names `__Host-espalier` with `path=/`, `secure`, `HttpOnly` and `SameSite=Strict` and without `domain`.
    - Rate limit tests (`async: false`) set the real limit of the bucket under test with `put_rate_limit/2` and send their requests from addresses of `unique_ip/0`. They assert that the 31st `POST /api/auth/password` from one IP within a minute answers 429 with `retry-after`, that the eleventh attempt for one fixture address from eleven different IPs answers 429, and that `TrustedProxy` takes the rightmost `X-Forwarded-For` entry from a trusted peer and ignores the header from any other peer and when it is malformed.
    - Logging tests assert that a failed sign-in emits the telemetry event `authn_login_fail` with factor `password`, that neither the telemetry metadata nor the captured log contains the password or the address, that the formatter turns a synthetic log event with a newline in its message into one JSON line with a UTC `time`, that `SecurityLog.event(:made_up, %{})` raises, that `SecurityLog.event/3` with `level: :error` logs at that level, and that `Application.get_env(:phoenix, :filter_parameters)` contains every entry of step 37. A further test configures `Espalier.Mailer` with `Espalier.Test.FailingMailAdapter` (in `test/support/`, a `Swoosh.Adapter` whose `deliver/2` returns `{:error, :test}`), runs an `invitation` job with `perform_job/3`, and asserts that the job returns an error and that the captured log holds a warning with the job id and without the address.
    - A scope check runs `nix-shell --run "mix phx.gen.context Sandbox Thing things name:string"` in a scratch branch, confirms the `user_id` scoping in the generated code, and discards the branch.
    Exclude the tags `:timing` and `:mail` in `test/test_helper.exs` with the line `ExUnit.configure(exclude: [:timing, :mail])` before the generated `ExUnit.start()`. 0007 adds `:ldap` to the `exclude:` list of this `ExUnit.configure/1` call. `mix test --only mail` still runs the tagged tests, because `mix test` merges these excludes with its own options and `--only` includes the tag (Elixir 1.20, `Mix.Tasks.Test`).
46. Timing and mail checks:
    - `test/espalier_web/enumeration_timing_test.exs` (tag `:timing`, `async: false`) sets `t_cost: 2, m_cost: 16` for its duration, creates 20 local users with passwords, and sends 40 sign-in requests, alternating between a wrong password for one of the 20 known addresses and one of 20 distinct unknown addresses, so that no address is used twice and no failure counter reaches 5. It runs with the high test limits of step 34, so no request meets a 429, and it asserts that every response is the 401 of step 35 and that the medians of the two groups differ by less than 25 percent.
    - `test/espalier/accounts/mail_integration_test.exs` (tag `:mail`) delivers an invitation through `Espalier.Mailer.deliver(email, adapter: Swoosh.Adapters.SMTP, relay: "localhost", port: 1025, tls: :never, auth: :never, ssl: false)` and finds it through `GET http://localhost:8025/api/v1/search?query=to:<address>` with Req. Add the target `test-integration: ## Run the LDAP and mail tests against the dev services` with the command `$(NIX) "DATABASE_PORT=$(DATABASE_PORT) mix test --only ldap --only mail"` (README section 12, 0001 step 18). 0007 runs its directory tests through the same target.
    - Argon2 on the production image: write `scripts/argon2_bench.exs`, which reads `ARGON2_T_COST` and `ARGON2_M_COST` (defaults 2 and 16), prints `Argon2.Stats.report(t_cost: t, m_cost: m, parallelism: 1)`, then verifies one hash 200 times through `Task.async_stream/3` with `max_concurrency: System.schedulers_online() * 4`, rescues `ArgumentError`, prints the error count, the median and the 95th percentile, and exits 1 on any error. Add
      ```make
      argon2-bench: ## Benchmark Argon2 parameters inside the production image
      	docker run --rm --env-file .env -v "$(PWD)/scripts:/scripts:ro" $(IMAGE):$(TAG) /app/bin/espalier eval 'Code.eval_file("/scripts/argon2_bench.exs")'
      ```
      Read the moduledoc of `Argon2.Stats` first (`nix-shell --run "iex -S mix"`, then `h Argon2.Stats`) and take the time target it documents. For argon2_elixir 4.1.3 the moduledoc names 500 milliseconds and attributes the value to the Argon2 draft guidelines. Keep `t_cost: 2, m_cost: 16` when one hash takes at most that target; otherwise lower `m_cost` to 15. The OWASP Password Storage Cheat Sheet minimum for Argon2id (19 MiB, `t=2`, `p=1`) is the floor, and `m_cost: 15` (32 MiB) with `t_cost: 2` stays above it. Concurrent hashes run on the dirty CPU schedulers, so memory peaks at about their number times 2^`m_cost` KiB; state that figure for the container memory limit in `docs/security/authentication.md`.

## Deliverables
- The `Makefile` has the targets `auth-reference`, `argon2-bench` and `test-integration`, `compose.dev.yaml` runs Mailpit, and `mix.exs`, `config/*.exs` and `.env.example` carry the changes of steps 6 to 9, 37 and 41.
- Migrations exist for the users and token tables, `role_grants`, `external_identities`, `failure_counters`, `api_clients`, `audit_events` and Oban.
- The context code lives in `lib/espalier/accounts.ex`, `lib/espalier/accounts/{user,user_token,scope,user_notifier,role_grant,external_identity,failure_counter,failure_counters,api_client,password_policy,breached_passwords,device_summary,demo,bootstrap,mail_worker,purge_expired_tokens_worker}.ex`, `lib/espalier/audit.ex`, `lib/espalier/audit/audit_event.ex`, `lib/espalier/rate_limit.ex`, `lib/espalier/security_log.ex`, `lib/espalier/logger/json_formatter.ex` and `lib/espalier/identity/{config,config_error}.ex`, and `lib/espalier/release.ex` has the functions of step 24.
- The rotation-only schemas live in `lib/espalier/crypto/rotation/{users,users_tokens,external_identities}.ex`, and `Espalier.Crypto.Rotation.schemas/0` lists them.
- The web code lives in `lib/espalier_web/user_auth.ex`, `lib/espalier_web/transaction_cookie.ex` (with `main_session_options/0`, `session_options/0`, `fetch/1`, `get/2`, `put/3`, `delete/2`, `clear/1` and `read_main_session/1`), `lib/espalier_web/plugs/{trusted_proxy,security_headers,fetch_metadata,rate_limit}.ex`, the controllers and JSON views of step 35, `FallbackController` and `ErrorJSON`, together with the router and endpoint changes.
- `priv/security/` holds `common-passwords.txt`, `context-words.txt` and `README.md`, and `scripts/argon2_bench.exs` exists.
- `docs/security/` holds the extended `asvs-l2.md` with the ownership table of step 42, `authentication.md`, `logging.md` and the completed rows of this task in `crypto-inventory.md`.
- The tests and fixtures of steps 44 to 46 exist, together with `test/support/failing_mail_adapter.ex`.

## Acceptance
- [ ] `make auth-reference` exits 0, `tmp/auth-reference/espalier/lib/espalier_web/user_auth.ex` exists, and `git status --porcelain tmp` prints nothing.
- [ ] `grep -L "Derived from phx.gen.auth (Phoenix 1.8.15)." lib/espalier/accounts.ex lib/espalier/accounts/user.ex lib/espalier/accounts/user_token.ex lib/espalier/accounts/scope.ex lib/espalier/accounts/user_notifier.ex lib/espalier_web/user_auth.ex` prints nothing.
- [ ] `nix-shell --run "mix test"` passes with the cases of step 45.
- [ ] `nix-shell --run "mix test test/espalier/crypto"` passes, including the `uncovered/2` assertion of `rotation_test.exs` and `inventory_test.exs` from 0003.
- [ ] `nix-shell --run "mix run --no-start -e 'IO.inspect(Espalier.Crypto.Rotation.schemas())'"` lists `Espalier.Crypto.Rotation.Users`, `Espalier.Crypto.Rotation.UsersTokens` and `Espalier.Crypto.Rotation.ExternalIdentities`.
- [ ] In `docs/security/crypto-inventory.md`, every row with the task `0004` has the status `done` and names its module.
- [ ] `nix-shell --run "mix sobelow --config --exit"` exits 0. Deleting the `# sobelow_skip ["Config.CSRF"]` line above `pipeline :api` temporarily makes it exit non-zero with a `Config.CSRF` finding for the pipeline `api`; restoring the line makes it exit 0.
- [ ] Moving `post "/auth/demo"` temporarily into a scope without `:api` makes `nix-shell --run "mix test test/espalier_web/csrf_coverage_test.exs"` fail; moving it back makes it pass.
- [ ] With `make run`, `curl -si http://localhost:4000/api/session -H 'sec-fetch-site: same-origin'` shows the headers of step 30 and a `set-cookie` for `__Host-espalier` with `secure`, `HttpOnly` and `SameSite=Strict` and without `domain`.
- [ ] With `make run`, `curl -si -X POST http://localhost:4000/api/auth/password -H 'sec-fetch-site: cross-site' -H 'content-type: application/json' -d '{}'` answers 403 with `{"error":"cross_site_request"}`.
- [ ] With `make run`, `curl -s http://localhost:4000/auth/providers -H 'sec-fetch-site: same-origin'` prints `{"providers":[]}`.
- [ ] With `make services-up` and `make run`, `Espalier.Release.invite_user("ada@example.org")` in the `iex` session leads to one message for `ada@example.org` in Mailpit at `http://localhost:8025`, and its link contains `/invite#token=`.
- [ ] After `make services-up`, `docker compose -f compose.dev.yaml port mailpit 8025` prints `127.0.0.1:8025`.
- [ ] With Mailpit running, `make test-integration` passes the `:mail` test.
- [ ] `nix-shell --run "mix test --only timing"` passes.
- [ ] After `make docker-build`, `make argon2-bench` reports zero errors, and the chosen parameters and timings appear in `docs/security/authentication.md`.
- [ ] With `make docker-up`, `docker compose logs --no-log-prefix app | head -n 5 | jq -e .time` exits 0.
- [ ] With `make docker-up`, `docker compose exec app bin/espalier eval 'Espalier.Release.grant_role("admin", "nobody@example.org")'` exits 0 and prints `{:error, :not_found}`, and the app container keeps serving `/health`.
- [ ] `grep -rlF "Oban.Migration.up" priv/repo/migrations` lists exactly one file (with the module name of step 8 when the resolved guide names another one).
- [ ] The rows of `docs/security/asvs-l2.md` for the listed requirements name the code and the test, and every row of the ownership table of step 42 exists with its owning task first in `Task`.
- [ ] The row 6.2.8 of `docs/security/asvs-l2.md` has the status `deviation`, and the section `Deviations` holds its entry with the NFC rule and NIST SP 800-63B-4 section 3.1.1.2 as the reason.
- [ ] `nix-shell --run "mix test test/espalier/accounts/password_policy_test.exs"` passes, and `grep -rlE 'Argon2\.(hash_pwd_salt|verify_pass)' lib` prints only `lib/espalier/accounts/user.ex`.
- [ ] `docs/architecture/domain-records.puml` shows `new_email : encrypted` and `device_summary : string` on `UserToken`, `details : map` on `AuditEvent`, `provider_key : string` on `RoleGrant` and `last_used_at : datetime` on `ApiClient`, and `make docs` renders it.
- [ ] README section 6.5 (row "Session cookie") names the session token, the CSRF token, the pending second-factor state and the WebAuthn ceremony id, and README section 8 lists every route of step 35.
- [ ] `make check` passes.

## Addendum: implementation
The implementation departs from the steps above in the points below, and later
tasks rely on the implemented form. Task 0004a carries these points into the
specs that cite them.

- Mail in production (steps 9 and 41): SMTP is optional. Without `SMTP_HOST`,
  `config/runtime.exs` sets `Espalier.Mailer.DisabledAdapter`, which refuses
  every delivery with `{:error, :mail_disabled}`, and the boot logs a warning,
  so a demo instance without mail boots. `MAIL_FROM` is required in
  production only together with `SMTP_HOST`; its default is
  `Espalier <noreply@localhost>`. With `SMTP_HOST`, the adapter is
  `Swoosh.Adapters.SMTP` with `tls: :always`, `auth: :always` and
  `tls_options` (`verify: :verify_peer`, `cacerts: :public_key.cacerts_get()`,
  server name indication, `pkix_verify_hostname_match_fun(:https)`).
- Configuration (step 41): `Espalier.RuntimeConfig.parse!/2` parses and
  validates the variables of step 41 and returns the keys `session_idle_minutes`,
  `session_max_hours`, `session_max_concurrent`, `local_accounts`, `signup`,
  `signup_domains`, `password_breach_check`, `password_context_words`,
  `auth_demo`, `bootstrap_admin_emails`, `trusted_proxies`, `public_url` and
  `mail_from` of `config :espalier`. It removes one pair of surrounding double
  quotes from a value, because `docker run --env-file` keeps them.
  `RuntimeConfig.proxy!/1` parses one `TRUSTED_PROXIES` entry into
  `{address, prefix_length}`.
- `SECRET_KEY_BASE` (step 41): a production boot stops when the value is
  shorter than 64 bytes. The generated `config/runtime.exs` accepted an empty
  value, and the encrypted cookie store then answered every request with 500.
- Sessions (step 18): `reissue_session/2` returns `{:ok, new_token}` or
  `{:error, :not_found}`. The copy of steps 18 and 35 is
  `Espalier.Accounts.copy_session/2`. `create_session/2` stores only the
  attributes of step 18, which `UserToken.build_session_token/3` lists, so a
  task that adds a session column (such as `idp_amr` of 0006) extends that
  function; `reissue_session/2` copies every schema field.
- Failure counters (step 17): `FailureCounters.record_failure/3` returns
  `{:ok, counter}` with the updated row (`consecutive_failures`,
  `locked_until`, `disabled_at`). `FailureCounters.reset/2` returns the count
  before the reset, or 0 when no row exists, and `authenticate_password/3`
  uses it for step 16.5.
- Rate limits (step 34): a controller applies an account bucket with
  `EspalierWeb.Plugs.RateLimit.check_account(conn, bucket, identifier)`, which
  returns the conn or the halted 429 answer and logs
  `excess_rate_limit_exceeded` with the bucket in `reason`; the controller
  continues only when `conn.halted` is false. `Espalier.RateLimit.check_account/2`
  returns `{:allow, count}` or `{:deny, retry_after_ms}` for callers outside a
  controller.
- Password change (steps 21 and 35): `update_user_password/3` returns
  `{:ok, {user, token}}`, where `token` is the raw token of the copied session
  row of the option `keep_session:` (the session row of the calling client) or
  `nil`, and `{:error, changeset}`. A missing or wrong current password is a
  changeset error on `current_password` with the code `required` or `invalid`
  (422 `validation_failed`).
- Pending state (step 33): `fetch_pending_second_factor/1` reads the state
  from the conn and returns only `{:ok, pending}` or `:error`, without a conn,
  so it cannot delete the state. `fetch_current_scope_for_user/2` deletes an
  expired or malformed state on each request of the `:api` pipeline that
  `protect_api_from_forgery/2` lets pass. `put_reissued_session/2` puts a
  reissued or copied token into a renewed session, and `UserToken.method!/1`
  turns a stored method name back into its atom.
- Sign-in events (step 33): `log_in_user/3` takes `provider:` for its events
  (default: `provider_key`, or `local`). It logs `session_created` with
  `user_id`, `session_id`, `ip` and `provider`, and `authn_login_success` with
  these and `factor`, the methods of the session joined by `+` (for example
  `password+totp`); it logs no `methods` and no `strength`. `log_out_user/1`
  logs `session_logout` with `user_id`, `session_id`, `ip` and the reason
  `user`.
- CSRF (step 33): `protect_api_from_forgery/2` rejects a mutating request
  without the `x-csrf-token` header before `Plug.CSRFProtection` runs, because
  `Plug.CSRFProtection` also accepts the body parameter `_csrf_token`.
- Request bodies (step 35): a request without the required fields answers
  400 `bad_request` on `POST /api/auth/password`, `POST /api/auth/invitations`
  and `PUT /api/me/email`, and on `POST /api/auth/demo` with a slot outside 1
  to 20. `POST /api/auth/invitations/accept` also answers 404 with
  `LOCAL_ACCOUNTS=false`.
- Errors (step 36): `EspalierWeb.ErrorJSON` maps 400 to `bad_request`, 401 to
  `unauthenticated`, 403 to `forbidden`, 404 to `not_found` and 429 to
  `rate_limited`, every other 4xx status to `bad_request` and every other
  status to `internal_error`. `EspalierWeb.ChangesetJSON.error_codes/1`
  renders the codes of `validation_failed`. Bandit 1.12.5 logs 500 to 599 by
  default, so the endpoint sets no `log_exceptions_with_status_codes`.
- Security events (step 39): `SecurityLog.event/3` also raises
  `ArgumentError` for an attribute key outside its allowlist.
- Administration (steps 23 and 38): `resend_invitation/2` writes the audit
  event `user.invitation_resent` and returns `:ok`, `{:error, :not_invitable}`
  or `{:error, :forbidden}`. `Audit.list_events/2` takes the filters `:action`,
  `:subject_id` and `:limit` (default 100) and orders by `at` and
  `inserted_at`, both with second precision.
- Mail (steps 26 and 27): `UserNotifier.invitation_email/2` builds the
  invitation mail, which the `:mail` test delivers to Mailpit. A failed
  delivery logs `mail delivery failed: job <id>, kind <kind>`, because
  `job_id` is no metadata key of the JSON formatter.
- Migrations (step 11): `phx.gen.schema` gave two pairs of migrations the
  same timestamp, so their versions were renumbered
  (`20261008114548` to `20261008114553`, Oban `20261008114603`).
- Password list (step 14): the SecLists file
  `Passwords/Common-Credentials/xato-net-10-million-passwords-1000000.txt`
  (MIT) yields 10,898 entries; `NOTICE` carries the attribution, and
  `priv/security/README.md` the license text and the filter. Sobelow's
  `Traversal.FileModule` finding on `PasswordPolicy.read_list/1`, which reads
  the two fixed file names, is accepted in code.
- Tests (steps 44 and 45): `api_conn/0` and `next_request/1` set
  `plug_skip_csrf_protection` to `false`, because `Phoenix.ConnTest.build_conn/0`
  sets it and `Plug.CSRFProtection` then accepts any token; every API test
  therefore runs the real token check. `ConnCase` also has `put_setting/2`
  and `next_request/1`, and `Espalier.AccountsFixtures`, which `ConnCase`
  imports, has `session_fixture/2` (one or two arguments),
  `email_token_fixture/4` (two to four arguments) and
  `sessions_with_idp_sid/2`. Security events are asserted through
  `attach_security_events/0` (`Espalier.Test.SecurityEvents`), because
  `capture_log/1` sees only warning-level lines under `config/test.exs`. `test/test_helper.exs` starts ExUnit with
  `capture_log: true`. Phoenix compiles `:filter_parameters` at boot, so the
  logging test reads `config/config.exs` with `Config.Reader` and checks
  `Phoenix.Logger.filter_values/2`. The `TrustedProxy` tests sit in
  `test/espalier_web/plugs/rate_limit_test.exs`. The scope check of step 45
  ran in the working tree before the commit, and its files were removed.
- Headers (step 30): Bandit 1.12.5 adds its own `vary: accept-encoding`
  after the plugs have run (`Bandit.Compression`), whether or not it
  compresses the answer, so most answers carry two `Vary` headers. Answers of
  `send_file` carry one.
- `docs/architecture/domain-records.puml` shows `idp_sid_hash` as
  `binary (keyed hash)` (step 12).
- Open: whether the browsers used for development store the `__Host-espalier`
  cookie over `http://localhost` (Notes) is not yet checked in a browser;
  task 0004a assigns the check.

## Notes
- `phx.gen.auth` at tag `v1.8.15` of Phoenix (released 2026-09-25): it refuses projects without `phoenix_html`; it stores session tokens raw and e-mail tokens as SHA-256 hashes; it reissues session tokens after 7 days without deleting the old row and never purges expired rows; its remember-me cookie lives 14 days with `SameSite=Lax`; `require_sudo_mode/2` uses a 10-minute window; `renew_session` deletes the CSRF token at sign-in and sign-out; the `:api` pipeline of a `--no-html` project holds only `plug :accepts, ["json"]`. The endpoint's `Plug.Session` cookie is signed and readable without `encryption_salt` (Plug 1.20.3).
- Sobelow 0.16.0 (`lib/sobelow/config.ex`, `vuln_pipeline?/2` for `:csrf`) reports a pipeline as `Config.CSRF` when its block lists `plug :fetch_session` and no plug named `:protect_from_forgery`; the accepted formats play no part in this check. It reads each `pipeline` block on its own and compares plug names, so it neither recognizes the function plug `:protect_api_from_forgery` nor proves that a mutating route rejects a request without the token. Step 32 accepts the two findings with skip comments, and the router-wide tests of step 45 carry the CSRF proof (0002, Notes).
- `Cloak.Ecto.HMAC` in cloak_ecto 1.3.0 (`lib/cloak_ecto/types/hmac.ex`) hashes every binary that `dump/1` receives and returns the stored value from `load/1`. A value loaded from an HMAC field and written into another HMAC field is therefore hashed twice, which is why `idp_sid_hash` is a plain `:binary` field (step 12) and why lookups pass the plaintext input, as `subject_hash` lookups pass `hash_input/3` (step 11).
- Hammer 7.5.0 (2026-09-02) is current; `hammer_plug` is end-of-life and pins Hammer 6, so the plug of step 34 is written here. The default `:fix_window` aligns windows to `div(now, scale)` and allows up to twice the limit across a window boundary; `:fix_window_per_key` (Hammer 7.4.0) anchors the window at the first hit of a key.
- `Plug.RewriteOn` takes the leftmost `X-Forwarded-For` entry (Plug 1.20.3). The reverse proxy must overwrite the header (README section 6.10, checked in 0017).
- `argon2_elixir` 4.1.3 defaults to `t_cost: 3`, 64 MiB and `parallelism: 4`. Open issue #73 (2026-06-29) reports `Threading failure` from `Argon2.verify_pass/2` on Elixir 1.20.1 and OTP 28.5.0.2, and the vendored C code creates threads only for `parallelism` above 1. The OWASP minimum for Argon2id is 19 MiB, `t=2`, `p=1`.
- `Argon2.Stats` in argon2_elixir 4.1.3 names 500 milliseconds as the time target and attributes it to the Argon2 draft guidelines (hexdocs of argon2_elixir 4.1.3, read on 2026-10-07). Step 46 has the implementer read the moduledoc of the resolved release, because a later release can name another target.
- NIST SP 800-63B-4 section 3.1.1.2 (pages.nist.gov/800-63-4/sp800-63b.html, read on 2026-10-07) states that each Unicode code point SHALL be counted as one character, and that a verifier which accepts Unicode SHOULD apply the normalization process for stabilized strings with NFC before hashing. ASVS 5.0.0 6.2.8 requires verification exactly as received. README section 15, decision D12, follows NIST with `String.normalize(password, :nfc)` in `PasswordPolicy.prepare/1`, and the matrix records 6.2.8 as a deviation (step 42).
- NFC composes `e` followed by U+0301 into the single code point U+00E9, so `"Lernpfad Cafe\u0301!"` has 15 code points as received and 14 after NFC. U+0344 is excluded from composition and becomes two code points under NFC. Both cases are the reason why every length check runs on the result of `prepare/1`.
- The Oban installation guide of release 2.24.1 (`https://oban.hexdocs.pm/installation.html`, read on 2026-10-07) writes the migration with `Oban.Migration.up(version: 14)` and `Oban.Migration.down(version: 1)`.
- The OWASP ASVS repository tags release 5.0.0 as `v5.0.0_release`, and no tag `v5.0.0` exists (GitHub tag list of `OWASP/ASVS`, 2026-10-07). Step 42 therefore names that tag.
- The Pwned Passwords range API needs no key; `Add-Padding: true` pads responses to 800 to 1,000 entries with count 0. Req 0.7.5 (2026-10-06) is current; `phx.new` 1.8.15 writes `{:req, "~> 0.5"}`, which admits 0.7, and step 6 narrows it.
- Fetch Metadata is supported from Chrome 76, Edge 79, Firefox 90 and Safari 16.4; the OWASP CSRF Prevention Cheat Sheet requires the `Origin` fallback of step 31 when the header is missing.
- Mailpit v1.31.4 receives SMTP on port 1025 and serves UI and API on port 8025. Oban stores job arguments in plain JSON, which is why step 27 keeps tokens and addresses out of them.
- Development runs on `http://localhost:5173` through the Vite proxy. Check with `make run` and the browser developer tools that the browsers used for development store the `__Host-espalier` cookie over `http://localhost`, and note the result in `docs/security/authentication.md`; 0017 checks the cookies on the container.
- Interfaces for later tasks (README section 6.12): 0005 uses `put_pending_second_factor/3`, `fetch_pending_second_factor/1`, `log_in_user/3`, `reissue_session/2`, `require_enrollment_session/2`, `require_recent_auth/2`, `FailureCounters`, `SecurityLog.event/3`, `UserNotifier` and `MailWorker`, keeps the WebAuthn ceremony id in the main session with `put_session/3`, adds its clauses to `UserToken.strength_valid?/3`, and implements `enrolled?/1`; 0006 and 0007 use the pending state, `replace_idp_role_grants/3`, `external_identities` with `ExternalIdentity.hash_input/3` and its changeset (step 11), the `:oidc_transaction` and `:auth_bare` pipelines, `Espalier.RateLimit.account_hash/1`, and add their provider types to `Espalier.Identity.Config.parse!/2`, which fill `:identity_providers`, `:auth_providers` and the answer of `GET /auth/providers`; 0006 uses `EspalierWeb.TransactionCookie` (`get/2` and `clear/1` in `POST /api/auth/finish`, `read_main_session/1` in the `:oidc_transaction` pipeline) and computes `idp_sid_hash` with `UserToken.hash_idp_sid/1` in its callback and in `delete_sessions_by_idp_sid/2` (step 12); 0009 adds OpenAPI operations for the routes of step 35; 0013 reuses Oban, `create_api_client/2` and `get_api_client_by_token/1`; 0015 calls `invite_user/2`, `resend_invitation/2`, `disable_user/2`, `end_user_sessions/2`, `end_all_sessions/1`, `grant_role/3`, `revoke_role/3` and `Audit.list_events/2` for the admin user routes of README section 8; 0017 verifies the headers and cookies of this task on the running container and checks `TransactionCookie.session_options/0` there.
- `POST /api/auth/finish`, its controller and the sign-in ticket belong to 0006 (README section 6.12).
- Error codes of this task, which later tasks and the SPA use as written here: `unauthenticated` (401), `invalid_credentials` (401), `invalid_token` (400), `reauth_required` (403, missing second factor within 10 minutes), `enrollment_required` (403), `forbidden` (403), `csrf` (403), `cross_site_request` (403), `not_found` (404), `validation_failed` (422), `rate_limited` (429), `bad_request` (400) and `internal_error` (500). The shared codes follow README section 6.10.
