.POSIX:

# Every toolchain call runs through NIX; CI overrides it.
NIX ?= nix-shell --run
IMAGE ?= espalier
TAG ?= latest
PHX_NEW_VERSION ?= 1.8.15

# Phoenix reads no .env file by itself. DOTENV exports every assignment of
# .env into the recipe shell and skips a missing file.
DOTENV = set -a; if [ -f .env ]; then . ./.env; fi; set +a;

# Host port of the development database. The test recipes take only this key
# from .env, so that no other variable of .env reaches the test suite.
DATABASE_PORT ?= $(shell sed -n 's/^DATABASE_PORT=\([0-9][0-9]*\).*/\1/p' .env 2>/dev/null)

all: help

.PHONY: init
init: deps ## install dependencies and compile
	$(NIX) 'mix compile'

.PHONY: deps
deps: ## fetch Mix and npm dependencies
	$(NIX) 'mix deps.get'
	$(NIX) 'npm --prefix frontend ci'

.PHONY: services-up
services-up: ## start the development services (PostgreSQL, Mailpit)
	docker compose -f compose.dev.yaml up -d --wait

.PHONY: services-down
services-down: ## stop the development services
	docker compose -f compose.dev.yaml down

.PHONY: setup
setup: init ## install, compile and set up the database
	$(NIX) '$(DOTENV) mix ecto.setup'

.PHONY: run
run: ## start Phoenix with IEx, the Vite dev server and the mock OIDC provider
	$(NIX) '$(DOTENV) iex -S mix phx.server'

.PHONY: dev-oidc
dev-oidc: ## Start the mock OIDC provider on port 4010
	$(NIX) '$(DOTENV) mix espalier.dev_oidc --port 4010'

.PHONY: refresh-db
refresh-db: ## drop, create and migrate the database
	$(NIX) '$(DOTENV) mix do ecto.drop, ecto.create, ecto.migrate'

.PHONY: lint
lint: ## format and fix the code of both projects
	$(NIX) 'mix format'
	$(NIX) 'npm --prefix frontend run lint -- --fix'
	$(NIX) 'npm --prefix frontend run format'

# hex.audit runs in its own mix process, because Hex requires it to run before
# any task that loads or starts the application (`mix help hex.audit`).
.PHONY: check
check: ## run every static check, dependency audit and test of both projects
	$(NIX) 'mix format --check-formatted'
	$(NIX) 'mix compile --warnings-as-errors'
	$(NIX) 'mix credo --strict'
	$(NIX) 'mix sobelow --config --exit'
	$(NIX) 'scripts/check-hex-version.sh'
	$(NIX) 'mix hex.audit'
	$(NIX) 'mix deps.audit'
	$(NIX) 'mix deps.unlock --check-unused'
	$(NIX) 'DATABASE_PORT=$(DATABASE_PORT) mix test'
	$(NIX) 'npm --prefix frontend run typecheck'
	$(NIX) 'npm --prefix frontend run lint'
	$(NIX) 'npm --prefix frontend run format:check'
	$(NIX) 'npm --prefix frontend run test -- --run'

.PHONY: test
test: ## run the test suites of both projects
	$(NIX) 'DATABASE_PORT=$(DATABASE_PORT) mix test'
	$(NIX) 'npm --prefix frontend run test -- --run'

.PHONY: auth-reference
auth-reference: ## Regenerate the phx.gen.auth reference project in tmp/auth-reference
	rm -rf tmp/auth-reference.previous
	if [ -d tmp/auth-reference ]; then mv tmp/auth-reference tmp/auth-reference.previous; fi
	mkdir -p tmp/auth-reference
	$(NIX) "mix archive.install hex phx_new $(PHX_NEW_VERSION) --force"
	$(NIX) "cd tmp/auth-reference && mix phx.new espalier --module Espalier --binary-id --no-assets --no-dashboard --no-install"
	$(NIX) "cd tmp/auth-reference/espalier && mix deps.get && printf 'Y\n' | mix phx.gen.auth Accounts User users --no-live --hashing-lib argon2"
	test -f tmp/auth-reference/espalier/lib/espalier_web/user_auth.ex

.PHONY: test-integration
test-integration: ## Run the LDAP and mail tests against the dev services
	$(NIX) "DATABASE_PORT=$(DATABASE_PORT) mix test --only ldap --only mail"

.PHONY: argon2-bench
argon2-bench: ## Benchmark Argon2 parameters inside the production image
	docker run --rm --env-file .env -v "$(PWD)/scripts:/scripts:ro" $(IMAGE):$(TAG) /app/bin/espalier eval 'Code.eval_file("/scripts/argon2_bench.exs")'

.PHONY: gen-keys
gen-keys: ## print new CLOAK_KEY_V1 and CLOAK_HMAC_SECRET values for .env
	@$(NIX) "elixir scripts/gen-keys.exs"

.PHONY: secrets-scan
secrets-scan: ## scan the Git history for secrets
	$(NIX) 'gitleaks detect --no-banner --redact'

.PHONY: docs
docs: ## render PlantUML diagrams to docs/architecture/out/
	$(NIX) 'plantuml -tsvg -o out docs/architecture/*.puml'

.PHONY: docker-build
docker-build: ## build the production image IMAGE:TAG (default espalier:latest)
	docker build -t $(IMAGE):$(TAG) .

.PHONY: docker-up
docker-up: ## start app and database from compose.yaml
	docker compose up -d

.PHONY: docker-down
docker-down: ## stop the compose.yaml services
	docker compose down

.PHONY: docker-logs
docker-logs: ## follow the application logs
	docker compose logs -f app

.PHONY: docker-migrate
docker-migrate: ## run migrations in the app container
	docker compose exec app bin/migrate

.PHONY: help
help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
