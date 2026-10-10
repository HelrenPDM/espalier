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
- The neutral demo pack `content/demo/` ("AI assistant basics (demo)"),
  imported by `make setup` and `make refresh-db`, and the dependency
  `yaml_elixir` 2.12 (task 0008).

### Changed

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

[Unreleased]: https://github.com/HelrenPDM/espalier/commits/main
