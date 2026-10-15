# Demo instance

A demo instance shows Espalier with the demo pack to visitors and to the
participants of usability tests. It runs the production image with the demo
profile of README section 15, decision D5: demo sign-in as the only sign-in
pathway, no external identity provider and data-sparing tracking. This guide
describes the profile and the reason for each value, the Makefile targets
that write the environment file and start the instance, the demo banner, the
test notes for usability tests, and the reset. The setup of a production
instance is in [`self-hosting.md`](self-hosting.md), and the commands for a
running instance are in [`operations.md`](operations.md).

## The demo profile

`.env.demo.example` at the root of the repository holds the profile:

| Variable | Value | Reason |
|---|---|---|
| `AUTH_DEMO` | `true` | Visitors sign in as one of 20 pseudonymous test persons without an e-mail address, so the instance stores no personal data beyond these persons. |
| `AUTH_PROVIDERS` | empty | No external identity provider: the instance connects to no directory and no OIDC provider of an organization and receives no claims about real people. |
| `LOCAL_ACCOUNTS` | `false` | No local accounts, so no e-mail address enters the database and no invitation goes out. The boot check accepts an instance without local accounts and providers only while `AUTH_DEMO=true`. |
| `TRACKING_DETAIL` | `minimal` | Per person, the instance stores only enrollment and path, module completion, exam attempt outcomes, acknowledgements, attendance and credentials. Practice answers feed the anonymous item statistics only, and the resume state stays in the browser (README section 10). |
| `REGISTRAR_ENABLED` | `false` | No per-person credential list for the role `registrar`. |
| `TEST_NOTES` | commented out | The test notes of the section "Test notes for usability tests" stay off until a usability test needs them. |
| `PHX_HOST`, `PUBLIC_URL` | `demo.example.org`, `https://demo.example.org` | Placeholders for the dedicated host name of the demo instance and its `https` origin. |
| `SECRET_KEY_BASE`, `CLOAK_KEY_V1`, `CLOAK_HMAC_SECRET`, `POSTGRES_PASSWORD`, `DATABASE_URL` | empty | `make demo-env` fills them with generated values. |

The profile sets no `SMTP_HOST`, so the instance sends no mail. Every boot
of a demo instance logs two warnings, one for `AUTH_DEMO=true` and one for
the missing `SMTP_HOST`:

```text
AUTH_DEMO=true: demo sign-in is enabled; use it for test sessions only
SMTP_HOST is not set: this instance delivers no mail
```

Demo users hold only the role `learner`. The pages of the admin area stay
closed on a demo instance, and the demo persons work through the program of
the demo pack as learners.

Every other variable keeps the default of `Espalier.RuntimeConfig`, which
the line `Effective settings: ...` lists at every boot
([`operations.md`](operations.md), section "Logs").

## Writing `.env.demo`

```sh
make demo-env
```

`make demo-env` runs `scripts/fill-secrets.sh .env.demo.example .env.demo`.
The script copies the profile to `.env.demo` and fills each empty secret
line with values read from `/dev/urandom`:

| Variable | Value |
|---|---|
| `SECRET_KEY_BASE` | 64 random bytes, Base64-encoded |
| `CLOAK_KEY_V1`, `CLOAK_HMAC_SECRET` | 32 random bytes each, Base64-encoded |
| `POSTGRES_PASSWORD` | 32 letters and digits |
| `DATABASE_URL` | `ecto://postgres:<password>@db/espalier_prod` with the same password |

The file is readable by its owner only. The script refuses to overwrite an
existing `.env.demo`; remove the file first to write a new one. Git ignores
`.env.demo`, and `.dockerignore` keeps it out of the image.

Set `PHX_HOST` and `PUBLIC_URL` in `.env.demo` to the host name of the demo
instance before the first start. The section "Serving the demo" covers a
demo on `localhost`.

## Starting the instance

```sh
make docker-build
make demo-up
```

`make docker-build` builds the image `espalier:latest`, and `make demo-up`
starts it with these steps:

```sh
unset POSTGRES_PASSWORD
ENV_FILE=.env.demo ESPALIER_IMAGE=espalier:latest \
  docker compose --env-file .env.demo -p espalier-demo up -d
docker compose --env-file .env.demo -p espalier-demo port app 4000
curl -fsS http://localhost:4000/health
docker compose --env-file .env.demo -p espalier-demo exec -T app bin/migrate
docker compose --env-file .env.demo -p espalier-demo exec -T app \
  bin/espalier eval 'Espalier.Release.seed_demo()'
```

The project name `espalier-demo` gives the instance containers, volumes and
a network of its own, so the volumes of a production instance on the same
host stay untouched. `--env-file .env.demo` gives Docker Compose the
`POSTGRES_PASSWORD` of the profile, and `ENV_FILE=.env.demo` makes the same
file the environment of `app`. Docker Compose takes a `POSTGRES_PASSWORD` of
the shell before the one of the env file, while `app` reads `DATABASE_URL`
from `.env.demo` alone, so the target unsets the variable first. The target
reads the published port with `docker compose port app 4000`, asks `/health`
on it every two seconds and stops with `No answer from /health` after 90
attempts. `bin/migrate`
creates the tables, and `Espalier.Release.seed_demo()` imports and publishes
the demo pack that the image carries and seeds the policy `usage-policy` and
the approved tools of the demo. Its output ends with a line that starts with
`Published` and the line `Seeded <n> policies and <m> approved tools.`

`IMAGE` and `TAG` choose another image (`make demo-up IMAGE=espalier
TAG=<tag>`). The application port on the host is `127.0.0.1:4000`; a second
instance on the same host, such as a production instance, needs another
port. `APP_PORT=4001` in `.env.demo` or in the shell sets it for Docker
Compose, and the wait on `/health` follows the published port.

## Serving the demo

`compose.yaml` publishes the application port on the loopback address
only. Browsers reach the demo through the reverse proxy example of
[`self-hosting.md`](self-hosting.md), section "The reverse proxy". Add the
host name for the proxy and the address of the proxy to `.env.demo`:

```sh
SITE_ADDRESS=demo.example.org
TRUSTED_PROXIES=172.30.0.10
```

Docker Compose reads `SITE_ADDRESS` from `.env.demo` through
`--env-file .env.demo`, so every command of the project finds it, and the
application ignores it. Start the proxy in the project of the demo:

```sh
ENV_FILE=.env.demo docker compose --env-file .env.demo -p espalier-demo \
  -f compose.yaml -f docs/guides/examples/compose.caddy.yaml up -d
```

For a public host name, Caddy obtains a publicly trusted certificate
through ACME, as `self-hosting.md` describes.

For a look at the demo on one machine, set the host to `localhost`:

```sh
PHX_HOST=localhost
PUBLIC_URL=https://localhost
SITE_ADDRESS=localhost
TRUSTED_PROXIES=172.30.0.10
```

Then start the proxy as above and open `https://localhost`. Caddy issues the
certificate for `localhost` from its local CA. A browser trusts it after the
root certificate of that CA is imported into its trust store; the file lies
at `/data/caddy/pki/authorities/local/root.crt` in the container:

```sh
mkdir -p tmp
ENV_FILE=.env.demo docker compose --env-file .env.demo -p espalier-demo \
  -f compose.yaml -f docs/guides/examples/compose.caddy.yaml \
  cp caddy:/data/caddy/pki/authorities/local/root.crt tmp/caddy-root.crt
```

`tmp/` is ignored by Git, so the copy stays out of the repository.

The proxy is needed on one machine as well for a browser that stores no
`Secure` cookie received over plain HTTP. A browser that talks to
`http://localhost:4000` directly receives the session cookie
`__Host-espalier` with `Secure`: Chromium and Firefox store it, while WebKit
stores no cookie and receives 403 `csrf` on the demo sign-in
([`../security/authentication.md`](../security/authentication.md), section
"Cookies and CSRF").

A second instance with the proxy example on the same host, such as a
production instance, needs another `HTTPS_PORT`, `PROXY_SUBNET` and
`PROXY_ADDRESS`, because two networks of one host cannot share a subnet.

## The demo banner

With `AUTH_DEMO=true`, every page shows a banner at the top of its header:

```text
Demo mode: every account here is a pseudonymous test account.
```

The German interface shows "Demo-Modus: Jedes Konto hier ist ein
pseudonymes Testkonto." The SPA reads the flag `demo` from the session
payload of `GET /api/session`, which is `true` on every request while
`AUTH_DEMO=true`, so the banner also appears on the sign-in page and on
pages without a session. The component is `Layout` in
`frontend/src/app/Layout.tsx`.

The sign-in page of the demo profile lists only the section "Demo accounts"
with the buttons "Test person 1" to "Test person 20". Each button signs in
through `POST /api/auth/demo` with its slot. A slot is one user, which keeps
its id and its records across sign-ins and restarts, so two visitors who
choose the same slot work in the same account. The rate limit `demo_ip`
admits ten demo sign-ins per minute from one client address
([`../security/authentication.md`](../security/authentication.md)).

## Test notes for usability tests

`TEST_NOTES=true` switches on the test notes of README section 7, domain
rule 13, and task 0014, step 11. Uncomment the line in `.env.demo` and
recreate the application container:

```sh
ENV_FILE=.env.demo docker compose --env-file .env.demo -p espalier-demo \
  up -d --force-recreate app
```

An instance that runs the proxy example adds
`-f compose.yaml -f docs/guides/examples/compose.caddy.yaml` to this
command, so that `app` stays on the network of `caddy`.

While the flag is set, the program pages show the panel "Test notes" below
their content. The SPA records the events of the test session there: a
station opened, a path switched, an item answered correctly or wrongly, a
poll answered, explanations opened after an answer, an exam passed or
failed, and a vote for a companion format, each with its time since the log
started. The log lives in the `sessionStorage` of the browser tab under the
key `espalier.test_notes` until the next sign-out or sign-in. It holds no
user id, display name, e-mail address or token, and it never reaches the
server. "Copy" puts the log as text on the clipboard, and "Clear" empties
it.

Remove the line again, or comment it out, after the test, and recreate the
container in the same way.

## Reset

```sh
make demo-down
```

`make demo-down` runs the command below. `down` with `-p` and without `-f`
finds the containers, networks and volumes of the project by its label and
needs neither the env file nor `POSTGRES_PASSWORD`. It removes the database,
the database certificates and the SCORM exports, and for an instance behind
the proxy example also the `caddy` container and the volume `caddy_data`.
`make demo-up` then starts an empty instance and seeds the demo pack again.
`.env.demo` stays, so the instance keeps its secrets.

```sh
docker compose -p espalier-demo down -v
```
