# ASVS verification matrix

Espalier verifies against OWASP ASVS 5.0.0 at tag `v5.0.0_release` of the
[OWASP ASVS repository](https://github.com/OWASP/ASVS/tree/v5.0.0_release/5.0/en).
The target is Level 2, with the selected Level 3 items of README section 6.1:
6.3.5 and 6.3.7 (notifications), 6.3.8 (no enumeration), 6.5.6 (every factor
revocable), 3.4.8 (COOP) and 3.5.8 (Fetch Metadata).

Each row names the tasks that implement the requirement, the owner first and
the extending tasks after it, as the ownership table of task 0004 (step 42)
assigns them. `Code` names the module or document, and `Test` names the test
file that proves it. A requirement the platform deviates from carries the
status `deviation` and an entry in the section "Deviations".

Status values:

| Status | Meaning |
|---|---|
| `open` | At least one named task has not yet added its code and test. `Notes` states what each task delivers and what remains. |
| `implemented` | Code exists, and the test that proves it is missing. |
| `verified` | Every named task has added its code and its test. |
| `deviation` | The platform deviates on purpose; the section "Deviations" gives the rule and the reason. |
| `not applicable` | The requirement does not apply; `Notes` gives the reason. |

Test files without a directory lie in `test/espalier/crypto/`.

## V11 Cryptography

| ID | Level | Requirement | Task | Status | Code | Test | Notes |
|---|---|---|---|---|---|---|---|
| 11.1.1 | 2 | Key management policy and key lifecycle | 0003, 0017 | open | `docs/security/key-management.md` | `keys_test.exs`, `rotation_test.exs` | 0003 documents the lifecycle of `CLOAK_KEY_V<n>` and `CLOAK_HMAC_SECRET` in `docs/security/key-management.md`. 0017 adds the lifecycle of the deployment secrets and certificates (rotation of `SECRET_KEY_BASE` and API tokens, renewal of the database certificates) in `docs/guides/operations.md`. |
| 11.1.2 | 2 | Cryptographic inventory of keys, algorithms and certificates | 0003, 0017 | open | `docs/security/crypto-inventory.md` | `inventory_test.exs` | 0003 lists the keys, algorithms and protected columns of the account tasks in `docs/security/crypto-inventory.md`. 0017 adds the certificates of the production deployment (the CA certificate of the PostgreSQL connection in `DATABASE_CA_CERT_FILE` and the TLS settings of the reverse proxy example). |
| 11.2.1 | 2 | Industry-validated crypto implementations | 0003 | verified | `Espalier.Crypto.StrictAESGCM`, `Espalier.Hashed.HMAC` (OTP `:crypto` through Cloak; no own primitive) | `strict_aes_gcm_test.exs`, `cipher_allowlist_test.exs` | |
| 11.2.2 | 2 | Crypto agility, key replacement and re-encryption | 0003 | verified | `Espalier.Vault` (versioned cipher tags, key list read at runtime), `Espalier.Crypto.Rotation`, `Espalier.Release.rotate_encryption/0` | `rotation_test.exs`, `cipher_allowlist_test.exs` | A key or a cipher is replaced without a schema change. Runbook: `docs/security/key-management.md`. |
| 11.2.3 | 2 | At least 128 bits of security | 0003 | verified | `Espalier.Crypto.Keys` (32-byte keys), `Espalier.Crypto.StrictAESGCM` (AES-256-GCM), `Espalier.Hashed.HMAC` (HMAC-SHA256) | `keys_test.exs`, `cipher_allowlist_test.exs` | |
| 11.3.2 | 1 | Only approved ciphers and modes | 0003 | verified | `Espalier.Vault`, `Espalier.Crypto.StrictAESGCM` | `cipher_allowlist_test.exs` | The vault holds only the strict AES-GCM wrapper, and the test fails on any other cipher. |
| 11.3.3 | 2 | Authenticated encryption against modification | 0003 | verified | `Espalier.Crypto.StrictAESGCM`, `Espalier.Vault.decrypt!/1` | `tamper_test.exs`, `strict_aes_gcm_test.exs` | A changed value or a wrong key makes the read raise. |
| 11.4.1 | 1 | Only approved hash functions | 0003 | verified | `Espalier.Hashed.HMAC` | `encrypted_types_test.exs` | `init/1` fixes SHA-256 whatever the configuration says. |
| 11.5.1 | 2 | CSPRNG values with at least 128 bits | 0003, 0004, 0005 | open | `scripts/gen-keys.exs` (`:crypto.strong_rand_bytes(32)`), `Espalier.Crypto.Keys` | `keys_test.exs` | 0003 generates the Cloak keys. 0004 adds session, e-mail and API tokens. 0005 adds recovery codes, TOTP secrets, WebAuthn challenges and user handles. |

## V13 Configuration

| ID | Level | Requirement | Task | Status | Code | Test | Notes |
|---|---|---|---|---|---|---|---|
| 13.3.1 | 2 | Secrets management, no secrets in source or build artifacts | 0003, 0006, 0007, 0013, 0017 | open | `config/runtime.exs`, `.env.example`, `Espalier.Crypto.Keys` | `keys_test.exs` | 0003 covers the Cloak keys; the operator part is in `docs/security/key-management.md`. 0006 covers the OIDC client secrets and the key of the client certificate, 0007 the LDAP bind password, 0013 the webhook secrets, and 0017 every other secret, the image and the Git history. |
| 13.3.2 | 2 | Least privilege for secret assets | 0003 | verified | `docs/security/key-management.md` (Storage and access, Memory of the running node), `rel/env.sh.eex`, `Espalier.Vault.format_status/1` | `cipher_allowlist_test.exs` | Key access is limited to the people who deploy the application, and keys stay out of database backups; the operator part is in `docs/security/key-management.md`. |

## V14 Data Protection

| ID | Level | Requirement | Task | Status | Code | Test | Notes |
|---|---|---|---|---|---|---|---|
| 14.1.1 | 2 | Sensitive data classified into protection levels | 0003 | open | `docs/security/crypto-inventory.md` (Protection levels, Columns) | `inventory_test.exs` | 0003 classifies the account and authentication data. The data protection workstream of README section 10 adds the other data classes; the row stays `open` until that workstream has classified them. |
| 14.1.2 | 2 | Protection requirements per protection level | 0003 | verified | `docs/security/crypto-inventory.md` (Protection levels) | `inventory_test.exs`, `schema_rules_test.exs` | |
| 14.2.4 | 2 | Controls implemented as the protection level defines | 0003 | verified | `Espalier.Encrypted.*`, `Espalier.Hashed.HMAC`, `Espalier.Crypto.SchemaRules`, `Espalier.Telemetry.QueryLog` | `encrypted_types_test.exs`, `schema_rules_test.exs`, `query_log_test.exs` | `docs/security/crypto-inventory.md`, section "Controls and tests", maps each control to its test. |

## V16 Security Logging and Error Handling

| ID | Level | Requirement | Task | Status | Code | Test | Notes |
|---|---|---|---|---|---|---|---|
| 16.2.5 | 2 | Logging enforced by protection level | 0003, 0004, 0005, 0006, 0007, 0013 | open | `config/prod.exs` (`log: false`), `Espalier.Telemetry.QueryLog` | `query_log_test.exs`, `cipher_allowlist_test.exs` | 0003 keeps plaintext out of query logs and telemetry. 0004 adds request and security event logs, 0005 keeps codes and factor secrets out of the logs, 0006 keeps authorization codes, ID tokens, tickets and intents out of the logs, 0007 keeps the bind request and LDAP exception texts out of the logs, and 0013 keeps API tokens, webhook secrets and signatures out of the logs. |
| 16.5.3 | 2 | Fail securely, no fail-open | 0003, 0006, 0007 | open | `Espalier.Crypto.StrictAESGCM`, `Espalier.Vault.decrypt!/1` | `tamper_test.exs` | 0003 makes a failed decryption raise, so no code path loads a tampered value as data. 0006 and 0007 make the sign-in fail closed when an identity provider or the directory is unreachable. |

## Deviations

No requirement of the rows above deviates.
