# Self-hosting

This guide sets up Espalier on one host with Docker Compose: the image, the
environment file, PostgreSQL with TLS, the reverse proxy, the first admin,
the content and the media store, backups and upgrades. The commands for a
running instance (logs, health, background jobs, sessions, keys, the backup
of the media store and the release functions) are in
[`operations.md`](operations.md). A demo instance with demo sign-in is in
[`demo-instance.md`](demo-instance.md), sign-in through the identity
provider or the directory of an organization in
[`identity-providers.md`](identity-providers.md), and the security settings
with every outgoing connection in [`security.md`](security.md).

## Requirements

- One host with Docker Engine and the Docker Compose plugin. The compose
  files of this guide pass `docker compose config` with Docker Compose 2.40.
- A host name of its own for Espalier (section "Host name").
- For a public deployment, a DNS record of that host name that points to the
  host, and port 443 of the host reachable from the internet.
- For mail, an SMTP server that offers STARTTLS and authentication (section
  "Mail").
- Disk space for the media store: the quota `MEDIA_STORAGE_MAX_GB` (default
  50 GB) and the temporary files beyond it (section "The media store").
- To build the image, a checkout of the repository. The build downloads its
  base images, the Hex and npm packages and the SCORM schema files.

The Makefile targets of this guide (`docker-build`, `docker-up`,
`docker-migrate`, `smoke`, `release-push`) call Docker, `curl` and a POSIX
shell, and need no Nix toolchain.

## Host name

Espalier runs on a host name of its own, for example `espalier.example.org`,
and no other application runs on that host name (ASVS 3.5.4). The proxy
example serves Espalier alone on its `SITE_ADDRESS`. Two settings name the
host:

| Variable | Value |
|---|---|
| `PHX_HOST` | `espalier.example.org` |
| `PUBLIC_URL` | `https://espalier.example.org`, an origin without user info, path, query or fragment; with a port when the proxy listens on another port than 443 |

A production boot stops when `PUBLIC_URL` uses another scheme than `https`,
carries user info, a path, query or fragment, or names another host than
`PHX_HOST`. The application uses `PUBLIC_URL` with a lower-case host and
without the default port 443, which is the form of the origin that browsers
send. Passkeys belong to the host of `PUBLIC_URL`, which is their relying party
id, so a passkey enrolled under one host name does not work under another.
Choose the host name before the first person enrolls a passkey.

## The image

```sh
make docker-build
```

`make docker-build` builds the image `espalier:latest` from the checkout
(`IMAGE` and `TAG` choose another name). `compose.yaml` runs the image that
`ESPALIER_IMAGE` names, by default `espalier:latest`. An image from a
registry goes into `.env`:

```sh
ESPALIER_IMAGE=registry.example.org/team/espalier:latest
```

`make release-push REGISTRY=registry.example.org/team` tags `IMAGE:TAG` as
`registry.example.org/team/espalier:<date>-<time>.<version>-<env>` and as
`registry.example.org/team/espalier:latest` and pushes both tags. `<version>`
comes from `mix.exs`, and `<env>` is `RELEASE_ENV`, by default `prod`.

The image holds the release in `/app`, the license text in `/app/LICENSE`,
the attribution notices in `/app/NOTICE`, the demo pack, and `ffmpeg` and
`ffprobe` of the Debian package `ffmpeg`, which convert the media files and
run as programs of their own. It runs `/app/bin/server` as the user
`nobody`, listens on port 4000 and defines a health check
([`operations.md`](operations.md), section "Health"). The release and both
files belong to `root`, so the user `nobody` can change none of them. The
image holds no secret, no env file, no cookie of the Erlang distribution, no
`.git` directory and no development route; `scripts/check-release.sh` checks
this on a running container.

## The environment file

`compose.yaml` reads `.env` in the directory of the repository twice: Docker
Compose takes the variables of the compose files from it (`POSTGRES_PASSWORD`,
`ESPALIER_IMAGE`, `APP_PORT` and the variables of the examples), and the
service `app` receives every line of it as its environment. `ENV_FILE` names
another file for `app`.

`.env.example` holds no credential: `POSTGRES_PASSWORD`, `DATABASE_URL`,
`SECRET_KEY_BASE`, `CLOAK_KEY_V1` and `CLOAK_HMAC_SECRET` are empty lines
(ASVS 13.2.3). Without `POSTGRES_PASSWORD`, Docker Compose stops with
`set POSTGRES_PASSWORD`. Write `.env` from `.env.example` with generated
secrets:

```sh
scripts/fill-secrets.sh .env.example .env
```

The script fills each of these empty lines with values read from
`/dev/urandom`: `SECRET_KEY_BASE` from 64 random bytes and `CLOAK_KEY_V1`
and `CLOAK_HMAC_SECRET` from 32 random bytes each, all Base64-encoded, and a
password of 32 letters and digits in `POSTGRES_PASSWORD`, which it repeats
in `DATABASE_URL=ecto://postgres:<password>@db/espalier_prod`. The file is
readable by its owner only, and the script refuses to overwrite an existing
`.env`.

An operator who fills the lines by hand sets a password of their own in
`POSTGRES_PASSWORD` and repeats it in `DATABASE_URL`. A password of letters
and digits needs no escaping in the URL, for example:

```sh
head -c 24 /dev/urandom | base64 | tr -d '+/='
```

Keep a copy of `CLOAK_KEY_V1` and `CLOAK_HMAC_SECRET` apart from the
database backups ([`../security/key-management.md`](../security/key-management.md),
section "Storage and access").

Then set the host name (`PHX_HOST`, `PUBLIC_URL`), the address of the proxy
(`TRUSTED_PROXIES`, section "The reverse proxy"), the mail settings and the
first admin (section "The first admin").

### Required settings

| Variable | Rule in production |
|---|---|
| `DATABASE_URL` | `ecto://USER:PASS@HOST/DATABASE` with a host and one database name as its path, without the query parameter `ssl`, because the TLS options come from `DATABASE_CA_CERT_FILE`, and with integers for `timeout`, `pool_size` and `idle_interval`, for which Ecto would otherwise print the URL with its password; characters such as `@`, `:` or `/` in the password need percent-encoding |
| `SECRET_KEY_BASE` | at least 64 bytes; `mix phx.gen.secret` or `head -c 64 /dev/urandom \| base64 \| tr -d '\n'` generates one |
| `CLOAK_KEY_V1`, `CLOAK_HMAC_SECRET` | 32 random bytes each, Base64 with padding; `openssl rand -base64 32` generates one value |
| `PHX_HOST`, `PUBLIC_URL` | section "Host name" |
| `DATABASE_CA_CERT_FILE` | a file that exists; `compose.yaml` sets it |
| `EXPORT_DIR` | the directory of the SCORM packages; `compose.yaml` sets `/data/exports` |
| `MEDIA_DIR` | the root of the media store; `compose.yaml` sets `/data/media` |
| `POSTGRES_PASSWORD` | read by Docker Compose for the service `db` |
| a sign-in pathway | `LOCAL_ACCOUNTS=true` (the default), a provider in `AUTH_PROVIDERS`, or `AUTH_DEMO=true` |

An empty value or one of spaces counts as missing. The variables that
`compose.yaml` sets under `environment` take precedence over the same names
in `.env`.

### How the settings are read

`config/runtime.exs` reads the connection and secret variables
(`DATABASE_URL`, `DATABASE_CA_CERT_FILE`, `SECRET_KEY_BASE`, `PHX_HOST`,
`CLOAK_*`, `SMTP_*`, `PORT`, `POOL_SIZE`) through
`Espalier.RuntimeConfig.value/2`. `Espalier.RuntimeConfig` of task 0004
parses the account and session variables (`SESSION_*`, `LOCAL_ACCOUNTS`,
`SIGNUP`, `SIGNUP_DOMAINS`, `PASSWORD_BREACH_CHECK`, `AUTH_DEMO`,
`BOOTSTRAP_ADMIN_EMAILS`, `TRUSTED_PROXIES`, `PUBLIC_URL`, `MAIL_FROM`,
`ADMIN_REQUIRE_PASSKEY`) and the application settings of the later tasks
(learning records, insights, retention, credentials, webhooks,
`PACK_UPLOAD_MAX_MB`, `EXPORT_DIR`, and `MEDIA_DIR` with the other `MEDIA_*`
variables); its module documentation lists every variable with its default,
and [`media.md`](media.md), section "Settings", the media variables with
their ranges. In production, the boot check also finds `ffmpeg`, `ffprobe`
and `timeout` and checks the release, the encoders and the demuxers of
ffmpeg. `Espalier.Identity.Config` parses the `AUTH_*` variables of the
providers. Each of these values is trimmed, and one pair of surrounding
double quotes is removed, so `Espalier.BootCheck` checks the value that the
configuration uses. `ECTO_IPV6`, `DNS_CLUSTER_QUERY` and `PHX_SERVER` are
read as they stand.

`Espalier.BootCheck` runs before the configuration is built and collects
every missing or invalid setting, so one boot names every gap. Two checks
name only their first finding: `Espalier.Identity.Config` for the `AUTH_*`
variables, and `Espalier.Crypto.Keys.check!/0`, which checks the values of
the Cloak keys when the application starts. A boot on a host with a
supported ffmpeg, without `SECRET_KEY_BASE` and `CLOAK_KEY_V1`, with `LOCAL_ACCOUNTS=false`, an empty
`AUTH_PROVIDERS` and `TRACKING_DETAIL=full` stops with:

```text
The environment stops the boot:
  * Missing environment variables: SECRET_KEY_BASE, CLOAK_KEY_V1
  * No sign-in pathway: LOCAL_ACCOUNTS=false, AUTH_DEMO is not true and AUTH_PROVIDERS names no provider
  * TRACKING_DETAIL must be one of minimal, standard
```

No message contains the value of a secret variable. A boot that passes logs the
line `Effective settings: ...` with the session and data protection
settings ([`operations.md`](operations.md), section "Logs").

### Mail

SMTP is optional. Without `SMTP_HOST`, the instance sends no mail: every
delivery fails, and each boot logs the warning `SMTP_HOST is not set: this
instance delivers no mail`. Invitations, recovery links and notifications
travel by mail, and every local account starts from an e-mail link, so an
instance whose people use local accounts needs SMTP.

| Variable | Content |
|---|---|
| `SMTP_HOST` | host name of the SMTP server, which its certificate must name |
| `SMTP_PORT` | a number from 1 to 65535, default 587 |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | the account at the server; the client always authenticates |
| `MAIL_FROM` | `noreply@example.org` or `"Espalier <noreply@example.org>"`; required together with `SMTP_HOST` |

The client connects to `SMTP_HOST` itself and looks up no MX record of that
name. The connection starts without TLS and upgrades with STARTTLS, which the
client requires, so a server that offers implicit TLS only (port 465) does
not fit. The client accepts TLS 1.2 and TLS 1.3, verifies the certificate of
the server against the CA certificates of the operating system in the image,
and checks that the certificate names `SMTP_HOST`.

## PostgreSQL

### The bundled database

`compose.yaml` runs PostgreSQL 18 (`postgres:18`) as the service `db`. The
application reaches it only through TLS with certificate and host name
verification (ASVS 12.3.1), and it trusts only the CA that the one-shot
service `db-certs` generates (ASVS 12.3.4).

On its first run, `db-certs` generates with `openssl` a CA and a server
certificate for the host name `db`, both with EC P-256 keys, SHA-256
signatures and a validity of 825 days. The CA key exists only in a temporary
directory while the service runs, so no further certificate can be signed
with it. The service writes `server.pem`, `server.key` (owner 999, the
`postgres` user of the image, mode 600) and a `pg_hba.conf` with the lines
`local all all trust` and `hostssl all all all scram-sha-256` into the volume
`db-tls`, and `ca.pem` into the volume `db-ca`. A later run finds the files
and prints the expiry of `server.pem`:

```text
db-certs: the certificates exist; server.pem notAfter=Jan 17 09:35:47 2029 GMT
```

`db` starts after `db-certs` has completed, with `ssl=on`, the minimum
version TLS 1.2 and the `pg_hba.conf` of `db-tls`. A TCP connection without
TLS fails with `no pg_hba.conf entry ... no encryption`; the first-run
initialization of the image, `pg_isready` and `psql` inside the container use
the local socket. `app` mounts `db-ca` read-only and sets
`DATABASE_CA_CERT_FILE=/etc/espalier/db-ca/ca.pem`, and the host of
`DATABASE_URL`, `db`, matches the name in the server certificate. The
expiry check and the renewal of these certificates are in
[`../security/key-management.md`](../security/key-management.md#database-certificates),
section "Other keys and certificates", subsection "Database certificates".

### An external PostgreSQL server

An instance that uses a PostgreSQL server of its own sets `DATABASE_URL` and
`DATABASE_CA_CERT_FILE` to the values of that server. The server needs TLS
with a certificate that names the host of `DATABASE_URL`, and the CA
certificate that signed it as a PEM file on the Docker host. The application
connects with certificate and host name verification and trusts this CA
alone.

`compose.yaml` sets `DATABASE_CA_CERT_FILE` under `environment`, where it
takes precedence over `.env`. An override file runs `app` without the
services `db-certs` and `db` and mounts the CA file of the server. Save it as
`compose.external-db.yaml` next to `compose.yaml`:

```yaml
# app with an external PostgreSQL server, without db-certs and db.
services:
  db-certs: !reset null
  db: !reset null
  app:
    depends_on: !reset {}
    environment:
      DATABASE_CA_CERT_FILE: /etc/espalier/database-ca.pem
    volumes: !override
      - exports:/data/exports
      - ${DATABASE_CA_CERT:?set DATABASE_CA_CERT to the CA certificate of the database server}:/etc/espalier/database-ca.pem:ro
```

The entries of `.env`:

```sh
DATABASE_URL=ecto://espalier:<password>@postgres.example.org/espalier_prod
# The CA certificate on the Docker host; the override mounts it.
DATABASE_CA_CERT=/etc/espalier/postgres-ca.pem
# compose.yaml requires a value, which no service reads with this override.
POSTGRES_PASSWORD=unused
```

```sh
docker compose -f compose.yaml -f compose.external-db.yaml up -d
```

Docker Compose resolves the variables of `compose.yaml` before it applies
`!reset`, so `POSTGRES_PASSWORD` needs a value even though the service `db`
does not run. The application opens up to `POOL_SIZE` connections (default
10), and every `bin/espalier eval` call opens its own.

## Starting Espalier

```sh
docker compose up -d
docker compose exec app bin/migrate
docker compose restart app
curl -fsS http://localhost:4000/health
```

`docker compose up -d` (or `make docker-up`) starts `db-certs`, `db` and
`app`. `app` waits for the health check of `db`. `bin/migrate` (or
`make docker-migrate`) creates the tables. The restart lets the boot run
against the migrated database: the boot task that grants `admin` to
`BOOTSTRAP_ADMIN_EMAILS` runs at every boot and finds no tables on the first
one. `/health` answers `{"status":"ok"}` once the application reaches the
database.

`compose.yaml` publishes the application port on `127.0.0.1:4000` only
(`APP_PORT` changes the host port), so no other host reaches the application
over plain HTTP (ASVS 4.1.2). Browsers reach it through the reverse proxy.

## The reverse proxy

### The Caddy example

`docs/guides/examples/compose.caddy.yaml` adds the service `caddy` (image
`caddy:2.11`) with the Caddyfile of `docs/guides/examples/Caddyfile`:

```sh
docker compose -f compose.yaml -f docs/guides/examples/compose.caddy.yaml up -d
```

| Variable | Default | Content |
|---|---|---|
| `SITE_ADDRESS` | none, required | the dedicated host name of Espalier, the host of `PUBLIC_URL` |
| `HTTPS_PORT` | `443` | the published HTTPS port |
| `PROXY_SUBNET` | `172.30.0.0/24` | the subnet of the network `proxy` between `caddy` and `app` |
| `PROXY_ADDRESS` | `172.30.0.10` | the fixed address of `caddy` in that network |
| `CADDYFILE` | `docs/guides/examples/Caddyfile` | the path of the Caddyfile, relative to the directory of `compose.yaml` |

Docker Compose reads these variables from `.env` or the shell. With the
example, `.env` holds:

```sh
SITE_ADDRESS=espalier.example.org
PHX_HOST=espalier.example.org
PUBLIC_URL=https://espalier.example.org
TRUSTED_PROXIES=172.30.0.10
```

`TRUSTED_PROXIES` names `PROXY_ADDRESS`. The application takes the client
address from `X-Forwarded-For` only on requests from a listed address.
Without the entry, every request appears to come from the proxy, the logs
carry its address, and the rate limits per client address count all clients
together.

The example meets these requirements:

- `caddy` publishes the HTTPS port alone, and no other host reaches a port
  that answers over plain HTTP (ASVS 4.1.2).
- TLS 1.2 and TLS 1.3 only (ASVS 12.1.1). The cipher suites that the example
  offers are recorded in [`security.md`](security.md) (ASVS 12.1.2).
- Every response carries
  `Strict-Transport-Security: max-age=63072000; includeSubDomains`
  (ASVS 3.4.1). The application sends no HSTS header of its own
  (`config/prod.exs`, `force_ssl` with `hsts: false`), so this header comes
  from the proxy alone. `includeSubDomains` extends the rule to every name
  below `SITE_ADDRESS`.
- `TRACE` answers 405, with the HSTS header (ASVS 13.4.4).
- `reverse_proxy` replaces the `X-Forwarded-For` header of the client with
  the address that Caddy sees (ASVS 4.1.3).
- The Caddyfile configures no cache, so the proxy stores no response
  (ASVS 14.2.2).

### Certificates

A public deployment uses a publicly trusted certificate (ASVS 12.2.2). For
a public `SITE_ADDRESS`, Caddy obtains one through ACME and renews it. It
answers the TLS-ALPN challenge of the certificate authority on the HTTPS
port, which the authority validates on port 443 (RFC 8737), so
`HTTPS_PORT` stays 443 for a public deployment. The volume `caddy_data`
holds the certificate and its key.

For `SITE_ADDRESS=localhost`, Caddy issues the certificate from its local
CA, whose root certificate lies at `/data/caddy/pki/authorities/local/root.crt`
in the container. The local CA serves `localhost` only, for a test on one
machine; [`demo-instance.md`](demo-instance.md) describes such a setup.

### Proxy and application on one host

The hop from `caddy` to `app:4000` runs over HTTP on the compose network of
one host. The verification matrix records this hop as a deviation from
ASVS 12.3.1 and 12.3.3 (README section 15, decision D17), and
[`security.md`](security.md) names it. Run the proxy and the application on
the same host. A proxy on another host needs TLS on the hop to the
application.

### An existing reverse proxy on the same host

A host that already runs a reverse proxy for several sites on port 443
leaves no port for the service `caddy`. The existing proxy then forwards the
dedicated host name of Espalier to `app:4000` over a Docker network that the
proxy container and `app` both join, which keeps proxy and application on
one host (decision D17). A network with a fixed subnet gives the proxy a
fixed address, for example:

```sh
docker network create --subnet 172.31.0.0/24 espalier-edge
docker network connect --ip 172.31.0.10 espalier-edge <proxy container>
```

An override joins `app` to that network. Save it as
`compose.proxy-network.yaml` next to `compose.yaml`:

```yaml
# app on the network of an existing reverse proxy of this host.
services:
  app:
    networks:
      - default
      - edge

networks:
  edge:
    name: ${PROXY_NETWORK:?set PROXY_NETWORK to the network of the reverse proxy}
    external: true
```

```sh
PROXY_NETWORK=espalier-edge
PHX_HOST=espalier.example.org
PUBLIC_URL=https://espalier.example.org
TRUSTED_PROXIES=172.31.0.10
```

```sh
docker compose -f compose.yaml -f compose.proxy-network.yaml up -d
```

`TRUSTED_PROXIES` names the address of the proxy on the shared network, and
`PHX_HOST` and `PUBLIC_URL` name the host name. The existing proxy takes over
every requirement that the Caddy example meets:

| The proxy | Requirement |
|---|---|
| serves the host name of Espalier on the HTTPS port only | ASVS 4.1.2 |
| accepts TLS 1.2 and TLS 1.3 only, with ECDHE key exchange and AES-GCM or ChaCha20-Poly1305 for TLS 1.2 | ASVS 12.1.1, 12.1.2 |
| uses a publicly trusted certificate for a public host name | ASVS 12.2.2 |
| sends `Strict-Transport-Security: max-age=63072000; includeSubDomains` on every response, because the application sends none | ASVS 3.4.1 |
| answers `TRACE` with 405 | ASVS 13.4.4 |
| replaces `X-Forwarded-For` with the client address it sees | ASVS 4.1.3 |
| stores no response in a cache | ASVS 14.2.2 |
| serves no other application on that host name | ASVS 3.5.4 |

The proxy also sends `X-Forwarded-Proto: https` with every request, as
Caddy does. The application redirects a request without that header to
`https` (`force_ssl` in `config/prod.exs`), so behind a proxy that leaves it
out, every request ends in a redirect.

After the setup, `scripts/check-headers.sh` checks the headers of the
application and the HSTS header of the proxy through the proxy:

```sh
scripts/check-headers.sh https://espalier.example.org
CHECK_CA_FILE=/etc/espalier/proxy-ca.pem \
  scripts/check-headers.sh https://espalier.example.org
```

The first form fits a publicly trusted certificate. The second passes the
CA certificate of the proxy to `curl --cacert`. The script compares the HSTS
header with the exact value of the table.

### One file list for every command

Every `docker compose` command of an instance needs the same compose files,
`exec` and `logs` included. `COMPOSE_FILE` in `.env` sets the list once, and
the Makefile targets `docker-up`, `docker-migrate` and `docker-logs` then
use it as well:

```sh
COMPOSE_FILE=compose.yaml:docs/guides/examples/compose.caddy.yaml
```

## Identity providers and certificate files

[`identity-providers.md`](identity-providers.md) describes the variables of
each provider type. The paths in `AUTH_<KEY>_CLIENT_CERT_FILE`,
`AUTH_<KEY>_CLIENT_KEY_FILE` and `AUTH_<KEY>_CA_CERT_FILE` refer to files
inside the container, so an override mounts them into `app`, read-only:

```yaml
services:
  app:
    volumes:
      - ./secrets:/etc/espalier/secrets:ro
```

The container user `nobody` must be able to read the files. The hosts that
the application connects to, for an egress allowlist, are listed in
[`security.md`](security.md).

## The first admin

No account exists after the installation. The first admin comes from
`BOOTSTRAP_ADMIN_EMAILS` or from `Espalier.Release.grant_role/2` (README
section 6.11, [`../security/authentication.md`](../security/authentication.md),
section "Bootstrap admin and release functions").

### With `BOOTSTRAP_ADMIN_EMAILS`

This way needs local accounts and SMTP.

1. Set `BOOTSTRAP_ADMIN_EMAILS=admin@example.org` in `.env` and recreate
   the container of `app` with the new environment
   (`docker compose up -d --force-recreate app`).
2. At boot, an unknown address becomes a local user with the role `admin`
   and an invitation. The running application sends the invitation mail.
3. The link `/invite#token=...` in the mail works once and for 10 minutes. It
   opens an enrollment session, in which the person enrolls a passkey, or
   sets a password and confirms a TOTP factor.
4. When the link has expired, `Espalier.Release.invite_user/1` sends a new
   invitation:

   ```sh
   docker compose exec app \
     bin/espalier eval 'Espalier.Release.invite_user("admin@example.org")'
   ```

The bootstrap runs at every boot. A local admin whose grant was revoked
receives it again at the next boot while the address stays in
`BOOTSTRAP_ADMIN_EMAILS`. An address that belongs to an account with an
external identity receives no grant, and the boot logs a warning with the
user id.

### With `grant_role/2`

An account that exists, for example after the first sign-in of a person
through an identity provider, receives the role through an explicit
operator action:

```sh
docker compose exec app \
  bin/espalier eval 'Espalier.Release.grant_role("admin", "admin@example.org")'
```

The call prints `{:ok, ...}` with the grant, `{:error, :not_found}` for an
unknown address, or `{:error, :unknown_role}`. A change of the role grants
ends every session of that user, so the person signs in again.

### The passkey of an admin

`ADMIN_REQUIRE_PASSKEY=true`, the default, requires a passkey of every
admin. An admin without one receives 403 `passkey_required` on every admin
route and enrolls a passkey on the page `/account/security`, to which the
admin area links. Admin actions that change data also need a second factor
from the last 10 minutes. With `ADMIN_REQUIRE_PASSKEY=false`, each boot logs
a warning, and admins without a passkey reach the admin routes.

## Content

The image carries the demo pack. An instance for a first look imports and
publishes it and seeds the policy `usage-policy` and the approved tools of
the demo:

```sh
docker compose exec app bin/espalier eval 'Espalier.Release.seed_demo()'
```

An organization imports its own packs after the deployment, through the
upload of the admin area, the pack workbench or
`Espalier.Release.import_pack/2`; [`content-packs.md`](content-packs.md)
describes the format and the import. The SCORM export writes its packages to
`EXPORT_DIR`, which `compose.yaml` sets to `/data/exports` in the volume
`exports`; [`scorm-export.md`](scorm-export.md) describes the export and its
prerequisites. The directory belongs to one installation and its database.

## The media store

The media library keeps its files below `MEDIA_DIR`, which `compose.yaml`
sets to `/data/media` in the volume `media`. The image creates the directory
for the user `nobody`, as it does for `/data/exports`. `compose.yaml` also
sets `PLUG_TMPDIR=/data/media/uploads`, so `Plug.Upload` writes the body of a
media upload into the same volume, and the upload moves into the store with a
rename and without a copy. Without that setting, an upload of up to
`MEDIA_VIDEO_MAX_MB` lands in the temporary directory of the container
first. The directory belongs to one installation and its database, because
the sweep of the media store deletes stored files that no asset of its
database names.

The volume needs the quota `MEDIA_STORAGE_MAX_GB` plus space for the uploads
in progress, the outputs of the running conversions and the staging of draft
downloads ([`media.md`](media.md), section "Space beyond the quota"). The
conversions run in the container of `app`: two image jobs and one video job
at a time, each ffmpeg process with `MEDIA_FFMPEG_THREADS` threads (default
2) and no single allocation above 512 MiB, so a host that serves videos plans
CPU time and memory for them next to the application
([`security.md`](security.md), section "Resource-demanding functions").

### The optional malware scan

`docs/guides/examples/compose.clamav.yaml` adds a service `clamav` that runs
clamd of the image `clamav/clamav:1.5.4`, and sets
`MEDIA_CLAMAV_SOCKET=/run/clamav/clamd.sock` for `app`. The two services share
the socket in the volume `clamd-socket`, so clamd opens no network port, and
`app` starts once clamd answers. With the file, every uploaded and imported
media file passes a scan before the conversion; without it, no scan runs,
which the ASVS matrix records as a deviation (decision D19). The file joins
the file list of the instance (section "One file list for every command"):

```sh
COMPOSE_FILE=compose.yaml:docs/guides/examples/compose.caddy.yaml:docs/guides/examples/compose.clamav.yaml
```

clamd keeps its signatures in memory: the service used 954 to 979 MiB after its start, and up to 1.9 GiB while clamd loaded new signatures after an update.
freshclam in the same container fetches new signatures from
`database.clamav.net` once a day. [`media.md`](media.md), section "Malware
scan", describes the settings of `clamd.conf`, the limits that must cover
`MEDIA_VIDEO_MAX_MB`, and a test with the test signature of the example.

## Backups

```sh
sudo install -d -m 700 -o "$(id -u)" -g "$(id -g)" /var/backups/espalier
(umask 077; docker compose exec -T db pg_dump -U postgres -Fc espalier_prod \
  > /var/backups/espalier/espalier.dump)
```

The first line runs once. The directory belongs to the account that runs
`docker compose`, so the dumps of this section and of the section
"Upgrades" and the restore need no `sudo`.

`pg_dump` runs inside the container `db` over its local socket and writes a
dump in the custom format to the host. The dump holds the personal data of
the instance, so it belongs outside the checkout of the repository, in a
directory that only its owner can open. `umask 077` in the subshell creates
the file with the mode 600 and leaves the umask of the shell unchanged. A
restore stops the application, loads the dump and starts the application
again:

```sh
docker compose stop app
docker compose exec -T db \
  pg_restore -U postgres -d espalier_prod --clean --if-exists \
  < /var/backups/espalier/espalier.dump
docker compose start app
```

The Cloak keys are not part of a database backup. The encrypted columns of a
dump need the keys `CLOAK_KEY_V<n>` and `CLOAK_HMAC_SECRET` that were in use
when the dump was taken, so keep them in a separate place; a backup that
holds both the database and the keys protects nothing
([`../security/key-management.md`](../security/key-management.md), section
"Storage and access"). A dump also holds the rows that the retention job
deletes later from the live tables, and the earlier order of the anonymous
tables (README section 10). An external PostgreSQL server is backed up with
the means of its operator.

The database names every media file by its digest and every queued source
file by the id of its asset, so the directories `files/` and `incoming/` of
the media store belong to the same backup: a restored database without them
lists assets whose files are missing. [`operations.md`](operations.md),
section "Backup and restore of the media store", saves and restores both
together.

## Upgrades

[`CHANGELOG.md`](../../CHANGELOG.md) lists the changes of each version. An
upgrade takes a backup, brings the new image, migrates and restarts:

```sh
(umask 077; docker compose exec -T db pg_dump -U postgres -Fc espalier_prod \
  > /var/backups/espalier/espalier-before-upgrade.dump)
docker compose pull app
docker compose up -d
docker compose exec app bin/migrate
docker compose restart app
```

`docker compose pull app` fetches the image that `ESPALIER_IMAGE` names from
its registry; for an image built from a checkout, `make docker-build` in the
updated checkout takes its place. The order follows from where the
migrations live: they ship in the release, so `bin/migrate` runs in a
container of the new image, which `docker compose up -d` creates when the
image has changed. Between that start and the end of `bin/migrate`, the new
release serves requests against the old schema. The restart then starts the
application on the migrated schema, so that the boot, with the bootstrap of
`BOOTSTRAP_ADMIN_EMAILS`, runs against it. `Espalier.Release.rollback/2`
reverts migrations ([`operations.md`](operations.md), section "Release
functions").

## Checking an image

```sh
make docker-build
make smoke
make smoke-proxy
```

`make smoke` runs `scripts/smoke.sh` against the image `IMAGE:TAG`. The
script writes `tmp/smoke.env` from the demo profile with generated secrets,
starts `compose.yaml` under the project name `espalier-smoke`, so that the
`.env` and the volumes of an instance stay untouched, and runs
`bin/migrate`, `seed_demo/0`, `scripts/check-headers.sh`,
`scripts/check-release.sh`, a demo sign-in and an answered item, and it
checks the line `Effective settings:` in the log of the boot. The secrets of
`tmp/smoke.env` come into being after the build, so `scripts/check-release.sh`
compares the secret values of the `.env` of the checkout with the metadata
of the image, and skips that comparison without a `.env`. The script removes
its instance with its volumes at the end. `make smoke-proxy` adds the Caddy
example with `SITE_ADDRESS=localhost` and checks the headers through the
proxy, the client address in the log and two request smuggling probes. Both
need Docker, `curl` and a POSIX shell. They publish `APP_PORT` (default 4000)
and, with the proxy, `HTTPS_PORT` (default 443) and the subnet
`PROXY_SUBNET`, so on a host with a running instance they need other values
of these variables. A changed `PROXY_SUBNET` needs `PROXY_ADDRESS` and
`PROBE_ADDRESS` (default 172.30.0.20) inside it.
