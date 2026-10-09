# Cryptographic inventory

This document lists every key, every algorithm and every protected column of
Espalier (ASVS 11.1.2), and the protection level of the account and
authentication data (ASVS 14.1.1 and 14.1.2). The key lifecycle and the
rotation runbook are in [`key-management.md`](key-management.md). The
verification matrix is [`asvs-l2.md`](asvs-l2.md).

Every task that adds an encrypted, hashed or password-hash column adds its row
here in the same change, and `test/espalier/crypto/inventory_test.exs` fails
when a schema field of these kinds is missing from this document (AGENTS.md).

## Threat model

Cloak protects stored columns against someone who holds a database dump, a
replica or a backup without the keys (README section 6.9). The keys live
outside the database and outside its backups. An attacker who runs code inside
the application, or who holds both the database and the keys, is outside this
threat model (section "Limits").

## Protection levels

The table classifies the account and authentication data (ASVS 14.1.1) and
gives the requirements for storage, lookup, logging and rotation of each level
(ASVS 14.1.2). The other data classes follow in the data protection workstream
of README section 10.

| Level | Data | Storage | Lookup | Logging | Rotation |
|---|---|---|---|---|---|
| `encrypted` | personal data and authenticator secrets that the application reads back | AES-256-GCM through `Espalier.Encrypted.*` | only through a keyed hash column | never | `rotate_encryption/0` |
| `keyed hash` | lookup values for encrypted data and for the identity provider's session id, and recovery codes and the bindings of sign-in tickets and OIDC intents that the application only compares | HMAC-SHA256 under `CLOAK_HMAC_SECRET` through the type `Espalier.Hashed.HMAC`, or through `Espalier.Hashed.HMAC.hash/1` into a plain `:binary` column for a value copied between rows, or under a key derived from `CLOAK_HMAC_SECRET` | equality only | never | none in the first version |
| `hash` | random secrets of at least 128 bits that the application only compares | SHA-256 | hash of the presented value | never | a new secret replaces the old one |
| `password hash` | passwords | Argon2id | verification only | never | not applicable |
| `plain` | values without personal or secret content | plain column | any SQL | allowed | not applicable |

Rules that apply to every level except `plain`:

- The column type is `:binary` (`bytea`), and the schema field carries
  `redact: true`, so `inspect/1` shows no value
  (`Espalier.Crypto.SchemaRules.unredacted_cloak_fields/1`).
- No encrypted or hashed type appears inside an embedded schema, because Cloak
  types embed as plaintext JSON (`Espalier.Crypto.SchemaRules.embedded_cloak_fields/1`).
- "Never" in the column Logging means: the Repo runs with `log: false` in
  production, `Espalier.Telemetry.QueryLog` logs queries without parameters
  and results, no Repo call sets its own `log:` option, and every telemetry
  handler for Repo events calls `Espalier.Telemetry.QueryLog.scrub/1` first.

## Columns

Each row starts with the status `planned` and names the task that creates the
column. That task sets the status to `done` and names its module.

| Column | Level | Type or function | Key | Task | Status |
|---|---|---|---|---|---|
| `users.email` | `encrypted` | `Espalier.Encrypted.Binary` in `Espalier.Accounts.User`; rotation through `Espalier.Crypto.Rotation.Users` | `CLOAK_KEY_V<n>` | 0004 | done |
| `users.display_name` | `encrypted` | `Espalier.Encrypted.Binary` in `Espalier.Accounts.User`; rotation through `Espalier.Crypto.Rotation.Users` | `CLOAK_KEY_V<n>` | 0004 | done |
| `users.org_unit` | `encrypted` | `Espalier.Encrypted.Binary` in `Espalier.Accounts.User`; rotation through `Espalier.Crypto.Rotation.Users` | `CLOAK_KEY_V<n>` | 0004 | done |
| `users.email_hash` | `keyed hash` | `Espalier.Hashed.HMAC` in `Espalier.Accounts.User` of the trimmed, lower-cased address (`Espalier.Accounts.normalize_email/1`), unique index; not rotated in the first version (README section 6.9) | `CLOAK_HMAC_SECRET` | 0004 | done |
| `users.hashed_password` | `password hash` | Argon2id with `argon2_elixir` in `Espalier.Accounts.User` (`argon2_type: 2`, `t_cost: 2`, `m_cost: 16`, `parallelism: 1`; measurements in `authentication.md`) over the NFC-normalized password | none | 0004 | done |
| `users_tokens.token_hash` | `hash` | SHA-256 of a 32-byte random token in `Espalier.Accounts.UserToken` for the contexts `session`, `invite`, `change_email`, `recovery_email` and `login_ticket`, and `oidc_intent` from 0006 | none | 0004 | done |
| `users_tokens.sent_to_hash` | `keyed hash` | `Espalier.Hashed.HMAC` in `Espalier.Accounts.UserToken` of the normalized address an e-mail link went to; not rotated in the first version | `CLOAK_HMAC_SECRET` | 0004 | done |
| `users_tokens.new_email` | `encrypted` | `Espalier.Encrypted.Binary` in `Espalier.Accounts.UserToken`; rotation through `Espalier.Crypto.Rotation.UsersTokens` | `CLOAK_KEY_V<n>` | 0004 | done |
| `users_tokens.idp_sid_hash` | `keyed hash` | plain `:binary` field of `Espalier.Accounts.UserToken`, filled by `UserToken.hash_idp_sid/1` (HMAC-SHA256 under `CLOAK_HMAC_SECRET` through `Espalier.Hashed.HMAC.hash/1`) of the provider's `sid`, computed once by 0006 and copied unchanged through the sign-in ticket, the pending second-factor state, the enrollment session and every reissued session row; lookups compare with `hash_idp_sid/1` of the presented `sid` | `CLOAK_HMAC_SECRET` | 0004 | done |
| `users_tokens.binding_hash` | `keyed hash` | `Espalier.Hashed.HMAC` in `Espalier.Accounts.UserToken` of the Base64url-encoded 32-byte binding of a sign-in ticket (`Espalier.Accounts.create_login_ticket/1`), or of the id of the session row that created an OIDC intent (`create_oidc_intent/3`); set on `login_ticket` and `oidc_intent` rows only, compared with `Plug.Crypto.secure_compare/2` against `Espalier.Hashed.HMAC.hash/1` of the presented value; not rotated in the first version | `CLOAK_HMAC_SECRET` | 0006 | done |
| `users_tokens.link_identity` | `encrypted` | `Espalier.Encrypted.Binary` in `Espalier.Accounts.UserToken`: JSON with issuer, tenant id and subject of an identity to link, on `login_ticket` rows of the purpose `link` only, deleted with the ticket after at most 60 seconds; rotation through `Espalier.Crypto.Rotation.UsersTokens` | `CLOAK_KEY_V<n>` | 0006 | done |
| `api_clients.token_hash` | `hash` | SHA-256 of a 32-byte random token in `Espalier.Accounts.ApiClient` (`Espalier.Accounts.create_api_client/2`) | none | 0004 | done |
| `external_identities.subject` | `encrypted` | `Espalier.Encrypted.Binary` in `Espalier.Accounts.ExternalIdentity`, written by 0004 (demo identities), 0006 and 0007; rotation through `Espalier.Crypto.Rotation.ExternalIdentities` | `CLOAK_KEY_V<n>` | 0004 | done |
| `external_identities.subject_hash` | `keyed hash` | `Espalier.Hashed.HMAC` in `Espalier.Accounts.ExternalIdentity` of `Espalier.Accounts.ExternalIdentity.hash_input(issuer, tenant_id, subject)`, filled by the changeset, unique index with `provider_key`; written by 0004 (demo identities, `Espalier.Accounts.Demo`), 0006 and 0007; not rotated in the first version | `CLOAK_HMAC_SECRET` | 0004 | done |
| `external_identities.directory_dn` | `encrypted` | `Espalier.Encrypted.Binary` in `Espalier.Accounts.ExternalIdentity`: the DN that the directory returned for a directory identity, written at the link or the first sign-in and refreshed at every directory sign-in (`Espalier.Accounts.sign_in_external/2`, `link_external_identity/3`); nil for OIDC identities; rotation through `Espalier.Crypto.Rotation.ExternalIdentities` | `CLOAK_KEY_V<n>` | 0007 | done |
| `external_identities.directory_upn` | `encrypted` | `Espalier.Encrypted.Binary` in `Espalier.Accounts.ExternalIdentity`: the `userPrincipalName` of an Active Directory identity, written and refreshed like `directory_dn`; rotation through `Espalier.Crypto.Rotation.ExternalIdentities` | `CLOAK_KEY_V<n>` | 0007 | done |
| `external_identities.directory_login` | `encrypted` | `Espalier.Encrypted.Binary` in `Espalier.Accounts.ExternalIdentity`: the `sAMAccountName` (Active Directory) or `uid` (generic LDAP), written and refreshed like `directory_dn`; rotation through `Espalier.Crypto.Rotation.ExternalIdentities` | `CLOAK_KEY_V<n>` | 0007 | done |
| `failure_counters.subject_hash` | `keyed hash` | `Espalier.Hashed.HMAC` in `Espalier.Accounts.FailureCounter` of `Espalier.Accounts.ExternalIdentity.hash_input("ldap:" <> provider_key, nil, subject)`, the same input as `external_identities.subject_hash` of the directory identity; set on rows of the authenticator `ldap` only (`Espalier.Accounts.FailureCounters.reserve_directory/5`), unique index with `authenticator` and `provider_key` where it is set; no rotation-only schema, because the table holds no ciphertext; not rotated in the first version (README section 6.9) | `CLOAK_HMAC_SECRET` | 0007 | done |
| `totp_factors.secret` | `encrypted` | `Espalier.Encrypted.ClosureBinary` in `Espalier.Accounts.TotpFactor` (20 bytes from `NimbleTOTP.secret/0`, which calls `:crypto.strong_rand_bytes(20)`), loaded as `fn -> secret end`; rotation through `Espalier.Crypto.Rotation.TotpFactors` | `CLOAK_KEY_V<n>` | 0005 | done |
| `recovery_codes.code_hmac` | `keyed hash` | HMAC-SHA256 of a 26-character code (16 bytes from `:crypto.strong_rand_bytes/1`) under `Espalier.Accounts.RecoveryCodes.key/0`, the key derived from `CLOAK_HMAC_SECRET` with the label `espalier/recovery-codes/v1`; plain `:binary` column, compared with `Plug.Crypto.secure_compare/2`; no rotation-only schema, because the column holds no ciphertext | recovery-code key (derived from `CLOAK_HMAC_SECRET`) | 0005 | done |

Each table with an `encrypted` column has a rotation-only schema
`Espalier.Crypto.Rotation.<Table>` in `lib/espalier/crypto/rotation/<table>.ex`,
registered in `Espalier.Crypto.Rotation.schemas/0` by the task that creates the
column. `test/espalier/crypto/rotation_test.exs` fails when an encrypted field
of the application has no rotation-only schema.

## Values encrypted outside Ecto types

`Espalier.Vault.encrypt!/1` can encrypt a value that no Ecto type stores.
`rotate_encryption/0` walks Ecto schemas only and does not rewrite such
values, so the rotation runbook waits until no value under the old tag is
still read (`key-management.md`). Each such value has a row here, added in the
same change as the code that writes it.

| Location | Content | Encryption | Lifetime | Task | Status |
|---|---|---|---|---|---|
| `oban_jobs.args` of `Espalier.Accounts.MailWorker` | e-mail addresses of the kinds `signup`, `change_email` and `email_changed`, written by `Espalier.Accounts.MailWorker.encrypt_arg/1` from `Espalier.Accounts.request_invitation/1`, `request_email_change/2` and `confirm_email_change/3` | `Espalier.Vault.encrypt!/1`, Base64 | read while the job is `available`, `scheduled`, `executing` or `retryable`; the finished row stays until `Oban.Plugins.Pruner` deletes it after 24 hours (`max_age: 86_400`) | 0004 | done |

## Keys and algorithms outside the database

| Key | Algorithm | Use | Location | Task | Status |
|---|---|---|---|---|---|
| `CLOAK_KEY_V<n>` | AES-256-GCM with a 12-byte random IV, a 16-byte GCM tag and the cipher tag `AES.GCM.V<n>` (`Espalier.Crypto.StrictAESGCM` over Cloak) | encrypts the columns of the level `encrypted` and the values of the section "Values encrypted outside Ecto types"; no other use | environment, the vault ETS table `:"Elixir.Espalier.Vault.Config"`, the vault state, and Base64-encoded in the application environment under `Espalier.Vault` (Limits (1)) | 0003 | done |
| `CLOAK_HMAC_SECRET` | HMAC-SHA256 (`Espalier.Hashed.HMAC` over `Cloak.Ecto.HMAC`) | keys the columns of the level `keyed hash` and is the input of the recovery-code key; it encrypts nothing | environment, and Base64-encoded in the application environment under `Espalier.Hashed.HMAC` (Limits (1)) | 0003 | done |
| recovery-code key | HMAC-SHA256, derived from `CLOAK_HMAC_SECRET` as HMAC-SHA256 over the label `espalier/recovery-codes/v1` (README section 6.6) | keys `recovery_codes.code_hmac` only | derived in the node from `CLOAK_HMAC_SECRET` by `Espalier.Accounts.RecoveryCodes.key/0` at every use; never stored | 0005 | done |
| `SECRET_KEY_BASE` | keys derived with PBKDF2-HMAC-SHA256 (`Plug.Crypto.KeyGenerator`), signatures with HMAC-SHA256 (`Plug.Crypto.MessageVerifier`), cookie encryption with AES-GCM (`Plug.Crypto.MessageEncryptor`) | Phoenix signing (0001), the encrypted `Plug.Session` cookies `__Host-espalier` and `__Host-espalier_tx` with the salts of `EspalierWeb.TransactionCookie` (0004), and the input of the rate-limit key | environment and the endpoint configuration in the application environment | 0001, 0004 | done |
| rate-limit key | HMAC-SHA256 over normalized identifiers; the key is derived once at boot with `Plug.Crypto.KeyGenerator.generate(secret_key_base, "espalier rate limit", length: 32)` in `Espalier.RateLimit.init_key/1` | keys the bucket names of the rate limits and `Espalier.RateLimit.account_hash/1` only | `:persistent_term` of the node | 0004 | done |
| session tokens | 32 bytes from `:crypto.strong_rand_bytes(32)` (`Espalier.Accounts.UserToken.generate/0`), stored as SHA-256 (`users_tokens.token_hash`) | identify a session; the raw token exists only in the encrypted session cookie | the session cookie; the database holds the hash only | 0004 | done |
| WebAuthn challenge | 32 random bytes from `wax_` (`Wax.Challenge`, `:crypto.strong_rand_bytes(32)`) | binds one passkey ceremony; it leaves the server only in the options JSON | `auth_challenges.challenge` for at most 300 seconds, deleted at its first use by `Espalier.Accounts.Challenges.consume/3`, and by the daily purge after expiry; the session cookie holds only the id of the row | 0005 | done |
| WebAuthn user handle | 64 random bytes from `:crypto.strong_rand_bytes(64)` (`Espalier.Accounts.ensure_webauthn_user_handle/1`) | the `user.id` of the passkeys of one account; it holds no personal data | `users.webauthn_user_handle`, unique index | 0005 | done |
| OIDC client certificate and key | an RSA key (`Espalier.Identity.Oidc.ClientKey.load!/3` refuses every other key type and a key that does not belong to the certificate); oidcc signs each `private_key_jwt` client assertion with the first algorithm of `token_endpoint_auth_signing_alg_values_supported` that the key supports, and `Espalier.Identity.Oidc.quirks/1` sets PS256 alone for every provider with a certificate (README section 15, decision D13); the key id follows `AUTH_<KEY>_CLIENT_KID_FORMAT` (`x5t`, the default and the format that Entra ID accepts, or `x5t_s256` or `sha1_hex` of the DER certificate) | authenticates the client at the token endpoint of `entra` and of `oidc` with `private_key_jwt` only | the PEM files named in `AUTH_<KEY>_CLIENT_CERT_FILE` and `AUTH_<KEY>_CLIENT_KEY_FILE`, and the JWK in `:persistent_term` that `Espalier.Identity.Oidc.Supervisor.init/1` loads; module `Espalier.Identity.Oidc.ClientKey` | 0006 | done |
| `AUTH_<KEY>_CLIENT_SECRET` | none: the platform applies no cryptographic operation to the secret, and oidcc sends it to the token endpoint in the HTTP Basic header (`client_secret_basic`) or in the form body (`client_secret_post`), on hosts that `Espalier.Identity.Oidc.check_endpoints/2` allows | authenticates the client at the token endpoint for `google` and for `oidc` without certificate in every environment, and for `entra` only in dev and test, because README section 6.7 allows client secrets for Entra ID only in development and `Espalier.Identity.Config.parse!/2` raises for an Entra secret outside dev and test | environment; `Espalier.Identity.Config.parse!/2` reads the variable when `config/runtime.exs` runs and keeps the value in the field `client_secret` of `%Espalier.Identity.OidcProvider{}` under `:identity_providers` (left out of `inspect/1`). `Espalier.Identity.Config` reads it, and `Espalier.Identity.Oidc.client_secret/1` hands it to oidcc_plug, or the fixed value `"unused-see-oidcc-issue-442"`, which is no secret, for certificate clients. The repository holds only the fixture secret of the mock in `config/dev.exs` and `config/test.exs` | 0006 | done |
| LDAP CA certificate | X.509 trust anchors for LDAPS and StartTLS: `verify: :verify_peer` with these certificates as `cacerts`, the host name through `server_name_indication`, TLS 1.3 and TLS 1.2 only (`Espalier.Identity.Ldap.tls_options/1`) | the only trust anchors of the directory connections; the operating system trust store is not used (ASVS 12.3.4) | the PEM file that `AUTH_<KEY>_CA_CERT_FILE` names, decoded at boot by `Espalier.Identity.Ldap.Config.parse!/3` with `:public_key.pem_decode/1` into the field `cacerts` (DER) of the provider struct under `:identity_providers`; read by `Espalier.Identity.Ldap.Config` | 0007 | done |
| `AUTH_<KEY>_BIND_PASSWORD` (`AUTH_LDAP_BIND_PASSWORD` for the key `ldap`) | none: the platform applies no cryptographic operation to the password, and `:eldap` sends it in the simple bind of the service account inside the TLS connection only (a deviation from ASVS 13.2.1, `asvs-l2.md`) | the simple bind of the service account on connection 1 (`Espalier.Identity.Ldap.lookup/2`), the only directory credential that the platform stores | environment; `config/runtime.exs` reads it once at boot through `Espalier.Identity.Ldap.Config.parse!/3`, which keeps it in the field `bind_password` of `%Espalier.Identity.Ldap.Config{}` under `:identity_providers` (left out of `inspect/1`); module `Espalier.Identity.Ldap`, whose `lookup/2` sends it. The guide describes its rotation through a second service account | 0007 | done |
| webhook secrets | HMAC-SHA256 signatures | sign outgoing webhook payloads only | 0013 completes the row with the module that reads them | 0013 | planned |

## Limits

1. Keys and plaintext live in the memory of the BEAM node. The cipher keys sit
   in the `:protected` ETS table `:"Elixir.Espalier.Vault.Config"`, which every
   process on the node can read, in the vault state, and Base64-encoded in the
   application environment under `Espalier.Vault`, where `config/runtime.exs`
   puts them. The HMAC secret never enters the vault; it stays Base64-encoded
   in the application environment under `Espalier.Hashed.HMAC`, which
   `Cloak.Ecto.HMAC` reads on every dump. `format_status/1` hides the keys in
   the vault state and has no effect on the application environment, which
   every process reads with `Application.get_env/2`. Crash dumps and remote
   consoles reach all of these places, so the release environment
   (`rel/env.sh.eex`) writes no crash dump file and starts no Erlang
   distribution unless the operator overrides it.
2. Query logs and telemetry carry plaintext when the rules of AGENTS.md are
   broken: a Repo call with its own `log:` option, or a telemetry handler that
   does not call `Espalier.Telemetry.QueryLog.scrub/1` first.
3. A backup that holds both the database and the keys protects nothing.
4. The ciphertext length reveals the plaintext length, because Cloak adds no
   padding. Each encrypted value grows by 40 bytes (1 type byte, 1 length
   byte, 10 tag bytes, 12 IV bytes, 16 GCM tag bytes).
5. Keyed hashes reveal which rows hold equal values, and with the dump and the
   HMAC secret, low-entropy values such as e-mail addresses can be guessed
   offline.
6. The AAD is the constant `"AES256GCM"`, so someone with write access to the
   database can copy a valid ciphertext into another row or column under the
   same key without detection. That attacker is outside the threat model, and
   the fallback plan of `key-management.md` binds the AAD to table and column.
7. SQL cannot sort, range-filter or search encrypted columns.
8. An attacker who runs code inside the application is not stopped.
9. A failed load raises `ArgumentError` with the ciphertext in its message,
   and a failed dump raises `Ecto.ChangeError` with the plaintext in its
   message. A dump fails when the vault is not running, which the supervision
   order (the vault starts before `Espalier.Repo`) and the data migration rule
   of AGENTS.md prevent.

## Controls and tests

Each control of this document has a test under `test/espalier/crypto/`
(ASVS 14.2.4).

| Control | Code | Test |
|---|---|---|
| Keys are 32 bytes in Base64, distinct, and checked at boot | `Espalier.Crypto.Keys` | `keys_test.exs` |
| AES-256-GCM with a 12-byte IV; a failed authentication returns `:error` | `Espalier.Crypto.StrictAESGCM` | `strict_aes_gcm_test.exs` |
| The vault holds only the strict GCM wrapper, and only allowed modules name Cloak | `Espalier.Vault` | `cipher_allowlist_test.exs` |
| Encrypted columns hold tagged ciphertext; keyed hashes use SHA-256; `inspect/1` shows no value | `Espalier.Encrypted.*`, `Espalier.Hashed.HMAC` | `encrypted_types_test.exs` |
| A changed value, a wrong key or an unknown tag makes the read raise | `Espalier.Vault`, `Espalier.Crypto.StrictAESGCM` | `tamper_test.exs` |
| Rotation rewrites every value under the current key and keeps `updated_at` | `Espalier.Crypto.Rotation` | `rotation_test.exs` |
| No Cloak type inside an embedded schema; every Cloak field has `redact: true` | `Espalier.Crypto.SchemaRules` | `schema_rules_test.exs` |
| Production query logs and telemetry carry no plaintext | `Espalier.Telemetry.QueryLog`, `config/prod.exs` | `query_log_test.exs`, `cipher_allowlist_test.exs` |
| Every protected field of the application is listed here | this document | `inventory_test.exs` |
