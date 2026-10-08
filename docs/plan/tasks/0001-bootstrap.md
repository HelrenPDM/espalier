# 0001: Bootstrap the repository with the standard generators

> Milestone: M0 Foundation, Depends on: none

## Context to read first
- `docs/plan/README.md`, sections 2 (principles), 3 (stack), 4 (layout), 5 (request flow), 6.11 (the format of the provider variables in `.env`), 12 (Makefile, container), 13 (quality gates, CI) and 15 (decisions D2, license, and D3, repository host).
- `docs/architecture/context.puml`.
- Reference shape: the `Makefile`, `shell.nix`, `Dockerfile`, `docker-compose.yml` and `.env.example` of `sl_vanilla`. Copy the shape and update the stack as listed in section 3 of the plan.

## Goal
The repository contains a Phoenix API project at the root and a Vite/React
project in `frontend/`, both created by their standard generators inside a
pinned `nix-shell`. `make run` serves the SPA through Vite with a proxy to
Phoenix, and `make docker-build` produces an image that serves the built SPA and
`/health`.

## Scope
- In: `shell.nix`, generator runs, Vite proxy and build output, SPA and health controllers, `.gitignore`, `.env.example`, `compose.dev.yaml` (PostgreSQL only), `compose.yaml`, Makefile, Dockerfile with frontend stage, project section in `AGENTS.md`, `README.md`, the CI workflow `.github/workflows/ci.yml` with `make check`.
- Out: authentication (0004), Tailwind and routing (0010), lint and CI beyond `mix format` and `tsc` (0002), the Mailpit service (0004) and the lldap service (0007) in `compose.dev.yaml`, the SCORM build in the Dockerfile (0016), the SPA route `/auth/finish` and its proxy exclusion (0011).

## Security requirements
The ASVS ownership table in 0004 step 42 assigns no row of `docs/security/asvs-l2.md` to this task, so this task adds no code and no test to the matrix. The task creates no table and no encrypted or keyed-hash column, so it registers no rotation schema `Espalier.Crypto.Rotation.<Table>` and adds no row to `docs/security/crypto-inventory.md` (both owned by 0003). It keeps secrets out of the repository and out of the image build context (README section 2, principle 7): `.gitignore` excludes `.env` and `.env.*` (step 13), `.env.example` holds placeholders only (step 15), and `.dockerignore` excludes `.env` and `.env.*` (step 16). The `secret_key_base` values of development and test hold no high-entropy literal (step 8). `shell.nix` provides gitleaks, which 0002 runs as `make secrets-scan`.

## Steps
1. In the repository root, run `git init -b main`. `phx.new` runs its own `git init` only outside a Git repository (Phoenix 1.8.15, `installer/lib/mix/tasks/phx.new.ex`, `maybe_init_git/2`), so the existing repository keeps the branch `main`.
2. Write `shell.nix`:
   ```nix
   let
     pkgs = import (fetchTarball {
       # nixos-26.05, resolved 2026-10-07
       url = "https://github.com/NixOS/nixpkgs/archive/b25309931cfda5f0b8805f462a29897eeae50168.tar.gz";
       sha256 = "<fill in from nix-prefetch-url --unpack>";
     }) { };
     beam = pkgs.beam28Packages;
   in
   pkgs.mkShell {
     name = "espalier-shell";
     nativeBuildInputs = [
       beam.erlang
       beam.elixir_1_20
       pkgs.nodejs_24
       pkgs.postgresql_18
       pkgs.plantuml
       pkgs.graphviz
       pkgs.gitleaks
       pkgs.gnumake
     ] ++ pkgs.lib.optional pkgs.stdenv.isLinux pkgs.inotify-tools;

     shellHook = ''
       export MIX_HOME="$PWD/.nix-mix"
       export HEX_HOME="$PWD/.nix-hex"
       export PATH="$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH"
       export ERL_AFLAGS="-kernel shell_history enabled"
       export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
       export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
     '';
   }
   ```
   Compute the hash with `nix-prefetch-url --unpack <url>` and fill it in.
3. Install Hex and the Phoenix installer into the project-local `MIX_HOME`:
   `nix-shell --run "mix local.hex --force && mix archive.install hex phx_new 1.8.15 --force"`.
4. Generate the Phoenix project into the existing directory and answer `Y` to the directory prompt:
   `nix-shell --run "mix phx.new . --app espalier --module Espalier --no-html --no-assets --no-dashboard --binary-id --no-install"`.
5. Fetch dependencies and generate the release files:
   `nix-shell --run "mix deps.get && mix phx.gen.release --docker"`.
6. Generate the frontend:
   `nix-shell --run "npm create vite@9.2.1 frontend -- --template react-ts --no-interactive --no-immediate && npm --prefix frontend install"`.
7. Replace `frontend/vite.config.ts`:
   ```ts
   import { defineConfig, type Plugin } from "vite";
   import react from "@vitejs/plugin-react";

   // `make run` starts the dev server as a Phoenix watcher in its own session, so
   // it would outlive Phoenix and keep port 5173. Phoenix holds the other end of
   // its standard input, so the server exits when that input closes. A direct
   // `npm run dev < /dev/null` therefore exits at once. Vitest also calls
   // configureServer and would end a run early with exit code 0, so the hook
   // skips it.
   function exitWithPhoenix(): Plugin {
     return {
       name: "espalier:exit-with-phoenix",
       apply: "serve",
       configureServer() {
         if (process.env.VITEST) return;
         process.stdin.on("close", () => process.exit(0));
         process.stdin.resume();
       },
     };
   }

   export default defineConfig(({ command }) => ({
     plugins: [react(), exitWithPhoenix()],
     base: command === "build" ? "/spa/" : "/",
     server: {
       port: 5173,
       strictPort: true,
       proxy: {
         "/api": "http://localhost:4000",
         "/auth": "http://localhost:4000",
         "/health": "http://localhost:4000",
       },
     },
     build: { outDir: "../priv/static/spa", emptyOutDir: true },
   }));
   ```
8. In `config/dev.exs`, set the endpoint watcher:
   `watchers: [npm: ["run", "dev", cd: Path.expand("../frontend", __DIR__)]]`.
   In `config/dev.exs` and `config/test.exs`, set the `port` of `Espalier.Repo` from `DATABASE_PORT`, the host port of the `db` service of step 14. Both files bind it at the top, so that an empty or whitespace-only value counts as unset:
   ```elixir
   # Host port of the database from compose.dev.yaml (DATABASE_PORT in .env).
   # An empty value counts as unset.
   database_port =
     case String.trim(System.get_env("DATABASE_PORT", "")) do
       "" -> 5432
       port -> String.to_integer(port)
     end
   ```
   and add `port: database_port` after `hostname: "localhost"`. Replace the generated `secret_key_base` literal of the endpoint with `String.duplicate("d", 64)` in `config/dev.exs` and `String.duplicate("t", 64)` in `config/test.exs`, as 0003 builds its development keys. gitleaks 8.30.1 reports both generated literals as `generic-api-key`, and `make secrets-scan` of 0002 reads the whole Git history with an empty allowlist, so they never enter a commit.
9. In `lib/espalier_web.ex`, extend `static_paths/0` with `spa`.
10. Add `EspalierWeb.HealthController` (`GET /health` returns `{"status":"ok"}` after `Ecto.Adapters.SQL.query(Espalier.Repo, "SELECT 1", [])`, and status 503 with `{"status":"error"}` when the query fails).
11. Add `EspalierWeb.SpaController` with `index/2`. When the first element of the path parameter `path` is `api`, `auth` or `health`, it answers 404 with `json(conn, EspalierWeb.ErrorJSON.render("404.json", %{}))`, so that the SPA is served only outside `/api`, `/auth` and `/health` (README section 5). For every other path it sends `priv/static/spa/index.html` (resolved with `Application.app_dir/2`) as `text/html`. When the file is missing, it responds 404 with the text `SPA not built. Run make run or make docker-build.` A route without the `path` parameter, such as the route `/auth/finish` that 0011 adds, receives `index.html` whatever its path.
12. In the router, add `get "/health", HealthController, :index` outside `/api`, and as the last route a scope without pipeline that matches `get "/*path", SpaController, :index`. Keep `/api` and `/auth` scopes and the dev routes above it. Add `test/espalier_web/controllers/spa_controller_test.exs`, which asserts that `GET /api/unknown`, `GET /auth/unknown` and `GET /health/unknown` answer 404 with a JSON body.
13. Extend `.gitignore` with `.nix-mix/`, `.nix-hex/`, `/priv/static/spa/`, `/priv/scorm_player/`, `/frontend/node_modules/`, `/docs/architecture/out/`, `.env`, `.env.*` and `!.env.example`.
14. Write `compose.dev.yaml` with the project name `name: espalier-dev` and one service `db` from `postgres:18`, user and password `postgres`, port `"127.0.0.1:${DATABASE_PORT:-5432}:5432"`, a health check with `pg_isready`, and a named volume mounted at `/var/lib/postgresql` (PostgreSQL 18 images keep their data below that path). Docker Compose reads `DATABASE_PORT` from `.env` by itself. The project name keeps the containers and volumes of `compose.dev.yaml` apart from those of `compose.yaml`, which also defines a service `db`.
15. Write `.env.example` with `PHX_HOST`, `PORT`, `PUBLIC_URL`, `DATABASE_PORT`, `DATABASE_URL`, `POSTGRES_PASSWORD`, `POOL_SIZE` and `SECRET_KEY_BASE` (empty, with the hint `mix phx.gen.secret`). Every value is a placeholder, and `PORT` holds `4000`. `DATABASE_PORT` holds `5433`, so that the development database leaves port 5432 to a PostgreSQL installed on the host; without a value, `compose.dev.yaml` and the configuration of step 8 both use 5432. `PHX_SERVER` appears only in the comment `# PHX_SERVER=true is set by bin/server in the image; leave it unset for development.` The `config/runtime.exs` of `phx.new` reads `PORT` in every environment and starts the endpoint for every set value of `PHX_SERVER`, the empty string included (Phoenix 1.8.15, `installer/templates/phx_single/config/runtime.exs.eex`), and `rel/overlays/bin/server` of step 5 runs `PHX_SERVER=true exec ./espalier start`. Because `make run` reads `.env` (step 18), the development server stays on port 4000, where the Vite proxy of step 7 expects it, and a `mix run` with the variables of `.env` starts no second endpoint. The placeholders of `DATABASE_URL` and `POSTGRES_PASSWORD` match each other and point to the `db` service of `compose.yaml`, so that a copied `.env` with a generated `SECRET_KEY_BASE` starts the image.
16. Extend the generated `Dockerfile`: add a first stage
    ```dockerfile
    FROM node:24-trixie-slim AS frontend
    WORKDIR /frontend
    COPY frontend/package.json frontend/package-lock.json ./
    RUN npm ci
    COPY frontend/ ./
    RUN npm run build -- --outDir /out/spa
    ```
    and in the builder stage, after `COPY priv priv` and before `mix compile`, `COPY --from=frontend /out/spa priv/static/spa`. Extend the generated `.dockerignore` with `.env`, `.env.*`, `.nix-mix/`, `.nix-hex/`, `/frontend/node_modules/` and `/priv/static/spa/`. The build context then carries no secrets, and `COPY frontend/ ./` keeps the `node_modules` that `npm ci` installed in the image.
17. Write `compose.yaml` with the project name `name: espalier`, `db` (`postgres:18`, `POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}` interpolated from `.env`, `POSTGRES_DB: espalier_prod`, volume at `/var/lib/postgresql`, health check, no published port) and `app` (image `espalier:latest`, `depends_on` with `service_healthy`, port 4000, `env_file: .env`). The release has no `ecto.create`, so the image creates the database that `DATABASE_URL` of step 15 names. Without a published port, `make docker-up` runs next to `make services-up`.
18. Write the `Makefile` in the shape of `sl_vanilla` (`.POSIX:`, `all: help`, `##` comments, `help` target). Use a variable `NIX ?= nix-shell --run` for every toolchain call so CI can override it, and the variables `IMAGE ?= espalier` and `TAG ?= latest`, which 0004, 0007 and 0017 use. Targets: `init`, `deps`, `services-up`, `services-down`, `setup`, `run`, `refresh-db`, `lint`, `check`, `test`, `docs`, `docker-build`, `docker-up`, `docker-down`, `docker-logs`, `docker-migrate`, `help`. A target that README section 12 lists runs the command given there, limited to the tools this task installs; 0002 completes `lint` and `check`. Phoenix reads no `.env` file by itself, so the Makefile defines `DOTENV = set -a; if [ -f .env ]; then . ./.env; fi; set +a;`, and `run` executes `$(NIX) '$(DOTENV) iex -S mix phx.server'`. The variables of `.env` then reach Phoenix and the Vite watcher in development, and `make run` still starts when no `.env` exists. The Playwright `webServer` of 0010 starts `make run`, so `make e2e` runs against a server with the same variables. Every later recipe that starts the application in development or reads the provider variables of README section 6.11 puts `$(DOTENV)` in front of its command in the same way. In this task, `deps` runs `mix deps.get` and `npm --prefix frontend ci`, and `init` depends on `deps` and runs `mix compile`. `services-up` runs `docker compose -f compose.dev.yaml up -d --wait`, so that `make services-up && make setup` continues only once the health check of `db` passes. `setup` depends on `init` and runs `$(DOTENV) mix ecto.setup`, because `ecto.setup` runs the seeds and thereby starts the application; `refresh-db` runs `$(DOTENV) mix do ecto.drop, ecto.create, ecto.migrate`; 0008 and 0013 add the demo import and the demo seed to both. The test suite must not depend on the provider variables of a developer's `.env`, so the test recipes take only the database port from it: the Makefile defines `DATABASE_PORT ?= $(shell sed -n 's/^DATABASE_PORT=\([0-9][0-9]*\).*/\1/p' .env 2>/dev/null)`, and every recipe that runs `mix test` executes `$(NIX) 'DATABASE_PORT=$(DATABASE_PORT) mix test'` (with its own arguments). `?=` lets an exported variable or `make test DATABASE_PORT=…` override the value, and without `.env` the empty value selects 5432 (step 8). `check` runs `mix format --check-formatted`, `mix compile --warnings-as-errors`, `DATABASE_PORT=$(DATABASE_PORT) mix test` and `npm --prefix frontend run build`, and `test` runs `DATABASE_PORT=$(DATABASE_PORT) mix test`. `docker-build` runs `docker build -t $(IMAGE):$(TAG) .`, so the defaults build the image `espalier:latest` that `compose.yaml` runs. `docs` runs `plantuml -tsvg -o out docs/architecture/*.puml`.
19. In the generated `AGENTS.md`, delete the heading "Phoenix v1.8 guidelines" with its bullet list, which refers to LiveView, layouts and core components only (this project has no HEEx templates). Add a section "Project rules" with: run every toolchain command through `make` or `nix-shell`; create code with `mix phx.gen.*` before editing it by hand; no secrets and no organization names in the repository; the plan and task specs live in `docs/plan/`; diagrams in `docs/architecture/` are updated in the same change as the code they describe.
20. Replace the generated `README.md` with a short project README: one paragraph on the purpose, quick start (`cp .env.example .env`, `make services-up`, `make setup`, `make run`, open `http://localhost:5173`), one sentence that the development database listens on `127.0.0.1` at `DATABASE_PORT`, links to `docs/plan/README.md` and `docs/architecture/README.md`, and a section `License` with the sentence `Espalier is licensed under the Apache License, Version 2.0 (SPDX identifier Apache-2.0).` followed by links to `LICENSE` and `NOTICE`. 0002 adds both files with the license text and the attribution notice.
21. Write `.github/workflows/ci.yml` (decision D3, README section 13): workflow `CI` on push and pull request to `main`, `permissions: contents: read`, one job `check` named `make check` on `ubuntu-24.04` with `timeout-minutes: 30` and a service `postgres` from `postgres:18` (`POSTGRES_PASSWORD: postgres`, port `5432:5432`, health check with `pg_isready -U postgres`). Pin every action to a commit SHA with the release tag as comment: `actions/checkout` (with `persist-credentials: false`), `cachix/install-nix-action`, and `actions/cache` for `deps`, `_build` and `~/.npm`, keyed on `hashFiles('shell.nix')` and `hashFiles('mix.lock', 'frontend/package-lock.json')`. The steps run `nix-shell --run 'mix local.hex --force && mix local.rebar --force'`, `nix-shell --run 'make deps NIX="sh -c"'` and `nix-shell --run 'make check NIX="sh -c"'`. The job runs on the runner, so the service answers on `localhost:5432`, and the empty `DATABASE_PORT` of a checkout without `.env` selects 5432 (step 8). `NIX="sh -c"` runs every recipe in the one `nix-shell` of the step.

## Deliverables
- `shell.nix`, `Makefile` with the `DOTENV` loader, `.env.example`, `compose.dev.yaml`, `compose.yaml`, `Dockerfile`, `.dockerignore`, `rel/`, `lib/espalier/release.ex`.
- Phoenix project files from `phx.new`, `EspalierWeb.HealthController`, `EspalierWeb.SpaController`, `test/espalier_web/controllers/spa_controller_test.exs`.
- `config/dev.exs` with the Vite watcher, `config/dev.exs` and `config/test.exs` with `DATABASE_PORT`.
- `frontend/` from `create-vite` with the adjusted `vite.config.ts`.
- Updated `AGENTS.md`, `README.md`, `.gitignore`.
- `.github/workflows/ci.yml`.

## Acceptance
- [ ] `nix-shell --run "elixir --version"` prints Elixir 1.20.4 and Erlang/OTP 28.
- [ ] `make help` lists every target with its description.
- [ ] With `.env` copied unchanged from `.env.example`, `make services-up && make setup` exits 0, also on a host whose own PostgreSQL listens on port 5432, and `docker compose -f compose.dev.yaml port db 5432` prints `127.0.0.1:5433`.
- [ ] With `make run` running, `curl -s localhost:4000/health` prints `{"status":"ok"}` and `curl -s localhost:5173/ | grep -c '<div id="root">'` prints `1`.
- [ ] `make run` reads `.env`. With `.env` copied from `.env.example` and the line `PORT=4002` appended, `curl -s localhost:4002/health` prints `{"status":"ok"}` while `make run` runs. With `.env` removed, `make run` starts, and `curl -s localhost:4000/health` prints `{"status":"ok"}`.
- [ ] With `make run` running, `curl -s -o /dev/null -w '%{http_code}' localhost:4000/api/unknown` and the same call for `localhost:4000/auth/unknown` each print `404`.
- [ ] `curl -s localhost:5173/health` returns the same JSON through the Vite proxy.
- [ ] After `System.halt()` in the `iex` session of `make run`, `ss -ltn | grep -c ':5173 '` prints `0` within five seconds, and a new `make run` serves `curl -s localhost:5173/health` without the log line `Port 5173 is already in use`.
- [ ] `make check` exits 0.
- [ ] `make docker-build` succeeds. With a `.env` that has a generated `SECRET_KEY_BASE`, `make docker-up` followed by `curl -s localhost:4000/` returns the built `index.html`, and every asset path under `/spa/assets/` referenced in it answers 200.
- [ ] `make docs` writes one SVG file per PlantUML source: `ls docs/architecture/*.puml | wc -l` and `ls docs/architecture/out/*.svg | wc -l` print the same number.
- [ ] `grep -n 'Apache-2.0' README.md` prints the license sentence of step 20.
- [ ] `git status --porcelain` lists no `.env`, `node_modules`, `.nix-mix` or `priv/static/spa` entries.
- [ ] After the first commit, `nix-shell --run "gitleaks detect --no-banner --redact"` reports no leaks.
- [ ] `nix-shell -p actionlint --run "actionlint .github/workflows/ci.yml"` exits 0, and after a push to `main`, `gh run list --workflow ci.yml --limit 1` shows the run as `completed` and `success`.

## Notes
- `phx.new` with `--no-html --no-dashboard` generates no LiveView dependency and comments out the live socket in the endpoint. Leave the comment in place.
- The generated `AGENTS.md` contains usage rules from Phoenix between `usage-rules-start` and `usage-rules-end`. Keep that block, so that later `mix usage_rules` updates stay possible.
- Keep the npm lockfile (`frontend/package-lock.json`) in Git. The Dockerfile depends on it.
- `make run` reads `.env` as shell code (`set -a` exports every assignment), and `compose.yaml` reads the same file through `env_file`. Both readers take `KEY=value` lines, comment lines, a comment after a space at the end of an unquoted value, and values in double quotes, and both drop the quotes. A value with a space, `;` or `#`, such as `AUTH_LDAP_LABEL="Company account"` or the role maps of README section 6.11, therefore stands in double quotes. Values from `mix phx.gen.secret` and `openssl rand -base64 32` consist of Base64 characters, which both readers take literally.
- An empty placeholder such as `SMTP_HOST=` reaches the application as an empty string once `.env` is loaded. A parser in `config/runtime.exs` that runs in every environment therefore treats an empty or whitespace-only value like an unset variable.
- The Vite watcher outlives Phoenix without the plugin of step 7. With Erlang/OTP 28.5.0.7 and Vite 8.3.3, `npm run dev` runs under the watcher in a session of its own. After `System.halt()` or a SIGTERM to the BEAM, `npm run dev` and Vite were reparented to PID 1 and kept port 5173. The next `make run` logged `Error: Port 5173 is already in use`, its watcher task terminated, and the Vite of the previous run kept serving the port until it ended after some later requests. With the plugin, Vite exits after `System.halt()`, a SIGTERM and a SIGKILL to the BEAM.
- The `VITEST` guard of step 7 protects the Vitest setup of 0002, which reads the same `vite.config.ts`. With Vitest 5.0.3, `configureServer` runs under Vitest with `VITEST=true`. Without the guard, a failing test whose standard input is a pipe that closes after 0.5 seconds ended with exit code 0 and no report; with the guard, the same run reports the failure and exits 1.
- `PGPORT` cannot replace `DATABASE_PORT`. ecto_sql 3.14.0 puts port 5432 into the connection options (`lib/ecto/adapters/postgres/connection.ex`, `Keyword.put_new(:port, @default_port)`) before Postgrex falls back to `PGPORT`, so only `mix ecto.create` honors `PGPORT`, while the pool of `Espalier.Repo` connects to 5432. 0002 step 9 reads the database host from `DATABASE_HOST` in `config/test.exs` next to the port of step 8.
- The Vite proxy key stays `"/auth"` in this task. 0011 replaces it with `"^/auth/(?!finish)"` when it adds the SPA route `/auth/finish` (README sections 5 and 6.5).
