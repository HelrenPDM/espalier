# Espalier

Espalier is an open-source learning platform for competence programs that end
in a credential. A credential names the tasks it unlocks and holds no score or
rank of the person. The backend is an Elixir/Phoenix JSON API, and the user
interface is a Vite/React single-page application in `frontend/`.

## Quick start

Requirements: Nix and Docker with the Compose plugin. Every toolchain command
runs inside the pinned `nix-shell` through the Makefile (`make help` lists all
targets).

```sh
cp .env.example .env
make services-up
make setup
make run
```

Then open <http://localhost:5173>. Vite serves the SPA and proxies `/api`,
`/auth` and `/health` to Phoenix on port 4000.

The development database listens on `127.0.0.1` at the port in
`DATABASE_PORT` (`.env.example` sets 5433), so a PostgreSQL installed on the
host can keep port 5432.

## Documentation

- [Guides](https://github.com/HelrenPDM/espalier/blob/main/docs/guides/README.md): [what Espalier is for](docs/guides/purpose.md),
  [installation and setup](docs/guides/setup.md),
  [instance, tenant and authentication](docs/guides/tenant-and-authentication.md)
  and [course YAML building blocks](docs/guides/course-yaml.md), followed by
  the reference guides
- [Implementation plan and task specs](docs/plan/README.md)
- [Architecture diagrams](https://github.com/HelrenPDM/espalier/blob/main/docs/architecture/README.md)

## License

Espalier is licensed under the Apache License, Version 2.0 (SPDX identifier Apache-2.0).
See [`LICENSE`](https://github.com/HelrenPDM/espalier/blob/main/LICENSE) and [`NOTICE`](https://github.com/HelrenPDM/espalier/blob/main/NOTICE).
