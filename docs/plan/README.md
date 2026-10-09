# Implementation plan

Espalier is an open-source learning platform for competence programs that end
in a credential. A credential names the tasks it unlocks and holds no score or
rank of the person. Every topic follows constructive alignment: it states its
learning objectives in the four competence areas of CORE (constructive oriented
research and education), and each objective is tied to the activities that
teach it and the evidence that shows it. The backend is an Elixir/Phoenix JSON API,
and the user interface is a Vite/React single-page application styled with
standard Tailwind CSS.

This document is the entry point. The diagrams live in
[`../architecture/`](../architecture/README.md), and the executable task specs
live in [`tasks/`](tasks/). Each task spec is self-contained: read it, do what it
says, run its acceptance checks, stop.

## 1 Scope

### Goals

1. The internal data model represents programs, qualifications, modules,
   lessons, rules, items, exams with pass rules, companion formats and
   organizational policies. It is independent of any delivery standard.
2. People sign in with the identity provider their organization already runs,
   OIDC (Microsoft Entra ID for Microsoft 365, Google Workspace, any
   standards-compliant OIDC provider) or LDAP / Active Directory, or with a
   local account secured by passkeys or by a password with a second factor.
   All account security is built from standard Elixir and Erlang libraries
   inside the Phoenix application. The platform runs no separate identity
   server. Test sessions can use pseudonymous demo accounts.
3. Learners on different experience levels go through the same mandatory
   content. A short path starts explanations collapsed, a full path starts them
   open, and no lesson is skipped on either path.
4. Records are separated by purpose, and the operating organization configures
   how much is recorded per person.
5. Content lives in versioned content packs (YAML and Markdown), so that an
   organization keeps its course content in Git next to its review process.
6. The UI uses the Tailwind CSS default palette and utilities. An adopter
   restyles it in one CSS file.
7. SCORM 1.2 and SCORM 2004 are export targets for organizations that deliver
   through an existing LMS.
8. Every topic supports constructive alignment. A topic (a module) declares
   learning objectives in the four CORE competence areas (subject, method, self
   and social competence), each with a depth and a phase of the five-phase arc.
   Each objective is aligned with the lessons that teach it and with the items,
   exams and companion formats that provide evidence for it. The importer checks
   the alignment, learners see the objectives of each topic, and reports and
   SCORM exports carry them.

### Out of scope for the first version

WYSIWYG authoring, SAML, SCIM provisioning, OIDC back-channel logout, xAPI and
cmi5, multi-tenancy, native mobile apps, and any gamification that ranks people. Each of these has an
extension point in the architecture (provider behaviour, runtime adapter,
webhooks), and none of them is built now.

## 2 Principles

1. **Records are separated by purpose.** The anonymous self-assessment, the
   acknowledgement of a policy version, the completion with pass, and the
   attendance certificate for a format outside the platform each have their own
   table, their own visibility and their own retention. Evidence of a human
   review at a single work item (for example a field in a CMS) belongs to the
   system where that work happens. The platform trains it with the
   `checklist_drill` item kind and stores nothing about real work items.
2. **A credential names tasks.** `Qualification.unlocks` lists what a holder may
   do. The credential copies that list at issue time. No table stores a score
   per person beyond the outcome of an exam attempt.
3. **Data minimization is a setting.** `TRACKING_DETAIL`, `REGISTRAR_ENABLED`,
   `INSIGHTS_MIN_GROUP_SIZE` and the retention variables decide what is stored
   and who sees it. The defaults are the most data-sparing values. The legal
   assessment under the GDPR, the retention periods and the data protection
   documentation form a separate workstream after the first version
   (section 10).
4. **Every statement shows its provenance.** Blocks and items carry one of
   `invented`, `sourced`, `vendor_statement`, `assumption` or `placeholder`, and
   the player renders it as a visible badge. Citations point to sources with
   edition date and retrieval date.
5. **Content is code.** Content packs are validated on import, upserted by
   stable keys, and published explicitly. Records reference stable rows, so a
   new pack version keeps existing progress intact.
6. **Visual neutrality.** Plain Tailwind utilities, Headless UI for accessible
   primitives, Heroicons for icons. No commercial component kit, no custom
   palette beyond one accent token.
7. **No secrets and no organization names in the repository.** Configuration
   comes from environment variables. `.env.example` holds placeholders. Dev
   fixtures (the mock OIDC provider, the LDAP seed) use invented people.
8. **Account security follows a published baseline.** OWASP ASVS 5.0.0 Level 2
   is the verification target, NIST SP 800-63B-4 (AAL2) the reference for
   authenticators and sessions, and RFC 9700 and RFC 10017 the rules for the
   OAuth client and the backend-for-frontend cookies. Every security task names
   the ASVS requirements it covers (section 6).
9. **Standard generators and nix-shell.** The skeleton comes from
   `mix phx.new`, `mix phx.gen.*`, `mix phx.gen.release --docker` and
   `npm create vite`. The account core comes from `mix phx.gen.auth`, generated
   in a reference project (section 6.4). Every toolchain command runs inside `nix-shell`, and the
   Makefile wraps each one, following the repository shape of `sl_vanilla`.
10. **Objective, activity and evidence belong together.** In a pack with the
    default `alignment: strict`, no objective exists without a lesson that
    teaches it and evidence that shows it, and no item that counts for a
    credential exists without an objective. The check runs at every import, so
    that a topic cannot teach subject knowledge and claim method, self or social
    competence it never practises. A pack with `alignment: warn` imports with
    these findings as warnings (domain rule 14).

## 3 Stack and versions

The versions below are those of the pinned nixpkgs commit and of the npm and
Hex registries on 2026-10-07. Lockfiles (`mix.lock`,
`frontend/package-lock.json`) pin the exact library versions at bootstrap.

| Layer | Choice | Version |
|---|---|---|
| Toolchain | nixpkgs `nixos-26.05`, commit `b25309931cfda5f0b8805f462a29897eeae50168`, fetched as tarball in `shell.nix` | pinned |
| Runtime | Erlang/OTP from `beam28Packages`, Elixir `beam28Packages.elixir_1_20` | OTP 28.5.0.7, Elixir 1.20.4 |
| Web framework | Phoenix, API only (`--no-html --no-assets --no-dashboard`), Bandit | phx_new 1.8.15 |
| Database | PostgreSQL (`postgresql_18` in nix, `postgres:18` image) | 18.6 |
| Jobs | Oban | current Hex release |
| Account security | see the library table in section 6.3 | pinned per library |
| API contract | `open_api_spex` (spec and request validation) | current Hex release |
| Frontend tooling | Node.js `nodejs_24`, Vite via `create-vite` template `react-ts` | Node 24.21, create-vite 9.2.1, Vite 8.3 |
| Frontend libraries | React 19, TypeScript (as pinned by the template), Tailwind CSS with `@tailwindcss/vite`, React Router, TanStack Query, Headless UI, Heroicons, react-i18next, react-markdown with remark-gfm and remark-directive, openapi-typescript and openapi-fetch | React 19.3, TypeScript 6.0, Tailwind 4.3, React Router 8.4, TanStack Query 5, Headless UI 2.2 |
| Lint and audit | `mix format`, Credo, Sobelow 0.16, mix_audit 2.1, `mix hex.audit` (Hex 2.5.1 or later); Oxlint (template default), Prettier | |
| Tests | ExUnit, Vitest with Testing Library, Playwright | Playwright 1.59.1, matching `playwright-driver.browsers` in nixpkgs; passkey tests use the Chromium DevTools virtual authenticator |
| Docs | PlantUML, Graphviz | PlantUML 1.2026.3 |
| Container | Dockerfile from `phx.gen.release --docker` (hexpm/elixir on Debian trixie slim) plus a `node:24` stage for the frontend | |

`phx.new` 1.8.15 resolves `ecto_sql ~> 3.13` to Ecto 3.14.2 and ecto_sql
3.14.0. The Cloak tests of task 0003 run on these versions and on the pinned
toolchain.

TypeScript 7 is available on npm. The template ships TypeScript 6.0, and the
plan keeps the template version until the toolchain around it (Oxlint,
`@vitejs/plugin-react`, openapi-typescript) is checked against 7.

### Departures from the `sl_vanilla` stack

`sl_vanilla` provides the repository shape (Makefile with `help`, `nix-shell
--run` wrappers, pinned `shell.nix`, multi-stage Dockerfile, compose file,
`.env.example`). Its stack is older, and the plan updates it as follows.

| `sl_vanilla` | Espalier |
|---|---|
| `beam26Packages`, Elixir 1.18, nixpkgs 25.11 | `beam28Packages.elixir_1_20`, nixos-26.05 commit |
| `nodejs_20` with yarn | `nodejs_24` with npm |
| esbuild and Tailwind through Phoenix assets | Vite project in `frontend/`, Tailwind through `@tailwindcss/vite` |
| GraphQL (Absinthe) with JWT (Guardian) | REST with OpenAPI, server-side session with `__Host-` cookie and CSRF defenses |
| `docker-compose` v1 command, `docker-compose.yml` | `docker compose` v2, `compose.yaml` and `compose.dev.yaml` |
| Google Artifact Registry targets | registry-neutral `REGISTRY` variable |
| `postgres:16-alpine` | `postgres:18` |

## 4 Repository layout

```text
.
├── .github/workflows/     CI: `make check` and `make secrets-scan` in GitHub Actions
├── AGENTS.md              generated by phx.new, extended with project rules
├── Makefile               every developer command, each wrapped in nix-shell
├── shell.nix              pinned toolchain (Elixir, Node, PostgreSQL client, PlantUML, Playwright browsers, gitleaks)
├── .env.example           placeholders for every environment variable
├── .env.demo.example      defaults of a demo instance for usability tests (decision D5), secrets left empty
├── compose.yaml           app and database, production-like
├── compose.dev.yaml       PostgreSQL, lldap and Mailpit for development
├── Dockerfile             from phx.gen.release --docker, extended with a frontend stage
├── mix.exs, config/, lib/, priv/, rel/, test/      Phoenix project from phx.new
├── frontend/              Vite project from create-vite (react-ts)
├── content/demo/          neutral demo content pack in English
├── dev/                   lldap bootstrap files and secrets script, test CA generator for LDAPS (dev/ldap-ca/)
├── test/support/dev_oidc/ mock OIDC provider for development and tests (not compiled in prod)
├── test/support/dev_e2e/  seeding routes for end-to-end tests, mounted only with dev routes
└── docs/
    ├── architecture/      PlantUML sources
    ├── plan/              this plan and the task specs
    ├── security/          asvs-l2.md, crypto-inventory.md, key-management.md, authentication.md, logging.md, wax-spike.md
    └── guides/            self-hosting.md, identity-providers.md, content-packs.md, scorm-export.md, security.md, operations.md
```

The Phoenix project sits at the repository root, as in `sl_vanilla`. The
frontend is a sibling directory with its own `package.json`.

## 5 Architecture

### Components

[`context.puml`](../architecture/context.puml) shows the system. The Phoenix
application has two web entry points (`/api` for JSON, `/auth` for the browser
redirects of OIDC sign-in) and one SPA controller that returns `index.html`. The contexts below hold
the business logic. Oban runs scheduled and long-running work.

| Context | Responsibility | Schemas |
|---|---|---|
| `Espalier.Accounts` | Users, sessions, second factors, recovery, role grants, machine clients, bootstrap admin, notifications | `User`, `UserToken`, `ExternalIdentity`, `WebauthnCredential`, `TotpFactor`, `RecoveryCode`, `AuthChallenge`, `FailureCounter`, `RoleGrant`, `ApiClient` |
| `Espalier.Identity` | OIDC providers (`oidcc`), LDAP wrapper (`:eldap`), claim normalization and role mapping | none |
| `Espalier.Vault` | Cloak vault with the strict AES-GCM cipher and the HMAC secret | none |
| `Espalier.Catalog` | Programs and content; pack import, validation, publish | `PackImport`, `Program`, `Station`, `Segment`, `Qualification`, `Requirement`, `Module`, `LearningObjective`, `Lesson`, `Block`, `Rule`, `Item`, `Option`, `Assessment`, `CompanionFormat`, `GlossaryTerm`, `Source`, `Citation` |
| `Espalier.Learning` | Enrollment and path, item evaluation, exam attempts, module completion | `Enrollment`, `ItemResponse`, `AssessmentAttempt`, `ModuleCompletion` |
| `Espalier.Policies` | Policy versions, acknowledgements, approved tool list | `Policy`, `PolicyVersion`, `Acknowledgement`, `ApprovedTool` |
| `Espalier.Credentials` | Requirement evaluation, issue, validity, refresher, attendance, webhooks | `Credential`, `AttendanceCertificate`, `Webhook` |
| `Espalier.Insights` | Anonymous responses, item statistics, reports with group threshold, retention | `SelfAssessmentResponse`, `InterestVote`, `FeedbackResponse`, `ItemStat`, `ParticipationMarker` |
| `Espalier.Interop` | Content pack export, SCORM export | `Export` |
| `Espalier.Audit` | Trail of administrative actions | `AuditEvent` |

### Request flow

- **Development.** `make run` starts Phoenix on port 4000. A Phoenix watcher in
  `config/dev.exs` starts the Vite dev server on port 5173. The browser opens
  `http://localhost:5173`, and Vite proxies `/api`, `/auth` (except the SPA
  route `/auth/finish`) and `/health` to Phoenix. Cookies and OIDC callbacks
  therefore stay on one origin.
- **Production.** `vite build` writes to `priv/static/spa/` with base `/spa/`.
  `Plug.Static` serves the assets, and `SpaController` returns `index.html` for
  every GET route outside `/api`, `/auth` and `/health`.

### Session, cookies and CSRF

Phoenix acts as backend-for-frontend (BFF) in the sense of RFC 10017: the SPA
never sees a token. The browser holds one session cookie that carries an opaque
random session token; the server stores only its SHA-256 hash and the session
state. Section 6.5 lists the cookie attributes, timeouts and the layered CSRF
defense.

### Scopes

`Espalier.Accounts.Scope` carries the current user, roles and the strength of
the current session. It is registered as the default scope in
`config/config.exs`, so that `mix phx.gen.context` and `mix phx.gen.json`
generate user-scoped code for person-linked records. Catalog, policies and
anonymous insights are generated with `--no-scope`.

## 6 Account security

### 6.1 Baseline

| Source | Use in this plan |
|---|---|
| OWASP ASVS 5.0.0 (30 May 2025), Level 2 | Verification target. Selected Level 3 items: 6.3.5 and 6.3.7 (notifications), 6.3.8 (no enumeration), 6.5.6 (every factor revocable), 3.4.8 (COOP), 3.5.8 (Fetch Metadata). |
| NIST SP 800-63B-4 (July 2025), AAL2 | Rules for passwords, OTP, look-up secrets, passkeys, throttling and session timeouts. |
| RFC 9700 (OAuth 2.0 Security BCP, January 2025) | Rules for the OIDC client: PKCE S256, exact redirect URIs, mix-up defense. |
| RFC 10017 (OAuth 2.0 for Browser-Based Applications, August 2026) | BFF rules: confidential client, `Secure` and `HttpOnly` cookies, `SameSite=Strict`, CSRF defense. |
| OpenID Connect Core 1.0 (errata set 2) | ID token validation. |

`docs/security/asvs-l2.md` holds the verification matrix: one row per Level 1
and Level 2 requirement and per selected Level 3 item, with its status, the
code that implements it and the test that proves it, or the reason why it does
not apply. Requirements the platform deviates from are listed in the matrix
with the reason. Task 0003 creates the matrix, 0004 holds the ownership table
that assigns every applicable row to its owning task and to the tasks that
extend it, and every security task updates its rows. The section "Security
requirements" of each task spec lists exactly the rows whose `Task` column
names that task (decision D16), and `test/docs/asvs_matrix_test.exs` checks
this rule in `make check`.

### 6.2 Authentication pathways

ASVS 6.1.3 asks for a documented list of every pathway with consistent
strength. Every pathway ends in the same `log_in` function, which creates the
session and records the methods used.

| Pathway | First step | Second factor | Session strength |
|---|---|---|---|
| Passkey | WebAuthn discoverable credential with user verification | included (user verification) | `mfa`, phishing-resistant |
| Password | password (Argon2id) | TOTP, passkey or recovery code | `mfa` |
| Invitation | single-use e-mail link | enrollment of a passkey, or of a password with TOTP | `enrollment` (enrollment routes only, 30 minutes) until a factor exists |
| Recovery | saved recovery code and a link sent by e-mail | none; the session only allows re-enrollment | `recovery` (30 minutes) |
| OIDC (Entra ID, Google Workspace, other) | identity provider | per provider: local passkey, TOTP or recovery code (`local`, default), or the provider's MFA (`idp_trusted`) | `mfa`; `enrollment` at the first sign-in without a local factor |
| LDAP / Active Directory | directory bind | local passkey, TOTP or recovery code (`local`, the only mode) | `mfa`; `enrollment` at the first sign-in without a local factor |
| Demo (test sessions only) | choice of a pseudonymous account | none | `demo`, flagged on every page |

Rules that apply to every pathway:

1. An e-mail link never opens a full session. Under NIST SP 800-63B-4 e-mail is
   no authenticator, so invitation and recovery links only lead to enrollment.
2. Local accounts cannot exist without a second factor (ASVS 6.3.3). The first
   sign-in after an invitation enrolls one.
3. External identities are keyed by issuer and subject (Entra ID: issuer,
   `tid` and `oid`; Active Directory: `objectGUID`; other LDAP servers:
   `entryUUID`). Accounts are never created or linked
   through e-mail, `preferred_username` or `upn` (ASVS 6.8.1, 10.5.2). Linking
   an external identity to an existing account requires a signed-in session on
   that account with a recent second factor.
4. The `idp_trusted` mode is an operator decision for providers that enforce MFA
   themselves (for example Entra ID Conditional Access). The application logs it
   at boot and records it in the session's methods. When the ID token carries
   `amr`, the session records it; when it does not, the documented fallback is
   the operator's statement (ASVS 6.8.4).
5. Demo accounts and every other pathway share the code path after sign-in.
   `AUTH_DEMO=true` shows a banner on every page and logs a warning at boot.

### 6.3 Libraries

The versions are those of Hex, npm and the upstream repositories on
2026-10-07.

| Purpose | Library | Version | Notes |
|---|---|---|---|
| Account core | `phx.gen.auth` from Phoenix | 1.8.15 | Generated in a reference project and ported (6.4). |
| Password hashing | `argon2_elixir` | ~> 4.1 (4.1.3) | Argon2id with `parallelism: 1`, which avoids the native thread creation reported in upstream issue #73 on this OTP version. Parameters are benchmarked on the production image. |
| Passkeys (server) | `wax_` with `x509` | 0.7.0, x509 ~> 0.9 | The only maintained Elixir WebAuthn library; it leaves several checks to the application (6.6). Task 0005 starts with a spike on the target toolchain. |
| Passkeys (browser) | `@simplewebauthn/browser` | ^14.0.0 | `startRegistration` and `startAuthentication` with conditional UI. |
| TOTP | `nimble_totp`, `eqrcode` | 1.0.0, 0.2.1 | HMAC-SHA-1, 6 digits, 30 seconds, as RFC 6238 defines TOTP by default; `nimble_totp` 1.0.0 offers no other algorithm, and the matrix records HMAC-SHA-1 as a deviation from ASVS 11.4.1 (decision D14). QR code as SVG. |
| OIDC client | `oidcc`, `oidcc_plug`, `jose` | ~> 3.9, ~> 0.5.1, ~> 1.11 | Erlang Ecosystem Foundation, OpenID-certified relying party. 3.9.0 and 0.5.1 are minimums because they fix CVE-2026-75759, CVE-2026-66883 and CVE-2026-66884. |
| LDAP | `:eldap` from OTP | OTP 28.5.0.x (eldap 1.2.16.1) | Own wrapper `Espalier.Identity.Ldap`; no wrapper dependency (6.8). |
| Encryption at rest | `cloak`, `cloak_ecto` | exactly 1.1.4 and 1.3.0 | Only AES-256-GCM through a strict wrapper and HMAC-SHA256 (6.9). |
| Throttling | `hammer` | ~> 7.5 | ETS backend for short windows; durable failure counters live in the database. |
| HTTP client | `req` | ~> 0.7 | Breached-password range queries. |
| Mail | `swoosh`, `gen_smtp` | ~> 1.28, ~> 1.1 | Delivery through Oban, so that response times do not reveal accounts. |
| Test tooling | Mailpit image, `lldap/lldap`, `otpauth` (npm) | v1.31.4, v0.6.3, ^9.5 | |

### 6.4 Account core from `phx.gen.auth`

`mix phx.gen.auth` refuses to run in a project generated with `--no-html`. The
plan therefore generates it in a reference project and ports the result:

1. `make auth-reference` creates `tmp/auth-reference/` (git-ignored) with
   `mix phx.new espalier --module Espalier --binary-id --no-assets
   --no-dashboard --no-install` and runs
   `mix phx.gen.auth Accounts User users --no-live --hashing-lib argon2`.
2. The context layer (`Accounts`, `User`, `UserToken`, `Scope`, `UserNotifier`),
   the migration, the fixtures and the context tests are copied into the API
   project. `UserAuth` is ported to JSON responses. HTML controllers and
   templates are not copied.
3. Every ported module starts with the comment
   `# Derived from phx.gen.auth (Phoenix 1.8.15).` After a Phoenix upgrade,
   `make auth-reference` regenerates the reference, and a diff against the
   previous reference shows fixes that need porting.

The port keeps the security properties of the generator (session renewal and
CSRF token rotation at sign-in, revocable tokens in the database, two-step
consumption of e-mail tokens, token wipe on password change, the pre-stuffing
guard, re-authentication before sensitive changes) and changes these defaults:

| Generator default | Espalier |
|---|---|
| Session tokens stored as plain values | Stored as SHA-256 hashes, like e-mail tokens. |
| Sliding validity of 14 days, reissue after 7 days, remember-me cookie | Inactivity timeout 60 minutes and absolute lifetime 24 hours (`SESSION_IDLE_MINUTES`, `SESSION_MAX_HOURS`); no remember-me cookie; a reissue deletes the previous row in the same transaction. |
| Expired tokens stay in the table | An Oban job purges expired rows daily. |
| Sign-in by e-mail link, valid 15 minutes | E-mail links only for invitation, e-mail change and recovery, valid 10 minutes, token in the URL fragment so it reaches neither server logs nor the Referer header. |
| Open registration that reveals existing addresses | `SIGNUP=closed` by default (`invite` and `domain` as options); every response is identical for known and unknown addresses; mail goes out through Oban. |
| Password 12 to 72 characters, bcrypt | Argon2id; 15 to 128 code points; normalized to Unicode NFC before the length check, the blocklist checks, hashing and verification (NIST SP 800-63B-4 section 3.1.1.2; a documented deviation from ASVS 6.2.8, decision D12); directory passwords go to the LDAP server unchanged; checked against a bundled common-password list, a context-word list and, with `PASSWORD_BREACH_CHECK=hibp`, the Pwned Passwords range API (k-anonymity with padding). When the API is unreachable, the bundled lists still apply. |
| Sudo mode: authenticated within 10 minutes | `require_recent_auth`: a second factor within 10 minutes, recorded on the session row. Applies to e-mail, password and factor changes, recovery codes, session revocation and every admin change. |
| `email` as `citext` with unique index | `email` encrypted with Cloak, `email_hash` (HMAC-SHA256 of the trimmed, lower-cased address) with unique index; `users_tokens.sent_to_hash` stores the hash; the e-mail change token is bound to the user id, and the new address is stored encrypted in `users_tokens.new_email`. |
| No notifications | E-mail to the account on: new factor, removed factor, recovery codes regenerated, password change, e-mail change (to the old address), recovery used, authenticator disabled after the failure limit, sign-in after repeated failures. |

### 6.5 Sessions, cookies and CSRF

| Item | Setting |
|---|---|
| Session cookie | `__Host-espalier`, `Secure`, `HttpOnly`, `Path=/`, no `Domain`, `SameSite=Strict`; `Plug.Session` cookie store with `encryption_salt`, configured in the `/api` router pipelines with the options of `EspalierWeb.TransactionCookie.main_session_options/0`; content: the session token, the CSRF token of `Plug.CSRFProtection`, during sign-in the pending second-factor state, and the id of a running WebAuthn ceremony; no personal data. |
| Sign-in transaction cookie | `__Host-espalier_tx`, same attributes with `SameSite=Lax`, 10 minutes, configured as the `Plug.Session` of the `/auth/oidc` pipeline (`:oidc_transaction`) with the options of `EspalierWeb.TransactionCookie.session_options/0`; holds the data of one OIDC flow (nonce, PKCE verifier, a hash of `state`, peer IP and user agent as stored by `oidcc_plug`, plus provider key, purpose and user id), and the ticket binding until `POST /api/auth/finish` deletes it. The intent token is consumed at the authorization request and is not stored. `EspalierWeb.TransactionCookie` (task 0004) is the only module that reads or writes it outside `Plug.Session`. |
| Session token | 32 bytes from `:crypto.strong_rand_bytes/1`; SHA-256 hash in `users_tokens`; new token at every sign-in, step-up and role change (ASVS 7.2.4). |
| Session row | `strength`, `auth_methods`, `authenticated_at`, `mfa_at`, `provider_key`, `idp_sid_hash`, `idp_amr`, `device_summary` (browser and system family only), `last_seen_at`, `expires_at`. |
| Timeouts | Inactivity 60 minutes, absolute 24 hours (NIST AAL2); enrollment and recovery sessions 30 minutes; checked on the server; cookie expiry is never the only check. A change of manual role grants ends the sessions of that user. |
| Concurrent sessions | At most `SESSION_MAX_CONCURRENT` (default 5) per user; the oldest is ended. |
| Termination | Logout deletes the row. Disabling a user ends all sessions. Users list and end their sessions after re-authentication; admins end the sessions of a user or of all users (ASVS 7.4, 7.5). |
| CSRF | Three layers: (1) `Plug.CSRFProtection` token in the `x-csrf-token` header on every mutating request of the session pipelines (the integration route of task 0013 takes a bearer token and no session cookie); (2) a Fetch Metadata plug that rejects `Sec-Fetch-Site: cross-site` except for the allowlisted navigation endpoints (OIDC callback, `/auth/finish`, front-channel logout in an iframe), with an `Origin` check when the header is missing; (3) the `Strict` session cookie. Sobelow does not flag a JSON pipeline without CSRF protection, so a test covers every mutating route, with the integration route of task 0013 as its only exemption. |
| Strict cookie and redirects | The OIDC callback arrives as a cross-site navigation and never carries the `Strict` cookie. The callback therefore validates the response, stores a single-use sign-in ticket (60 seconds, hashed, bound to a value in the transaction cookie) and redirects to the SPA route `/auth/finish#ticket=<ticket>`. The SPA posts the ticket same-origin to `POST /api/auth/finish`, which sets the `Strict` session cookie and deletes the transaction cookie. Phoenix serves `/auth/finish` through `SpaController`, and the Vite dev proxy excludes it (proxy key `^/auth/(?!finish)`). |
| Headers | Own plug for every response: CSP `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'`, Trusted Types first in report-only mode, `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Resource-Policy: same-origin`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-Content-Type-Options: nosniff`, `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), publickey-credentials-create=(self), publickey-credentials-get=(self)`, `Cache-Control: no-store` on `/api/session`, `/api/auth/*` and `/api/me/*` (task 0004), on `/api/admin/*` (task 0015) and on `/api/facilitator/*`, `/api/registrar/*` and `/api/integration/*` (task 0013), `Vary: Sec-Fetch-Site, Sec-Fetch-Mode, Sec-Fetch-Dest`. HSTS comes from the reverse proxy. |

The `__Host-Http-` prefix from RFC 10017 is not used yet, because Safari does
not support it. The plan revisits it in task 0017.

### 6.6 Passkeys, TOTP and recovery codes

**Passkeys** (`wax_` 0.7.0). Registration and authentication use attestation
`"none"`, `user_verification: "required"` (the exact string; a test asserts the
`:user_not_verified` error), an explicit `rp_id`, an exact origin list and a
300-second timeout. Credentials are discoverable (`residentKey: "required"`),
so the sign-in page offers conditional UI (`autocomplete="username webauthn"`).
The application adds the checks that `wax_` leaves open:

- challenges are stored server-side, single-use, bound to the ceremony and the
  user or the anonymous attempt, and deleted on every outcome;
- after registration, the credential's COSE algorithm must be one of -7, -8 or
  -257 (`wax_` issue #59); -257 (RS256) stays for Windows Hello authenticators,
  which the FIDO metadata lists with RS256 only, and the matrix records it as a
  deviation from ASVS 11.6.1 (decision D13);
- `clientDataJSON` is parsed by the application, and `crossOrigin: true` or any
  `topOrigin` is rejected (`wax_` issue #60);
- authenticator data with backup state set but backup eligibility unset is
  rejected;
- the `userHandle` of an assertion must belong to the account that owns the
  credential;
- a sign count that does not increase is logged as a risk signal;
- every `Wax` call is wrapped, because malformed input raises (`wax_` issue #61).

**TOTP** (`nimble_totp` 1.0.0). A 20-byte secret, encrypted with Cloak (closure
type), activated only after one valid code. Verification accepts the current
and the previous 30-second step and stores the last used step, so that each code
works once (ASVS 6.5.1). This drift window follows RFC 6238, section 5.2, which
recommends at most one past time step as transmission delay, and the matrix
records it as a deviation from the 30-second limit of ASVS 6.5.5 (decision
D15). Codes are HMAC-SHA-1 values (section 6.3, decision D14).

**Recovery codes.** Ten codes of 128 bits each (ASVS 11.5.1), shown once as 26
base32 characters. Stored as HMAC-SHA256 with a key derived from
`CLOAK_HMAC_SECRET` (label `espalier/recovery-codes/v1`) and a `used_at`
column; rotating that secret invalidates all recovery codes. Each code works
once. A code serves as second factor at sign-in, and as saved recovery code in
the recovery pathway. Recovery needs a saved recovery code and a link sent by
e-mail (two methods, NIST SP 800-63B-4 section 4.2), leads only to
re-enrollment, issues a new set of ten codes and resets the failure counters.
Regeneration requires a recent second factor and invalidates all earlier codes.

**Factor management.** Users add and remove passkeys and TOTP after a recent
second factor. The last remaining second factor cannot be removed. A failed
passkey ceremony never falls back to a weaker factor without a visible choice
of the user.

### 6.7 OIDC sign-in

`oidcc` and `oidcc_plug` implement the confidential client. One supervised
`Oidcc.ProviderConfiguration.Worker` per provider refreshes discovery and keys.
[`auth-oidc.puml`](../architecture/auth-oidc.puml) shows the flow.

- Authorization code flow with PKCE S256 (`require_pkce: true`), `state` and
  `nonce` on every request; response mode `query`.
- One redirect URI per provider; the RFC 9207 `iss` parameter is required where
  the provider advertises it (Google). These two measures are the mix-up defense
  (RFC 9700).
- ID token validation per OpenID Connect Core 3.1.3.7 with an algorithm
  allowlist (RS256, PS256, ES256), `aud` equal to the client id (ASVS 10.5.4),
  keys only from the configured issuer. Google and Entra ID list RS256 as their
  only ID token signing algorithm, and the matrix records RS256 as a deviation
  from ASVS 11.6.1 (decision D13).
- The provider's access and refresh tokens are not kept. The platform calls no
  provider API after sign-in.
- **Entra ID.** Single-tenant issuer
  `https://login.microsoftonline.com/<tenant-guid>/v2.0`; `tid` must equal the
  configured tenant; identity key issuer, `tid` and `oid`; roles from App Roles
  (`roles` claim); a groups overage indicator fails the sign-in. Entra's
  discovery document lists neither `code_challenge_methods_supported` nor
  `token_endpoint_auth_signing_alg_values_supported`, so the configuration adds
  both through `quirks.document_overrides`; without the first override, `oidcc`
  drops PKCE without warning. Client authentication uses a certificate
  (`private_key_jwt`) with PS256 assertions, the algorithm that Microsoft
  documents (decision D13); the spike of task 0006 (2026-10-09) showed that
  Entra accepts the key id as `x5t`, the issuer as audience and PS256. Client
  secrets are allowed only in development.
- **Google Workspace.** `hd` must equal the configured domain; identity key
  issuer and `sub`.
- **Linking and step-up.** `POST /api/auth/oidc/:provider/intents` creates a
  single-use intent (5 minutes, bound to the creating session) for linking an
  identity or for a step-up. A step-up for `idp_trusted` users is a new
  authorization request with `max_age=0`, followed by a check of `auth_time`;
  Entra ID sends `auth_time` and `sid` only as configured optional claims, and
  the spike of task 0006 saw no `amr`, so `idp_trusted` mode rests on the
  operator's statement for Entra ID.
- **Logout.** RP-initiated logout through `:oidcc_logout.initiate_url/3` where
  the provider offers an `end_session_endpoint`, with the post-logout redirect
  URI `PUBLIC_URL/signed-out`. `DELETE /api/session` returns the `logout_url`
  for such sessions. Entra ID front-channel logout reaches
  `GET /auth/oidc/:provider/front-channel-logout`, which ends every session
  whose `idp_sid_hash` matches the `sid` parameter. Back-channel logout is out of
  scope; neither `oidcc` 3.9 nor Entra ID offers it.
- **Development.** `test/support/dev_oidc/` contains a mock OIDC provider
  (`Plug.Router` on Bandit, port 4010 in development and 4011 in tests, never
  compiled in production). It signs RS256 ID
  tokens with JOSE, checks PKCE, and offers an Entra-like and a Google-like user
  set plus switches for invalid signature, wrong audience, expired token,
  missing nonce, unknown key id and a groups overage claim. The Entra-like
  profile omits `code_challenge_methods_supported`, so a test covers the
  override.

### 6.8 LDAP and Active Directory sign-in

`Espalier.Identity.Ldap` is a thin wrapper around `:eldap`.
[`auth-ldap.puml`](../architecture/auth-ldap.puml) shows the flow.

- Search, then bind: a read-only service account searches the user
  (`sAMAccountName` or `userPrincipalName` for AD, `uid` for other servers,
  `size_limit: 2`, exactly one result required); the user's bind runs on a new,
  dedicated connection. Both connections close in an `after` block, and a handle
  is never reused after an error or timeout (`:eldap` does not match responses
  by message id).
- LDAPS on port 636 by default; StartTLS as option, always with
  `server_name_indication`; `verify: :verify_peer` with the CA from
  `AUTH_LDAP_CA_CERT_FILE`; TLS 1.2 and 1.3 only. Plain LDAP is refused outside
  dev and test.
- Empty or whitespace-only usernames, DNs and passwords are rejected before any
  call. `:eldap` blocks only the empty charlist; an empty Elixir binary reaches
  the server as an unauthenticated bind, which Active Directory accepts by
  default. A fake LDAP server in the unit tests covers this case.
- Only the bare atom `:ok` from `simple_bind/3` and `start_tls/3` counts as
  success. Every failure returns the same error.
- Disabled AD accounts (`userAccountControl` bit 0x2) are rejected.
- The identity key is `objectGUID`, converted to a UUID (the first three fields
  are little-endian); DN, UPN and `sAMAccountName` are refreshable attributes.
- Role mapping checks each mapped group with the matching rule
  `1.2.840.113556.1.4.1941` (nested groups) on the user's DN.
- Values arrive as byte lists and are converted with `:erlang.list_to_binary/1`.
- Timeouts from `AUTH_LDAP_TIMEOUT_MS` (default 5000) per operation and an
  overall deadline of three times that value per sign-in; no `{log, fun}`
  option, because `:eldap` logs the bind request with the password.
- Failed directory sign-ins answer after a fixed floor of one second, because
  no dummy password check applies.
- The per-username failure limit stays below the directory's own lockout
  threshold.
- Integration tests run against `lldap/lldap:v0.6.3` with LDAPS on port 6360
  and a test CA from `dev/ldap-ca/generate.sh`. lldap has no StartTLS, no nested
  groups and no disabled users; those paths are covered by unit tests with a
  fake server.
  Active Directory specifics (UPN bind, `objectGUID`, `userAccountControl`,
  nested groups) need a Samba AD container and form an optional CI job.

### 6.9 Encryption at rest with Cloak

Cloak protects stored columns against someone who holds a database dump,
replica or backup without the keys.

- **Versions.** `cloak` 1.1.4 and `cloak_ecto` 1.3.0, pinned exactly. Both have
  had no release since April 2024. The advisories EEF-CVE-2026-95105 (AES-CTR)
  and EEF-CVE-2026-94206 (`Cloak.Ecto.PBKDF2`) affect modules the platform does
  not use; `mix.exs` lists them under `hex: [ignore_advisories: [...]]` with that
  reason, and a test fails if any cipher other than the strict GCM wrapper is
  configured.
- **Cipher.** `Espalier.Crypto.StrictAESGCM` wraps `Cloak.Ciphers.AES.GCM`
  with `iv_length: 12` and turns a failed authentication into an error. The
  unwrapped cipher returns `{:ok, :error}` for a tampered value or a wrong key.
- **Keys.** `CLOAK_KEY_V1` and `CLOAK_HMAC_SECRET` (32 random bytes each,
  Base64) come from the environment, are checked at boot, and are kept out of
  the database backups. The vault starts before the Repo.
- **Fields.** `docs/security/crypto-inventory.md` lists every protected column
  and the task that creates it. Encrypted: `users.email`, `users.display_name`,
  `users.org_unit`, `users_tokens.new_email`, `users_tokens.link_identity`,
  `external_identities.subject`, `external_identities.directory_dn`,
  `directory_upn` and `directory_login`, `totp_factors.secret`. Keyed hashes
  (HMAC-SHA256): `users.email_hash`, `users_tokens.sent_to_hash`,
  `users_tokens.idp_sid_hash`, `users_tokens.binding_hash`,
  `external_identities.subject_hash`, `failure_counters.subject_hash`,
  `recovery_codes.code_hmac`. Session tokens, e-mail tokens and API client tokens
  are stored as SHA-256 hashes. No key can restore those values.
- **Key versions.** Each `CLOAK_KEY_V<n>` defines the tag `AES.GCM.V<n>`. The
  highest version encrypts, the others only decrypt.
- **Limits.** No Cloak types inside embedded schemas (Cloak stores them as
  plain JSON). Encrypted columns cannot be sorted or searched in SQL. Residual
  exposures: the keys sit in a protected ETS table that every process on the
  node can read and in crash dumps; the associated data is a constant, so a
  database writer can swap ciphertexts between rows; the ciphertext length
  shows the plaintext length; HMAC columns show equal values. The first
  version has no rotation for `CLOAK_HMAC_SECRET`; a rotation needs a second
  hash column per lookup.
- **Logs.** Ecto logs query parameters before encryption, so the Repo runs
  with `log: false` in production, `Espalier.Telemetry.QueryLog` logs queries
  without parameters, no call site sets its own `log:` option, and telemetry
  handlers drop `params`, `cast_params` and `result`.
- **Rotation.** A new key version is added, `Espalier.Release.rotate_encryption/0`
  re-encrypts rows through the rotation-only schemas
  `Espalier.Crypto.Rotation.<Table>` (each task registers the schemas of its
  tables; they carry no timestamps, so `updated_at` stays unchanged), and the
  old key is removed once `encryption_status/0` reports no row with its tag.
  The runbook is `docs/security/key-management.md`. `mix cloak.migrate.ecto` is not used, because it
  crashes on schemas with `Ecto.Enum` fields.
- **Fallback.** If upstream stays inactive or an advisory affects GCM or HMAC,
  an own Ecto type on `:crypto` that reads the Cloak byte format replaces
  `cloak_ecto`.

### 6.10 Abuse protection, errors and security events

- **Throttling.** Hammer (ETS) limits requests per IP and per account key
  (HMAC of the normalized identifier) on sign-in, e-mail requests, TOTP,
  recovery codes, WebAuthn challenges, OIDC callbacks and LDAP binds, and
  answers 429 with `Retry-After`. Durable counters in the database track
  consecutive failures per account and authenticator: from the fifth failure
  each attempt waits longer (30 seconds, doubling, up to one hour); after 50
  the authenticator is disabled until recovery (NIST limit: 100). A success
  resets the counter.
- **Proxy.** IP-based limits rely on the reverse proxy overwriting
  `X-Forwarded-For`; the application trusts it only from configured proxy
  addresses.
- **Enumeration.** Sign-in, invitation, recovery and e-mail change return the
  same body, status and timing for known and unknown accounts; unknown users
  run a dummy Argon2 verification (ASVS 6.3.8).
- **Parameter filtering.** `:filter_parameters` covers passwords, e-mail
  addresses, codes, tokens, tickets, intents, secrets and WebAuthn payloads.
- **Errors.** JSON errors carry a code and no internals. Shared codes:
  `unauthenticated` (401), `reauth_required` (403, step-up needed),
  `enrollment_required` (403), `csrf` (403), `rate_limited` (429). When an identity
  provider or the directory is unreachable, the sign-in fails closed
  (ASVS 16.5.3).
- **Security events.** Authentication, session, authorization and account
  events use the names of the OWASP Logging Vocabulary (`authn_login_success`,
  `authn_login_fail`, `session_created`, `authz_fail`, `user_updated` and
  others), written as structured JSON with UTC timestamps, factor type and
  provider. Logs never contain passwords, codes, tokens or session ids. Admin
  actions additionally go to `audit_events`.

### 6.11 Roles and configuration

Every signed-in user holds the role `learner`. Role maps per provider add
`facilitator`, `author`, `registrar`, `analyst` or `admin` from claims or
groups. Grants with source `idp_claim` are replaced at every sign-in, and grants
with source `manual` stay. The first admin comes from `BOOTSTRAP_ADMIN_EMAILS`
or from `bin/espalier eval "Espalier.Release.grant_role(\"admin\", \"a@example.org\")"`.
`ADMIN_REQUIRE_PASSKEY=true` (default) requires admins to hold a passkey.

Providers are configured through environment variables, parsed in
`config/runtime.exs`. `AUTH_PROVIDERS` lists the active external providers in
the order of the sign-in page; local accounts are always available unless
`LOCAL_ACCOUNTS=false`. `Espalier.Identity.Config.parse!/2` parses the
`AUTH_*` variables of the providers. `Espalier.RuntimeConfig.parse!/2` parses
the account and session settings of task 0004, and every later task that adds
an application setting outside `AUTH_*` extends that module. The connection
and secret variables (`DATABASE_*`, `SECRET_KEY_BASE`, `CLOAK_*`, `SMTP_*`)
stay in `config/runtime.exs`, and the boot check of task 0017 reports each
required one that is missing. Both modules trim each value,
remove one pair of surrounding double quotes, which `docker run --env-file`
keeps, and stop the boot with a message that names the variable.

```sh
AUTH_PROVIDERS=entra,ldap

AUTH_ENTRA_TYPE=entra
AUTH_ENTRA_LABEL="Microsoft 365"
AUTH_ENTRA_TENANT_ID=
AUTH_ENTRA_CLIENT_ID=
AUTH_ENTRA_CLIENT_CERT_FILE=
AUTH_ENTRA_CLIENT_KEY_FILE=
AUTH_ENTRA_ROLE_MAP="admin=Espalier.Admin;author=Espalier.Author"
AUTH_ENTRA_MFA=local                 # local | idp_trusted
AUTH_ENTRA_PROVISION=true

# AUTH_GOOGLE_TYPE=google, AUTH_GOOGLE_HOSTED_DOMAIN=example.org, AUTH_GOOGLE_CLIENT_ID=, AUTH_GOOGLE_CLIENT_SECRET=
# AUTH_<KEY>_TYPE=oidc, AUTH_<KEY>_ISSUER=, AUTH_<KEY>_CLIENT_ID=, AUTH_<KEY>_CLIENT_SECRET= (task 0006 lists every key)

AUTH_LDAP_TYPE=ldap
AUTH_LDAP_LABEL="Company account"
AUTH_LDAP_HOST=
AUTH_LDAP_PORT=636
AUTH_LDAP_TLS=ldaps                  # ldaps | starttls | none (none only in dev and test)
AUTH_LDAP_CA_CERT_FILE=
AUTH_LDAP_BIND_DN=
AUTH_LDAP_BIND_PASSWORD=
AUTH_LDAP_BASE_DN=
AUTH_LDAP_DIRECTORY=ad                # ad | generic
AUTH_LDAP_USER_ATTR=sAMAccountName,userPrincipalName
AUTH_LDAP_ORG_UNIT_ATTR=department
AUTH_LDAP_ROLE_MAP="admin=CN=espalier-admins,OU=Groups,DC=example,DC=org"
AUTH_LDAP_TIMEOUT_MS=5000
AUTH_LDAP_FAILURE_LIMIT=             # required, below the directory's own lockout threshold
AUTH_LDAP_LOCK_MINUTES=30
AUTH_LDAP_MFA=local

LOCAL_ACCOUNTS=true
SIGNUP=closed                        # closed | invite | domain
SIGNUP_DOMAINS=                      # used with SIGNUP=domain
BOOTSTRAP_ADMIN_EMAILS=
ADMIN_REQUIRE_PASSKEY=true
PASSWORD_BREACH_CHECK=off            # off | hibp
PASSWORD_CONTEXT_WORDS=
TRUSTED_PROXIES=
MAIL_FROM=
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SESSION_IDLE_MINUTES=60
SESSION_MAX_HOURS=24
SESSION_MAX_CONCURRENT=5
AUTH_DEMO=false
PUBLIC_URL=http://localhost:5173
CLOAK_KEY_V1=
# CLOAK_KEY_V2=                      # added during key rotation
CLOAK_HMAC_SECRET=
```

`SIGNUP=closed` allows admin invitations only. `invite` additionally lets an
invited, not yet enrolled account request a new link. `domain` additionally
allows self-service sign-up for addresses in `SIGNUP_DOMAINS`.
`BOOTSTRAP_ADMIN_EMAILS` grants `admin` only to active local accounts holding
that address; an e-mail claim from an identity provider never triggers it.

### 6.12 Shared interfaces between the account tasks

Tasks 0003 to 0007 and 0011 build on each other. The names below are fixed, so
that each task can rely on the others.

| Interface | Owner | Used by |
|---|---|---|
| `Espalier.Vault`, `Espalier.Crypto.StrictAESGCM`, `Espalier.Encrypted.Binary`, `Espalier.Encrypted.Map`, `Espalier.Encrypted.ClosureBinary`, `Espalier.Hashed.HMAC`, `Espalier.Crypto.Rotation`, `docs/security/crypto-inventory.md`, `docs/security/asvs-l2.md` | 0003 | every task with protected columns registers its rotation schemas and inventory rows |
| `users`, `users_tokens`, `external_identities`, `failure_counters`, `role_grants`, `api_clients`, `audit_events` | 0004 | 0005, 0006, 0007 add columns through their own migrations; 0007 makes `failure_counters.user_id` nullable for directory counters |
| `EspalierWeb.UserAuth.log_in_user/3` with `auth_methods:` and `strength:`, `put_reissued_session/2`, `require_authenticated_user/2`, `require_recent_auth/2` (403 `reauth_required`), the pending second-factor state with `put_pending_second_factor/3` and `fetch_pending_second_factor/1`, the `:enrollment` pipeline | 0004 | 0005, 0006, 0007 |
| `EspalierWeb.TransactionCookie` (`main_session_options/0`, `session_options/0`, `fetch/1`, `get/2`, `put/3`, `delete/2`, `clear/1`, `read_main_session/1`); the router of 0004 reads both option sets | 0004 | 0006 (`get/2`, `clear/1`, `read_main_session/1`), 0017 (checks `session_options/0` in the container) |
| `GET /auth/providers` (`ProviderController`, pipeline `:auth_bare`), `Espalier.Identity.Config.parse!/2` with `public_entry/1`; application env `:identity_providers` (full structs) and `:auth_providers` (public entries with `key`, `type`, `kind`, `label`, `start_url`) | 0004 | 0006 adds the types `entra`, `google`, `oidc`; 0007 adds `ldap` |
| `Espalier.RateLimit`, `EspalierWeb.Plugs.RateLimit` with `check_account/3`, `Espalier.Accounts.FailureCounters`, `Espalier.SecurityLog.event/3`, `Espalier.Accounts.UserNotifier` through Oban, `Espalier.RuntimeConfig` | 0004 | all account tasks; `Espalier.RuntimeConfig` also 0009 and 0013 to 0017, and the rate limiter also 0009 and 0014 |
| Second factors, `POST /api/auth/second-factor`, `POST /api/me/reauth`, `Accounts.enrolled?/1`, `Accounts.Factors.complete_enrollment/3`, recovery | 0005 | 0006, 0007, 0011, 0015 |
| `Accounts.sign_in_external/2`, `link_external_identity/3`, `deliver_identity_linked/2`, `POST /api/auth/finish`, `POST /api/auth/oidc/:provider/intents` | 0006 | 0007, 0011 |
| Answers of `POST /api/auth/finish` and of the LDAP sign-in: `{"next": "second_factor"}`, `{"next": "enroll_second_factor"}`, or the session payload of `GET /api/session` for a full session (with `"linked": true` after a link) | 0006, 0007 | 0011 |
| Mail link formats: `/invite#token=`, `/recover#token=`, `/account/email/confirm#token=`; post-logout page `/signed-out` | 0004, 0005, 0006 | 0011 |
| OpenAPI operations: routes of 0004 and the learner routes of 0009 | 0009 | 0010, 0011 |
| OpenAPI operations: routes of 0005, 0006 and 0007 | 0011 | 0015 |
| OpenAPI operations: routes of 0013, 0014, 0015 and 0016 | each of these tasks for its own routes | the SPA |

## 7 Domain rules

The class diagrams are [`domain-catalog.puml`](../architecture/domain-catalog.puml),
[`domain-records.puml`](../architecture/domain-records.puml) and
[`domain-values.puml`](../architecture/domain-values.puml). The learner flow is
[`learner-journey.puml`](../architecture/learner-journey.puml). The rules below
each get at least one test.

1. **Path.** A program offers segments in its self-assessment station. Each
   segment has a default path (`short` or `full`). The SPA preselects the path
   from the chosen segment, and the learner can switch it. The enrollment
   stores the path and a flag for a manual choice. It never stores the segment.
2. **Collapsed explanations.** A block lists the paths on which it starts
   collapsed. A module with `single_path: true` ignores the path.
3. **Reveal on wrong answer.** An item lists lessons whose explanations expand
   when the answer is wrong on the short path. The API returns these lesson ids
   in the feedback, and the player expands them.
4. **Server-side evaluation.** In the platform, answer keys and per-option
   feedback stay on the server until the learner submits. The response returns
   correctness, feedback for every option and the referenced rules.
5. **Pass rule.** An exam attempt fails with `failed_core` when a core item is
   wrong, fails with `failed_errors` when more than `max_wrong` answers are
   wrong, and passes otherwise. A new attempt is always possible.
6. **Requirements.** A qualification lists requirements of five kinds:
   `module_completed`, `assessment_passed`, `policy_acknowledged`, `attendance`
   and `qualification_held`. `Credentials.evaluate/2` runs after every event
   that can satisfy a requirement and issues the credential when all are met.
7. **Validity and refresher.** [`credential-lifecycle.puml`](../architecture/credential-lifecycle.puml)
   defines the states. A daily Oban job moves credentials to `refresh_due`
   (notice period reached) and to `expired` (grace period passed). Publishing a
   policy version with `requires_refresher: true` moves every credential whose
   qualification requires that policy to `refresh_due`. The refresher mode of
   the qualification decides what restores `active`: the module flagged
   `refresher_unit`, a full run of all requirements, or the exam alone.
8. **Placeholders and policies.** A block of kind `placeholder` renders the
   current version of the policy named by `placeholder_key`. Until a policy
   version exists, the block shows its placeholder text with the `placeholder`
   badge. The approved tool list is a maintained table with status, conditions
   and review date.
9. **Glossary.** Markdown uses `[[term:slug]]` or `[[term:slug|label]]`. The
   player renders a button with an accessible short explanation that links to
   the glossary entry.
10. **Handbook.** `GET /api/programs/:slug/handbook` returns every rule with its
    statement and action, plus the policy placeholders. The SPA renders a
    printable page.
11. **Companion formats.** Learners mark interest in a format anonymously.
    Facilitators issue attendance certificates for sessions held outside the
    platform. Formats with `attendance_counts: true` can satisfy requirements.
12. **Feedback station.** The questions come from the content pack. Answers are
    stored anonymously, and a participation marker prevents double counting.
13. **Test session notes.** For usability tests, the SPA can log the learner's
    interactions in the browser and export them as text. The log never reaches
    the server. The feature is off unless `TEST_NOTES=true`.
14. **Constructive alignment per topic.** A topic is a module. Its
    `objectives.yaml` declares learning objectives, each with a statement
    ("Learners can ..."), one CORE competence area (`subject`, `method`, `self`,
    `social`), a depth (`know`, `apply`, `judge`), a phase of the five-phase arc,
    optionally one of the module's content domains, and the lessons that teach
    it. Items and companion formats name the objectives they practise or provide
    evidence for. The pack validator applies four checks:
    1. every objective has at least one teaching lesson and at least one piece
       of evidence: an item of an assessment, a practice item with a correct
       answer (every kind except `poll`), a checklist drill, or a companion
       format whose attendance counts;
    2. every item in an assessment that counts for a credential provides
       evidence for at least one objective;
    3. every module covers all four competence areas, or its `module.yaml`
       names each missing area with the place where it is covered
       (`areas_elsewhere`, for example social competence in a companion format);
    4. the kind of evidence fits the depth (`know`: single or multiple choice;
       `apply`: slot builder, classification, checklist drill; `judge`:
       classification with a case comparison, or a companion format); a
       mismatch is a warning.
    `pack.yaml` sets `alignment: strict` (default; checks 1 to 3 are errors) or
    `warn`. `mix espalier.alignment PATH` and the alignment section of the pack
    page in the admin area (task 0015) show the alignment matrix: topic by
    competence area by depth, with objectives, activities and evidence.
15. **Objectives in the journey.** A module station opens with the objectives of
    the topic, grouped by competence area. At module completion the station shows
    which objectives have evidence. The server derives the status `evidenced`
    from the learner's own records on the evidence linked to the objective: a
    passed attempt of an exam that holds a linked item, an attendance
    certificate for a linked format and, with `TRACKING_DETAIL=standard`, a
    correct practice answer to a linked evidence item. The SPA adds the status
    `practised` from the practice state, which stays in the browser with
    `TRACKING_DETAIL=minimal` and comes from the progress answer with
    `standard`. No table stores a status per objective and person. The
    competence report (task 0014) groups item statistics by competence area and
    depth through the objectives, and the SCORM export writes the objectives of
    a module to `cmi.objectives`.

## 8 API outline

All routes under `/api` return JSON and are described in the OpenAPI document
at `/api/openapi`. The frontend generates its types from that document.

| Area | Method and path | Role |
|---|---|---|
| Session | `GET /api/session` (user, roles, session strength, CSRF token, providers, flags), `DELETE /api/session` | public / signed in |
| Local sign-in | `POST /api/auth/passkey/options` (purpose `sign_in`, `second_factor` or `reauth`), `POST /api/auth/passkey`, `POST /api/auth/password`, `POST /api/auth/second-factor` (TOTP, passkey or recovery code), `POST /api/auth/finish` (OIDC ticket) | public |
| Invitation and recovery | `POST /api/auth/invitations` (self-service, `SIGNUP=invite` or `domain`), `POST /api/auth/invitations/accept`, `POST /api/auth/recovery/start`, `POST /api/auth/recovery/verify` | public |
| External sign-in | `GET /auth/providers`, `GET /auth/oidc/:provider`, `GET /auth/oidc/:provider/callback`, `GET /auth/oidc/:provider/front-channel-logout`, `POST /api/auth/oidc/:provider/intents`, `POST /api/auth/ldap/:provider`, `POST /api/auth/demo` | public (intents: signed in) |
| Account | `GET /api/me/security`, `POST /api/me/passkeys/options`, `POST /api/me/passkeys`, `DELETE /api/me/passkeys/:id`, `POST /api/me/totp`, `POST /api/me/totp/confirm`, `DELETE /api/me/totp`, `POST /api/me/recovery-codes`, `PUT /api/me/password` (`current_password`, `password`), `PUT /api/me/email`, `POST /api/me/identities/ldap/:provider`, `POST /api/me/email/confirm`, `GET /api/me/sessions`, `DELETE /api/me/sessions/:id`, `POST /api/me/reauth` | signed in (changes need a recent second factor) |
| Catalog | `GET /api/programs`, `GET /api/programs/:slug`, `GET /api/modules/:id`, `GET /api/programs/:slug/glossary`, `GET /api/programs/:slug/handbook` | learner |
| Learning | `POST /api/enrollments`, `PATCH /api/enrollments/:id`, `POST /api/items/:id/responses`, `POST /api/assessments/:id/attempts`, `POST /api/modules/:id/completion`, `GET /api/me/progress` | learner |
| Learner records | `GET /api/me/requirements`, `GET /api/me/participation` | learner |
| Policies | `GET /api/policies`, `POST /api/policy-versions/:id/acknowledgements`, `GET /api/approved-tools` | learner |
| Credentials | `GET /api/me/credentials`, `GET /api/me/credentials/:id` | learner |
| Insights | `POST /api/self-assessments`, `POST /api/formats/:id/votes`, `POST /api/feedback` | learner |
| Attendance | `POST /api/facilitator/user-lookups` (address in the body), `POST /api/formats/:id/attendance` | facilitator |
| Registrar | `GET /api/registrar/credentials` (only with `REGISTRAR_ENABLED=true`) | registrar |
| Reports | `GET /api/insights/self-assessment`, `GET /api/insights/items`, `GET /api/insights/competence`, `GET /api/insights/formats`, `GET /api/insights/feedback`, `GET /api/insights/credentials` | analyst |
| Administration | `POST /api/admin/packs`, `GET /api/admin/packs/:id`, `GET /api/admin/packs/:id/diff`, `POST /api/admin/packs/:id/publish`, CRUD on `/api/admin/policies`, `/api/admin/policy-versions`, `/api/admin/approved-tools`, `/api/admin/role-grants`, `/api/admin/api-clients`, `/api/admin/webhooks`, `/api/admin/users` (invite, resend invitation, disable, end sessions, reset factors, reset failure counters), `POST /api/admin/user-lookups` (address in the body), `DELETE /api/admin/sessions` (all users), `POST /api/admin/credentials/:id/revoke`, `GET /api/admin/audit` | author / admin (changes need a recent second factor) |
| Exports | `POST /api/admin/exports`, `GET /api/admin/exports/:id`, `GET /api/admin/exports/:id/download` | author |
| Integration | `POST /api/integration/credential-lookups` (machine token, scope `credentials:read`, address in the body) | machine client |
| Health | `GET /health` | public |

## 9 Frontend

### Structure

```text
frontend/src/
├── main.tsx
├── app/          router, providers, layout, error boundaries
├── api/          openapi-fetch client, generated schema.d.ts, query hooks
├── auth/         session hook, sign-in (passkey with conditional UI, password and second factor, providers, LDAP, demo), invitation, recovery
├── account/      security settings: passkeys, TOTP, recovery codes, password, e-mail, sessions, step-up dialog
├── learner/      program overview, stations, module view, exam, credential, handbook, formats, feedback
├── admin/        packs, preview, exports, users, policies, approved tools, roles, API clients, webhooks, audit, attendance, reports, registrar list
├── player/       content renderer: blocks, items, glossary terms, provenance badges, path logic
├── runtimes/     platform.ts, scorm12.ts, scorm2004.ts, standalone.ts
├── i18n/         en.json, de.json
└── styles/       app.css (Tailwind import, theme tokens, print rules)
```

### Admin area

The admin area under `/admin` serves every role beyond `learner`. Its guard
admits `author`, `admin`, `facilitator`, `analyst` and `registrar` (task 0010),
and each section appears only for its role (task 0015). Authors see packs and
exports. Admins see users, policies, approved tools, roles, API clients,
webhooks and the audit log. Facilitators see the attendance page, analysts see
the reports of task 0014, and registrars see the credential list at
`/admin/registrar`. While `REGISTRAR_ENABLED=false`, the registrar route answers
404 (task 0013), and the registrar page states that the list is switched off.
The guards decide what the SPA shows, and the server checks every role.

### Runtime adapter

The player depends on one interface. The platform build uses
`PlatformRuntime`, the SCORM build uses `Scorm12Runtime` or `Scorm2004Runtime`,
and the admin preview uses `StandaloneRuntime`.

```ts
export interface Runtime {
  loadProgram(slug: string): Promise<ProgramView>;
  submitItem(itemId: string, answer: Answer): Promise<ItemFeedback>;
  submitAssessment(assessmentId: string, answers: Record<string, Answer>): Promise<AttemptResult>;
  completeModule(moduleId: string): Promise<void>;
  loadState(): Promise<ResumeState | null>;
  saveState(state: ResumeState): Promise<void>;
}
```

### UI conventions

- Tailwind default palette with neutral grays. One accent token
  (`--color-accent-*` in `@theme`) is the only place an adopter changes color.
- Dark mode through the `dark:` variant, following the system preference with a
  toggle stored in `localStorage`.
- `@tailwindcss/typography` renders Markdown prose.
- Headless UI provides `Disclosure` (collapsible explanations), `RadioGroup`,
  `Dialog`, `Tabs` and `Listbox`.
- Station changes move focus to the station heading. Every interactive element
  is reachable by keyboard. The target is WCAG 2.2 AA, checked with axe in
  component tests and Playwright.
- Credential and handbook pages have print styles.
- UI strings exist in English and German. Content language comes from the pack.

## 10 Record separation and data protection settings

The legal assessment under the GDPR follows in a separate workstream after the
first version. It covers the records of processing, the data protection impact
assessment, the retention periods, the note on the breached-password range
query, the org unit in anonymous rows and the data protection guide for
operators. Until then the mechanisms below exist with data-sparing defaults,
and the retention variables are unset, which disables automatic deletion of
learning records.


| Variable | Default | Effect |
|---|---|---|
| `TRACKING_DETAIL` | `minimal` | `minimal` stores per person only enrollment and path, module completion, exam attempt outcomes, acknowledgements, attendance and credentials; practice answers feed `ItemStat` only, and resume state stays in the browser. `standard` adds `ItemResponse` rows (correctness and attempt number) for resume across devices. Raw answers are never stored per person. |
| `REGISTRAR_ENABLED` | `false` | Enables the per-person credential list for the registrar role (`GET /api/registrar/credentials` and the page `/admin/registrar`). |
| `INSIGHTS_MIN_GROUP_SIZE` | `5` | Reports suppress every cell with fewer responses or people. |
| `INSIGHTS_ORG_UNIT` | `false` | Stores the org unit in anonymous rows. Without it, reports break down by program and month only. |
| `RETENTION_ATTEMPTS_DAYS` | unset | Deletes exam attempts older than the limit, keeping the newest passed attempt that a credential depends on. |
| `RETENTION_ITEM_RESPONSES_DAYS` | unset | Deletes `ItemResponse` rows. |
| `RETENTION_ANONYMOUS_DAYS` | unset | Deletes anonymous insight rows. |
| `RETENTION_AUDIT_DAYS` | unset | Deletes audit events. |

| Data | Learner (own) | Facilitator | Registrar | Analyst | Admin |
|---|---|---|---|---|---|
| Enrollment, path, completion, attempts | yes | no | no | no | no |
| Credentials | yes | no | list, if enabled | aggregated | revoke only |
| Acknowledgements | yes | no | no | no | no |
| Attendance certificates | yes | issue only | no | no | no |
| Anonymous insights | no | no | no | aggregated | no |
| Audit events | no | no | no | no | yes |

The table lists the access that the routes of section 8 grant. The registrar
list holds display name, org unit, status, issue date and validity per person
for one qualification. A facilitator issues certificates and receives one
result per person (`issued`, `exists` or `not_found`). No route lists the
certificates that a facilitator has issued. The analyst reports aggregate the
anonymous rows (self-assessments, item statistics, format votes, feedback) and
count credentials per qualification and status, and every cell below
`INSIGHTS_MIN_GROUP_SIZE` is suppressed. No report covers enrollments, module
completions, exam attempts, acknowledgements or attendance certificates.

Anonymous rows carry a date with day precision, a random primary key and no
user key. A `ParticipationMarker` records that a person has answered, without the
answer and without a timestamp. The nightly retention job reorders the anonymous
tables by their random primary key (`CLUSTER`), so that the physical insertion
order cannot be matched with the order of the markers.

The anonymity holds against every role of the application. A database
administrator who reads the tables between two reorder runs, the write-ahead log
or a backup can still correlate insertion order. Operators who need protection
against that restrict database access accordingly; the GDPR workstream documents
this limit for operators.

## 11 Interoperability

### Content packs

```text
content/demo/
├── pack.yaml              schema version, key, title, locale, license, version, alignment
├── sources.yaml
├── glossary.yaml
├── segments.yaml
├── stations.yaml
├── qualifications.yaml
├── formats.yaml
├── feedback.yaml
└── modules/
    ├── 01-basics/
    │   ├── module.yaml      number, title, summary, phases, domains, single_path, refresher_unit, areas_elsewhere
    │   ├── objectives.yaml  learning objectives: key, statement, area, depth, phase, domain, taught_in
    │   ├── rules.yaml
    │   ├── items.yaml
    │   ├── assessment.yaml
    │   └── lessons/
    │       ├── 01-first-lesson.md
    │       ├── 02-second-lesson.md
    │       └── 03-third-lesson.md
    └── 02-checking/         module.yaml, objectives.yaml, rules.yaml, items.yaml, lessons/01-first-lesson.md, lessons/02-second-lesson.md (no exam, so no assessment.yaml)
```

A lesson file has YAML front matter (`title`, `position`) and a body of
container directives. Each top-level directive becomes one block.

```markdown
---
title: What a language model does
position: 1
---

:::text{provenance=invented}
A [[term:llm|language model]] continues text.
:::

:::explanation{collapsed_on=short provenance=sourced cite="vendor-guide#Overview"}
The next word follows from probabilities learned in training.
:::

:::placeholder{key=input-rules}
Your organization adds its rules for inputs here.
:::
```

An objective lists the lessons that teach it, and items and companion formats
list the objectives they serve. A module names in `areas_elsewhere` each
competence area that its own objectives leave out. The excerpts below use keys
of the demo pack (task 0008, step 12):

```yaml
# modules/01-basics/module.yaml (excerpt)
number: 1
domains: [drafting, research]

# modules/01-basics/objectives.yaml (excerpt)
- key: m1-subject-varying-answers
  statement: Learners can explain why the same prompt can produce different answers.
  area: subject
  depth: know
  phase: understand
  domain: drafting
  taught_in: [02-second-lesson]

# modules/02-checking/module.yaml (excerpt)
number: 2
areas_elsewhere:
  self:
    where: format:workshop
    reason: The workshop practises deciding which of one's own tasks an assistant may support.
  social:
    where: format:workshop
    reason: The workshop practises agreeing in a team how the use of an assistant is made visible.

# modules/02-checking/objectives.yaml (excerpt)
- key: m2-method-release-check
  statement: Learners can run the release checks on a generated text and confirm them with their initials.
  area: method
  depth: apply
  phase: anchor
  taught_in: [02-second-lesson]

# modules/02-checking/items.yaml (excerpt)
- key: m2-release-drill
  kind: checklist_drill
  objectives: [m2-method-release-check]

# formats.yaml (excerpt)
- key: workshop
  attendance_counts: true
  objectives: [m1-self-own-responsibility, m1-social-team-transparency]
```

The importer validates every file with embedded Ecto schemas, checks the
alignment (domain rule 14) and reports errors and warnings with file and line.
A successful import is stored as a draft `PackImport` with the validated pack as
JSON. The admin previews the draft in the browser through `StandaloneRuntime`.
Publishing applies the draft to the live tables in one transaction and upserts
rows by stable keys (`module.number`, `item.key`, `objective.key`,
`rule.number`, `source.key`); rows whose keys are missing from the new version
receive `archived_at`. `mix espalier.import PATH` and the admin
upload use the same code path. `mix espalier.export SLUG PATH` writes a pack
back to disk.

Content packs of an adopting organization live in that organization's own
repository. This repository ships the neutral demo pack only.

### SCORM export

[`scorm-export.puml`](../architecture/scorm-export.puml) shows the flow. The
frontend has a second Vite build (`vite.scorm.config.ts`) that bundles the player
with the SCORM runtimes into `priv/scorm_player/`. The export worker writes
`content.json` with answer keys, copies the bundle, writes `imsmanifest.xml` for
SCORM 1.2 or SCORM 2004 4th edition, and zips the package. One module becomes
one SCO, and its learning objectives become `cmi.objectives` entries with the
status of their evidence in the package. The resume state uses a compact encoding that fits the 4,096 characters
of `cmi.suspend_data` in SCORM 1.2.

The person-linked report of the receiving LMS (learner id, status, score, time)
is a property of SCORM and happens outside this platform. The export contains no
anonymous insights.

### Integration API and webhooks

Machine clients authenticate with a bearer token (stored as a hash, scoped).
`POST /api/integration/credential-lookups` with `{"email": ...}` in the body
returns the credentials in force (status `active` or `refresh_due`) with their
status, unlocked tasks and validity. The address travels in the body, so no
URL carries it (ASVS 14.2.1). The route runs without the session cookie, the
CSRF layer and the Fetch Metadata plug, because a bearer token in the
`authorization` header is its only credential and a browser never sends a
bearer token by itself (task 0013). Webhooks go only to hosts and ports that
the operator lists in `WEBHOOK_ALLOWED_HOSTS` (ASVS 1.3.6). Webhooks send `credential.issued`,
`credential.refresh_due`, `credential.expired` and `credential.revoked` as JSON,
signed with HMAC-SHA256 in the header `x-espalier-signature`. Webhook secrets
come from environment variables. Binding a credential to a permission in another
system stays the decision of the operating organization.

## 12 Build, run and deploy

### Makefile

The Makefile follows `sl_vanilla`: `.POSIX`, a `help` target that lists every
target with its `##` comment, and `nix-shell --run` around every toolchain call.

| Target | Command inside nix-shell |
|---|---|
| `make init` | `mix deps.get`, `npm --prefix frontend ci`, `mix compile` |
| `make services-up` / `services-down` | `docker compose -f compose.dev.yaml up -d --wait` / `down` (PostgreSQL, Mailpit, lldap) |
| `make auth-reference` | regenerates the `phx.gen.auth` reference project in `tmp/auth-reference/` (`PHX_NEW_VERSION`, default 1.8.15) |
| `make gen-keys` | prints new values for `CLOAK_KEY_V1` and `CLOAK_HMAC_SECRET` |
| `make argon2-bench` | runs `Argon2.Stats` to choose the hashing parameters |
| `make ldap-ca`, `make ldap-secrets`, `make services-seed` | create the LDAPS test CA and the lldap secrets, and seed lldap |
| `make dev-oidc` | starts the mock OIDC provider on port 4010 (also started by `make run` in dev) |
| `make setup` | `init`, then `mix ecto.setup`, `mix espalier.import content/demo` and `mix espalier.seed_demo` |
| `make run` | `iex -S mix phx.server` (starts Vite through the watcher) |
| `make refresh-db` | `mix do ecto.drop, ecto.create, ecto.migrate`, the demo import and `mix espalier.seed_demo` |
| `make lint` | `mix format`, `npm --prefix frontend run lint -- --fix`, Prettier write |
| `make check` | format check, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix sobelow --config --exit`, `mix hex.audit`, `mix deps.audit`, `mix deps.unlock --check-unused`, `mix test`, the `api-types` diff check, `tsc -b`, Oxlint, Prettier check, `vitest run`, `npm run build:scorm`, `npm audit --omit=dev` |
| `make test` | `mix test` with `DATABASE_PORT` from `.env`, and `npm --prefix frontend run test -- --run` |
| `make test-integration` | `mix test --only ldap --only mail` with `DATABASE_PORT` from `.env`, against the dev services |
| `make e2e` | Playwright against `make run` |
| `make api-types` | `mix openapi.spec.json --spec EspalierWeb.ApiSpec` into `frontend/openapi.json`, then `openapi-typescript` into `frontend/src/api/schema.d.ts` |
| `make docs` | PlantUML to `docs/architecture/out/` |
| `make secrets-scan` | `gitleaks detect` |
| `make docker-build` | `docker build -t $(IMAGE):$(TAG) .` |
| `make docker-up` / `docker-down` / `docker-logs` | `docker compose` on `compose.yaml` |
| `make docker-migrate` | `docker compose exec app bin/migrate` |
| `make smoke` | starts the production image with demo sign-in and runs a smoke test |
| `make demo-env` / `make demo-up` | write `.env.demo` from `.env.demo.example` with generated secrets / start a demo instance with the demo content |
| `make release-push` | tag and push to `$(REGISTRY)` |

### Container

`mix phx.gen.release --docker` generates the Dockerfile, `rel/overlays/bin/server`,
`rel/overlays/bin/migrate` and `lib/espalier/release.ex`. The plan adds a first
stage `FROM node:24-trixie-slim AS frontend` that runs `npm ci` and both Vite
builds, and the builder stage copies `priv/static/spa` and `priv/scorm_player`
from it before `mix release`. The runner image stays as generated (Debian slim,
user `nobody`).

`compose.yaml` runs `postgres:18` and the app image with a health check, reading
`.env`. `compose.dev.yaml` runs `lldap/lldap:v0.6.3` and
`axllent/mailpit:v1.31.4` with fixed local ports, and `postgres:18` on
`127.0.0.1` at `DATABASE_PORT`. `.env.example` sets 5433, so that a PostgreSQL
installed on the host keeps port 5432. The mock OIDC provider runs inside the
Phoenix application in dev and test.

## 13 Quality gates

A task is done when `make check` passes and its acceptance checks pass.
Security tasks are done when, in addition, their rows in
`docs/security/asvs-l2.md` name the code and the test for each requirement.
CI runs in GitHub Actions (`.github/workflows/ci.yml`): one job on
`ubuntu-24.04` installs Nix, runs `make check` and `make secrets-scan` inside
the pinned `nix-shell`, and reaches a `postgres:18` service container on
`localhost:5432`. CI installs Hex 2.5.1 or later, because `mix hex.audit`
reports advisories and honors `ignore_advisories` only from that version.
`mix.exs` sets `hex: [cooldown: "7d"]`, so that a dependency release is used
only after seven days. The commands are the same in any runner that has Nix.

The maintainer keeps a local deny-list of organization and project names
outside the repository and runs it as a pre-push hook. The repository contains
no copy of that list.

## 14 Milestones and tasks

| # | Task | Milestone | Depends on |
|---|---|---|---|
| 0001 | [Bootstrap the repository with the standard generators](tasks/0001-bootstrap.md) | M0 Foundation | none |
| 0002 | [Quality gates, CI and open-source files](tasks/0002-quality-ci-oss.md) | M0 Foundation | 0001 |
| 0003 | [Encryption at rest with Cloak](tasks/0003-encryption-at-rest.md) | M1 Accounts | 0001 |
| 0004 | [Accounts and sessions from phx.gen.auth](tasks/0004-accounts-sessions.md) | M1 Accounts | 0002, 0003 |
| 0004a | [Sync the task specs with task 0004](tasks/0004a-spec-sync.md) | M1 Accounts | 0004 |
| 0005 | [Second factors: passkeys, TOTP and recovery codes](tasks/0005-second-factors.md) | M1 Accounts | 0004, 0004a |
| 0006 | [OIDC sign-in with oidcc and the mock provider](tasks/0006-oidc.md) | M1 Accounts | 0005 |
| 0007 | [LDAP and Active Directory sign-in](tasks/0007-ldap.md) | M1 Accounts | 0006 |
| 0008 | [Catalog schemas, content pack importer and demo pack](tasks/0008-catalog-content-packs.md) | M2 Content | 0001, 0004a |
| 0009 | [Learner API with OpenAPI](tasks/0009-learner-api.md) | M3 Learning | 0004, 0004a, 0008 |
| 0010 | [Frontend shell: Tailwind, routing, i18n, API client](tasks/0010-frontend-shell.md) | M3 Learning | 0004, 0004a |
| 0011 | [Account UI: sign-in, enrollment, recovery and security settings](tasks/0011-account-ui.md) | M3 Learning | 0007, 0009, 0010 |
| 0012 | [Player and learner UI](tasks/0012-player-learner-ui.md) | M3 Learning | 0009, 0010 |
| 0013 | [Policies, credentials, attendance, refresher and integration API](tasks/0013-policies-credentials.md) | M4 Records | 0009, 0010, 0012 |
| 0014 | [Anonymous insights, reports and retention](tasks/0014-insights.md) | M4 Records | 0012, 0013 |
| 0015 | [Admin area](tasks/0015-admin-area.md) | M5 Administration | 0011, 0012, 0013, 0014 |
| 0016 | [SCORM 1.2 and 2004 export, and pack export](tasks/0016-scorm-export.md) | M6 Interop and operations | 0012, 0015 |
| 0017 | [Production image, guides and hardening](tasks/0017-production-hardening.md) | M6 Interop and operations | 0002, 0015, 0016 |

0007 follows 0006, because it reuses the external-identity functions of 0006.
0004a carries the implemented interfaces of 0004, the ASVS scan rows and the
decisions D13 to D17 into the specs of the later tasks. 0008 and 0010 can
start as soon as 0004a is done.

Each task has a GitHub issue under its milestone, and
[`tasks/EPIC.md`](tasks/EPIC.md) records the issue and status of every task.

## 15 Decisions

| # | Decision | Status |
|---|---|---|
| D1 | Project name | Decided: Espalier (module `Espalier`, app `:espalier`). A tree trained along a frame stands for guided growth without ranking. On 2026-10-07 the name was free on Hex, and no GitHub learning project used it. |
| D2 | License | Decided: Apache-2.0. |
| D3 | Public repository host | Decided: a public GitHub repository is the only host. It runs CI with GitHub Actions and accepts issues and pull requests (task 0002). |
| D4 | Entra ID test tenant | Decided: a test tenant is provided before the spike in 0006. The spike checks the key id and audience of the client assertion, PS256 against RS256, whether `max_age=0` forces re-authentication, whether the ID token carries `auth_time`, `amr` and `sid`, and the query parameters of front-channel logout. Done on 2026-10-09 in a Microsoft 365 business tenant of the maintainer; the identity provider guide records the results. |
| D5 | Defaults for demo instances | Decided: `TRACKING_DETAIL=minimal`, `REGISTRAR_ENABLED=false`, `AUTH_DEMO=true`, no external identity provider. `.env.demo.example` holds these values, and `make demo-env` and `make demo-up` start a demo instance (task 0017). |
| D6 | SAML | Later: a SAML adapter only when an adopter needs it. |
| D7 | TypeScript 7 | Later: evaluate after 0012, once the frontend has tests. |
| D8 | MFA for federated users | Decided: default `local` (passkey, TOTP or recovery code after the provider). `idp_trusted` per provider when the operator confirms that the provider enforces MFA. |
| D9 | Session numbers | Decided: inactivity 60 minutes, absolute 24 hours, five concurrent sessions. A longer absolute lifetime is a documented deviation from NIST AAL2 and ASVS 7.1.1. |
| D10 | Breached-password check | Decided: `PASSWORD_BREACH_CHECK=off` with the bundled lists. `hibp` stays available as an option; the GDPR workstream assesses it before anyone enables it. |
| D11 | Recovery without any factor | Decided: admin-assisted reset after identity verification by the organization (`POST /api/admin/users/:id/reset-factors`, task 0015), logged and notified. No self-service path without a recovery code. |
| D12 | Password normalization | Decided: passwords are normalized to Unicode NFC (`String.normalize(password, :nfc)`) in `PasswordPolicy.prepare/1` before every length check, blocklist check, hash and verification. This follows NIST SP 800-63B-4 section 3.1.1.2 and deviates from ASVS 6.2.8, which asks for verification exactly as received; the matrix records the deviation. The platform stores no passwords before this rule applies, so no rehash migration is needed. |
| D13 | RS256 | Decided: RS256 stays only for verification, where a provider or an authenticator offers no other algorithm. The ID token allowlist keeps RS256 next to PS256 and ES256, because the discovery documents of Google and Entra ID list RS256 as their only signing algorithm (retrieved 2026-10-08). Passkeys keep COSE -257 next to -7 and -8, because the FIDO metadata lists the Windows Hello authenticators with RS256 only and WebAuthn Level 3 asks relying parties to offer it. Every `private_key_jwt` client assertion uses PS256 alone, the algorithm that Microsoft documents for Entra ID, and a provider that accepts no PS256 authenticates the client with a secret. oidcc signs no request object and no DPoP proof, because task 0006 switches both off. The spike of decision D4 showed on 2026-10-09 that Entra accepts PS256. ASVS Appendix C lists RSASSA-PKCS1-v1_5 as disallowed, so the matrix records RS256 as a deviation from ASVS 11.6.1. |
| D14 | SHA-1 | Decided: TOTP computes HMAC-SHA-1, as RFC 6238 defines it by default and as `nimble_totp` 1.0.0 offers it (task 0005), and the breached-password check sends the SHA-1 prefix that the Pwned Passwords range API defines (task 0004). ASVS Appendix C rates both as legacy, and the matrix records each use as a deviation from ASVS 11.4.1. |
| D15 | Announced deviations | Decided: the ownership table marks the deviations that the task specs announce, as it marks 6.2.8: the previous TOTP step under ASVS 6.5.5 (task 0005), the password bind of the directory service account under ASVS 13.2.1 (task 0007), and `code`, `state` and the OIDC intent in a query string under ASVS 14.2.1 (task 0011, with the measures of task 0006). The section "Deviations" of the matrix holds each entry with rule and reason. |
| D16 | ASVS scan rows | Decided: every row of the matrix appears in the ownership table of task 0004 (step 42), and the section "Security requirements" of each task spec lists exactly the rows whose `Task` column names that task. `test/docs/asvs_matrix_test.exs` checks both rules in `make check`. |
| D17 | Proxy hop | Decided: the hop from the reverse proxy to the application stays HTTP on the compose network of one host, which `self-hosting.md` requires (task 0017), and the matrix records it as a deviation from ASVS 12.3.1 and 12.3.3. A proxy on another host needs TLS on that hop. |

## 16 Risks

| Risk | Mitigation |
|---|---|
| For users in many groups, Entra ID replaces the groups claim with an overage indicator. | The Entra preset maps App Roles (`roles` claim). A groups overage indicator fails the sign-in. |
| Entra ID may reject the client assertion that `oidcc` builds (only `kid` in the header, audience defaults to the issuer). | Spike in 0006 against a tenant (D4), 2026-10-09: Entra accepts the assertion with the key id `x5t` and the issuer as audience, so the fallback around `Oidcc.Token.retrieve/3` is not needed. |
| `cloak` and `cloak_ecto` have no maintainer activity since 2024 and carry two advisories. | Only AES-GCM and HMAC are used, both unaffected. The strict wrapper and an own rotation function cover known defects. Fallback type on `:crypto` (6.9). |
| `wax_` has one maintainer, no independent security review, and gaps that the application must close. | Spike first in 0005, recorded in `docs/security/wax-spike.md`; the application checks listed in 6.6 each have a test; the repository watches for a `wax_` 0.8 release. |
| The first directory or federated sign-in enrolls a second factor on the strength of the first factor alone. | The user receives a notification for every new factor; admins can reset factors (D11). |
| Active Directory behaviour (UPN search, nested groups, StartTLS sent with message id 0) is untested until a Samba AD CI job exists. | Unit tests with a fake server; the Samba AD job is listed as future work in 0007. |
| `argon2_elixir` reports a threading failure on Elixir 1.20 and OTP 28.5 (issue #73). | `parallelism: 1` and a load test on the production image in 0004. |
| `:eldap` accepts an empty Elixir binary as password and sends an anonymous bind. | Guard before every call, plus a fake-server test (6.8). |
| Playwright's cross-browser virtual authenticator needs version 1.61; nixpkgs pins 1.59.1. | Passkey end-to-end tests use the Chromium DevTools virtual authenticator until nixpkgs ships 1.61 or later. |
| An LDAP server without a trusted certificate leads operators to plain LDAP. | The adapter refuses `AUTH_LDAP_TLS=none` outside dev and test. The guide shows how to mount a CA file. |
| Small org units re-identify people in anonymous tables. | `INSIGHTS_ORG_UNIT=false` by default, day-precision dates, group threshold in every report. |
| SCORM packages contain answer keys. | The guide states it. Exams that count for a credential run on the platform. |
| SCORM 1.2 limits resume state to 4,096 characters. | Compact state encoding with a size test in 0016. |
| Playwright in npm and the browsers in nixpkgs drift apart. | `@playwright/test` is pinned to the version of `playwright-driver` in the pinned nixpkgs. |
| The content pack schema changes after adopters have packs. | `pack.yaml` carries `schema: 1`. The importer migrates older schema versions or rejects them with a message. |
