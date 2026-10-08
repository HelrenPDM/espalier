# Contributing to Espalier

Espalier accepts issues and pull requests on GitHub. Everyone who takes part
follows the [code of conduct](CODE_OF_CONDUCT.md). A vulnerability goes to the
private address in [`SECURITY.md`](SECURITY.md), never into a public issue.

## Setup

Requirements: Git, Nix and Docker with the Compose plugin. Every toolchain
command (`mix`, `npm`, `node`, `plantuml`, `gitleaks`) runs inside the pinned
`nix-shell` of `shell.nix`, and the Makefile wraps each one. `make help` lists
all targets.

```sh
cp .env.example .env
nix-shell --run "mix local.hex --force && mix local.rebar --force"
make services-up
make setup
make run
```

`shell.nix` keeps the homes of Mix and Hex in `.nix-mix/` and `.nix-hex/`
inside the clone, so a new clone installs Hex and rebar there once.
`make services-up` starts PostgreSQL on `127.0.0.1` at the port in
`DATABASE_PORT` (`.env.example` sets 5433). `make setup` fetches the Mix and
npm dependencies, compiles the project and creates the database. `make run`
starts Phoenix and the Vite dev server on <http://localhost:5173>.

## Project rules

- Run every toolchain command through `make` or `nix-shell --run`, never with
  a globally installed tool.
- Create code with `mix phx.gen.*`, `mix ecto.gen.migration` and the other
  standard generators first, and edit the generated code by hand afterwards.
- Keep secrets and organization names out of the repository. Configuration
  comes from environment variables, and `.env.example` holds placeholders
  only.
- The implementation plan and the task specs live in [`docs/plan/`](docs/plan/).
  A change that alters the architecture updates the diagrams in
  `docs/architecture/` in the same commit.

## Checks

`make check` runs every static check, dependency audit and test of both
projects. It needs the database of `make services-up`.

```sh
make services-up
make check
```

| Step | Command |
|---|---|
| Elixir format | `mix format --check-formatted` |
| Compiler warnings | `mix compile --warnings-as-errors` |
| Elixir lint | `mix credo --strict` |
| Security analysis | `mix sobelow --config --exit` |
| Hex version | `scripts/check-hex-version.sh` (Hex 2.5.1 or later) |
| Hex advisories and retirements | `mix hex.audit` |
| GitHub advisories | `mix deps.audit` |
| Unused lock entries | `mix deps.unlock --check-unused` |
| Elixir tests | `mix test` |
| Types | `npm --prefix frontend run typecheck` |
| Frontend lint | `npm --prefix frontend run lint` |
| Frontend format | `npm --prefix frontend run format:check` |
| Frontend tests | `npm --prefix frontend run test -- --run` |

`make lint` applies `mix format`, the automatic Oxlint fixes and Prettier.
`make test` runs only the ExUnit and Vitest suites. `make secrets-scan` scans
the Git history for secrets. CI runs `make check` and `make secrets-scan` on
every push and pull request to `main`.

When `scripts/check-hex-version.sh` stops the gate, update Hex with
`nix-shell --run "mix local.hex --force"`. An older Hex neither reports
advisories in `mix hex.audit` nor reads `ignore_advisories` from `mix.exs`.

After you remove a dependency from `mix.exs`, run
`nix-shell --run "mix deps.unlock --unused"`, so that `mix.lock` holds no
entry without a dependency.

## Pull requests

1. Fork [the repository](https://github.com/HelrenPDM/espalier) on GitHub and
   clone your fork.
2. Create a branch from `main` for your change.
3. Run `make check` on your own machine until it passes.
4. Push the branch to your fork and open a pull request against `main`.

The workflow of `.github/workflows/ci.yml` runs on the pull request. A
maintainer merges a pull request after the job `make check` of its workflow
run has passed. The merge keeps the author of each commit, so the contribution
stays attributed to you.

## Commit messages

- Write the subject line in the imperative mood, start it with a capital
  letter, keep it under 72 characters and end it without a period.
- Name the task in parentheses when a commit delivers a task spec, for
  example `Bootstrap Phoenix API and Vite frontend (task 0001)`.
- Explain in the body, wrapped at 72 characters, why the change is needed
  when the subject does not say it.

## Accepting a Sobelow finding

A Sobelow finding is accepted only in code, next to the function or router
pipeline it concerns. A comment states the reason, and a
`# sobelow_skip ["<Check>"]` comment follows it as the last line above the
function or pipeline:

```elixir
# The routes of this pipeline accept only GET, for which
# Plug.CSRFProtection checks no token.
# sobelow_skip ["Config.CSRF"]
pipeline :oidc_transaction do
  ...
end
```

The skip comments take effect because `.sobelow-conf` sets `skip: true`.
Findings are never accepted through `ignore` in `.sobelow-conf` or through a
`.sobelow-skips` file from `mix sobelow --mark-skip-all`, because neither shows
a reason next to the code.

## Dependencies and the release cooldown

`mix.exs` sets `hex: [cooldown: "7d"]`. Hex then resolves only releases that
are at least seven days old. The cooldown applies when Hex resolves
dependencies, for example in `mix deps.update` or for a dependency that
`mix.lock` does not hold yet. Installs from the existing `mix.lock` are not
filtered, and a locked version that is retired or carries an advisory
bypasses the cooldown, so that a security fix is not held back.

A release younger than seven days for any other reason needs an explicit
override. `HEX_COOLDOWN` takes precedence over the setting in `mix.exs`:

```sh
nix-shell --run "HEX_COOLDOWN=0d mix deps.update <package>"
```

State in the commit message why the change cannot wait for the cooldown.

## Secret scanning

`make secrets-scan` runs `gitleaks detect` over the whole history with the
default rules of gitleaks and the configuration in `.gitleaks.toml`. A real
secret that reaches a commit counts as published: revoke it and replace it.

A test fixture that looks like a secret, such as a key generated for a test,
gets an entry in the allowlist of `.gitleaks.toml`. Each entry names its
reason in `description` and matches only the fixture:

```toml
[[allowlists]]
description = "<what the fixture is and why it holds no real secret>"
paths = ['''^<path of the fixture>$''']
```

Prefer `paths` with an anchored, exact path over `regexes` or `stopwords`,
which accept the matching text in every file.

## Maintainers: deny-list before every push

Every commit pushed to GitHub is public. The maintainer keeps a deny-list of
organization and project names outside the repository, one term per line.
`scripts/denylist-check.sh` searches the tracked files for these terms
without regard to case. It exits 1 and lists the files when a term occurs,
and exits 0 with a notice when `DENYLIST_FILE` is unset.

Install the check as a pre-push hook in your clone:

```sh
cat > .git/hooks/pre-push <<'EOF'
#!/bin/sh
export DENYLIST_FILE="$HOME/.config/espalier/denylist.txt"
exec scripts/denylist-check.sh
EOF
chmod +x .git/hooks/pre-push
```

The hook checks the working tree. Before the first push of a clone, check
the whole history as well, both for secrets and for the terms of the list:

```sh
nix-shell --run 'gitleaks detect --no-banner --redact --log-opts="--all"'
tr -d '\r' <"$DENYLIST_FILE" | grep -v '^[[:space:]]*$' |
  git grep -i -l -F -f - $(git rev-list --all)
```

The second command prints nothing when no commit holds a term of the list.

## License

Espalier is licensed under the [Apache License, Version 2.0](LICENSE).
Section 5 of the license applies to every contribution:

> Unless You explicitly state otherwise, any Contribution intentionally
> submitted for inclusion in the Work by You to the Licensor shall be under
> the terms and conditions of this License, without any additional terms or
> conditions.

Source files carry no license header. `LICENSE`, `NOTICE` and the SPDX
identifiers in `mix.exs` and `frontend/package.json` state the license of the
project.
