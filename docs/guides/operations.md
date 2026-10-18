# Operations

This guide covers the operation of a running Espalier instance of
[`self-hosting.md`](self-hosting.md): the release functions, the logs with
their security events, log access and log forwarding, the health check, the
background jobs and the output of the retention job, the backup of the media
store, ending sessions, and the procedures for keys and certificates in
[`../security/key-management.md`](../security/key-management.md). The
commands run in the directory of `compose.yaml` with the compose files of
the instance (`-f` options or `COMPOSE_FILE`, `self-hosting.md`, section
"One file list for every command").

## Commands in the container

The release functions of `Espalier.Release` run with `bin/espalier eval` in
the container of `app`:

```sh
docker compose exec app bin/espalier eval 'Espalier.Release.encryption_status()'
```

Each call starts a node of its own next to the running application. The
release sets `RELEASE_DISTRIBUTION=none` (`rel/env.sh.eex`), so
`bin/espalier remote` and `bin/espalier rpc` cannot attach to the running
node, and `bin/espalier eval` is the way into the release. A function that
sends mail or other jobs inserts the jobs without processing them, and the
running application processes them. `docker compose run --rm app ...` runs
the same call in a new container, which also works while `app` is stopped
and takes extra volumes with `-v`.

## Release functions

| Function | Effect and output |
|---|---|
| `migrate/0` | Runs every pending migration. `bin/migrate` calls it. |
| `rollback/2` | Reverts the migrations of a repo down to and including a version. |
| `rotate_encryption/0` | Re-encrypts every encrypted column under the current Cloak key and prints the rows per schema and the cipher tags per column, without values or keys. |
| `encryption_status/0` | Prints the cipher tags per encrypted column and the number of values under each. |
| `grant_role/2` | Grants a `manual` role to the account of an address and prints `{:ok, grant}`, `{:error, :unknown_role}`, `{:error, :not_found}` or `{:error, :demo_user}`. |
| `invite_user/1` | Invites a new address, or sends a new invitation to an invited account, and prints the result. |
| `end_all_sessions/0` | Ends every session of every user and prints the number of ended sessions. |
| `check_ldap/1` | Checks the connection to an LDAP provider step by step and prints one line per step (TLS handshake for `ldaps`, connect, StartTLS for `starttls`, service bind, base-scope search), without passwords or directory data. |
| `reset_directory_lock/2` | Clears the directory failure counter of a user name at an LDAP provider and prints `:ok`, `{:error, :not_found}` or `{:error, :unavailable}`. |
| `import_pack/2` | Imports a content pack directory as `mix espalier.import` does, prints the report and the outcome, and publishes the import unless `draft: true` is given. It converts the media files of the pack in its own process before the publish, and prints one line `<path>: <status>` per media file that is not ready. |
| `create_api_client/2` | Creates a client of the integration API with a name and scopes and prints its token once. |
| `seed_demo/0` | Imports and publishes the demo pack of the image with its media files and seeds the policy `usage-policy` and the approved tools of the demo. |

The calls:

```sh
# migrate/0
docker compose exec app bin/migrate
# rollback/2: VERSION is a number from the table schema_migrations
docker compose exec app bin/espalier eval 'Espalier.Release.rollback(Espalier.Repo, VERSION)'
# rotate_encryption/0 and encryption_status/0
docker compose exec app bin/espalier eval 'Espalier.Release.rotate_encryption()'
docker compose exec app bin/espalier eval 'Espalier.Release.encryption_status()'
# grant_role/2 with a role (learner, facilitator, author, registrar, analyst, admin)
docker compose exec app bin/espalier eval 'Espalier.Release.grant_role("admin", "a@example.org")'
# invite_user/1
docker compose exec app bin/espalier eval 'Espalier.Release.invite_user("a@example.org")'
# end_all_sessions/0
docker compose exec app bin/espalier eval 'Espalier.Release.end_all_sessions()'
# check_ldap/1 and reset_directory_lock/2 with a provider key
docker compose exec app bin/espalier eval 'Espalier.Release.check_ldap("ldap")'
docker compose exec app bin/espalier eval 'Espalier.Release.reset_directory_lock("ldap", "jdoe")'
# import_pack/2 with the pack directory mounted read-only
docker compose run --rm -v "$PWD/packs/my-pack:/srv/packs/my-pack:ro" app \
  bin/espalier eval 'Espalier.Release.import_pack("/srv/packs/my-pack")'
docker compose run --rm -v "$PWD/packs/my-pack:/srv/packs/my-pack:ro" app \
  bin/espalier eval 'Espalier.Release.import_pack("/srv/packs/my-pack", draft: true)'
# create_api_client/2
docker compose exec app bin/espalier eval 'Espalier.Release.create_api_client("hr-system", ["credentials:read"])'
# seed_demo/0
docker compose exec app bin/espalier eval 'Espalier.Release.seed_demo()'
```

The versions for `rollback/2` come from `psql` (section "Database access"):

```sh
docker compose exec db psql -U postgres -d espalier_prod \
  -c 'select version from schema_migrations order by version desc limit 5'
```

A downgrade runs `rollback/2` in the newer image, which carries the
migrations to revert, before the older image starts.
[`content-packs.md`](content-packs.md) describes the pack import, and
[`identity-providers.md`](identity-providers.md) the LDAP checks.

## Logs

### Format and security events

The application writes its logs to standard output only, as one JSON object
per line at the level `info` and above. A line holds `time` (UTC), `level`,
`message`, `request_id` and the attributes of a security event.
Authentication, session, authorization and account events carry the names
of the OWASP Logging Vocabulary in `event`, such as `authn_login_success`,
`authn_login_fail`, `session_created` and `authz_fail`. No line holds a
password, code, token, cookie value or e-mail address. The inventory of
every event, every other logged failure and what is never logged is
[`../security/logging.md`](../security/logging.md). Administrative actions
are also written to the table `audit_events`, which the admin area shows
on its audit page.

```sh
docker compose logs -f app
docker compose logs --no-color app | grep '"event":"authn_login_fail"'
```

`make docker-logs` runs the first command.

### Lines at boot

Every boot logs the effective session and data protection settings in one
line, with values only and no secret or address
(`Espalier.Application.settings_line/0`). With the defaults of
`.env.example`, the line reads:

```text
Effective settings: SESSION_IDLE_MINUTES=60 SESSION_MAX_HOURS=24 SESSION_MAX_CONCURRENT=5 SIGNUP=closed LOCAL_ACCOUNTS=true AUTH_DEMO=false PASSWORD_BREACH_CHECK=off TRACKING_DETAIL=minimal INSIGHTS_ORG_UNIT=false REGISTRAR_ENABLED=false INSIGHTS_MIN_GROUP_SIZE=5 FEEDBACK_FREE_TEXT=false TEST_NOTES=false RETENTION_ATTEMPTS_DAYS=unset RETENTION_ITEM_RESPONSES_DAYS=unset RETENTION_ANONYMOUS_DAYS=unset RETENTION_AUDIT_DAYS=unset; providers: none
```

Each provider appears after `providers:` with its key, type and MFA mode,
for example `entra (entra, MFA local)`. The boot also logs the line
`Encryption keys: ...` with the cipher tags of the Cloak keys
([`../security/key-management.md`](../security/key-management.md), section
"Boot checks") and one line per LDAP provider with key, host, port, TLS
mode, directory profile and the number of mapped groups.

The boot logs a warning for each of these settings:

| Setting | Warning |
|---|---|
| `AUTH_DEMO=true` | `AUTH_DEMO=true: demo sign-in is enabled; use it for test sessions only` |
| `SESSION_MAX_HOURS` above 24 | `SESSION_MAX_HOURS is above 24, which deviates from decision D9 (NIST AAL2, ASVS 7.1.1)` |
| `ADMIN_REQUIRE_PASSKEY=false` | `ADMIN_REQUIRE_PASSKEY=false: admins may sign in and work without a passkey` |
| no `SMTP_HOST` | `SMTP_HOST is not set: this instance delivers no mail` |
| an OIDC provider with `AUTH_<KEY>_MFA=idp_trusted` | one warning per provider ([`identity-providers.md`](identity-providers.md), section "MFA modes") |

A setting that is missing or invalid stops the boot before these lines with
the message `The environment stops the boot:` and one line per gap
([`self-hosting.md`](self-hosting.md), section "How the settings are read").

### Log access

The application writes to standard output and keeps no log file. The
container user `nobody` therefore has no file to change or delete: the
Docker daemon reads the output and stores it. With the default logging
driver `json-file`, the daemon writes the lines to files in its data
directory on the host, and `docker logs` and `docker compose logs` read them
there (ASVS 16.4.2).

Whoever can run `docker` on the host reads these logs. The same access
shows the environment of the containers, secrets included, with
`docker inspect`, and members of the `docker` group can start a container
with root rights on the host, so membership in that group equals root
access. Restrict it, and with it the log access, to the operators of the
instance.

The `json-file` driver rotates no file by default. Its options `max-size`
and `max-file` limit the stored logs; the retention period of the logs is
the operator's decision.

### Forwarding to a separate system

`docs/guides/examples/compose.logging.yaml` forwards the logs of `app` over
TLS to a syslog receiver on a separate system, so that a copy of every line
lies outside the host of the instance (ASVS 16.4.3):

```sh
docker compose -f compose.yaml -f docs/guides/examples/compose.logging.yaml up -d
```

| Variable | Content |
|---|---|
| `SYSLOG_HOST` | host name of the receiver, which its certificate must name, for example `logs.example.org` |
| `SYSLOG_CA_CERT` | path on the Docker host of the CA certificate that signed the certificate of the receiver |

The file sets the `syslog` logging driver of Docker for `app` with the
address `tcp+tls://<SYSLOG_HOST>:6514`, the CA file of `SYSLOG_CA_CERT`, the
format `rfc5424micro` and the tag `espalier`. The daemon sends each line of
standard output as one RFC 5424 message, and the JSON object of the line is
its message text. The driver rejects every option key it does not know with
`unknown log opt`;
`docker compose -f compose.yaml -f docs/guides/examples/compose.logging.yaml create app`
checks the options without starting the container. On a running instance,
`create` replaces the container of `app` with a stopped one, so run the
check before `up`, or start `app` again afterwards. Combine the file with
the proxy example by adding both `-f` options or both entries of
`COMPOSE_FILE`.

The Docker documentation ("Use docker logs with remote logging drivers")
states that `docker logs` reads the container logs regardless of the
configured logging driver: when the driver supports no reading, the Docker
Engine keeps the latest lines in a local cache, by default at most 5 files
of 20 MB each per container, and the option `cache-disabled` switches the
cache off. The cache lies on the host as well, so the access rule of the
section "Log access" applies to it. The same page states that a network
issue of a remote driver prevents the write to the local cache.

## Health

`GET /health` runs `SELECT 1` against the database. It answers 200 with
`{"status":"ok"}`, or 503 with `{"status":"error"}` when the database does
not answer. The route is public (README section 8) and carries no other
data.

```sh
curl -fsS http://localhost:4000/health
docker compose ps
```

The image defines a health check that runs `/app/bin/health` every 10
seconds, with a timeout of 5 seconds, a start period of 30 seconds and 3
retries before the status `unhealthy`. The script asks `/health` on the port
of `PORT` (default 4000), which it reads as `config/runtime.exs` does.
`docker compose ps` shows the status. The service `db` runs
`pg_isready` every 5 seconds, `app` starts after `db` is healthy, and the
proxy example starts `caddy` after `app` is healthy. The restart policy
`unless-stopped` restarts a container whose process ends; the health status
itself restarts no container.

## Background jobs

Oban runs the background jobs in the database (table `oban_jobs`). The queues
of `config/config.exs`:

| Queue | Slots | Jobs |
|---|---|---|
| `default` | 10 | the scheduled jobs below |
| `mail` | 5 | every mail (`Espalier.Accounts.MailWorker`), up to 5 attempts |
| `webhooks` | 5 | the credential events to webhook receivers (`Espalier.Credentials.WebhookWorker`), up to 10 attempts |
| `exports` | 1 | the SCORM exports (`Espalier.Interop.ExportWorker`), one at a time, one attempt |
| `media` | 2 | the conversion of images, SVG files and captions (`Espalier.Media.ProcessWorker`), two at a time, one attempt |
| `media_video` | 1 | the conversion of videos (`Espalier.Media.ProcessWorker`), one at a time, one attempt |

The plugin `Oban.Plugins.Cron` schedules these jobs, in UTC:

| Schedule | Job | Work |
|---|---|---|
| 02:00 daily | `Espalier.Accounts.PurgeExpiredTokensWorker` | deletes expired tokens, session rows idle for `SESSION_IDLE_MINUTES` and expired WebAuthn challenges |
| 03:00 daily | `Espalier.Credentials.SweepWorker` | moves credentials to `refresh_due` or `expired` |
| 03:30 daily | `Espalier.Insights.RetentionWorker` | the retention job of the next section |
| 03:45 daily | `Espalier.Media.RetentionWorker` | deletes the imported media assets (origin `pack`) that no program, draft or validated import has used for 30 days, with their files ([`media.md`](media.md), section "Deletion and retention") |
| every 15 minutes | `Espalier.Interop.StaleExportWorker` | ends interrupted SCORM exports and applies the export retention ([`scorm-export.md`](scorm-export.md)) |
| every 15 minutes | `Espalier.Media.StaleWorker` | fails media assets whose job was interrupted with `interrupted`, and removes incoming files, work and staging directories, upload files and stored files that no asset names, each older than one hour ([`media.md`](media.md), section "Failures and timeouts") |

`Oban.Plugins.Pruner` deletes finished jobs after one day. No
`Oban.Plugins.Lifeline` is configured, so the job row of a build that a
stop of the node interrupted keeps the state `executing`. The jobs per
queue and state:

```sh
docker compose exec db psql -U postgres -d espalier_prod \
  -c 'select queue, state, count(*) from oban_jobs group by queue, state order by queue, state'
```

The logged failures of the workers (`mail delivery failed`, `webhook
failed`, `export failed`, `media asset <id> failed` and others) are listed in
[`../security/logging.md`](../security/logging.md), section "Other logged
failures".

### Output of the retention job

The retention job applies the retention variables of README section 10. An
unset variable deletes nothing, and the job logs one line at `info` for it:

```text
retention RETENTION_ITEM_RESPONSES_DAYS unset
retention RETENTION_ANONYMOUS_DAYS unset
retention RETENTION_AUDIT_DAYS unset
retention RETENTION_ATTEMPTS_DAYS unset
```

These four lines are the output of every run with the defaults. A set
variable deletes the rows older than its limit in days and logs one line
per table instead, with the number of deleted rows:

| Variable | Line |
|---|---|
| `RETENTION_ITEM_RESPONSES_DAYS` | `retention deleted <n> rows from item_responses` |
| `RETENTION_ANONYMOUS_DAYS` | one line each for `self_assessment_responses`, `interest_votes` and `feedback_responses` |
| `RETENTION_AUDIT_DAYS` | `retention deleted <n> rows from audit_events` |
| `RETENTION_ATTEMPTS_DAYS` | `retention deleted <n> rows from assessment_attempts`; the newest passed attempt that a credential in force depends on stays |

After the deletions, every run rewrites the three anonymous tables and
`participation_markers` and reorders each by its random primary key, which
logs no line (README section 10). The lines of the last runs:

```sh
docker compose logs --no-color app | grep '"message":"retention '
```

## Backup and restore of the media store

The database names every delivery file and poster of the media library by
its SHA-256 digest, and `MEDIA_DIR/files/` holds these files
([`media.md`](media.md), section "The media store"). `MEDIA_DIR/incoming/`
holds the files that wait for their conversion. A backup holds the database
dump of [`self-hosting.md`](self-hosting.md), section "Backups", and these
two directories from the same moment; `work/` and `uploads/` hold temporary
files only. An upload, a conversion or a deletion can change the database
and the files between two commands, so the backup stops `app` for both:

```sh
docker compose stop app
(umask 077; docker compose exec -T db pg_dump -U postgres -Fc espalier_prod \
  > /var/backups/espalier/espalier.dump)
(umask 077; docker compose run --rm --no-deps -T app \
  tar -C /data/media -cf - files incoming > /var/backups/espalier/media.tar)
docker compose start app
```

`docker compose run` starts a container of the image of `app` with its
volumes and runs `tar` as the user `nobody` in place of the server, and
`--no-deps` leaves the other services as they are. The archive goes to
standard output and from there into the backup directory, with the mode 600.
The restore loads the dump, replaces both directories and starts the
application again:

```sh
docker compose stop app
docker compose exec -T db \
  pg_restore -U postgres -d espalier_prod --clean --if-exists \
  < /var/backups/espalier/espalier.dump
docker compose run --rm --no-deps -T app \
  sh -c 'rm -rf /data/media/files /data/media/incoming && tar -C /data/media -xf -' \
  < /var/backups/espalier/media.tar
docker compose start app
```

After the start, the queued conversions of the backup run again. An asset
that was `processing` when `app` stopped turns `failed` with `interrupted`
at the first run of `Espalier.Media.StaleWorker` (every 15 minutes) at which
its last change lies more than ten minutes back, for a video as for an
image. A running job sets the time of the last change of its asset every
minute, so that change lies at most one minute before the stop
([`media.md`](media.md), section "Failures and timeouts"). The same file
then converts again when an author uploads it or the pack is imported again;
before that, an upload of the same file returns the asset in `processing`.
The media files are course content in plain form and need no key of the
instance; images and videos that show persons make the archive personal
data, which the backup directory of `self-hosting.md` protects with its
mode.

## Ending sessions

An admin ends the sessions of one person on the page `/admin/users` with
"End sessions", and the sessions of every person with "End all sessions"
in the section "All sessions" of the same page. Both actions need the role
`admin`, the passkey of an admin while `ADMIN_REQUIRE_PASSKEY=true`, and a
second factor from the last 10 minutes. "End all sessions" ends the session
of the acting admin as well. The audit events are `sessions.ended` and
`sessions.ended_all`. Disabling an account and a change of its role grants
also end every session of that person.

Without the admin area, the release function ends every session of every
user and prints the number of ended sessions:

```sh
docker compose exec app bin/espalier eval 'Espalier.Release.end_all_sessions()'
```

## Keys and certificates

[`../security/key-management.md`](../security/key-management.md) holds the
procedures:

| Task | Section |
|---|---|
| Rotate `SECRET_KEY_BASE`; every user signs in again | [`SECRET_KEY_BASE`](../security/key-management.md#secret_key_base) |
| Rotate the token of an API client | [API client tokens](../security/key-management.md#api-client-tokens) |
| Check the expiry of the database certificates (825 days from the first start) and renew them | [Database certificates](../security/key-management.md#database-certificates) |
| Rotate the Cloak encryption key with `rotate_encryption/0` | [Runbook: rotate the encryption key](../security/key-management.md#runbook-rotate-the-encryption-key) |
| The HMAC secret, which has no rotation | [HMAC secret](../security/key-management.md#hmac-secret) |
| The certificate of the reverse proxy | [Certificate of the reverse proxy](../security/key-management.md#certificate-of-the-reverse-proxy) |

`db-certs` prints the expiry of the database server certificate at every
start of the services:

```sh
docker compose logs db-certs
```

## Database access

`psql` in the container `db` connects over the local socket:

```sh
docker compose exec db psql -U postgres -d espalier_prod
```

The database holds the learning records of README section 10. That section
also describes what a reader of the tables, the write-ahead log or a backup
can match between anonymous rows and participation markers; operators who
need protection against that restrict database access accordingly.
