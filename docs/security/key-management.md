# Key management

This document describes the lifecycle of the encryption keys and the HMAC
secret of Espalier, from generation through storage, boot checks and rotation
to retirement and loss (ASVS 11.1.1). The section "Other keys and
certificates" describes the lifecycle of `SECRET_KEY_BASE`, of the API client
tokens and of the certificates of the database connection. The keys,
algorithms and protected columns are listed in
[`crypto-inventory.md`](crypto-inventory.md).

## Keys

| Name | Purpose | Format | Generation | Storage | Rotation |
|---|---|---|---|---|---|
| `CLOAK_KEY_V<n>` | AES-256-GCM key of the cipher tag `AES.GCM.V<n>`. The highest version encrypts new values; lower versions only decrypt. | 32 random bytes, Base64 with padding (44 characters) | `make gen-keys` or `openssl rand -base64 32` | environment, filled from the operator's secret store; an offline copy of every version that still protects data | runbook below |
| `CLOAK_HMAC_SECRET` | HMAC-SHA256 key of the keyed hash columns, and input of the recovery-code key (README section 6.6) | 32 random bytes, Base64 with padding (44 characters) | `make gen-keys` or `openssl rand -base64 32` | environment, filled from the operator's secret store; an offline copy | none in the first version (section "HMAC secret") |

## Generation

`make gen-keys` prints one new `CLOAK_KEY_V1` and one new `CLOAK_HMAC_SECRET`,
each 32 bytes from `:crypto.strong_rand_bytes/1` (a CSPRNG), Base64-encoded
(ASVS 11.5.1). On a machine without the toolchain, `openssl rand -base64 32`
generates one value per call. For a rotation, the new value goes into the
next version, for example `CLOAK_KEY_V2`.

The repository holds no production key. `config/dev.exs` and `config/test.exs`
hold invented keys built from a repeated character, which protect local and
test data only.

## Storage and access

Keys come from the environment, filled from the operator's secret store
(ASVS 13.3.1). They never enter the repository, the database, a log or the
backup set of the database. Only the people who deploy the application can
read them; developers work with the development keys (ASVS 13.3.2).

For every key version that still protects data in live rows or in a retained
backup, an offline copy is kept apart from the database backups. Losing every
copy of such a key makes those values unreadable for good. A backup that
holds both the database and the keys protects nothing.

## Boot checks

`config/runtime.exs` calls `Espalier.BootCheck.errors/2` directly after
`import Config`, before it builds any configuration, and raises once with
every message of the list, so that one boot names every gap of the
environment, the keys among them:

```text
The environment stops the boot:
  * Missing environment variables: SECRET_KEY_BASE, CLOAK_KEY_V1
```

`config/runtime.exs` then reads the keys in production, and
`Espalier.Crypto.Keys.check!/0` checks their values as the first step of
`Espalier.Application.start/2`, before the vault starts. The release
functions `rotate_encryption/0` and `encryption_status/0` run the same check.
No message contains a key value.

| Check | Message |
|---|---|
| A required variable is unset, empty or holds only whitespace, also inside one pair of double quotes (production): `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `DATABASE_CA_CERT_FILE`, `CLOAK_KEY_V1` when no `CLOAK_KEY_V<n>` holds a value, and `CLOAK_HMAC_SECRET` | `Missing environment variables: <names>`, one message that lists every missing variable in this order; `Espalier.BootCheck` returns it, and `config/runtime.exs` raises it together with every other message of `Espalier.BootCheck.errors/2` |
| `SECRET_KEY_BASE` is shorter than 64 bytes (production) | `SECRET_KEY_BASE is shorter than 64 bytes; generate one with mix phx.gen.secret` (`Espalier.BootCheck`) |
| `DATABASE_URL` has no host, the server name of the TLS connection, or a path other than one database name (no name, a trailing `/` or a second segment), for which Ecto would print the URL with its password (production) | `DATABASE_URL must be an ecto:// URL with a host and a database name` (`Espalier.BootCheck`) |
| `POOL_SIZE` holds a value that is no positive integer (production) | `POOL_SIZE must be a positive integer` (`Espalier.BootCheck`) |
| `DATABASE_URL` holds the query parameter `ssl`, which Ecto merges over the TLS options of the Repo (production) | `DATABASE_URL must not set ssl; TLS comes from DATABASE_CA_CERT_FILE` (`Espalier.BootCheck`) |
| `DATABASE_URL` gives the query parameter `timeout`, `pool_size` or `idle_interval` a value that is no integer, for which Ecto would print the URL with its password (production) | `DATABASE_URL must give timeout, pool_size and idle_interval as integers` (`Espalier.BootCheck`) |
| `DATABASE_CA_CERT_FILE` names no regular file (production) | `DATABASE_CA_CERT_FILE names no file` (`Espalier.BootCheck`) |
| `SMTP_PORT` holds a value that is no integer from 1 to 65535 (production) | `SMTP_PORT must be a port number from 1 to 65535` (`Espalier.BootCheck`) |
| `PORT` holds a value that is no integer from 1 to 65535 (every environment) | `PORT must be a port number from 1 to 65535` (`Espalier.BootCheck`) |
| `PUBLIC_URL` uses another scheme than `https` (production) | `PUBLIC_URL must use https in production, because passkeys derive their origin from it` (`Espalier.BootCheck`) |
| `PUBLIC_URL` holds user info, a path other than `/`, a query or a fragment (production) | `PUBLIC_URL must be an origin without user info, path, query or fragment` (`Espalier.BootCheck`) |
| The host of `PUBLIC_URL` differs from `PHX_HOST`, compared without regard to case (production) | `The host of PUBLIC_URL must equal PHX_HOST` (`Espalier.BootCheck`) |
| A value is not Base64 with padding or does not decode to exactly 32 bytes | `CLOAK_KEY_V<n> must be 32 random bytes, Base64-encoded`, or the same with `CLOAK_HMAC_SECRET` |
| Two key versions hold the same key | `CLOAK_KEY_V1 and CLOAK_KEY_V2 hold the same key` |
| The HMAC secret equals an encryption key | `CLOAK_HMAC_SECRET must differ from every CLOAK_KEY_V<n>` |
| No key is configured at all (outside production) | `No encryption key is configured; set CLOAK_KEY_V1` |

`config/runtime.exs` reads every variable `CLOAK_KEY_V<n>` whose `n` is a
positive integer without leading zeros; other names, such as `CLOAK_KEY_V01`,
are ignored. After the checks, the node logs one line that names the tags:

```text
[info] Encryption keys: AES.GCM.V2 encrypts, AES.GCM.V1 decrypts only
```

## Memory of the running node

The node holds the keys, the HMAC secret and decrypted values in memory
(`crypto-inventory.md`, Limits (1)). The release environment `rel/env.sh.eex`
therefore sets two defaults that every command of `bin/espalier` reads:

- `ERL_CRASH_DUMP_BYTES=0`: the runtime writes no crash dump file.
- `RELEASE_DISTRIBUTION=none`: the node starts no Erlang distribution, so
  `bin/espalier remote` and `bin/espalier rpc` cannot attach to it.
  `bin/espalier eval` starts a node of its own and keeps working. The image
  holds no `releases/COOKIE`, and each command receives a `RELEASE_COOKIE`
  of 32 random bytes from `/dev/urandom` in hex that no other node knows.

An operator who overrides either default for a debugging session or for a
cluster (`DNS_CLUSTER_QUERY` with `RELEASE_DISTRIBUTION=name` and a random
`RELEASE_COOKIE`) lets a crash dump or a remote console reach the keys. A
crash dump file then needs the same protection as the keys themselves; set
`ERL_CRASH_DUMP` to a path outside the image and delete the file after use.
With distribution, `rel/env.sh.eex` stops every command that has no
`RELEASE_COOKIE`; `openssl rand -hex 32` generates the value, and every node
of the cluster receives the same one from the secret store. The nodes then
connect to each other on the epmd port 4369 and on the distribution port of
each node. This traffic carries decrypted values and runs over plain TCP
without TLS, unless the operator configures `-proto_dist inet_tls` with the
options of `-ssl_dist_optfile` in the VM arguments of the release; the cookie
authenticates the nodes and encrypts nothing. `bin/espalier start` passes
`RELEASE_COOKIE` to the BEAM as `-setcookie` on its command line, where every
user of the host can read it in `/proc/<pid>/cmdline` unless `/proc` is
mounted with `hidepid=1` (`noaccess`) or a stricter value, which still lets
the group of its `gid=` option read it. A cluster on a host with other local users therefore runs the
distribution over TLS with `verify_peer` and `fail_if_no_peer_cert` in the
options of `-ssl_dist_optfile`, so that the cookie alone admits no node.

## Cryptoperiod and rotation triggers

The operator sets a cryptoperiod for the encryption key. NIST SP 800-57
Part 1 Rev. 5 (May 2020, section 5.3.6, item 6 b, and Table 1), the current
final version on 2026-10-08, suggests an originator-usage period of up to two
years for a symmetric data-encryption key that encrypts smaller volumes of
data, and a recipient-usage period of no more than three years beyond the end
of the originator-usage period. Revision 6 of that publication exists as an
initial public draft of December 2025. In Espalier, the originator-usage
period is the time during which a key version is the highest version and
encrypts new values. After a rotation, the old version only decrypts values in
retained backups.

Rotate earlier in these cases:

- after a suspected exposure of a key;
- when a person with key access leaves;
- before 2^32 encryptions under one key, the limit that NIST SP 800-38D
  (section 8.3) sets for random 96-bit IVs. Each write of an encrypted field
  counts as one encryption.

## Runbook: rotate the encryption key

1. Generate a key and store it as `CLOAK_KEY_V2`; keep `CLOAK_KEY_V1`.
2. Restart every application node. The boot log shows
   `AES.GCM.V2 encrypts, AES.GCM.V1 decrypts only`. Note the UTC time at which
   the last node has restarted.
3. Run `docker compose exec app bin/espalier eval "Espalier.Release.rotate_encryption()"`
   (in a plain release, `bin/espalier eval` with the same expression). It
   prints the rows per rotation schema and the tags per column.
4. Run `Espalier.Release.encryption_status()` the same way and confirm that
   every column reports only `AES.GCM.V2`.
5. Wait for the values of the section "Values encrypted outside Ecto types" of
   `crypto-inventory.md`, which the rotation does not rewrite. For the Oban
   mail jobs of 0004, run
   `SELECT count(*) FROM oban_jobs WHERE inserted_at < '<time of step 2>' AND state IN ('available', 'scheduled', 'executing', 'retryable')`
   in `psql` and repeat it until it returns 0.
6. Take a new database backup.
7. Remove `CLOAK_KEY_V1` from the environment and restart.

Every backup taken before the backup of step 6, including a backup taken
while step 3 ran, still holds V1 values. The offline copy of V1 therefore
stays until every backup taken before the backup of step 6 has expired, and
is destroyed after that.

If step 3 stops halfway, the table holds V1 and V2 values side by side. Both
stay readable while both keys are configured, and step 3 can run again.

`rotate_encryption/0` locks each batch of 500 rows with `FOR UPDATE`, so it
can run while the application serves requests; a concurrent write waits for
the batch. It leaves `updated_at` and the hash columns untouched.

## HMAC secret

The first version has no rotation for `CLOAK_HMAC_SECRET`, because Cloak
cannot re-hash a value without its plaintext. The secret alone reveals no
data; together with a dump it allows offline guessing of hashed values. A
change of the secret also invalidates every stored recovery code, because the
recovery-code key derives from it (`Espalier.Accounts.RecoveryCodes.key/0`,
README section 6.6), so every user then regenerates the codes with
`POST /api/me/recovery-codes`. No rotation procedure exists for this secret. A rotation needs a second hash column per lookup,
filled from the decrypted plaintext, a switch of every lookup, and the removal
of the old column. That work is a task of its own.

## Upstream status and fallback plan

The pinned versions are `cloak` 1.1.4 and `cloak_ecto` 1.3.0. Both were
released on 2024-04-06, and both have one owner on Hex. Two advisories
without a fixed version affect modules that Espalier does not use, and
`mix.exs` lists them under `hex: [ignore_advisories: [...]]`:

- EEF-CVE-2026-95105 (HIGH): `Cloak.Ciphers.AES.CTR` and
  `Cloak.Ciphers.Deprecated.AES.CTR` store no MAC.
- EEF-CVE-2026-94206 (MEDIUM): `Cloak.Ecto.PBKDF2.dump/1` runs 32 rounds where
  600,000 are configured.

The vault holds only `Espalier.Crypto.StrictAESGCM`, lookups use
`Cloak.Ecto.HMAC`, and `test/espalier/crypto/cipher_allowlist_test.exs` fails
if another cipher is configured or if `lib/` or `config/` names one of the
affected modules. An ignored advisory stays acceptable only while these
conditions hold.

### Watch list

At every Espalier release, and whenever `mix hex.audit` or `mix deps.get`
reports a new advisory, the maintainer runs `mix hex.outdated`, reads the
advisory tracking issues cloak#132 and cloak_ecto#66, the release request
cloak_ecto#64, cloak_ecto PR #58 (`Ecto.Enum` fix) and cloak PR #128 (12-byte
IV default), and records the date and the result in the table below. An
upstream release is adopted after a review of its `lib/` diff against the
pinned version and a green run of `test/espalier/crypto/`, again pinned
exactly.

| Date | Result | Decision | Next review |
|---|---|---|---|
| 2026-10-08 | `cloak` 1.1.4 and `cloak_ecto` 1.3.0 are the latest Hex releases. cloak#132, cloak_ecto#66 and cloak_ecto#64 are open, and cloak_ecto PR #58 and cloak PR #128 are open and unmerged. No release fixes EEF-CVE-2026-95105 or EEF-CVE-2026-94206. | Keep the pins; first review of trigger (d). | 2027-04-08 |

### Triggers

The fallback starts when one of these triggers fires:

- (a) An advisory affects `Cloak.Ciphers.AES.GCM`, `Cloak.Vault`,
  `Cloak.Ecto.Type`, `Cloak.Ecto.Binary`, `Cloak.Ecto.Map` or
  `Cloak.Ecto.HMAC`.
- (b) An Elixir, OTP or Ecto release that the project adopts stops compiling
  `cloak` or `cloak_ecto` or makes a test under `test/espalier/crypto/` fail.
- (c) The threat model grows to an attacker with write access to the
  database.
- (d) The review date recorded in the watch list has passed, and since the
  previous review neither package has published a release that fixes
  EEF-CVE-2026-95105 or EEF-CVE-2026-94206 or contains the fix of
  cloak_ecto PR #58 (README section 6.9).

When trigger (d) fires, the maintainer either opens the fallback task or
records in the watch list a decision to keep the pins, with the date, the
reason and a new review date at most six months later.

### Fallback

The fallback stays inside the application and uses no fork as a Git
dependency. It is one change with these parts:

1. `Espalier.Crypto.AESGCM` on `:crypto.crypto_one_time_aead/6` and `/7`
   (AES-256-GCM, 12-byte IV from `:crypto.strong_rand_bytes/1`, 16-byte tag,
   failure returns `:error`) reads the Cloak format
   `<<1, tag_length, tag, iv::binary-12, gcm_tag::binary-16, ciphertext>>` with
   the AAD `"AES256GCM"` for the existing tags, and writes a new tag whose AAD
   names table and column.
2. `Espalier.Encrypted.*` become own `Ecto.ParameterizedType` modules under
   the same module names, so migrations stay unchanged.
3. Every encrypted field in a full schema and in its rotation-only schema gains
   the option `aad:` with its table and column, for example
   `field :email, Espalier.Encrypted.Binary, redact: true, aad: "users.email"`,
   and `init/1` raises when the option is missing. The AAD comes from this
   option, because Ecto passes the schema module and the field name to
   `init/1` and no table name. A full schema and its rotation-only schema are
   two modules on one table, so an AAD derived from the module would differ
   between them and the rotation could not read the values.
4. `Espalier.Crypto.Rotation` and `Espalier.Crypto.SchemaRules` read the
   module from `{:parameterized, {module, params}}`, as
   `SchemaRules.cloak_type?/1` already does.
5. `Espalier.Hashed.HMAC` computes `:crypto.mac(:hmac, :sha256, secret, value)`
   in `dump/1` and `hash/1`, the same bytes that `Cloak.Ecto.HMAC` stores, so
   every hash column stays valid.
6. `rotate_encryption/0` moves all rows to the new tag. After that, `cloak` and
   `cloak_ecto` leave `mix.exs` together with the `ignore_advisories` entries.
7. The tests under `test/espalier/crypto/` run against the new modules, except
   the assertions that record upstream behavior.

## Other keys and certificates

The keys and certificates of this section protect no stored column. Their
algorithms and locations are listed in
[`crypto-inventory.md`](crypto-inventory.md), section "Keys and algorithms
outside the database". None of them enters the repository, the image or a
log.

### `SECRET_KEY_BASE`

- Generation: `mix phx.gen.secret`, which prints 64 random characters, or 64
  random bytes in Base64 on a machine without the toolchain:
  `head -c 64 /dev/urandom | base64 | tr -d '\n'` (88 characters).
  `scripts/fill-secrets.sh`, which `make demo-env` and `scripts/smoke.sh`
  run, uses the second way. `Espalier.BootCheck` stops a production boot
  with a missing value or a value shorter than 64 bytes (section "Boot
  checks").
- Storage: the environment, filled from the operator's secret store, like
  the Cloak keys. The node keeps the value in the endpoint configuration of
  the application environment.
- Rotation: generate a new value, replace the old one in the secret store and
  restart every application node. The endpoint holds one value at a time.
  Rotate after a suspected exposure and when a person with access to the
  value leaves.
- Effect of a rotation: every session cookie `__Host-espalier` and every
  transaction cookie `__Host-espalier_tx` becomes unreadable, because task
  0004 derives their encryption and signing keys from the value (the
  `Plug.Session` cookie store with the salts of
  `EspalierWeb.TransactionCookie`). Every user signs in again, and a sign-in
  in progress, a pending second factor or an OIDC flow, starts again. The
  session rows of the old cookies stay in `users_tokens` until the daily
  purge deletes them once they are idle for the inactivity limit;
  `docker compose exec app bin/espalier eval "Espalier.Release.end_all_sessions()"`
  deletes them at once. The rate-limit key derives from the value as well
  (`Espalier.RateLimit.init_key/1` at boot), so the account keys of the rate
  limit buckets change, and a security event carries another `account_hash`
  for the same identifier after the rotation than before it. The rate limit
  counters live in ETS and start empty at every restart.

### API client tokens

- Generation: `Espalier.Accounts.create_api_client/2` draws 32 bytes with
  `:crypto.strong_rand_bytes/1`, stores their SHA-256 hash in
  `api_clients.token_hash` and returns the token once, Base64url-encoded
  without padding. Two entry points create a client: the release function
  `docker compose exec app bin/espalier eval 'Espalier.Release.create_api_client("hr-system", ["credentials:read"])'`,
  which prints the token once, and the admin area of task 0015
  (`POST /api/admin/api-clients`). The only scope is `credentials:read`.
- Storage: the receiving system keeps the token in its own secret store. The
  platform holds the hash only and cannot show the token again. A token has
  no expiry and stays valid until its client is deleted.
- Rotation: create a new client with the same scopes, set its token in the
  receiving system, and then delete the old client in the admin area
  (`DELETE /api/admin/api-clients/:id`), which writes the audit event
  `api_client.deleted`. The release has no function that deletes a client.
  Rotate after a suspected exposure of a token and when the receiving system
  changes hands.
- Effect of a rotation: both tokens are valid until the old client is
  deleted. From then on, the old token answers 401 `unauthenticated`, and
  each such request logs `authn_login_fail` with the factor `api_token`.

### Database certificates

- Generation: the one-shot service `db-certs` of `compose.yaml` runs before
  `db` at every start of the services. On its first run, when the volumes
  hold no `server.pem`, `server.key` and `ca.pem`, it generates with
  `openssl` a CA (`CN=Espalier database CA`) and a server certificate for the
  host name `db` (subject alternative name `DNS:db`), both with EC P-256
  keys, ECDSA signatures with SHA-256 and a validity of 825 days, and a
  `pg_hba.conf` that admits TCP connections with TLS only. The CA key exists
  only in a temporary directory, which the service deletes when it exits, so
  no further certificate can be signed with that CA. A later run finds the
  files, changes nothing and prints the expiry of `server.pem`.
- Storage: `server.pem`, `server.key` (owner uid 999, the `postgres` user of
  the image, mode 600) and `pg_hba.conf` lie in the volume `db-tls`, which
  `db` mounts read-only. `ca.pem` lies in the volume `db-ca`, which `app`
  mounts read-only and `DATABASE_CA_CERT_FILE` names. The server key is the
  only secret of these files, so a backup of `db-tls` needs the protection of
  a key.
- Validity: 825 days from the first start. The first start on 2026-10-15
  printed `notAfter=Jan 17 09:35:47 2029 GMT`. This command shows the expiry
  in the directory of `compose.yaml`, with the `-p` option of the instance
  when it runs under another project name:

  ```sh
  docker compose run --rm --entrypoint openssl db-certs x509 -enddate -noout -in /tls/server.pem
  ```

  It prints `notAfter=<date>`, and `db-certs` prints the same value at every
  start. After that date, the application rejects the server certificate and
  reaches no database, so the renewal comes before it.
- Renewal:

  1. `docker compose down` stops and removes the containers and keeps the
     volumes. `docker compose down -v` would also delete `db_data`, the
     database.
  2. `docker volume rm espalier_db-tls espalier_db-ca` removes the
     certificates. The prefix is the project name, `espalier` from `name:` in
     `compose.yaml`.
  3. `docker compose up -d`, with the same `-f` files as before, starts the
     services: `db-certs` generates a new CA and a new server certificate,
     `db` starts with them, and the application reads the new CA at its next
     start, which this step brings.

- Effect of a renewal: the instance is unavailable between steps 1 and 3,
  and the data in `db_data` stays. An application node outside this compose
  project needs a copy of the new `ca.pem` and a restart, so that it reads
  the new CA at its next start. With an external PostgreSQL, the renewal
  follows that server; when its CA changes, `DATABASE_CA_CERT_FILE` names the
  new CA, and every application node restarts.

### Certificate of the reverse proxy

In the Caddy example of `docs/guides/examples/`, Caddy generates the key,
obtains the certificate and keeps it renewed (Caddy documentation,
"Automatic HTTPS"): through ACME for a public `SITE_ADDRESS`, and from its
local CA for `localhost`. The volume `caddy_data` holds the certificate, its
key and, for the local CA, the keys `root.key` and `intermediate.key`, so a
backup of that volume needs the protection of a key. A proxy other than the
example follows the procedure of its own documentation.
