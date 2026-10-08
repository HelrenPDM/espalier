# 0002: Quality gates, CI and open-source files

> Milestone: M0 Foundation, Depends on: 0001

## Context to read first
- `docs/plan/README.md`, sections 2 (principle 7), 3 (row "Lint and audit"), 6.5 (row "CSRF"), 6.9 (item "Versions"), 12 (Makefile), 13 (quality gates) and 15 (decision D2, license Apache-2.0, and decision D3, GitHub as the only host).
- The Apache License 2.0 as published at https://www.apache.org/licenses/LICENSE-2.0.txt, sections 4 (redistribution) and 5 (submission of contributions) and the appendix.
- `docs/plan/tasks/0004-accounts-sessions.md`, step 32 (router pipelines) and step 42 (ownership table of the ASVS matrix).
- `AGENTS.md` (project rules from 0001).

## Goal
`make check` runs every static check, dependency audit and test of both
projects. CI installs a current Hex and runs the same target on every push,
secret scanning is part of the gate, and the repository has the files an
open-source project needs. The project is licensed under the Apache License 2.0
(decision D2): `LICENSE` holds the published text, `NOTICE` names the project
and its copyright holders, and both package manifests carry the SPDX identifier
`Apache-2.0`.

## Scope
- In: the settings of the GitHub repository of decision D3, Credo, Sobelow, mix_audit, `mix hex.audit` with a Hex version guard, the Hex release cooldown, the check for unused lock entries, Prettier, Vitest with Testing Library and axe, the Makefile targets `check`, `lint`, `test` and `secrets-scan`, the secret scan in `.github/workflows/ci.yml`, gitleaks with `.gitleaks.toml`, deny-list script, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CHANGELOG.md`, `.editorconfig`, `LICENSE` with the Apache License 2.0, `NOTICE`, the SPDX identifier `Apache-2.0` in `mix.exs` and `frontend/package.json`.
- Out: Playwright (0010); the ASVS matrix (0003); its ownership table, the `# sobelow_skip` comments of the router pipelines and the CSRF test over every mutating route (0004); advisory acknowledgements for Cloak (0003); the `api-types` diff check in `make check` (0009), `npm run build:scorm` in `make check` (0016), `npm audit --omit=dev` in `make check` and the ASVS V15 rows (0017); production hardening (0017).

## Security requirements
The ownership table of 0004 step 42 assigns no row of `docs/security/asvs-l2.md`
to this task, so this task adds no code and no test to the matrix. The task
creates no table, no route and no encrypted or keyed-hash column, so it
registers no rotation schema `Espalier.Crypto.Rotation.<Table>` in
`lib/espalier/crypto/rotation/` and adds no row to
`docs/security/crypto-inventory.md` (both owned by 0003). Its gates form the part of `make check`
that 0017 names as the test of row 15.2.1: `mix hex.audit` and `mix deps.audit`
fail on a dependency with an open advisory unless `mix.exs` documents the
exception, and `scripts/check-hex-version.sh` stops the gate before the audit
when Hex is older than 2.5.1, because an older Hex neither reports advisories in
`mix hex.audit` nor reads `ignore_advisories` (README section 13).

## Steps
1. Add to `mix.exs` deps:
   - `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}`
   - `{:sobelow, "~> 0.16", only: [:dev, :test], runtime: false, warn_if_outdated: true}`
   - `{:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}`

   Check each version against Hex with `mix hex.info <name>` and use the current minor. Hex reads `warn_if_outdated: true` during dependency resolution and prints a warning that lists Sobelow when a newer release exists.
2. Add `cooldown: "7d"` to the `hex:` keyword list of `project/0` in `mix.exs`, with a comment that Hex then resolves only releases that are at least seven days old (README section 13). When 0003 has run first, the list already holds `ignore_advisories`. Otherwise create the list, and 0003 adds its key to it.
3. Run `nix-shell --run "mix deps.get && mix credo gen.config && mix sobelow --exit low --skip --save-config"`. Set `strict: true` in `.credo.exs`. Check that `.sobelow-conf` sets the exit threshold to `low` and `skip` to `true`.
4. Write `scripts/check-hex-version.sh` (POSIX `sh`, `set -eu`). It reads the installed version from the `Hex:` line of `mix hex.info` with `sed -n 's/^Hex: *//p'` and compares it with `2.5.1` through `sort -V`. When the version is 2.5.1 or later, it prints `Hex <version>` and exits 0. Otherwise it prints `Hex <version> is older than 2.5.1. Run mix local.hex --force.` to stderr and exits 1. An empty version counts as too old.
5. Extend the `precommit` alias in `mix.exs`: insert `hex.audit` as the first entry, and add `credo --strict`, `sobelow --config --exit` and `deps.audit`. `hex.audit` goes first, because Hex 2.5.1 requires it to run before any task that loads or starts the application (`mix help hex.audit`).
6. In `frontend/`, install dev dependencies: `prettier`, `vitest`, `jsdom`, `@testing-library/react`, `@testing-library/jest-dom`, `@testing-library/user-event`, `vitest-axe`. Add `.prettierrc.json` (`{}`) and `.prettierignore` (`dist`, `node_modules`, `src/api/schema.d.ts`).
7. Add a `test` block to `vite.config.ts` (`environment: "jsdom"`, `setupFiles: ["./src/test/setup.ts"]`) and `src/test/setup.ts` that imports `@testing-library/jest-dom/vitest` and extends `expect` with the axe matchers. Keep the plugin `exitWithPhoenix` of 0001 step 7 with its `VITEST` guard; without the guard, a Vitest run whose standard input closes exits 0 before it reports (0001, Notes). Add the scripts `test` (`vitest`), `typecheck` (`tsc -b`), `format` (`prettier --write .`) and `format:check` (`prettier --check .`) to `package.json`.
8. Write one component test for the generated `App.tsx` that renders it and asserts no axe violations.
9. Make `config/test.exs` read the database host from `DATABASE_HOST` with default `localhost`, next to the port from `DATABASE_PORT` (0001 step 8), and treat an empty value like an unset one in the same way. The CI job of 0001 step 21 runs on the runner and sets neither variable, so the tests reach the `postgres` service on `localhost:5432`. `DATABASE_HOST` serves a runner whose job runs in a container next to the service.
10. Replace the `check` target of 0001. Each command is its own `$(NIX)` call, in this order: `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix sobelow --config --exit`, `scripts/check-hex-version.sh`, `mix hex.audit`, `mix deps.audit`, `mix deps.unlock --check-unused`, `DATABASE_PORT=$(DATABASE_PORT) mix test` (0001 step 18), `npm --prefix frontend run typecheck`, `npm --prefix frontend run lint`, `npm --prefix frontend run format:check`, `npm --prefix frontend run test -- --run`. A bare `--exit` makes Sobelow exit non-zero for findings of confidence `low` and above (Sobelow 0.16.0, `lib/mix/tasks/sobelow.ex`). `mix hex.audit` runs in its own `mix` process for the reason given in step 5. Three later tasks complete the list of README section 12: 0009 inserts the `api-types` diff check after `mix test`, 0016 adds `npm --prefix frontend run build:scorm` after the Vitest run, and 0017 appends `npm --prefix frontend audit --omit=dev`. Set the target `lint` to `mix format`, `npm --prefix frontend run lint -- --fix` and `npm --prefix frontend run format`, and the target `test` to `DATABASE_PORT=$(DATABASE_PORT) mix test` and `npm --prefix frontend run test -- --run`. Add `secrets-scan: ## Scan the Git history for secrets` with `$(NIX) "gitleaks detect --no-banner --redact"`.
11. Write `.gitleaks.toml`. It extends the default rule set (`[extend]` with `useDefault = true`) and holds an allowlist without entries, with a comment that every entry names its reason. Take the allowlist syntax from the README of the gitleaks version that `shell.nix` provides (`nix-shell --run "gitleaks version"`), and check there that `gitleaks detect` reads `.gitleaks.toml` from the repository root. 0005 and 0006 add their fixture paths to this allowlist, each with its reason, when `make secrets-scan` reports them.
12. Write `scripts/denylist-check.sh`. It reads newline-separated terms from the file named in `DENYLIST_FILE`, searches the tracked files with `git grep -i -l -F -f "$DENYLIST_FILE"`, prints the matching files and exits 1 on a match. It exits 0 with a notice when `DENYLIST_FILE` is unset. The list itself never enters the repository (README section 13). Document the pre-push hook setup in `CONTRIBUTING.md` for maintainers.
13. Extend `.github/workflows/ci.yml` of 0001 step 21. Set `fetch-depth: 0` on `actions/checkout`, so that `gitleaks detect` reads the whole history, and append the step `nix-shell --run 'make secrets-scan NIX="sh -c"'` after `make check`. The step `mix local.hex --force` of 0001 installs the current Hex release into the project-local `MIX_HOME` on every run, so a cached archive older than 2.5.1 never reaches the audit, and `scripts/check-hex-version.sh` stops the job if one does. The cache holds `deps`, `_build` and `~/.npm` and never `.nix-mix`, for the same reason. Keep every action pinned to a commit SHA.
14. Write `.editorconfig` (UTF-8, LF, final newline, two-space indent, no trimming in Markdown).
15. Write `CONTRIBUTING.md` (setup through `make`, the generator rule, commit message style, how to run `make check`, how to accept a Sobelow finding, how to take a dependency release inside the cooldown, how to add a gitleaks allowlist entry with its reason, maintainer pre-push hook, and the license of contributions: section 5 of the Apache License 2.0 places every contribution submitted for inclusion under the terms of the license unless its author states otherwise), `SECURITY.md` (how to report a vulnerability; the contact address is a placeholder until the maintainer fills it in), `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1, full text), `CHANGELOG.md` (Keep a Changelog format, section `Unreleased`).
16. Add the license files and identifiers of decision D2 (Apache-2.0):
    - Download the license text into `LICENSE` with `curl -fsSL -o LICENSE https://www.apache.org/licenses/LICENSE-2.0.txt`. As of 2026-10-07, the published file is ASCII text with LF line endings, 202 lines and 11,358 bytes, and its SHA-256 is `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`. `LICENSE` stays byte-identical to the published file. The appendix "How to apply the Apache License to your work" therefore keeps its bracket placeholders, and the copyright line goes into `NOTICE`.
    - Write `NOTICE` with exactly two lines: `Espalier` and `Copyright <year> The Espalier contributors`. `<year>` is the year of the first commit of the repository (`git log --reverse --date=format:%Y --format=%ad | head -n 1`), or the current year (`date +%Y`) when the repository has no commit yet.
    - In `project/0` of `mix.exs`, add `package: [licenses: ["Apache-2.0"]]`. Hex expects SPDX identifiers in `licenses`.
    - In `frontend/package.json`, add `"license": "Apache-2.0"` and keep the entry `"private": true` that `create-vite` writes.

17. Configure the GitHub repository of decision D3, the only host of the project. Every commit pushed to it is public.
    - `gitleaks detect --no-banner --redact --log-opts="--all"` and `scripts/denylist-check.sh` (with the maintainer's `DENYLIST_FILE`) pass on the full history, and the maintainer's pre-push hook runs the deny-list check before every push.
    - A branch ruleset for `main` blocks force pushes and deletion.
    - The repository description states the purpose in the words of the first sentence of `README.md`, issues and pull requests stay open, and GitHub Actions run the workflow of step 13.
    - `CONTRIBUTING.md` describes the pull request path: fork, branch, `make check` on the own machine, pull request against `main`. A maintainer merges a pull request after the job `make check` of its workflow run has passed. The contribution keeps its author in the commit.

## Deliverables
- Updated `mix.exs` (with `package: [licenses: ["Apache-2.0"]]`), `.credo.exs`, `.sobelow-conf`, `config/test.exs`, and the `Makefile` with the targets `check`, `lint`, `test` and `secrets-scan`.
- `frontend/.prettierrc.json`, `frontend/.prettierignore`, `frontend/src/test/setup.ts`, `frontend/src/App.test.tsx`, updated `package.json` (with `"license": "Apache-2.0"`) and `vite.config.ts`.
- `.github/workflows/ci.yml` with the secret scan, `.gitleaks.toml`, `scripts/denylist-check.sh`, `scripts/check-hex-version.sh`, `.editorconfig`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CHANGELOG.md`, `LICENSE`, `NOTICE`.

## Acceptance
- [ ] `make check` exits 0 on a fresh checkout after `make setup`, and `mix hex.audit`, `mix deps.audit` and `mix deps.unlock --check-unused` report no finding in its output.
- [ ] `make -n check` prints the commands of step 10 in that order.
- [ ] Introducing an unused variable in an Elixir module makes `make check` fail; reverting it makes it pass.
- [ ] Adding a controller action that calls `String.to_atom(params["kind"])` makes `nix-shell --run "mix sobelow --config --exit"` exit non-zero with a `DOS.StringToAtom` finding; reverting it makes the command exit 0.
- [ ] Adding to the router a pipeline `:csrf_probe` with `plug :accepts, ["json"]` and `plug :fetch_session` makes `nix-shell --run "mix sobelow --config --exit"` exit non-zero with a `Config.CSRF` finding for `csrf_probe`. A reason comment followed by `# sobelow_skip ["Config.CSRF"]` directly above the pipeline makes the command exit 0, and removing the pipeline with both comments restores the previous state.
- [ ] `nix-shell --run "scripts/check-hex-version.sh"` prints `Hex 2.5.1` or a later version and exits 0. A stub `mix` placed first on `PATH` that prints `Hex:    2.5.0` makes the script exit 1 with the `mix local.hex --force` hint.
- [ ] `nix-shell --run "mix hex.audit"` exits 0.
- [ ] `grep -n 'cooldown: "7d"' mix.exs` shows the entry inside `project/0`.
- [ ] After `mix deps.get` with an added `{:nimble_csv, ">= 0.0.0"}`, removing that line from `mix.exs` makes `nix-shell --run "mix deps.unlock --check-unused"` exit non-zero; `mix deps.unlock --unused` restores a passing state.
- [ ] `make test` runs ExUnit and Vitest, and `make lint` followed by `git status --porcelain` prints nothing on a fresh checkout.
- [ ] `.gitleaks.toml` extends the default rules and holds no allowlist entry, and `make secrets-scan` exits 0.
- [ ] `DENYLIST_FILE=<file containing "espalier"> scripts/denylist-check.sh` exits 1 and lists files; without `DENYLIST_FILE` it exits 0.
- [ ] A workflow run on GitHub finishes the job `make check` with `success`, and `gh run view <run-id> --log` shows the `Hex` line of `scripts/check-hex-version.sh` with 2.5.1 or later and the `no leaks found` line of `make secrets-scan`.
- [ ] `curl -fsSL https://www.apache.org/licenses/LICENSE-2.0.txt | sha256sum` and `sha256sum < LICENSE` print the same line, and its hash is `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`.
- [ ] `wc -l < NOTICE` prints `2`, `head -n 1 NOTICE` prints `Espalier`, and `grep -cEx 'Copyright [0-9]{4} The Espalier contributors' NOTICE` prints `1`.
- [ ] `nix-shell --run "mix run --no-start -e 'IO.inspect(Mix.Project.config()[:package][:licenses])'"` prints `["Apache-2.0"]`, and `nix-shell --run "cd frontend && npm pkg get license"` prints `"Apache-2.0"`.

- [ ] `gh api repos/<owner>/espalier/rulesets` lists a ruleset for `main` whose rules contain `non_fast_forward` and `deletion`.
- [ ] `CONTRIBUTING.md` describes the pull request path on GitHub, including the condition under which a maintainer merges.

## Notes
- Sobelow's `Config.CSRF` check reads each router `pipeline` block on its own and reports, with confidence `high`, a pipeline that lists `plug :fetch_session` without a plug named `:protect_from_forgery` (Sobelow 0.16.0, `lib/sobelow/config.ex`, `vuln_pipeline?/2`, and `lib/sobelow/config/csrf.ex`). The `plug :accepts` list plays no part in this check, so a JSON pipeline that fetches a session is reported as well. The check compares plug names only. It does not check which pipelines a scope pipes through, it does not see a session fetched or a token checked in a plug outside the pipeline block, and it does not prove that a mutating JSON route rejects a request without `x-csrf-token`. For the JSON pipelines of this application the Sobelow result is therefore no CSRF proof, and the router-wide test of 0004 (step 45) sends every mutating route a request without the token and expects 403 (README section 6.5).
- The router of 0004 (step 32) triggers this check twice. The `:api` pipeline lists `plug :fetch_session` and checks the token with the function plug `:protect_api_from_forgery`, whose name the check does not match. The `:oidc_transaction` pipeline lists `plug :fetch_session` without a token check and serves only GET routes (0006 step 9, README section 8), for which `Plug.CSRFProtection` checks no token (Plug 1.20.3, `lib/plug/csrf_protection.ex`, `@unprotected_methods`). `mix sobelow --config --exit` therefore fails until each of the two pipelines carries an accepted `Config.CSRF` finding as the next note describes. The reason for `:api` is the token check in `:protect_api_from_forgery`, and the reason for `:oidc_transaction` is its GET-only routes. The `:auth_bare` pipeline fetches no session and produces no finding.
- Accept a Sobelow finding only in code: a comment that states the reason, followed by a `# sobelow_skip ["<Check>"]` comment as the last line above the function or pipeline. Sobelow rewrites the skip comment into a `@sobelow_skip` attribute and binds a pipeline skip to the pipeline statement that directly follows it in the same block (Sobelow 0.16.0, `lib/sobelow/parse/source.ex` and `lib/sobelow/parse/metadata.ex`). The skip comments take effect because `.sobelow-conf` sets `skip: true`, which equals the `--skip` flag (Sobelow 0.16.0 README, section "False Positives"). `Config.Headers` reports only pipelines that accept `html`, so the JSON pipelines produce no header finding; the response headers come from the plug described in README section 6.5.
- Hex 2.5.1 (2026-07-09) is the first release that reads `ignore_advisories` and `ignore_retirements`, and Hex 2.5.0 (2026-06-28) added advisory warnings to `mix deps.get` (Hex CHANGELOG). With an older Hex, the result of `mix hex.audit` does not follow the acknowledgements that 0003 adds to `mix.exs`, so the guard script stops the gate before the audit runs.
- The cooldown applies when Hex resolves dependencies, for example in `mix deps.update` or for a dependency that `mix.lock` does not hold yet. It does not apply to installs from an existing `mix.lock` (`mix help hex.config`, Hex 2.5.1). Locked versions that are retired or carry an advisory bypass the cooldown, so that the cooldown holds back no security fix for them (Hex CHANGELOG, v2.5.0). A release younger than seven days for a package whose locked version is neither retired nor under an advisory needs an override. `mix help hex.config` names `HEX_COOLDOWN` as the variable that overrides the `cooldown` setting. Before `CONTRIBUTING.md` documents `HEX_COOLDOWN=0d` as the override, check in https://hex.pm/docs/dependency-policies that it takes precedence over the `hex:` list in `mix.exs`.
- The two audits read different advisory sources: `mix hex.audit` reads the advisories and retirements on hex.pm, and `mix deps.audit` (mix_audit 2.1.5, `lib/mix_audit/repo.ex`) reads `mirego/elixir-security-advisories`, a mirror of the GitHub Advisory Database. `make check` runs both.
- GitHub starts service containers only on Linux runners, so the job stays on `ubuntu-24.04`. A runner without Docker would start PostgreSQL inside the job with `pg_ctl` from `shell.nix`, and `CONTRIBUTING.md` would document that choice.
- Section 4 of the Apache License 2.0 requires that every redistribution of the work or of a derivative work, in source or object form, gives its recipients a copy of the license (4 a) and a readable copy of the attribution notices in `NOTICE` (4 d).
- Source files carry no license header. `LICENSE`, `NOTICE` and the SPDX identifiers in `mix.exs` and `frontend/package.json` state the license of the project.
- A content pack declares its own license as an SPDX identifier in `pack.yaml` (README section 11, 0008), and the demo pack in `content/demo/` declares `CC0-1.0`. `LICENSE` and `NOTICE` cover the other files of the repository.
