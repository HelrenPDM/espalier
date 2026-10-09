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
