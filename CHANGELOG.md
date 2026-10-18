# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Phoenix JSON API and Vite/React single-page application from the standard
  generators, with a pinned `nix-shell` toolchain and a Makefile (task 0001).
- Apache License 2.0 in `LICENSE`, the attribution notice in `NOTICE`, and the
  SPDX identifier `Apache-2.0` in `mix.exs` and `frontend/package.json`.
- Quality gates in `make check`: Credo, Sobelow, `mix hex.audit` with a guard
  for Hex 2.5.1 or later, `mix deps.audit`, the check for unused lock entries,
  `tsc`, Oxlint, Prettier and Vitest with Testing Library and axe (task 0002).
- A seven-day Hex release cooldown in `mix.exs` (task 0002).
- Secret scanning with gitleaks in `make secrets-scan` and in CI, and a
  deny-list check for maintainers (task 0002).
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` and `.editorconfig`
  (task 0002).
- Encryption at rest with `cloak` 1.1.4 and `cloak_ecto` 1.3.0, pinned
  exactly: the vault `Espalier.Vault` with a strict AES-256-GCM cipher, the
  Ecto types `Espalier.Encrypted.Binary`, `Espalier.Encrypted.Map`,
  `Espalier.Encrypted.ClosureBinary` and `Espalier.Hashed.HMAC`, key checks at
  boot, and the release functions `rotate_encryption/0` and
  `encryption_status/0` (task 0003).
- `make gen-keys`, and the variables `CLOAK_KEY_V1` and `CLOAK_HMAC_SECRET`
  in `.env.example` (task 0003).
- A query log without parameters for production, and a release environment
  without crash dump files and without Erlang distribution (task 0003).
- `docs/security/crypto-inventory.md`, `docs/security/key-management.md` and
  the ASVS matrix `docs/security/asvs-l2.md` (task 0003).
- Accounts and sessions ported from `phx.gen.auth` (Phoenix 1.8.15) to JSON,
  with `make auth-reference`: encrypted user records, server-side sessions
  behind the encrypted `__Host-espalier` cookie with 60 minutes of inactivity,
  24 hours of absolute lifetime and five concurrent sessions, password sign-in
  up to the pending second-factor state, invitations, e-mail and password
  change, session listing, roles, the bootstrap admin, API clients, external
  identity rows and the demo sign-in (task 0004).
- Password policy with NFC normalization, 15 to 128 code points, a bundled
  common-password list from SecLists, context words and the optional
  Pwned Passwords range check; Argon2id with `parallelism: 1` and
  `make argon2-bench` (task 0004).
- CSRF token, Fetch Metadata and security header plugs, trusted proxy
  handling, rate limits with Hammer, durable failure counters, security event
  logging with JSON log lines in production, and audit events (task 0004).
- Oban with the daily token purge and mail delivery, Mailpit in
  `compose.dev.yaml` and `make test-integration` (task 0004).
- `docs/security/authentication.md`, `docs/security/logging.md`, and the
  ownership table and the full Level 2 scan of the ASVS matrix (task 0004).
- `test/docs/asvs_matrix_test.exs` in `make check`, which compares the ASVS
  matrix, its ownership table and the security requirements of the task specs
  (task 0004a).
- Second factors for local accounts (task 0005): discoverable passkeys with
  `wax_` 0.7.0 and the checks it leaves to the application, TOTP with
  `nimble_totp` 1.0.0 and a QR code from `eqrcode`, and ten single-use
  recovery codes of 128 bits stored as HMAC-SHA256. A password sign-in
  completes with `POST /api/auth/second-factor`, a passkey alone signs in a
  local account, an invited person enrolls a factor before any other page,
  and a person who lost the factors recovers with a saved recovery code and a
  link sent by e-mail. Factor changes need a second factor from the last 10
  minutes, and `POST /api/me/reauth` provides it.
- `ADMIN_REQUIRE_PASSKEY` (default `true`): the last passkey of an admin
  cannot be removed, and the session payload flags an admin without a
  passkey (task 0005).
- `docs/security/wax-spike.md` with the toolchain check of `wax_` and the
  recorded Chromium virtual authenticator payloads in
  `test/fixtures/webauthn/` (task 0005).
- OIDC sign-in with `oidcc` 3.9.0 and `oidcc_plug` 0.5.1 for Microsoft Entra
  ID, Google Workspace and any OIDC provider configured through
  `AUTH_<KEY>_*` (task 0006): PKCE S256, `state` and `nonce`, the ID token
  allowlist RS256, PS256 and ES256, `private_key_jwt` with PS256, provider
  rules for tenant, hosted domain and groups overage, an outbound host
  allowlist per provider, requests through Req that follow no redirect, a single-use
  sign-in ticket bound to the transaction cookie, the MFA modes `local` and
  `idp_trusted`, provisioning, linking and step-up through single-use
  intents, front-channel and RP-initiated logout, and the mail
  `identity_linked`.
- A mock OIDC provider in `test/support/dev_oidc/`, started by `make run`
  and `make dev-oidc` on port 4010 and by the test suite on port 4011
  (task 0006).
- `docs/guides/identity-providers.md` as a draft, with the results of the
  Entra spike; client certificates name themselves by the `x5t` key id,
  the only format that Entra ID accepts (task 0006).
- The catalog: programs, stations, segments, qualifications with their
  requirements, modules, learning objectives in the four CORE competence
  areas, lessons with blocks, rules, items with options, assessments,
  companion formats, glossary terms, sources and citations, with the join
  tables `objective_lessons`, `item_objectives` and `format_objectives` for
  constructive alignment (task 0008).
- Content packs in YAML and Markdown: `mix espalier.validate` checks a pack
  directory with file and line per finding, `mix espalier.import` and
  `Espalier.Release.import_pack/2` store it as a draft `PackImport` and
  publish it in one transaction by stable keys, and `mix espalier.alignment`
  prints the alignment matrix as text, CSV or JSON. The validator applies the
  four alignment checks of domain rule 14: the findings of checks 1 to 3 are
  errors with `alignment: strict` (the default) and warnings with
  `alignment: warn`, and the findings of check 4 are warnings in both modes
  (task 0008).
- The `license` of a pack is checked against the SPDX license expression
  grammar and the ids of the SPDX License List in `priv/spdx/`, which
  `make spdx-lists` writes from the pinned nixpkgs (task 0008).
- The neutral demo pack `content/demo/` ("AI assistant basics (demo)"),
  imported by `make setup` and `make refresh-db`, and the dependency
  `yaml_elixir` 2.12 (task 0008).
- The learner API (task 0009): published programs, modules, glossary and
  handbook without answer keys, with the learning objectives of each topic,
  their teaching lessons and their evidence, and the objective keys of each
  item; enrollment with a path that a manual choice keeps; server-side
  evaluation of practice answers with feedback, rules and lessons to reveal;
  exam attempts under the pass rule; module completion after the passed
  exams that count for a credential; and `GET /api/me/progress` with the
  status of every objective, derived per request from the learner's own
  records.
- `TRACKING_DETAIL` (`minimal` or `standard`) and `INSIGHTS_ORG_UNIT`, the
  anonymous item statistics `item_stats`, and the per-user rate limit buckets
  `learner_write` and `assessment_attempt` (task 0009).
- The OpenAPI document at `/api/openapi` with `open_api_spex` 3.22 for the
  learner routes and the routes of task 0004; `make api-types` writes
  `frontend/openapi.json` and `frontend/src/api/schema.d.ts` with
  `openapi-typescript`, `make check` fails when they differ from the
  committed files, and `openapi-fetch` is a dependency of the frontend
  (task 0009).
- The frontend shell (task 0010): Tailwind CSS 4 with one accent token, a
  layout with skip link, theme toggle, language switch, user menu and demo
  banner, React Router with learner and admin areas behind the guards
  `RequireAuth` and `RequireRole`, the session context with `signOut()`, a
  typed API client that sends the CSRF token and repeats a request once after
  a 403 `csrf`, the guarded message listener `listenMessages`, `return_to`
  validation, and English and German UI strings.
- The Oxlint rule `react/no-danger` and TypeScript strict mode in both
  `tsconfig` files (task 0010).
- `make e2e` with Playwright 1.59.1, axe and the demo sign-in, and the check
  whether the development browsers store the session cookie over
  `http://localhost`, with its result in `docs/security/authentication.md`
  (task 0010).
- The account UI (task 0011): the sign-in page with passkeys and conditional
  UI, the password with a second factor, the OIDC and LDAP providers and the
  demo accounts; the OIDC finish route `/auth/finish`; the invitation page,
  the enrollment wizard with saved recovery codes, recovery and the e-mail
  confirmation; the security page for passkeys, the authenticator app,
  recovery codes, password, e-mail, connected accounts and sessions; a
  step-up dialog that the API client opens on `reauth_required` before it
  repeats the request; sign-out through the provider's logout URL; and the
  session synchronization across tabs through `BroadcastChannel`.
- OpenAPI operations for the `/api` routes of tasks 0005, 0006 and 0007, the
  200 answer of `DELETE /api/session` with `logout_url`, and the member
  `linked_providers` of `GET /api/me/security` (task 0011).
- Development-only seeding routes under `/api/dev/e2e` and Playwright specs
  for invitation, passkeys, the authenticator app, recovery, e-mail change,
  OIDC and LDAP with the Chromium virtual authenticator, Mailpit, the mock
  OIDC provider and lldap (task 0011).
- The player and learner UI (task 0012): the program list, the program page
  with the path switch and the step list, the stations with previous and
  next, and the module station with the objectives of the topic grouped by
  the four competence areas, lessons with every block kind and collapsible
  explanations, practice items of every kind with feedback, objective chips
  and the reveal of explanations after a wrong answer on the short path, the
  exam with the pass rule, the rules recap, module completion and a summary
  of the objectives with the statuses evidenced, practised and open; the
  glossary with glossary terms in Markdown, and the printable handbook on A4.
- The `Runtime` interface with the view types and `PlatformRuntime`, which
  keeps opened explanations, visited stations and, with
  `TRACKING_DETAIL=minimal`, answered items in the `localStorage` entry
  `espalier.player.<program slug>` (task 0012).
- Markdown rendering with `react-markdown` 10.1.0 and `remark-gfm` 4.0.1,
  without raw HTML, and Playwright specs for the walk through module 1, the
  stations at 360 pixels and the handbook PDF (task 0012).
- Policies (task 0013): policies with numbered versions in Markdown, an
  effective date and the option to require a refresher; the learner's
  acknowledgement of a published version (`GET /api/policies` and
  `POST /api/policy-versions/:id/acknowledgements`); the approved tool list
  with vendor, status, conditions and review date (`GET /api/approved-tools`);
  and the current policy text in the placeholder blocks of
  `GET /api/modules/:id` and in the handbook.
- Credentials (task 0013): the evaluation of the requirements of each
  qualification after a passed exam, a module completion, an attendance
  certificate and a policy acknowledgement, which issues and restores
  credentials; the refresher, which moves the credentials that require a
  policy to `refresh_due` when a version that requires a refresher is
  published; the daily sweep `Espalier.Credentials.SweepWorker`, which moves
  credentials to `refresh_due` and `expired` and sends a mail for each move;
  revocation through `Credentials.revoke/2` for admins; and
  `GET /api/me/requirements`, `GET /api/me/credentials` and
  `GET /api/me/credentials/:id`. A credential carries no score.
- Attendance certificates as objective evidence (task 0013): a facilitator
  finds a learner by the exact address
  (`POST /api/facilitator/user-lookups`) and issues certificates for a
  companion format and date (`POST /api/formats/:id/attendance`); a format
  with `attendance_counts` evidences its learning objectives in
  `GET /api/me/progress`.
- The registrar list `GET /api/registrar/credentials` with the holders of
  the credentials of one qualification code, behind the role `registrar`
  and `REGISTRAR_ENABLED`, which defaults to `false` (task 0013).
- The integration API `POST /api/integration/credential-lookups`, which
  returns the credentials in force of one address to an API client with a
  bearer token and the scope `credentials:read`; its pipeline has no
  session, CSRF or Fetch Metadata layer (task 0013).
- Webhooks for the credential events `credential.issued`,
  `credential.refresh_due`, `credential.expired` and `credential.revoked`,
  signed with HMAC-SHA256 in `x-espalier-signature`, admitted only for the
  hosts in `WEBHOOK_ALLOWED_HOSTS`, with the secrets in `WEBHOOK_SECRET_*`
  variables, and delivered by the Oban queue `webhooks` (task 0013).
- `CREDENTIAL_NOTICE_DAYS` and `CREDENTIAL_GRACE_DAYS`, each 30 by default:
  the sweep moves a credential to `refresh_due` from `valid_until` minus the
  notice days on, and to `expired` once `valid_until` plus the grace days has
  passed (task 0013).
- `mix espalier.seed_demo`, which seeds the demo policy `usage-policy` and
  three approved tools and which `make setup` and `make refresh-db` run
  (task 0013).
- The learner pages for policies and credentials (task 0013): `/policies`
  with the current versions, the acknowledgement and the approved tool list;
  the credential station with the met and open requirements per
  qualification; `/me/credentials`; and `/me/credentials/:id`, which prints
  on A4.
- Anonymous insights (task 0014): the self-assessment
  (`POST /api/self-assessments`), the "would use" votes for companion
  formats (`POST /api/formats/:id/votes`) and the feedback
  (`POST /api/feedback`) are stored in `self_assessment_responses`,
  `interest_votes` and `feedback_responses` without a user key, with a
  random primary key and only the date. A participation marker per person
  and subject lets each person count once, and
  `GET /api/me/participation` returns from the markers alone what the user
  has answered. A format vote has the single choice `would_use`, so its
  marker states the vote with the user id; no role of the application reads
  another person's markers, and README section 10 names this limit for the
  GDPR workstream. A new self-assessment applies the segment's default path
  to the enrollment unless the learner chose the path by hand, and the
  feedback answers are checked against the questions of the feedback
  station.
- The reports for the role `analyst` under `/api/insights` (task 0014): the
  self-assessment segments by month, the attempts and the share correct per
  practice item and month, the competence report with the share correct per
  CORE competence area and depth of the learning objectives that the items
  name, the "would use" votes per format, the choice and scale distributions
  of the feedback with free text only from the threshold on, and the
  credentials per qualification and status. Every cell with a count below
  `INSIGHTS_MIN_GROUP_SIZE` (default 5) is suppressed, the reports break
  down by org unit only with `INSIGHTS_ORG_UNIT=true`, no report returns a
  person or a column total, and every answer carries
  `cache-control: no-store`. Every report names the threshold as
  `min_group_size` and the content language of the program as `locale`.
  Once the program has a self-assessment answer, the self-assessment report
  lists every live segment, per org unit with answers when the breakdown is
  on, so a missing row reveals nothing. An archived segment, a key that
  names no segment of the program and an archived qualification appear
  only with at least one shown cell. An item with fewer attempts than the
  threshold in one org unit of a month suppresses every cell of each area
  and depth it names in that month, in every org unit, and with the org-unit
  breakdown the competence report gives every area and depth a row for
  every org unit that has a shown cell, so that neither a difference with
  the item report, nor the bounds of a suppressed cell, nor the pattern of
  suppressed cells or listed org units reveals a count below the threshold.
- The learner stations for the self-assessment, the companion formats and
  the feedback, and the reports page `/admin/insights` for analysts, which
  renders a suppressed cell as "fewer than N" (task 0014).
- The nightly retention job `Espalier.Insights.RetentionWorker` at 03:30 UTC
  (task 0014): `RETENTION_ITEM_RESPONSES_DAYS`, `RETENTION_ANONYMOUS_DAYS`,
  `RETENTION_AUDIT_DAYS` and `RETENTION_ATTEMPTS_DAYS` delete the item
  responses, the anonymous rows, the audit events and the exam attempts
  older than their number of days, and the attempts keep the newest passed
  attempt per user and assessment that a credential in force depends on. The job deletes the attempts of
  each user after taking the evaluation lock of that user, so a credential
  that a running evaluation issues keeps its attempt. Every period is unset
  by default, so the job deletes nothing until an operator sets one. On
  every run, the job rewrites every row of the three anonymous tables and
  of the participation markers with one `UPDATE` per table, so that all
  rows of a table carry the transaction id of its `UPDATE`, and then
  reorders each table by its random primary key with `CLUSTER`, a separate
  statement that runs after the `UPDATE` has committed.
- `FEEDBACK_FREE_TEXT` (default `false`), which adds the free-text
  questions of the feedback station, and `TEST_NOTES` (default `false`),
  which records the events of a usability test in the `sessionStorage` key
  `espalier.test_notes` and shows them in a "Test notes" panel; the log
  never reaches the server, and sign-out and a new sign-in clear it. The
  session payload carries both settings in `flags` (task 0014).
- The per-user rate limit bucket `insights_write` for the three POST routes
  of the anonymous insights (task 0014).
- The admin area under `/api/admin` and `/admin` (task 0015): content pack
  upload with archive checks before any extraction, the alignment matrix and
  findings of a pack, the pack diff with the changed fields of learning
  objectives, and the publication, refused while the alignment checks report
  an error; user administration with invitation, disabling, ending the
  sessions of one user or of all users, the reset of second factors after an
  identity check by the organization (decision D11) with the mail
  `factors_reset`, and the reset of failure counters; policies, policy
  versions, the approved tool list, role grants, API clients, webhooks,
  credential revocation and the audit log; the attendance page for
  facilitators and the credential list for registrars. Every change under
  `/api/admin` needs a second factor from the last 10 minutes, and with
  `ADMIN_REQUIRE_PASSKEY=true` an admin reaches the admin routes only with a
  passkey.
- `PACK_UPLOAD_MAX_MB` (default 20), the upload limit of a content pack; an
  archive may hold at most 2,000 entries and declare at most five times that
  size (task 0015).
- The preview of a pack in the player with `StandaloneRuntime`, the
  TypeScript port of the evaluator in `src/player/evaluate.ts` and the
  shared fixture `test/fixtures/evaluator_cases.json` (task 0015).
- The SCORM export (task 0016): an author exports a module of a published
  program as a SCORM 1.2 or SCORM 2004 4th edition package on
  `/admin/exports` (`POST /api/admin/exports`, which needs a second factor
  from the last 10 minutes, `GET /api/admin/exports/:id` and its download).
  The Oban queue `exports` builds one package at a time with the player,
  `LICENSE` and `NOTICE`, `content.json` with the content and the answer keys
  of the module, `imsmanifest.xml` and the schema files of the version, and
  the request writes the audit event `export.requested`. The job reads the
  content under a shared advisory lock of the pack, so a running publish of
  the pack ends first, and runs at most 30 minutes. Every 15 minutes,
  `Espalier.Interop.StaleExportWorker` sets an export that stays `queued` or
  `running` for more than twice that time, at least one hour, to `failed` and
  removes its files. The worker changes a status only from the statuses it
  expects, with one conditional `UPDATE`, so a build that ends after the
  sweep failed its export removes its package and sets no status.
- The retention of SCORM exports (task 0016): `config :espalier,
  :export_retention` keeps at most `max_packages` (100) packages of `done`
  exports and deletes `done` and `failed` exports after `max_age_days` (7)
  with their files. The worker applies the count limit after each finished
  export, the sweep applies both limits and removes the files in
  `EXPORT_DIR` without an export row, and a deleted export answers 404. The
  admin page shows such an export as no longer available, without its
  download link.
- The SCORM player (task 0016): a second Vite build
  (`npm --prefix frontend run build:scorm`) bundles the module station and the
  glossary with `Scorm12Runtime` and `Scorm2004Runtime` into
  `priv/scorm_player`. The package finds the LMS API, reports completion,
  success, score and session time, writes one `cmi.objectives` entry per
  learning objective of the module with the state `passed`, `failed` or
  `incomplete`, derived from the evidence items in the package, and resumes
  from `cmi.suspend_data` in at most 4,096 characters, bound to the layout
  of the module by a fingerprint. SCORM 1.2 reports `completed` for a
  completed module without exam outcome and the score in percent for an exam
  of more than 100 items. Links that leave the page open in a new tab, and
  the package shows a notice when the LMS refuses the initialization and
  when the browser restores the page from its back/forward cache.
- `EXPORT_DIR`, the directory of the SCORM packages, with the defaults
  `tmp/exports` in development and `tmp/test-exports` in tests; production
  requires it (task 0016).
- `mix espalier.scorm_xsd` and `make scorm-xsd`, which fetch the XML schema
  files of both SCORM versions from two archives pinned by SHA-256 into
  `priv/scorm/xsd/`, because the repository does not hold them; `make setup`,
  `make e2e` and the builder stage of the Dockerfile run the task (task 0016).
- `mix espalier.export SLUG PATH`, which writes a published program back to
  disk as a content pack with `objectives.yaml`, the objectives of items and
  formats, `areas_elsewhere` and the `alignment` setting, with `ymlr` 5.1 as
  the YAML encoder; it reads the program under the same lock as the export
  job (task 0016).
- `docs/guides/scorm-export.md` with the package contents, the data model of
  both versions, the objective states, the suspend data and the procedure of
  the LMS test (task 0016).
- A production image that carries `LICENSE` and `NOTICE` at `/app`, the demo
  pack for `Espalier.Release.seed_demo/0`, a health check (`bin/health`
  with `curl`) on `/health` at the port of `PORT`, `EXPOSE 4000` and the
  directory `/data/exports` (task 0017).
- TLS between the application and PostgreSQL: the one-shot service
  `db-certs` of `compose.yaml` generates a CA and a server certificate with
  EC P-256 keys, the database admits TLS connections only, and the Repo
  verifies the server certificate against `DATABASE_CA_CERT_FILE` and the
  host name of `DATABASE_URL` (task 0017).
- `Espalier.BootCheck`: a missing or invalid setting stops the boot with one
  message that names every gap, and `Espalier.RuntimeConfig.errors/2`
  returns every invalid value instead of the first. Each boot logs the
  effective session and data protection settings and the providers with key,
  type and MFA mode (task 0017).
- The release functions `create_api_client/2` and `seed_demo/0` (task 0017).
- `scripts/check-headers.sh`, `scripts/check-release.sh` and
  `scripts/smoke.sh` with `make smoke` and `make smoke-proxy`, which need
  Docker, curl and a POSIX shell only; `make release-push`; the demo profile
  of decision D5 in `.env.demo.example` with `make demo-env`, `make demo-up`
  and `make demo-down` (task 0017).
- The reverse proxy example `docs/guides/examples/Caddyfile` with
  `compose.caddy.yaml`, and log forwarding over TLS to a syslog receiver in
  `compose.logging.yaml` (task 0017).
- The guides `self-hosting.md`, `demo-instance.md`, `content-packs.md`,
  `security.md` and `operations.md`, a troubleshooting section in
  `identity-providers.md`, and the keys and certificates of the deployment in
  `docs/security/key-management.md` and `docs/security/crypto-inventory.md`
  (task 0017).
- `npm --prefix frontend audit --omit=dev` as the last command of
  `make check`, and tests that check the example files of the content pack
  guide and the deployment files against the guides (task 0017).
- Four introductions in `docs/guides/` (what Espalier is for, installation and
  setup, instance, tenant and authentication, and the building blocks of course
  YAML) with an index `docs/guides/README.md`, and `test/docs/guides_links_test.exs`,
  which checks that the relative links of the guides and the README resolve.
- API documentation with ExDoc (`make docs-api`, `mix docs --warnings-as-errors`
  in `make check`): the module documentation grouped by layer with the content
  pack format first, and the guides, the security documents, the plan, the
  changelog and the contribution rules as pages.

### Changed

- A content pack sets the display order of its qualifications (issue #39).
  An entry of `qualifications.yaml` takes an optional `position` of 1 or
  more, set on every entry or on none and each value once; without it, the
  qualifications keep the order of the file instead of the order by code.
  The requirements of the credential station (`GET /api/me/requirements`),
  the credential report (`GET /api/insights/credentials`) and the pack that
  `mix espalier.export` writes follow that order, and an import that only
  reorders the file lists the moved qualifications as changed. The new
  column `qualifications.position` starts with the former order (add-ons
  last, each group by code), so a live program keeps its order until its
  next publish. An import validated before the change holds its
  qualifications in code order and publishes them in that order; a new
  import of the pack applies the order of the file.

- `bandit` 1.13.1 replaces 1.12.5, which carries EEF-CVE-2026-105660
  (CVE-2026-105660, GHSA-v53v-9hvg-37jf: an unvalidated HTTP/1 request-target
  authority lets a client choose `conn.host` and `conn.port`) and
  EEF-CVE-2026-105659 (below); `thousand_island` follows with 1.6.0. `mix.exs`
  ignores no `bandit` advisory, and the endpoint keeps serving no HTTP/2,
  because Espalier serves HTTP/1.1 behind its reverse proxy.

- The endpoint serves no HTTP/2 (`http_2_options: [enabled: false]`), because
  `bandit` 1.12.5 carries EEF-CVE-2026-105659 (CVE-2026-105659,
  GHSA-69m6-wcv4-rwcf: a peer that drips small `WINDOW_UPDATE` frames keeps
  HTTP/2 stream processes alive indefinitely) and no release fixes it yet.
  Over plain TCP, Bandit had accepted HTTP/2 with prior knowledge. `mix.exs`
  ignores the advisory until a release fixes it, and HTTP/1.1 is unchanged.

- `postcss-selector-parser` 7.1.6 replaces 6.0.10, which carries
  CVE-2026-104844 (GHSA-rj75-hqrm-r3gf: parse time quadratic in the classes
  and ids of a flat selector). `@tailwindcss/typography` 0.5.20 pins 6.0.10
  exactly, so an entry in `overrides` of `frontend/package.json` lifts the
  pin. The plugin parses only its own selectors at build time, and the built
  SPA and SCORM player stay byte for byte the same.

- The credential station labels an open attendance requirement "Obtain the
  format certificate:" and a met one "Format certificate held:" (German
  "Bescheinigung zum Format erhalten:" and "Bescheinigung zum Format
  vorhanden:") in place of "Attend the format:" and "Format attended:", so
  that the label also fits a format that the person leads or completes with a
  sign-off (task 0013).

- The header of a signed-in session holds a main navigation with the
  programs, the credentials, the policies and, for the roles of the admin
  area, the administration, with a "Menu" button below the `md` breakpoint;
  the user menu keeps the security settings and sign-out. The pages of a
  program show breadcrumbs and a program navigation with the overview, the
  stations, the glossary and the handbook, and the credential page shows
  breadcrumbs in place of its back link. The admin area had no entry point,
  and the learner pages were not reachable from every view (tasks 0010,
  0012, 0013 and 0015).

- The publisher gives a later publish of one pack a later `published_at`,
  also within one second, so that the fields of `pack.yaml` that no table
  holds come from the import published last (task 0016).
- `make check` ends with the build of the SCORM player, and `make e2e`
  fetches the schema files and builds the player before Playwright
  (task 0016).

- The endpoint parses no multipart body; only the pack upload reads one,
  behind the role and recent-auth checks (task 0015).
- Every answer under `/api/admin` carries `cache-control: no-store`, and
  `Audit.list_events/2` filters by actor and pages by 50 events with the id
  as the last ordering key (task 0015).
- `Accounts.resend_invitation/2` logs `user_updated` with
  `change: "invitation_resent"` (task 0015).
- The pages of the player build their program links from
  `ProgramBaseContext`, so that the preview of task 0015 keeps them below its
  route.

- The `localStorage` entry `espalier.player.<program slug>` carries the
  owner tag `o`, a SHA-256 digest prefix of the enrollment id, in entry
  version 2. The player reads the entry only for the person it belongs to, so
  people who sign in one after the other in the same browser no longer see
  each other's visited stations, opened explanations and, with
  `TRACKING_DETAIL=minimal`, answered items; entries of version 1 are
  dropped (task 0012).
- The `placeholders` of `GET /api/programs/:slug/handbook` are a list of
  objects with `key` and `policy` (the current version of the policy, or
  `null`) in place of a list of keys (task 0013).
- A repeated `POST /api/modules/:id/completion` checks the open exams again,
  so it answers 409 `assessments_open` after a pack adds an exam that counts
  for a credential; otherwise it records its time in `completed_at`, answers
  with the new time and evaluates the credentials (task 0013).
- `POST /api/formats/:id/attendance` answers 422 `validation_failed` with
  `fields.held_on` `["past"]` for a `held_on` before 2000-01-01, the earliest
  date of a session the platform records, next to `["future"]` for a date
  after today (task 0013).
- `Policies.publish_version/2` answers `{:error, :superseded}` when a
  published version of the same policy has a higher number, so an older draft
  cannot be published after a newer one and move credentials to
  `refresh_due` for a version that never becomes current (task 0013).
- Every writer of credentials takes the rows in one order: `evaluate/2` by
  `qualification_id`, and `sweep/1` and `mark_refresh_due_for_policy/1` by
  `user_id` and `qualification_id`, so the daily sweep and an evaluation
  cannot deadlock (task 0013).
- `GET /api/policies` carries `cache-control: no-store`, because it returns
  the user's own acknowledgement times (task 0013).

- Blocks in `GET /api/modules/:id` carry their `id`, and the pages of a
  program load in chunks of their own (task 0012).
- Dark styles apply on screen only, so printed pages are light (task 0012).

- `decimal` 3.1.2 replaces 3.1.1, which carries EEF-CVE-2026-97853
  (unbounded allocation in `Decimal.round/3`); the update bypasses the
  seven-day Hex cooldown.
- The Vite dev proxy forwards every path below `/auth` except the SPA route
  `/auth/finish`, which Phoenix also serves through `SpaController`
  (task 0011).
- The nix shell points libglvnd at the EGL driver of Mesa on Linux, so the
  WebKit of Playwright starts outside NixOS, and `make help` lists the
  targets whose names hold a digit, such as `e2e` (task 0010).
- Production requires an `https` `PUBLIC_URL`, because the passkey origin
  and relying party id derive from it (task 0005).
- `PUT /api/me/password` sets the password without the current one in an
  enrollment or recovery session (task 0005).

- The ownership table of the ASVS matrix names every row, and the matrix
  records the decided deviations for RS256, SHA-1, the previous TOTP step, the
  directory password bind, the OIDC query-string values and the proxy hop
  (decisions D13 to D17, task 0004a).
- A production boot stops when `SECRET_KEY_BASE` is shorter than 64 bytes,
  because the encrypted session cookies need it (task 0004).
- The production endpoint leaves HSTS to the reverse proxy
  (`force_ssl: [hsts: false]`), because Plug.SSL added a second
  `Strict-Transport-Security` header with another `max-age` to proxied
  answers for a host other than `localhost` (task 0017).
- `EspalierWeb.Plugs.TrustedProxy` turns an IPv4-mapped IPv6 peer address,
  which Bandit reports for an IPv4 client of its IPv6 listener, into its IPv4
  form, so that an IPv4 entry of `TRUSTED_PROXIES` matches the reverse proxy.
  An IPv4-mapped entry of `TRUSTED_PROXIES`, such as `::ffff:172.30.0.10`,
  counts as its IPv4 form, and an IPv6 range such as `::/0` matches IPv6
  peers only (task 0017).
- `EspalierWeb.Plugs.SecurityHeaders` appends `charset=utf-8` to every
  `text/*`, `*/*+xml` and `*/xml` content type without one, such as the
  script, the style and the SVG icon of the SPA (task 0017).
- `compose.yaml` publishes the application port on `127.0.0.1` only, restarts
  the services unless stopped, and reads `ENV_FILE`, `ESPALIER_IMAGE` and
  `APP_PORT` (task 0017).
- The frontend stage of the Dockerfile copies `test/fixtures/evaluator_cases.json`,
  which `tsc -b` needs for a test since task 0015; without it,
  `make docker-build` failed. `.dockerignore` keeps `.git`, nested
  repository metadata, `dev/` and agent worktrees out of the build context
  (task 0017).
- The `__Host-Http-` cookie prefix was revisited on 2026-10-15: Safari 27.0
  and iOS Safari 27.0 do not support it, so the cookie names stay (task 0017).
- The application takes `PUBLIC_URL` with a lower-case host and without the
  default port, the form of the origin that browsers send, so that passkeys
  and the Fetch Metadata check work with a value such as
  `https://Learn.Example.org:443` (task 0017).
- A production boot also stops for a `PUBLIC_URL` with user info, a
  `DATABASE_URL` without a host or with a path other than one database name,
  with the query parameter `ssl`, which Ecto merges over the TLS options of
  the Repo, or with a `timeout`, `pool_size` or `idle_interval` that is no
  integer (for these, Ecto prints the URL with its password), an
  `SMTP_PORT` outside 1 to 65535 and a `POOL_SIZE` that is no positive
  integer, and a boot in every environment for a `PORT` outside 1 to
  65535. `config/runtime.exs` reads the connection and secret variables
  trimmed and without one pair of surrounding double quotes, as the boot
  check does, and an empty `SMTP_USERNAME` or `SMTP_PASSWORD` counts as unset
  (task 0017).
- The OIDC redirect URI uses the same normalized `PUBLIC_URL` as the
  post-logout URI and the mail links (`Espalier.RuntimeConfig.normalize_url/1`,
  task 0017).
- The release in the image has no group or other write bits, `LICENSE` and
  `NOTICE` have the mode 0644, and `/data/exports` admits the group root;
  `make argon2-bench` runs with an env file written for `compose.yaml`
  (task 0017).
- Production mail goes to `SMTP_HOST` itself (`no_mx_lookups: true`);
  gen_smtp had connected to the MX hosts of that name when it had any
  (task 0017).
- The release in the image belongs to `root`, and the image holds no
  distribution cookie: `rel/env.sh.eex` gives every command a random cookie
  while the Erlang distribution is off and stops without `RELEASE_COOKIE`
  when it is on. `.dockerignore` keeps the env files of every directory out
  of the build context, `frontend/` included (task 0017).
- The PostgreSQL service of `compose.yaml` offers for TLS 1.2 only the suites
  with ECDHE and AES-GCM or ChaCha20-Poly1305 (`ssl_ciphers`) (task 0017).
- `make demo-down` runs `docker compose -p espalier-demo down -v`, which
  needs no env file and also removes the proxy example of the demo.
  `make demo-up` waits on the port that Docker Compose publishes, and
  `make demo-up` and `make smoke` ignore a `POSTGRES_PASSWORD` of the shell
  (task 0017).

[Unreleased]: https://github.com/HelrenPDM/espalier/commits/main
