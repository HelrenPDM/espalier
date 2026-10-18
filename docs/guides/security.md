# Security

This guide summarizes the security settings of an Espalier instance for
operators and reviewers: the verification target and its deviations, secrets
and keys, sessions and second factors, the TLS settings of every connection,
the outgoing connections, the resource-demanding functions with their limits,
the abuse limits, and the dependency policy. The full verification matrix of
OWASP ASVS 5.0.0, with the owning task, the status, the code and the test of
every row, is [`docs/security/asvs-l2.md`](../security/asvs-l2.md). The setup
of an instance is described in [`self-hosting.md`](self-hosting.md), and its
operation in [`operations.md`](operations.md).

## Verification target

Espalier verifies against OWASP ASVS 5.0.0 Level 2, at the tag
`v5.0.0_release` of the OWASP ASVS repository, and against the Level 3 items
that README section 6.1 selects: 3.4.8 (`Cross-Origin-Opener-Policy`), 3.5.8
(Fetch Metadata), 6.3.5 and 6.3.7 (notifications), 6.3.8 (no enumeration)
and 6.5.6 (every factor revocable). The matrix holds one row per Level 1 and
Level 2 requirement and per selected Level 3 item, and each row names the
code and the test, or the reason why the requirement does not apply.
`test/docs/asvs_matrix_test.exs` checks the ownership table of the matrix
against the task specs in `make check`.

| Chapter | What the matrix covers | Rows that do not apply |
|---|---|---|
| V1 Encoding and Sanitization | Ecto queries with bound parameters, output encoding by React and in the SCORM manifests, LDAP filters from the `:eldap` constructors, Markdown without raw HTML, pack files parsed without atoms and within size, depth and time limits, the rebuild of every SVG file from an allowlist, the XML parser of the SVG rebuild without entities and external DTDs, and the ffmpeg and ffprobe processes, started with an argument list and without a shell | 1.2.7 to 1.2.9, 1.3.1, 1.3.8 to 1.3.10, 1.4.1 to 1.4.3 |
| V2 Validation and Business Logic | OpenAPI request schemas and changesets, the cross-file and alignment checks of the pack validator, the documented business limits, transactions and anti-automation limits | 2.3.4 |
| V3 Web Frontend Security | cookie attributes and `__Host-` names, the CSP and the other headers of README section 6.5, HSTS from the reverse proxy, a dedicated host name, `Cross-Origin-Opener-Policy` and Fetch Metadata (both Level 3) | none |
| V4 API and Web Service | content types with `charset=utf-8`, no plain HTTP from other hosts, the client address from trusted proxies only, and the request framing probes | 4.3.1 and 4.3.2 (no GraphQL), 4.4.1 to 4.4.4 (no WebSocket) |
| V5 File Handling | the pack upload with its size, entry and path checks, the drafts of the pack workbench, the SCORM export downloads, the media upload with its signature, size and pixel checks and the conversion into new files, the malware scan with clamd, and the media route with fixed content types and a `sandbox` CSP | none |
| V6 Authentication | passwords, passkeys, TOTP and recovery codes, failure counters, notifications, admin resets, and the sign-in through OIDC and LDAP | 6.6.1, 6.8.3 |
| V7 Session Management | server-side sessions with inactivity and absolute limits, a new token at every sign-in and step-up, termination by users and admins, and the concurrent session limit | none |
| V8 Authorization | role checks per route and the documented field access of learners and admins | 8.4.1 |
| V9 Self-contained Tokens | the validation of ID tokens | none |
| V10 OAuth and OIDC | the OAuth client and OIDC relying party of the sign-in | 10.3.1 to 10.3.4, 10.4.1 to 10.4.11, 10.5.5, 10.6.1, 10.6.2, 10.7.1 to 10.7.3 |
| V11 Cryptography | AES-256-GCM through Cloak, keyed hashes with HMAC-SHA256, Argon2id, random values from a CSPRNG, the key lifecycle and the cryptographic inventory | 11.4.4 |
| V12 Secure Communication | TLS of the reverse proxy example, of the database connection, of SMTP and of the directory, and the certificate check of every TLS client | 12.1.3 |
| V13 Configuration | the documented connections, secrets from the environment, and no repository metadata, debug mode, directory listing or `TRACE` in production | none |
| V14 Data Protection | protection levels of the account data, `Cache-Control: no-store` on the session, account, admin and credential routes, `private` caching of media files, and client storage and the HTTP cache cleared at sign-out | none |
| V15 Secure Coding and Architecture | the dependency policy and audits, the resource-demanding functions, no extraneous functionality, mass assignment and parameter pollution defenses, outbound calls without redirects | none |
| V16 Security Logging and Error Handling | security events as JSON lines on standard output, log forwarding over TLS, error answers without internals, and a sign-in that fails closed | none |
| V17 WebRTC | nothing: the platform uses no WebRTC | every row |

### Deviations

The platform deviates on purpose from nine requirements, from 11.4.1 in two
places. The section "Deviations" of the matrix holds each entry with its rule
and reason, and README section 15 holds the decision.

| Requirement | Rule | Reason | Decision |
|---|---|---|---|
| 5.4.3 Untrusted files scanned for malware | With `MEDIA_CLAMAV_SOCKET` set, every uploaded and imported media file passes a clamd `INSTREAM` scan before ffprobe, ffmpeg, the XML parser or the WebVTT check reads it, and a finding, an exceeded scan limit or a failed scan rejects the file. Without the setting, no scan runs. | A scan needs a clamd service with current signatures and the memory for them, which not every installation runs; `docs/guides/examples/compose.clamav.yaml` provides one. Without it, only authors with a recent second factor upload, the signature allowlist admits eight formats, ffmpeg writes every still image, every GIF and APNG and every converted video anew, an animated WebP is written anew in the BEAM without its metadata chunks while its frame bitstreams pass unchanged, a remuxed video passes its VP9 and Opus streams unchanged into a new WebM container, every SVG file is rebuilt, every WebVTT file is checked, no file is executed, and the media route serves files to signed-in users only, with a `sandbox` CSP and `nosniff`. | D19 |
| 6.2.8 Passwords verified exactly as received | Every password is normalized to Unicode NFC (`Espalier.Accounts.PasswordPolicy.prepare/1`) before the length check, the blocklist checks, the breached-password check, the Argon2id hash and the verification. Directory passwords go to the LDAP server unchanged. | NIST SP 800-63B-4 section 3.1.1.2 asks verifiers that accept Unicode to apply NFC before hashing, so that a password verifies in the same way on every keyboard and device. | D12 |
| 6.5.5 Lifetime of TOTP | TOTP accepts the code of the current and of the previous 30-second step, so a code is accepted for up to 60 seconds, and each code works once. | RFC 6238 section 5.2 recommends that a verifier accepts one past time step as transmission delay. E-mail links keep the limit of 10 minutes. | D15 |
| 11.4.1 HMAC-SHA-1 in TOTP | TOTP codes are HMAC-SHA-1 values with 6 digits and 30-second steps (`nimble_totp` 1.0.0). | RFC 6238 builds TOTP on HOTP with HMAC-SHA-1, the key URI format of Google Authenticator states that its implementations ignore the algorithm parameter, and `nimble_totp` 1.0.0 offers no other algorithm. ASVS Appendix C rates HMAC-SHA-1 as legacy. | D14 |
| 11.4.1 SHA-1 in the range request | With `PASSWORD_BREACH_CHECK=hibp`, the first five hex characters of the SHA-1 hash of the password go to the Pwned Passwords range API. | The range API accepts a prefix of the SHA-1 or of the NTLM hash, and NTLM is MD4, which ASVS Appendix C disallows. The platform stores no SHA-1 value, and the check is off by default (decision D10). | D14 |
| 11.6.1 RS256 | The ID token allowlist holds RS256 next to PS256 and ES256 (task 0006), and passkey registration accepts COSE -257 next to -7 and -8 (task 0005). The platform creates no RS256 signature: every `private_key_jwt` client assertion uses PS256, and `db-certs` generates the database certificates with EC P-256 keys and ECDSA signatures with SHA-256. | The discovery documents of Google and of Entra ID list RS256 as their only ID token algorithm (retrieved 2026-10-08), the FIDO Metadata Service lists the Windows Hello authenticators with RS256 only, and WebAuthn Level 3 asks relying parties to offer -257. ASVS Appendix C rates RSASSA-PKCS1-v1_5 as disallowed. | D13 |
| 12.3.1 Encrypted connections to and from the application | The reverse proxy example forwards requests to the application over HTTP on the compose network. SMTP, the directory and PostgreSQL use TLS. | The reason of 12.3.3 applies, because both entries record the same hop. | D17 |
| 12.3.3 TLS between internal HTTP services | The reverse proxy example forwards requests to the application over HTTP on the compose network. | The proxy and the application run on one host and in one compose network, which `self-hosting.md` requires, so the hop does not leave the host. A proxy on another host needs TLS on this hop. | D17 |
| 13.2.1 Backend communication authenticated | The directory service account authenticates with a password in a simple bind (task 0007). | `:eldap` offers only `simple_bind`. The mitigations are a dedicated service account that only reads user objects below the base DN, the password from the environment, TLS on every directory connection outside dev and test, and the rotation of the password that `identity-providers.md` describes. | D15 |
| 14.2.1 No sensitive data in URLs | The authorization response of the OIDC flow (`code` and `state`) and the intent of `/auth/oidc/<key>?intent=<token>` travel in a query string. | The response mode `query` keeps the callback a GET navigation that carries the `Lax` transaction cookie, and the intent starts the provider flow as a top-level navigation. The code works once and is bound to the PKCE verifier, the intent works once, expires after 5 minutes and works only with the session that created it, and `filter_parameters` keeps `code`, `state` and `intent` out of the logs. | D15 |

## Secrets

Every secret of an instance comes from the environment of the application
container. The environment is the interface to the operator's secrets
manager: the operator fills the env file of `compose.yaml` (`ENV_FILE`,
default `.env`) or the environment of the container from that manager, and
Espalier reads its secrets from there. A secret that is a file, the OIDC
client key, lies in a file that the operator mounts and that a variable
names. The database, SMTP and directory credentials come from the environment
as well (ASVS 13.2.3).

| Variable | Secret |
|---|---|
| `SECRET_KEY_BASE` | the keys of the session cookie and the transaction cookie, and the input of the rate-limit key |
| `CLOAK_KEY_V<n>`, `CLOAK_HMAC_SECRET` | the encryption keys and the HMAC secret of the stored columns |
| `DATABASE_URL`, `POSTGRES_PASSWORD` | the database password |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | the SMTP credentials |
| `AUTH_<KEY>_CLIENT_SECRET`, and the file of `AUTH_<KEY>_CLIENT_KEY_FILE` | the client credentials of an OIDC provider |
| `AUTH_<KEY>_BIND_PASSWORD` | the password of the directory service account |
| `WEBHOOK_SECRET_<NAME>` | the signing secret of a webhook |
| `RELEASE_COOKIE` | the cookie of the Erlang distribution, only with a `RELEASE_DISTRIBUTION` other than `none` |

- `.env.example` holds empty placeholders for these values, and Git ignores
  every `.env` file except the two examples.
- The image carries no secret. `.dockerignore` keeps `.env` and `.env.*` of
  every directory out of the build context, the Dockerfile defines no secret
  as `ENV` or `ARG`, and the builder deletes the distribution cookie
  `releases/COOKIE` that `mix release` writes. `scripts/check-release.sh`,
  which `make smoke` runs, finds no env file and no `/app/releases/COOKIE` in
  the image. It compares every secret value of an env file that existed when
  the image was built (`SECRET_ENV_FILE`, by default `ENV_FILE` and then
  `.env`) with the output of `docker image inspect` and
  `docker history --no-trunc`, and fails on a match or on a secret variable
  defined as `ENV` or `ARG`. `make smoke` passes the `.env` of the checkout
  and skips the comparison without one.
- The Git history carries no secret. `make secrets-scan` runs `gitleaks` over
  the whole history, and CI runs it on every push and pull request to
  `main`. A real secret that reaches a commit counts as published and is
  revoked and replaced (`CONTRIBUTING.md`, "Secret scanning").
- No boot message contains the value of a variable: `Espalier.BootCheck`
  names the variables only. The logs carry no password, code, token or
  session id ([`logging.md`](../security/logging.md)).

## Key management

[`key-management.md`](../security/key-management.md) describes the lifecycle
of every key, and [`crypto-inventory.md`](../security/crypto-inventory.md)
lists every key, algorithm and protected column.

- `CLOAK_KEY_V1` and `CLOAK_HMAC_SECRET` are 32 random bytes each in Base64
  (`make gen-keys` or `openssl rand -base64 32`). They protect the encrypted
  and the keyed-hash columns. They are kept outside the database and its
  backups, with an offline copy of every key version that still protects data
  in live rows or in a retained backup; a backup that holds both the database
  and the keys protects nothing.
- A key rotation adds `CLOAK_KEY_V2`, restarts the nodes and runs
  `Espalier.Release.rotate_encryption/0` and
  `Espalier.Release.encryption_status/0` (runbook in `key-management.md`).
  `CLOAK_HMAC_SECRET` has no rotation in the first version.
- The release writes no crash dump file and starts no Erlang distribution
  (`rel/env.sh.eex`), so the keys in the memory of the node reach no file
  and no remote console while the operator keeps these defaults. Without
  distribution, `rel/env.sh.eex` gives every command of `bin/espalier` a
  random cookie; with distribution, it stops every command that lacks
  `RELEASE_COOKIE`.
- `SECRET_KEY_BASE`, the API client tokens, the database CA certificate, the
  database server certificate and its key, the trust anchor of
  `DATABASE_CA_CERT_FILE`, and the certificate and key of the reverse proxy
  have their generation, storage, rotation and the effect of a rotation in
  the section "Other keys and certificates" of `key-management.md`, and their
  rows in the section "Keys and algorithms outside the database" of
  `crypto-inventory.md`. The database certificates are valid for 825 days.

### Ignored advisories

`mix.exs` lists two advisories under `hex: [ignore_advisories: [...]]`,
each with its reason in a comment. `mix hex.audit` honors the list from Hex
2.5.1 on.

| Advisory | Package | Affected module | Reason the platform accepts it |
|---|---|---|---|
| EEF-CVE-2026-95105 (HIGH) | `cloak` 1.1.4 | `Cloak.Ciphers.AES.CTR` and `Cloak.Ciphers.Deprecated.AES.CTR`, which store no MAC | Espalier uses neither module: the vault holds only `Espalier.Crypto.StrictAESGCM` over `Cloak.Ciphers.AES.GCM`, and `test/espalier/crypto/cipher_allowlist_test.exs` fails if another cipher is configured or if `lib/` or `config/` names an affected module. No release fixes the advisory. |
| EEF-CVE-2026-94206 (MEDIUM) | `cloak_ecto` 1.3.0 | `Cloak.Ecto.PBKDF2`, whose `dump/1` runs 32 rounds where 600,000 are configured | Espalier uses no PBKDF2 type; lookups use `Cloak.Ecto.HMAC`, and the same test fails if that changes. No release fixes the advisory. |

`key-management.md` holds the watch list, the triggers and the fallback plan
for `cloak` and `cloak_ecto`.

## Sessions and cookies

| Setting | Variable | Default | Effect |
|---|---|---|---|
| Inactivity timeout | `SESSION_IDLE_MINUTES` | 60 | a session whose last use is this old ends at its next use |
| Absolute lifetime | `SESSION_MAX_HOURS` | 24 | the end of every session; a value above 24 logs a warning at boot (decision D9) |
| Concurrent sessions | `SESSION_MAX_CONCURRENT` | 5 | live sessions per user; a new sign-in ends the oldest |
| Enrollment and recovery sessions | fixed | 30 minutes | the end of these sessions |
| Pending second-factor state | fixed | 5 minutes | the time between the first and the second factor |

The server checks both timeouts whenever it reads a session
(`Espalier.Accounts.get_session_by_token/2`); the cookie expiry is never the
only check. [`authentication.md`](../security/authentication.md),
section "Sessions", describes the session row and every event that ends a
session.

| Cookie | Attributes | Pipeline |
|---|---|---|
| `__Host-espalier` | `Secure`, `HttpOnly`, `Path=/`, no `Domain`, `SameSite=Strict`, encrypted and signed | the `/api` pipelines |
| `__Host-espalier_tx` | `Secure`, `HttpOnly`, `Path=/`, no `Domain`, `SameSite=Lax`, `Max-Age=600`, encrypted and signed | the `/auth/oidc` pipeline only, for one OIDC flow |

`scripts/check-headers.sh` checks these attributes on the running container.

### The `__Host-Http-` prefix

RFC 10017, section 6.1.3.2, recommends a cookie name prefix such as
`__Host-Http-`. The revisit of 2026-10-15 found:

| Source | Result |
|---|---|
| caniuse (<https://caniuse.com/mdn-http_headers_set-cookie_http_host-http_prefixes>) | support in Chrome and Edge from 140, Opera from 124 and Firefox from 143 (142 partial); no support in Safari up to 27.2 and in iOS Safari up to 27.2 |
| MDN browser-compat-data (`http/headers/Set-Cookie.json`, key `http_host-http_prefixes`) | the same; `version_added: false` for Safari |
| Safari release notes index | Safari 27.0 (released 2026-09-14) is the current release, and 27.2 is in beta (2026-10-13) |
| Safari 27.0 release notes and the WebKit blog post "WebKit Features for Safari 27.0" | no mention of `__Host-Http-` |

The current Safari and iOS Safari do not support the prefix, so the cookie
names stay `__Host-espalier` and `__Host-espalier_tx` (README section 6.5).

## Second factors per provider

| Pathway | `AUTH_<KEY>_MFA` | Second factor | Recorded in the session |
|---|---|---|---|
| Local account | none | a passkey alone, or a password with a TOTP code, a passkey or a recovery code | methods `passkey`, or `password` and the factor; strength `mfa` |
| OIDC provider (`entra`, `google`, `oidc`) in `local` mode, the default | `local` | a local passkey, TOTP code or recovery code after every provider sign-in; a first sign-in without a local factor opens an enrollment session of 30 minutes, in which the user enrolls one | methods `oidc` and the local factor; strength `mfa`; `provider_key` and the keyed hash of the provider's session id |
| OIDC provider in `idp_trusted` mode | `idp_trusted` | the multi-factor sign-in of the provider: an ID token whose `amr` holds a value of `AUTH_<KEY>_MFA_AMR` (default `mfa`), or an ID token without `amr`; an `amr` without such a value leads to the local second factor | methods `oidc` and `idp_mfa`, and the provider's `amr` in `idp_amr`; strength `mfa` |
| LDAP or Active Directory (`ldap`) | `local` only | a local passkey, TOTP code or recovery code after every bind | methods `ldap` and the local factor; strength `mfa`; `provider_key` |
| Demo (`AUTH_DEMO=true`, meant for the demo profile; the boot logs a warning) | none | none | method `demo`; strength `demo` |

`idp_trusted` is an operator decision for a provider that enforces
multi-factor sign-in itself, and the boot logs a warning for each such
provider. Entra ID sends no `amr`, also after a sign-in with MFA (spike of
task 0006, 2026-10-09), so for Entra ID that decision needs an
application-scoped Conditional Access policy that enforces MFA
([`identity-providers.md`](identity-providers.md)).

`ADMIN_REQUIRE_PASSKEY=true`, the default, keeps an admin without a passkey
out of the admin routes with 403 `passkey_required` and keeps an admin from
removing the last passkey (409 `admin_passkey_required`). The value `false`
logs a warning at boot.

## TLS per connection

| Connection | Protocol | Certificate check | Configuration |
|---|---|---|---|
| Browser to the reverse proxy | TLS 1.2 and TLS 1.3 only (`protocols tls1.2 tls1.3`), with the cipher suites below; HSTS `max-age=63072000; includeSubDomains` on every response | the browser checks the certificate of `SITE_ADDRESS`: publicly trusted through ACME for a public name, from the local CA of Caddy for `localhost` only | `docs/guides/examples/Caddyfile`, `docs/guides/examples/compose.caddy.yaml`, which publishes the HTTPS port only |
| Reverse proxy to the application | HTTP on the network `proxy` of one host (deviation, decision D17) | none | `reverse_proxy app:4000`; `compose.yaml` publishes the application port on `127.0.0.1` only |
| Application to PostgreSQL | TLS; the server admits TCP connections with TLS only (`hostssl` in `pg_hba.conf`), TLS 1.2 as the lowest version (`ssl_min_protocol_version=TLSv1.2`) and for TLS 1.2 the suites with ECDHE and AES-GCM or ChaCha20-Poly1305 only (`ssl_ciphers=ECDHE+AESGCM:ECDHE+CHACHA20`, section "Cipher suites of the database") | `verify: :verify_peer` with `DATABASE_CA_CERT_FILE` as the only trust anchor, SNI and the host name check against the host of `DATABASE_URL` | `config/runtime.exs` (Repo `ssl`), `compose.yaml` (services `db-certs` and `db`) |
| Application to SMTP | a connection to `SMTP_HOST` itself, without an MX lookup (`no_mx_lookups: true`); STARTTLS required (`ssl: false`, `tls: :always`), TLS 1.2 and TLS 1.3, authentication required (`auth: :always`) | `verify: :verify_peer` against the CA store of the operating system (`:public_key.cacerts_get/0`), SNI and the host name check against `SMTP_HOST` | `config/runtime.exs`; without `SMTP_HOST`, the instance opens no mail connection |
| Application to a directory | LDAPS (`AUTH_<KEY>_TLS=ldaps`, the default) or StartTLS, TLS 1.3 and TLS 1.2 only; `AUTH_<KEY>_TLS=none` stops the boot outside dev and test | `verify: :verify_peer` with the certificates of `AUTH_<KEY>_CA_CERT_FILE` as the only trust anchors, the host name through SNI, wildcard names only with `AUTH_<KEY>_TLS_WILDCARD=true` | `Espalier.Identity.Ldap.tls_options/1` |
| Application to an OIDC provider | HTTPS: the issuer uses `https` outside dev and test, and `Espalier.Identity.Oidc.check_endpoints/2` refuses an endpoint without `https` before any redirect or token request. The provider worker loads the JWKS before that check, and oidcc 3.9.0 also accepts an `http` JWKS URL of the discovery document. | the TLS options of Req with `verify: :verify_peer`: the certificate and the host name against the CA store of the operating system | `Espalier.Identity.Oidc.HttpAdapter` |
| Application to a webhook receiver | HTTPS only: the `Espalier.Credentials.Webhook` changeset admits no `http` URL in production | the default TLS options of Req: the certificate and the host name against the CA store of the operating system | `Espalier.Credentials.Webhook`, `Espalier.Credentials.WebhookWorker` |
| Application to the Pwned Passwords range API | HTTPS (`https://api.pwnedpasswords.com/range/`) | the default TLS options of Req, as for webhooks | `Espalier.Accounts.BreachedPasswords` |
| Docker daemon to a syslog receiver | `tcp+tls` to port 6514 | the certificate of the receiver against the CA of `syslog-tls-ca-cert` | `docs/guides/examples/compose.logging.yaml` |
| Application to clamd | the Unix socket of `MEDIA_CLAMAV_SOCKET` in the volume `clamd-socket`, which only the containers of `app` and `clamav` mount; no network connection, so no TLS | none; the file system of the host decides who reaches the socket | `docs/guides/examples/compose.clamav.yaml`, `docs/guides/examples/clamd.conf` |

### Cipher suites of the reverse proxy example

`nmap --script ssl-enum-ciphers` (Nmap 7.98) reported these suites on
2026-10-15 against the Caddy example: Caddy 2.11.7 from the image
`caddy:2.11`, `SITE_ADDRESS=localhost`, and a certificate from the local CA
of Caddy with an ECDSA P-256 key.

| Version | Suites in the order that nmap reports | Key exchange | Cipher preference |
|---|---|---|---|
| TLS 1.2 | `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256`, `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384`, `TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256`, each grade A | secp256r1 | client |
| TLS 1.3 | `TLS_AKE_WITH_AES_128_GCM_SHA256`, `TLS_AKE_WITH_AES_256_GCM_SHA384`, `TLS_AKE_WITH_CHACHA20_POLY1305_SHA256` | X25519MLKEM768 | server |

The least strength that nmap reports is A. Every TLS 1.2 suite uses ECDHE
and AES-GCM or ChaCha20-Poly1305, so the Caddyfile needs no `ciphers`
subdirective (ASVS 12.1.2).

`openssl s_client` (OpenSSL 3.6.0) against the same example confirms the
versions: with `-tls1_1 -cipher 'DEFAULT@SECLEVEL=0'` the handshake fails
with `tlsv1 alert protocol version` (alert 70), with `-tls1_2` it reports
TLSv1.2 with `ECDHE-ECDSA-AES128-GCM-SHA256`, and without a version flag it
reports TLSv1.3 with `TLS_AES_128_GCM_SHA256` (ASVS 12.1.1).

The suite list depends on the key type of the certificate. The Caddy
documentation of the global option `key_type` lists the values `ed25519`,
`p256`, `p384`, `rsa2048` and `rsa4096` and names no default (retrieved
2026-10-15). In the source of Caddy 2.11.7, `makeCertMagicConfig` in
`modules/caddytls/automation.go` passes the configured key type, empty
while `key_type` is unset, to `certmagic.StandardKeyGenerator`, and certmagic
v0.25.6, the version in the `go.mod` of Caddy 2.11.7, generates an ECDSA P-256
key for an empty key type (`crypto.go`, `GenerateKey`). A certificate that
Caddy obtains through ACME for a public `SITE_ADDRESS` therefore carries a
P-256 key, the key type of the measurement. A deployment that sets `key_type`,
runs another Caddy release or uses another proxy repeats the measurement
against its own host.

### Cipher suites of the database

The service `db` of `compose.yaml` starts with
`ssl_ciphers=ECDHE+AESGCM:ECDHE+CHACHA20` (ASVS 12.1.2). The setting covers
TLS 1.2; PostgreSQL takes the TLS 1.3 suites from `ssl_tls13_ciphers`, which
keeps the default of OpenSSL. On 2026-10-15, `openssl s_client -starttls
postgres` (OpenSSL 3.5.7) offered each of 155 TLS 1.2 suite names of OpenSSL
with `@SECLEVEL=0`, and each TLS 1.3 suite, to PostgreSQL 18.6 from the image
`postgres:18` with an EC P-256 server certificate, the key type of
`db-certs`:

| Version | Suites that the server accepted |
|---|---|
| TLS 1.2 | `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256`, `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384`, `TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256` |
| TLS 1.3 | `TLS_AES_256_GCM_SHA384`, which a handshake without `-ciphersuites` negotiates, `TLS_CHACHA20_POLY1305_SHA256` and `TLS_AES_128_GCM_SHA256`; the server refused `TLS_AES_128_CCM_SHA256` and `TLS_AES_128_CCM_8_SHA256` |

A handshake with TLS 1.1 failed. In the same measurement, a server with the
default of PostgreSQL, `HIGH:MEDIUM:+3DES:!aNULL`, admitted 13 TLS 1.2
suites, among them suites with AES-CBC and suites with SHA-1 as MAC.

### HSTS, `TRACE` and request framing

Only the reverse proxy sends the header
`Strict-Transport-Security: max-age=63072000; includeSubDomains`.
`config/prod.exs` sets `force_ssl: [hsts: false, ...]`, because `Plug.SSL`
added a second header with `max-age=31536000` to proxied responses for a
host other than `localhost`. Caddy answers `TRACE` with 405
and the HSTS header, and the application has no `TRACE` route.

`scripts/smoke.sh --proxy` sent two HTTP/1.1 framing probes on 2026-10-15,
each through Caddy and directly to Bandit (ASVS 4.2.1):

| Probe | Through Caddy | Directly to Bandit |
|---|---|---|
| two differing `Content-Length` values | 400 | `HTTP/1.0 400 Bad Request` |
| `Content-Length` with `Transfer-Encoding: chunked`, with a complete request for `/api/smuggled` in the single chunk | one response, 404 for the outer `POST /health`, because Caddy frames the message by the chunked encoding | 400 ("Request cannot contain both 'content-length' and 'transfer-encoding'") |

The application log held no line for the inner request.

The application takes the client address from the rightmost
`X-Forwarded-For` entry only when the peer lies in `TRUSTED_PROXIES`
(`EspalierWeb.Plugs.TrustedProxy`), and Caddy overwrites the header with the
address it saw. Bandit listens on `::` and reports an IPv4 peer as an
IPv4-mapped IPv6 address (`::ffff:a.b.c.d`), so the plug turns such an
address into its IPv4 form before the `TRUSTED_PROXIES` check.
`Espalier.RuntimeConfig` turns an IPv4-mapped entry of `TRUSTED_PROXIES`
with a prefix of at least 96 into its IPv4 form in the same way, and an IPv6
range such as `::/0` matches IPv6 peers only. In
`scripts/smoke.sh --proxy`, the `authn_login_fail` line of a request with a
forged `X-Forwarded-For` carried the address that Caddy saw and never the
forged value (ASVS 4.1.3 and 15.3.4).

## Outgoing connections

Apart from name resolution, the running application opens only the
connections of this table. An egress allowlist of the container network or
an outbound proxy admits these hosts and ports (ASVS 13.1.1). Every HTTP
request of the application follows no redirect.

| Destination | Hosts | Port | When |
|---|---|---|---|
| PostgreSQL | the host of `DATABASE_URL`, `db` in `compose.yaml` | the port of `DATABASE_URL`, 5432 by default | always |
| Identity provider `entra` | `login.microsoftonline.com` | 443 | for a provider of this type in `AUTH_PROVIDERS`: discovery, JWKS and token requests |
| Identity provider `google` | `accounts.google.com`, `oauth2.googleapis.com`, `www.googleapis.com` | 443 | as above |
| Identity provider `oidc` | the issuer host and the endpoint hosts of its discovery document, within `AUTH_<KEY>_ALLOWED_HOSTS` | the port of each `https` URL, 443 by default | as above |
| Directory | `AUTH_<KEY>_HOST` | `AUTH_<KEY>_PORT`, 636 for LDAPS and 389 for StartTLS by default | for a provider of the type `ldap` |
| SMTP | `SMTP_HOST` | `SMTP_PORT`, 587 by default | with `SMTP_HOST` |
| Webhook receivers | the hosts of `WEBHOOK_ALLOWED_HOSTS`, `https` URLs only | the port of each entry, 443 for an entry without a port | for each active webhook that an admin configures (task 0013) |
| Pwned Passwords range API | `api.pwnedpasswords.com` | 443 | only with `PASSWORD_BREACH_CHECK=hibp`; the default is `off` |
| Other Espalier nodes (Erlang distribution) | the addresses that `DNS_CLUSTER_QUERY` resolves to | 4369 (epmd) and the distribution port of each node, which the runtime chooses at start unless `inet_dist_listen_min` and `inet_dist_listen_max` set a range | only with `DNS_CLUSTER_QUERY` and a `RELEASE_DISTRIBUTION` other than `none`; plain TCP without TLS unless the operator configures `-proto_dist inet_tls`, authenticated by `RELEASE_COOKIE` |
| Syslog receiver, from the Docker daemon | `SYSLOG_HOST` | 6514 | with `docs/guides/examples/compose.logging.yaml` |
| clamd | the Unix socket of `MEDIA_CLAMAV_SOCKET`, `/run/clamav/clamd.sock` in the example | none, a local socket | only with `MEDIA_CLAMAV_SOCKET`, for the scan of every uploaded and imported media file (`docs/guides/examples/compose.clamav.yaml`) |

With `RELEASE_DISTRIBUTION=none`, the default, `DNS_CLUSTER_QUERY` leads to
DNS lookups and opens no connection. In a cluster, each node also accepts
these connections from the other nodes. The distribution traffic carries
decrypted values, and the cookie authenticates the nodes without encrypting
the traffic, so a cluster needs `-proto_dist inet_tls` with the options of
`-ssl_dist_optfile` in the VM arguments of the release, or a network that
only its nodes reach. The release passes `RELEASE_COOKIE` on the command
line of the BEAM, where every user of the host can read it unless `/proc`
hides the processes of other users (`key-management.md`), so a host with
other local users needs the TLS distribution with `verify_peer` and
`fail_if_no_peer_cert`. `rel/env.sh.eex` stops every command with
distribution and without `RELEASE_COOKIE`
([`key-management.md`](../security/key-management.md), section "Memory of
the running node").

The server fetches no external media. A `video` block with an external file
or an embed names a host of `MEDIA_EXTERNAL_HOSTS` or `MEDIA_EMBED_HOSTS`, and
the browsers of the learners load the file or the player from that host; the
CSP of the application admits exactly these hosts in `media-src` and
`frame-src` ([`media.md`](media.md), section "External files and embeds").
ffmpeg and ffprobe read their input with `-protocol_whitelist file`, so no
media file makes them open a network connection. In the clamd example,
freshclam in the container `clamav` fetches signatures from
`database.clamav.net` once a day; the application has no part in
that connection.

[`identity-providers.md`](identity-providers.md), section "Outbound
connections", gives the source of the provider hosts and explains why the
JWKS request needs the allowlist. For a public `SITE_ADDRESS`, Caddy also
reaches the ACME server of its certificate authority (Caddy documentation,
"Automatic HTTPS"). The image build fetches the dependencies from hex.pm and
registry.npmjs.org and the SCORM schema files from `scorm.com`
(`mix espalier.scorm_xsd`); the running container needs none of these hosts.

## Resource-demanding functions

These functions demand memory, CPU time or disk beyond a common request
(ASVS 15.1.3). Each has the limit of the third column.

| Function | Demand | Limit | Setting |
|---|---|---|---|
| Password hashing and verification | Argon2id with `t_cost: 2`, `m_cost: 16` (64 MiB) and `parallelism: 1`; one hash took 0.09 seconds on 2026-10-08 on a host with 16 CPU cores. Concurrent hashes run on the dirty CPU schedulers, one per core, so memory peaks at about their number times 64 MiB, 1 GiB on that host. | the rate limits of the sign-in and account routes (section "Rate limits, failure counters and the session limit"); the container memory limit, which must leave room for the peak plus the memory of the node | `config/config.exs`; `make argon2-bench` measures the parameters on the production image ([`authentication.md`](../security/authentication.md), section "Argon2 parameters") |
| Pack import: the upload of the pack page, `mix espalier.import` and `Espalier.Release.import_pack/2` | reading, extracting and parsing a pack | the upload: at most `PACK_UPLOAD_MAX_MB` (default 20, 413 above it), at most 2,000 entries, declared uncompressed sizes of at most five times the upload limit, no symbolic links, absolute names, backslashes or `..` components, and the role `author` with a second factor in the last 10 minutes; the loader: 1 MiB per file, 32 MiB of decoded data per pack, 20,000 entries and 32 levels per pack directory, 50,000 YAML nodes and 32 levels of nesting per file, 10 seconds and 256 MiB per YAML parse, and 60 seconds per pack | `PACK_UPLOAD_MAX_MB`; [`content-packs.md`](content-packs.md) |
| Check and import of a draft of the pack workbench | the loader of the pack import on the files of a draft | 2,000 files, 1,048,576 bytes per file, five times `PACK_UPLOAD_MAX_MB` per draft (104,857,600 bytes with the default) and 50 drafts; at most two checks, imports and zip builds of draft downloads at once per node, and another one answers 429 `checks_busy`; the loader budget as above | `config :espalier, :pack_drafts` in `config/config.exs`; [`pack-workbench.md`](pack-workbench.md), section "Limits" |
| SCORM export | building one zip package per module and SCORM version, disk in `EXPORT_DIR` | the Oban queue `exports` with one slot, so a node builds one package at a time while further requests wait in status `queued`; one attempt and a timeout of 30 minutes per job; a sweep every 15 minutes ends an export that has stayed `queued` or `running` for more than one hour; at most 100 packages of `done` exports, and a `done` or `failed` export is deleted with its files 7 days after its last change; the role `author` with a second factor in the last 10 minutes | `config/config.exs` (queue `exports`, `:export_retention`); [`scorm-export.md`](scorm-export.md) |
| Media processing: the conversion of uploaded and imported media files with ffmpeg and ffprobe, the SVG rebuild, the WebVTT check and the malware scan | decoding and encoding of images and videos with CPU time, memory and disk in the container of `app`; ffmpeg runs as a program of its own | two image jobs (queue `media: 2`) and one video job (queue `media_video: 1`) at a time in the server, plus one inline job of an import that `mix espalier.import` or `Espalier.Release.import_pack/2` runs next to it; `MEDIA_FFMPEG_THREADS` threads per ffmpeg and ffprobe process (default 2, at most 16) through `-threads` and `-filter_threads`; `-max_alloc 536870912` per allocation; a deadline per job through `timeout --kill-after=10`: `image_timeout_seconds` (120) for an image, SVG or captions job, and `max(video_timeout_floor_seconds, video_timeout_factor * duration) + image_timeout_seconds` for a video job, with `video_timeout_floor_seconds` 600 and `video_timeout_factor` 25; a clamd scan timeout of 60 seconds plus one second per 4 MiB; the sizes `MEDIA_IMAGE_MAX_MB` (default 20), 1,048,576 bytes per SVG file, 524,288 bytes per WebVTT file and `MEDIA_VIDEO_MAX_MB` (default 1024); 40,000,000 pixels per image, checked in the header before any decoder and passed as `-max_pixels`; 3840 by 2160 pixels per video frame; 1,000 frames per animated image; `MEDIA_VIDEO_MAX_MINUTES` (default 60); `MEDIA_VIDEO_MAX_HEIGHT` (default 1080) and `MEDIA_IMAGE_MAX_EDGE` (default 2560) for the output; 10,000 cues per WebVTT file; the quota `MEDIA_STORAGE_MAX_GB` (default 50); at most 500 media files per pack and 500 media entries per draft; the upload only for the role `author` with a second factor in the last 10 minutes | the `MEDIA_*` variables; `config :espalier, :media` and the queues in `config/config.exs`; [`media.md`](media.md), sections "Settings", "Limits and quota" and "Failures and timeouts" |
| Media downloads: the media route, a draft download with media and a SCORM export with media | reading and zipping media files | the media route serves files with byte ranges through `Plug.Static`; a draft download and the media of one SCORM package stay within `export_max_mb` (1,024 MB), write `.webp` and `.webm` entries without compression and read every file in blocks; a draft download builds its zip below `MEDIA_DIR/work/` in one of the two slots of the checks and imports and frees that slot once the zip is written; at most two draft downloads run at once per node and one per user (`max_parallel_downloads`), each from the zip build until its zip is sent and removed, and another one answers 429 `checks_busy` and builds nothing; it sends the zip in blocks of 64 KiB within a deadline of the size of the zip at 256 KiB per second and at least 60 seconds, and a client that stops reading for the send timeout of 30 seconds loses the connection earlier; either end frees the slot | `config :espalier, :media` and `config :espalier, :pack_drafts` in `config/config.exs`; [`pack-workbench.md`](pack-workbench.md), [`scorm-export.md`](scorm-export.md) |
| Reports of task 0014 | six GET routes under `/api/insights` for the role `analyst`; each request reads the aggregated anonymous tables of one program, and the credential report the credentials of the program per qualification and status | no limit of their own: no queue and no rate limit bucket | none |

## Rate limits, failure counters and the session limit

[`authentication.md`](../security/authentication.md) documents the business
limits of the sign-in and account routes (ASVS 2.1.3):

- [Rate limits](../security/authentication.md#rate-limits): Hammer buckets
  per client IP and per keyed hash of the account, each with its window and
  limit, for example 30 sign-in requests per minute and IP and 10 password
  attempts per 15 minutes and account. A denial answers 429 with
  `retry-after` and logs `excess_rate_limit_exceeded`. The counters live in
  ETS and count per node. The learner and insights write routes have
  per-user buckets (`learner_write`, `assessment_attempt`,
  `insights_write`).
- [Failure counters](../security/authentication.md#failure-counters): from
  the fifth consecutive failure of a password or a second factor, the
  authenticator is locked for 30 seconds, doubling up to one hour; the
  fiftieth failure disables it until a recovery or an admin reset.
- [Directory failure counters](../security/authentication.md#directory-failure-counters):
  a directory account is locked for `AUTH_<KEY>_LOCK_MINUTES` from
  `AUTH_<KEY>_FAILURE_LIMIT` failures on, below the lockout threshold of the
  directory.
- [Concurrent session limit](../security/authentication.md#concurrent-session-limit):
  at most `SESSION_MAX_CONCURRENT` sessions per user (default 5); a new
  sign-in ends the oldest.

## Dependency policy

The maintainer sets the remediation time frame per advisory severity and the
update interval (ASVS 15.1.1):

| Severity of the advisory | Remediation |
|---|---|
| critical | within 7 days |
| high | within 30 days |
| medium | within 90 days |
| low | with the next regular update |

Dependencies are updated once a month. `mix.exs` sets the Hex cooldown
`hex: [cooldown: "7d"]`, so Hex resolves only releases that are at least
seven days old. A locked version that carries an advisory bypasses the
cooldown, so that a security fix is not held back, and any other younger
release needs `HEX_COOLDOWN=0d` and a reason in the commit message
(`CONTRIBUTING.md`, "Dependencies and the release cooldown").

`mix.lock` and `frontend/package-lock.json` form the dependency inventory
(ASVS 15.1.2). Every entry of `mix.lock` is a `:hex` entry from the
repository `hexpm`, and every `resolved` value of
`frontend/package-lock.json` starts with `https://registry.npmjs.org/`. On
2026-10-15, these checks covered 62 entries and 386 packages:

```sh
grep -cE '^  "[^"]+": \{:hex, :[a-z0-9_]+, "[^"]+", "[0-9a-f]{64}", \[[^]]*\], \[.*\], "hexpm", "[0-9a-f]{64}"\},?$' mix.lock
grep -c '^  "' mix.lock
nix-shell -p jq --run "jq '[.. | objects | select(has(\"resolved\")) | .resolved | select(startswith(\"https://registry.npmjs.org/\") | not)] | length' frontend/package-lock.json"
```

The first two commands print the same number, and the third prints `0`.

The media processing adds three components outside these lock files:

| Component | Version | Where | Update path |
|---|---|---|---|
| ffmpeg and ffprobe, the Debian package `ffmpeg` | 7.1.5 (package `7:7.1.5-0+deb13u1`) on 2026-10-15 | the runner image, installed with `apt-get install --no-install-recommends ffmpeg` on `debian:trixie-20261005-slim` | `apt-get update` at every image build fetches the current package of trixie and of its security archive, so `make docker-build` takes a security update of Debian; the monthly update moves `DEBIAN_VERSION` in the `Dockerfile` to a newer image. The package is built with GPL components; the release starts ffmpeg as a program of its own and links none of it, and `NOTICE` names the package. |
| `ffmpeg-headless` of nixpkgs | 8.1.2 | `shell.nix`, for development, the tests and CI | the nixpkgs revision that `shell.nix` pins; the monthly update moves the pin |
| ClamAV in the image `clamav/clamav` | `clamav/clamav:1.5.4` | `docs/guides/examples/compose.clamav.yaml`, optional | the tag in the example file, which the monthly update moves to the current stable release; freshclam in the container updates the signatures once a day. The development shell carries ClamAV 1.4.6 of nixpkgs for the integration test. |

The boot check of a production instance refuses an ffmpeg older than 7.1 and
one without the encoders and demuxers of the conversion
([`media.md`](media.md), section "Settings").

`make check` audits the dependencies (ASVS 15.2.1): `mix hex.audit` with
Hex 2.5.1 or later, which `scripts/check-hex-version.sh` checks first,
`mix deps.audit`, and, as its last command,
`npm --prefix frontend audit --omit=dev`. It fails on an open advisory
unless `mix.exs` documents the exception (section "Ignored advisories"). An
advisory in a transitive npm package is resolved by an update or by an entry
in `overrides` of `frontend/package.json`; the entry for
`@tailwindcss/typography` lifts `postcss-selector-parser` to 7.1.6 or later
for CVE-2026-104844 (`CONTRIBUTING.md`).

README section 16 names the dependencies with a maintenance risk:

| Dependency | Risk | Mitigation |
|---|---|---|
| `cloak` 1.1.4 and `cloak_ecto` 1.3.0 | no release since 2024-04-06, one owner on Hex each, and two advisories without a fixed version | only AES-GCM and HMAC are used; the strict GCM wrapper, the own rotation function, and the watch list with a review date and the fallback type on `:crypto` of `key-management.md` |
| `wax_` 0.7.0 | one maintainer, no independent security review, and gaps that the application closes | the spike in [`wax-spike.md`](../security/wax-spike.md); each application check of README section 6.6 has a test; the repository watches for a 0.8 release |
| `argon2_elixir` 4.1.3 | a threading failure on Elixir 1.20 and OTP 28.5 (upstream issue #73) | `parallelism: 1` and the load test of `make argon2-bench` on the production image |
| `:eldap` (OTP) | it accepts an empty binary as password and then sends an anonymous bind | a guard before every bind and a fake-server test (README section 6.8) |
