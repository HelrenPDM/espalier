# Installation and setup

This guide shows three ways to run Espalier and the shortest path to a
working instance on each: a development setup on one machine, a demo
instance with pseudonymous test persons, and a production installation with
Docker Compose. It helps the reader choose a route, lists the settings that a
production instance requires, and ends with a checklist for the first sign-in
and a table of common failures at start-up and at the first use. The detail of each route is in the
reference guides [`self-hosting.md`](self-hosting.md),
[`demo-instance.md`](demo-instance.md) and [`operations.md`](operations.md).
After the installation, read
[`tenant-and-authentication.md`](tenant-and-authentication.md) to connect a
sign-in pathway and assign roles, and [`course-yaml.md`](course-yaml.md) to
fill the instance with a course.

## Choosing a route

| Route | Use it to | Needs | Sign-in | Data |
|---|---|---|---|---|
| Development | change the code, try a pack on one machine, run the test suites | Nix, Docker with the Compose plugin, a clone of the repository | local accounts with mail in Mailpit, or demo accounts with `AUTH_DEMO=true` | a database with the demo pack |
| Demo instance | show Espalier to visitors or run a usability test | Docker with the Compose plugin and a clone | 20 pseudonymous demo persons, no e-mail address | the demo pack, reset with one command |
| Production | run Espalier for an organization | a host with Docker Engine and the Compose plugin, a host name of its own, a reverse proxy, an SMTP server for local accounts, disk space for the media store | local accounts, identity providers or a directory | the organization's packs and the records of its learners |

The development route compiles the project and needs the Nix toolchain. The
demo and production routes run the container image and need only Docker,
`curl` and a POSIX shell for the Makefile targets of this guide
([`self-hosting.md`](self-hosting.md), section "Requirements").

## Development

### Requirements

Nix and Docker with the Compose plugin. Every toolchain command (`mix`,
`npm`, `node`) runs inside the pinned `nix-shell` of
[`shell.nix`](https://github.com/HelrenPDM/espalier/blob/main/shell.nix), and the [`Makefile`](https://github.com/HelrenPDM/espalier/blob/main/Makefile) wraps each
one, so no global Elixir or Node installation is needed. The shell keeps the
homes of Mix and Hex in `.nix-mix/` and `.nix-hex/` inside the clone, so a
new clone installs Hex and rebar there once
([`../../CONTRIBUTING.md`](../../CONTRIBUTING.md), section "Setup"). The shell
also provides `ffmpeg` and `ffprobe` (`ffmpeg-headless`), which convert the
images and videos of a content pack, and `clamav` for the tests of the malware
scan ([`media.md`](media.md)).

### The shortest path

```sh
cp .env.example .env
nix-shell --run "mix local.hex --force && mix local.rebar --force"
make services-up
make setup
make run
```

Then open <http://localhost:5173>. Vite serves the single-page application
on port 5173 and proxies `/api`, `/health` and the paths below `/auth`
except the page `/auth/finish` to Phoenix on port 4000
(`frontend/vite.config.ts`). Open the application on port 5173: the
passkey origin and the links in mails point there in development
(`config/dev.exs`, `PUBLIC_URL` in `.env.example`).

A fresh development database holds no account. The next two sections give
the ways in: demo accounts with `AUTH_DEMO=true`, or a first admin with
`BOOTSTRAP_ADMIN_EMAILS`; both are set in `.env`, and `make run` restarts
with them.

Copy `.env.example` before `make services-up`. Docker Compose and the
Makefile both read `.env`, and the file sets `DATABASE_PORT`.

### What each step does

| Command | Effect |
|---|---|
| `make services-up` | Writes the LDAPS test certificates and the lldap secrets (`make ldap-ca`, `make ldap-secrets`), then starts the services of `compose.dev.yaml` and waits until they run (`up -d --wait`): PostgreSQL 18, Mailpit and lldap |
| `make setup` | Runs `make init` (`mix deps.get`, `npm --prefix frontend ci`, `mix compile`) and `make scorm-xsd` (downloads the SCORM schema files, which the repository does not hold), then `mix ecto.setup` (create and migrate the database), `mix espalier.import content/demo` and `mix espalier.seed_demo`; the import converts the media files of the demo pack with `ffmpeg` |
| `make run` | Starts `iex -S mix phx.server` with the variables of `.env`. The endpoint config starts the Vite dev server as a watcher, and the development configuration starts the mock OIDC provider on port 4010 |
| `make help` | Lists every target with its description |
| `make test-integration` | Runs the tests tagged `ldap`, `mail` and `clamav`: the first two against the services of `make services-up`, the last against a `clamd` that the test starts from the shell |
| `make check` | Runs the formatter check, the compiler with warnings as errors, Credo, the ExDoc build with warnings as errors, Sobelow, the dependency audits, the tests of both projects, the API type check, TypeScript, lint, the frontend format check, the SCORM player build and `npm audit`; it needs the database of `make services-up` |

`make setup` needs network access for the Hex and npm packages and the SCORM
schema files. The pack import publishes the demo pack, and `mix
espalier.seed_demo` adds the policy `usage-policy` and three approved tools
that the demo qualification uses. `make refresh-db` drops the database and
repeats the migration, the import and the seed.

### Media in development

The media store lies in `tmp/media` of the clone unless `MEDIA_DIR` in `.env`
names another directory, and `make run` converts uploaded files with the
`ffmpeg` of the shell. `.env.example` lists the media variables with their
defaults. In development, `MEDIA_EMBED_HOSTS` admits the host
`embed.espalier.test` when the variable is empty, and `MEDIA_CLAMAV_SOCKET` is
unset, so no scan runs ([`media.md`](media.md), section "Settings").

### Ports and services

| Port | Service | Setting |
|---|---|---|
| 4000 | Phoenix | `PORT` (default 4000); the Vite proxy targets port 4000 |
| 5173 | Vite dev server | fixed in `frontend/vite.config.ts` with `strictPort` |
| 5433 | PostgreSQL of `compose.dev.yaml` | `DATABASE_PORT` |
| 1025 and 8025 | Mailpit: SMTP and web interface | fixed in `compose.dev.yaml` |

The mock OIDC provider uses port 4010 (`config/dev.exs`), and lldap uses
3890, 6360 and 17170. `.env.example` sets `DATABASE_PORT=5433`, so a
PostgreSQL server installed on the host keeps port 5432; without a value,
the database and the application use port 5432 on both sides. The services
publish their ports on `127.0.0.1`. Development mail goes to Mailpit, whose
web interface at <http://localhost:8025> shows every mail, invitations
included.

### Demo accounts in development

Set `AUTH_DEMO=true` in `.env` and restart `make run`. The sign-in page then
lists the section "Demo accounts" with the buttons "Test person 1" to "Test
person 20". A demo person holds the role `learner` only and has no e-mail
address, so this route shows the learner side of the demo pack and leaves the
admin area closed ([`demo-instance.md`](demo-instance.md), section "The demo
banner"). The boot logs a warning for `AUTH_DEMO=true`. WebKit stores no
session cookie over `http://localhost`, and the demo sign-in answers 403
`csrf` there ([`../security/authentication.md`](../security/authentication.md),
section "Cookies and CSRF"); Chromium and Firefox work.

### The first admin in development

A development database holds no account. Set the address of the admin in
`.env` and restart `make run`:

```sh
BOOTSTRAP_ADMIN_EMAILS=admin@example.org
```

At boot, an unknown address becomes a local user with the role `admin` and an
invitation. Open Mailpit, follow the link `/invite#token=...` (it works once
and for 10 minutes) and enroll a passkey, or set a password and confirm a
TOTP factor. `ADMIN_REQUIRE_PASSKEY=true`, the default, requires an admin to
hold a passkey; `ADMIN_REQUIRE_PASSKEY=false` lifts the rule and logs a
warning at every boot. The mix tasks `make setup` runs do not run the
bootstrap, so `make run` grants the role.

### Importing another pack

`nix-shell --run "set -a; . ./.env; set +a; mix espalier.import path/to/pack"`
validates, imports and publishes a pack next to a running `make run`;
`--draft` stops after the draft ([`content-packs.md`](content-packs.md),
section "Validation and publication").

## Demo instance

A demo instance runs the production image with the demo profile of
`.env.demo.example`: demo sign-in as the only pathway, no local accounts, no
external identity provider and data-sparing tracking. It sends no mail, admits
no external video host and no embedded player, and runs no malware scan.

```sh
make docker-build
make demo-env
# set PHX_HOST, PUBLIC_URL, SITE_ADDRESS and TRUSTED_PROXIES in .env.demo
make demo-up
```

`make demo-env` copies `.env.demo.example` to `.env.demo` and fills the
secrets from `/dev/urandom`; it refuses to overwrite an existing file. The
profile names `demo.example.org` as a placeholder, so set `PHX_HOST` and
`PUBLIC_URL` in `.env.demo` to the host name of the demo before the first
start. `make demo-up` starts the project `espalier-demo`, waits for
`/health`, runs `bin/migrate` and `Espalier.Release.seed_demo()`, which also
converts the media files of the demo pack. The
application listens on `127.0.0.1:4000`. Browsers reach it through the
reverse proxy example, started in the project of the demo with
`SITE_ADDRESS` and `TRUSTED_PROXIES` in `.env.demo`; for a look on one
machine, `PHX_HOST=localhost` and `SITE_ADDRESS=localhost` serve it at
`https://localhost`. The project-scoped command is in
[`demo-instance.md`](demo-instance.md), section "Serving the demo". Step 5
of the production route uses the default project and `.env`, so it does not
apply to the demo. `make demo-down` removes the instance with its volumes.

[`demo-instance.md`](demo-instance.md) also describes the reset and the test
notes for usability tests.

## Production with Docker Compose

This route installs Espalier on one host. The steps below give the order;
[`self-hosting.md`](self-hosting.md) describes each one.

### 1. Choose the host name

Espalier runs on a host name of its own, for example `espalier.example.org`.
Passkeys belong to the host of `PUBLIC_URL`, so a passkey enrolled under one
host name does not work under another; choose the name before the first
person enrolls one.

### 2. Build the image

```sh
make docker-build
```

The target builds `espalier:latest` (`IMAGE` and `TAG` choose another name).
The image contains `ffmpeg` and `ffprobe` of the Debian package `ffmpeg`,
which convert the media files, and `procps`. The build downloads the base images, the Hex and npm packages and the SCORM
schema files. `compose.yaml` runs the image that `ESPALIER_IMAGE` names. An
image from a registry goes into `.env`, and `make release-push
REGISTRY=registry.example.org/team` pushes a tagged image.

### 3. Write the environment file

```sh
scripts/fill-secrets.sh .env.example .env
```

The script fills the empty lines of `SECRET_KEY_BASE`, `CLOAK_KEY_V1`,
`CLOAK_HMAC_SECRET`, `POSTGRES_PASSWORD` and `DATABASE_URL` with generated
values, makes the file readable by its owner only and refuses to overwrite an
existing `.env`. The other lines keep the values of `.env.example`, so edit
at least `PHX_HOST` and `PUBLIC_URL`. The file holds placeholders only;
a value with a space, `;` or `#` stands in double quotes, and the
application removes one pair of surrounding quotes.

| Variable | Rule in production |
|---|---|
| `DATABASE_URL` | `ecto://USER:PASS@HOST/DATABASE` with a host and one database name; no query parameter `ssl`, because TLS comes from `DATABASE_CA_CERT_FILE`; the bundled database uses `ecto://postgres:<password>@db/espalier_prod` |
| `POSTGRES_PASSWORD` | the password of the bundled database; Docker Compose stops with `set POSTGRES_PASSWORD` without it |
| `SECRET_KEY_BASE` | at least 64 bytes; `scripts/fill-secrets.sh` and `mix phx.gen.secret` generate one |
| `CLOAK_KEY_V1`, `CLOAK_HMAC_SECRET` | 32 random bytes each, Base64; `openssl rand -base64 32` generates a value, and `make gen-keys` prints both in a checkout with Nix |
| `PHX_HOST` | the host name of step 1 |
| `PUBLIC_URL` | `https://espalier.example.org`, an origin without user info, path, query or fragment, with the same host as `PHX_HOST` |
| `DATABASE_CA_CERT_FILE`, `EXPORT_DIR` | a file that exists, and the directory of the SCORM packages; `compose.yaml` sets both (`/data/exports`) |
| `MEDIA_DIR` | the root of the media store; `compose.yaml` sets `/data/media` in the volume `media` |
| `MAIL_FROM` | required together with `SMTP_HOST` |
| a sign-in pathway | `LOCAL_ACCOUNTS=true` (the default), a provider in `AUTH_PROVIDERS`, or `AUTH_DEMO=true` |

An empty value counts as missing. `SMTP_HOST` is optional, but an instance
without it sends no mail, and local accounts start from an e-mail link, so an
instance with local accounts needs `SMTP_HOST`, `SMTP_PORT` (default 587),
`SMTP_USERNAME`, `SMTP_PASSWORD` and `MAIL_FROM`. The mail client requires
STARTTLS. `TRUSTED_PROXIES` names the address of the reverse proxy. Keep a
copy of `CLOAK_KEY_V1` and `CLOAK_HMAC_SECRET` apart from the database
backups ([`../security/key-management.md`](../security/key-management.md)).
The account, session, learning, insights and media settings have defaults that
`Espalier.RuntimeConfig` documents in
[`lib/espalier/runtime_config.ex`](https://github.com/HelrenPDM/espalier/blob/main/lib/espalier/runtime_config.ex); the
`AUTH_*` variables are described in
[`identity-providers.md`](identity-providers.md), and `.env.example` lists
the others (`PORT`, `POOL_SIZE`, `SMTP_PORT`, `RELEASE_COOKIE`).

The media variables have defaults, and a production instance reviews these:

| Variable | Default | Effect |
|---|---|---|
| `MEDIA_STORAGE_MAX_GB` | `50` | The quota of the stored and incoming media files. The volume needs space beyond it for uploads and conversions in progress. |
| `MEDIA_IMAGE_MAX_MB`, `MEDIA_VIDEO_MAX_MB` | `20`, `1024` | The largest raster image and the largest video. |
| `MEDIA_EXTERNAL_HOSTS`, `MEDIA_EMBED_HOSTS` | empty | The hosts of external video files and of embedded players. An empty list admits no host, and each host enters the CSP. |
| `MEDIA_EMBED_CONSENT` | `click` | An embedded player loads after the learner agrees; `auto` loads it with the page. |
| `MEDIA_CLAMAV_SOCKET` | unset | The clamd socket; set, it switches the malware scan on. |

`MEDIA_VIDEO_MAX_MINUTES`, `MEDIA_VIDEO_MAX_HEIGHT`, `MEDIA_IMAGE_MAX_EDGE` and
`MEDIA_FFMPEG_THREADS` have defaults as well. [`media.md`](media.md), section
"Settings", gives every media variable with its range, and a change takes
effect when `app` restarts. In production, the boot check also finds `ffmpeg`,
`ffprobe` and `timeout`, requires ffmpeg 7.1 or later and the encoders and
demuxers of the conversion, and stops the boot with a line for each gap.

### 4. Start the services and migrate

```sh
docker compose up -d
docker compose exec app bin/migrate
docker compose restart app
curl -fsS http://localhost:4000/health
```

`make docker-up` and `make docker-migrate` run the first two commands. The
service `db-certs` generates the certificates of the database on the first
run, `db` accepts TLS connections only, and `app` starts when `db` is
healthy. The restart lets the boot run against the migrated database, which
matters for the first admin. `/health` answers `{"status":"ok"}` once the
application reaches the database. The application port is published on
`127.0.0.1:4000` only (`APP_PORT` changes the host port). The volume `media`
holds the media store at `/data/media`, next to the volume `exports`.

### 5. Put a reverse proxy in front

Browsers reach Espalier over HTTPS through a reverse proxy on the same host.
The example in `docs/guides/examples/` adds Caddy:

```sh
# in .env
SITE_ADDRESS=espalier.example.org
PHX_HOST=espalier.example.org
PUBLIC_URL=https://espalier.example.org
TRUSTED_PROXIES=172.30.0.10
# then
docker compose -f compose.yaml -f docs/guides/examples/compose.caddy.yaml up -d
```

For a public host name, Caddy obtains a
certificate through ACME on port 443. The proxy sets the
`Strict-Transport-Security` header, because the application sends none, and
sends `X-Forwarded-Proto: https`. `TRUSTED_PROXIES` must name the address of
the proxy, or every request appears to come from the proxy. A host that
already runs a proxy on port 443 forwards to `app:4000` over a shared Docker
network instead. [`self-hosting.md`](self-hosting.md), section "The reverse
proxy", describes both and the requirements the proxy meets.

Every later `docker compose` command of the instance (`up --force-recreate`,
`exec`, `restart`, `logs`) needs the same file list; a command without the
Caddy file recreates `app` from `compose.yaml` alone and takes it off the
network of the proxy. Set
`COMPOSE_FILE=compose.yaml:docs/guides/examples/compose.caddy.yaml` in `.env`
once, and the commands of the next steps and the Makefile targets use it
([`self-hosting.md`](self-hosting.md), section "One file list for every
command").

### 6. Create the first admin

No account exists after the installation. Three sources create the first
admin:

- Set `BOOTSTRAP_ADMIN_EMAILS=admin@example.org` in `.env`, recreate the
  container (`docker compose up -d --force-recreate app`) and open the
  invitation mail. The link works once and for 10 minutes. This way needs
  local accounts and SMTP. `docker compose exec app bin/espalier eval
  'Espalier.Release.invite_user("admin@example.org")'` sends a new
  invitation.
- After a person has signed in through an identity provider, grant the role
  explicitly:

  ```sh
  docker compose exec app \
    bin/espalier eval 'Espalier.Release.grant_role("admin", "admin@example.org")'
  ```

- With an identity provider of the type `entra`, `oidc` or `ldap`, an `admin=` entry
  in `AUTH_<KEY>_ROLE_MAP` grants the role at the first matching sign-in, and
  the `grant_role/2` step is then unnecessary
  ([`tenant-and-authentication.md`](tenant-and-authentication.md), section
  "Roles and the first admin").

The bootstrap runs at every boot, and an address that belongs to an account
with an external identity receives no grant. An admin enrolls a passkey on
the page `/account/security`; without one, the admin routes answer 403
`passkey_required`. [`self-hosting.md`](self-hosting.md), section "The first
admin", has the detail.

### 7. Import content

The image carries the demo pack. For a first look, import and publish it:

```sh
docker compose exec app bin/espalier eval 'Espalier.Release.seed_demo()'
```

An organization imports its own packs after the deployment with the upload in
the admin area (role `author`), the pack workbench, or
`Espalier.Release.import_pack/2`, which reads a pack directory that the
operator mounts into the container read-only.
[`content-packs.md`](content-packs.md) describes the format and the import,
[`pack-workbench.md`](pack-workbench.md) the editor, and
[`scorm-export.md`](scorm-export.md) the export to a learning management
system.

[`media.md`](media.md) describes the media library, the conversion of images,
SVG files and videos, and the limits.

[`self-hosting.md`](self-hosting.md) also covers an external PostgreSQL
server, mail, the media store, backups (the database and the media store are
saved together) and upgrades. [`operations.md`](operations.md) covers
logs, health, background jobs, sessions and keys, and
[`security.md`](security.md) the secrets, TLS per connection and every
outgoing connection.

### Optional: the malware scan for media

Without further steps, uploaded and imported media files pass the signature
check and the conversion, and no virus scan runs. The compose example
`docs/guides/examples/compose.clamav.yaml` adds a service `clamav` and sets
`MEDIA_CLAMAV_SOCKET` for `app`. The two services share the socket in the
volume `clamd-socket`, so clamd opens no network port. The file joins the file
list of the instance:

```sh
# in .env
COMPOSE_FILE=compose.yaml:docs/guides/examples/compose.caddy.yaml:docs/guides/examples/compose.clamav.yaml
# then
docker compose up -d
```

The service holds its signatures in memory (954 to 979 MiB after its start and
up to 1.9 GiB while clamd loads new signatures after an update), and `app`
starts once clamd answers, which can take several minutes at the first start.
While `MEDIA_CLAMAV_SOCKET` is set, `MEDIA_VIDEO_MAX_MB` stays at most 2047.
Raising `MEDIA_VIDEO_MAX_MB` above its default also needs larger limits in
`clamd.conf` ([`media.md`](media.md), section "The clamd example").
[`self-hosting.md`](self-hosting.md), section "The optional malware
scan", and [`media.md`](media.md), section "Malware scan", give the settings
of clamd and a test of the scan.

## Checklist before the first sign-in

1. `docker compose ps` shows `app` as healthy, and `curl -fsS
   http://localhost:4000/health` answers `{"status":"ok"}`.
2. The log of the boot has the line `Effective settings: ...` and no line
   that starts with `The environment stops the boot:`
   ([`operations.md`](operations.md), section "Lines at boot").
3. `bin/migrate` has run, and `app` has been restarted since.
4. `PUBLIC_URL` uses `https`, and its host equals `PHX_HOST` and the host
   name of the certificate.
5. `TRUSTED_PROXIES` names the address of the reverse proxy.
6. `SMTP_HOST` and `MAIL_FROM` are set when people use local accounts; the
   boot warning `SMTP_HOST is not set: this instance delivers no mail` is
   absent.
7. `BOOTSTRAP_ADMIN_EMAILS` names the first admin, or an account is ready for
   `grant_role/2`.
8. `scripts/check-headers.sh https://espalier.example.org` passes through the
   proxy. The script expects the base CSP and reports a mismatch on a CSP
   with `media-src` or `frame-src`, which `MEDIA_EXTERNAL_HOSTS` or
   `MEDIA_EMBED_HOSTS` add while either is set.
9. A copy of `CLOAK_KEY_V1` and `CLOAK_HMAC_SECRET` exists outside the
   database backups, and `AUTH_DEMO` is `false`.

## Troubleshooting

The boot check collects every missing or invalid setting and, in production,
every missing media tool, and names them in one message, without the values of secret variables
([`../../lib/espalier/boot_check.ex`](https://github.com/HelrenPDM/espalier/blob/main/lib/espalier/boot_check.ex)).

| Symptom | Cause | Fix |
|---|---|---|
| `Missing environment variables: ...` | a required variable is empty or absent | set the named variables ([step 3](#3-write-the-environment-file)) |
| `SECRET_KEY_BASE is shorter than 64 bytes` | the value has fewer than 64 bytes | generate a new one with `mix phx.gen.secret` or `scripts/fill-secrets.sh` |
| `PUBLIC_URL must use https in production` | `.env.example` sets `http://localhost:5173` | set `PUBLIC_URL=https://<PHX_HOST>` |
| `The host of PUBLIC_URL must equal PHX_HOST` | the two names differ | use the same host name in both |
| `DATABASE_URL must not set ssl` | the URL has the query parameter `ssl` | remove it; TLS comes from `DATABASE_CA_CERT_FILE` |
| `DATABASE_CA_CERT_FILE names no file` | the path does not exist in the container | use the compose default, or mount the CA file of an external server |
| `No sign-in pathway: ...` | `LOCAL_ACCOUNTS=false`, no provider and `AUTH_DEMO` not `true` | enable one pathway |
| Docker Compose stops with `set POSTGRES_PASSWORD` | the variable is empty | fill it in `.env`, or run `scripts/fill-secrets.sh` |
| every request ends in a redirect | the proxy omits `X-Forwarded-Proto: https` | add the header at the proxy |
| the logs show the proxy address for every client | `TRUSTED_PROXIES` is empty or wrong | list the address of the proxy |
| the invitation link has expired | the link works for 10 minutes | run `Espalier.Release.invite_user/1` again |
| an admin route answers 403 `passkey_required` | the admin holds no passkey | enroll one on `/account/security` |
| in development, the database cannot use its host port | a PostgreSQL server on the host holds port 5432 and `DATABASE_PORT` is unset | keep `DATABASE_PORT=5433` from `.env.example` in `.env` before `make services-up` |
| `MEDIA_DIR is required` | production without a media directory | use `compose.yaml`, which sets `/data/media`, or set `MEDIA_DIR` to a writable directory |
| `ffmpeg lacks the encoder libvpx-vp9`, `ffmpeg is not installed` or `ffmpeg 7.0 is older than 7.1` | the ffmpeg of the runtime misses a tool, an encoder or a release that the media conversion needs | run the image that `make docker-build` builds, which installs the Debian package `ffmpeg` |
| `MEDIA_VIDEO_MAX_MB must be at most 2047 while MEDIA_CLAMAV_SOCKET is set` | clamd scans at most 2 GiB per file | lower `MEDIA_VIDEO_MAX_MB` or unset `MEDIA_CLAMAV_SOCKET` |
| `MEDIA_EMBED_HOSTS must not name the host of PUBLIC_URL` | a same-origin iframe could leave its sandbox | remove the host of the instance from `MEDIA_EMBED_HOSTS` |
| `make run` cannot start Vite | port 5173 is in use; the port is fixed | stop the process that holds it |
| the demo sign-in answers 403 `csrf` in WebKit | WebKit stores no `Secure` cookie over `http://localhost` | use Chromium or Firefox, or the HTTPS proxy |
| a second instance on the same host fails to start | `APP_PORT`, `HTTPS_PORT` or `PROXY_SUBNET` is taken, or both instances share the Compose project name `espalier` of `compose.yaml` | set other values for the second instance: `APP_PORT`, `HTTPS_PORT`, `PROXY_SUBNET` and `PROXY_ADDRESS` (an address inside the new subnet, which `TRUSTED_PROXIES` names), and start it with its own project name (`-p`, as the demo does with `espalier-demo`) |
| an invitation mail never arrives | `SMTP_HOST` is unset; in development, Mailpit holds the mail | set `SMTP_HOST`; in development open <http://localhost:8025> |
