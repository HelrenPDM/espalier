.POSIX:

# Every toolchain call runs through NIX; CI overrides it.
NIX ?= nix-shell --run
IMAGE ?= espalier
TAG ?= latest

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
services-up: ## start the development services (PostgreSQL)
	docker compose -f compose.dev.yaml up -d --wait

.PHONY: services-down
services-down: ## stop the development services
	docker compose -f compose.dev.yaml down

.PHONY: setup
setup: init ## install, compile and set up the database
	$(NIX) '$(DOTENV) mix ecto.setup'

.PHONY: run
run: ## start Phoenix with IEx and the Vite dev server
	$(NIX) '$(DOTENV) iex -S mix phx.server'

.PHONY: refresh-db
refresh-db: ## drop, create and migrate the database
	$(NIX) '$(DOTENV) mix do ecto.drop, ecto.create, ecto.migrate'

.PHONY: lint
lint: ## format code with automatic fixes
	$(NIX) 'mix format'

.PHONY: check
check: ## run format check, strict compile, tests and frontend build
	$(NIX) 'mix format --check-formatted'
	$(NIX) 'mix compile --warnings-as-errors'
	$(NIX) 'DATABASE_PORT=$(DATABASE_PORT) mix test'
	$(NIX) 'npm --prefix frontend run build'

.PHONY: test
test: ## run the test suite
	$(NIX) 'DATABASE_PORT=$(DATABASE_PORT) mix test'

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
