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

[Unreleased]: https://github.com/HelrenPDM/espalier/commits/main
