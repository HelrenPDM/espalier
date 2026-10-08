# Authentication and sessions

This document describes the sign-in pathways, the sessions, the abuse
protection and the password rules of task 0004 (ASVS 6.1.1 to 6.1.3, 7.1.1,
7.1.2 and 8.1.1). The verification matrix is [`asvs-l2.md`](asvs-l2.md), the
log inventory is [`logging.md`](logging.md), and the plan is README sections
6.2 to 6.5, 6.10 and 6.11. Tasks 0005 to 0007 add their pathways and factors
to this document.

## Pathways and session strength

Every pathway ends in `EspalierWeb.UserAuth.log_in_user/3`, which calls
`Espalier.Accounts.create_session/2`. That function raises `ArgumentError`
unless `Espalier.Accounts.UserToken.strength_valid?/3` accepts the strength for
the methods of the sign-in, so a password alone never opens a session
(ASVS 6.3.4). README section 6.2 lists every pathway of the platform; this
task implements three of them and the state in between.

| Pathway | Route | First step | Result | Methods | Strength |
|---|---|---|---|---|---|
| Password | `POST /api/auth/password` | Argon2id verification | pending second-factor state in the session cookie, five minutes; no session row (task 0005 completes it) | `password` | none until the second factor |
| Invitation | `POST /api/auth/invitations/accept` | single-use e-mail link, 10 minutes | enrollment session, 30 minutes; it reaches only the `:enrollment` pipeline | `email_code` | `enrollment` |
| Demo (`AUTH_DEMO=true` only) | `POST /api/auth/demo` | choice of slot 1 to 20 | demo session; the flag `demo` of the session payload marks every page | `demo` | `demo` |

The strength check of this task accepts:

| Strength | Methods |
|---|---|
| `mfa` | a list with `passkey`, a list with `idp_mfa`, or `totp` together with `password`, `oidc` or `ldap` |
| `enrollment` | exactly `[email_code]` |
| `demo` | exactly `[demo]` |
| `recovery` | `recovery_code` and `email_code` |

Task 0005 adds the clauses for a recovery code as second factor, for the
completion of an enrollment or a recovery, and for the federated enrollment
sessions. Every other combination raises.

`require_authenticated_user/2` passes the strengths `mfa` and `demo` and
answers 403 `enrollment_required` for `enrollment` and `recovery`.
`require_enrollment_session/2` passes `enrollment`, `recovery` and `mfa` and
answers 403 `forbidden` for `demo`. `require_recent_auth/2` answers 403
`reauth_required` unless the session recorded a second factor (`mfa_at`)
within the last 10 minutes; it guards the password change, the e-mail change
and the ending of a session (ASVS 7.5.1).

## Sessions

### Settings

| Setting | Variable | Default | Effect |
|---|---|---|---|
| Inactivity timeout | `SESSION_IDLE_MINUTES` | 60 | a session row whose `last_seen_at` is this old is deleted at its next use |
| Absolute lifetime | `SESSION_MAX_HOURS` | 24 | `expires_at` of a session row; a value above 24 logs a warning at boot that names decision D9 |
| Enrollment and recovery sessions | fixed | 30 minutes | `expires_at` of these rows |
| Concurrent sessions | `SESSION_MAX_CONCURRENT` | 5 | live sessions per user |
| Pending second-factor state | fixed | 5 minutes | `expires_at` of the state in the session cookie |

Both timeouts are checked on the server in
`Espalier.Accounts.get_session_by_token/2`; cookie expiry is never the only
check (ASVS 7.3.1, 7.3.2). A row that fails a timeout is deleted and logged as
`session_expired` with the reason `idle` or `absolute`. `touch_session/2`
updates `last_seen_at` at most once a minute. The Oban job
`Espalier.Accounts.PurgeExpiredTokensWorker` deletes expired and idle rows
every day at 02:00 UTC.

### Session row

Each session is a row of `users_tokens` with the context `session`:

| Column | Content |
|---|---|
| `token_hash` | SHA-256 of the 32-byte token from `:crypto.strong_rand_bytes/1`; the raw token exists only in the encrypted cookie |
| `auth_methods`, `strength` | the methods and the strength of the sign-in |
| `authenticated_at`, `mfa_at` | the time of the sign-in and of the last second factor |
| `provider_key`, `idp_sid_hash` | the external provider and the keyed hash of its session id (task 0006); `null` for local and demo sessions |
| `device_summary` | browser and system family from the first `User-Agent` request header, such as `Firefox on Linux` (`Espalier.Accounts.DeviceSummary`); the full value is never stored or logged |
| `last_seen_at`, `expires_at` | the inactivity and the absolute limit |

`GET /api/me/sessions` lists the live sessions of the user with `device`,
`strength`, `auth_methods` and the three timestamps, and marks the calling
session with `current: true`.

### Concurrent session limit

`create_session/2` locks the user row, counts the live sessions and deletes
the oldest ones so that at most `SESSION_MAX_CONCURRENT` remain after the
insert, all in one transaction. Each deleted session is logged as
`excess_sessions_exceeded`. The oldest session ends; the new sign-in always
succeeds.

### Termination

| Event | Effect |
|---|---|
| Sign-in in a browser that holds a session | the row of the previous token is deleted in the transaction that creates the new one (`replaces`); a password sign-in deletes it when the pending state replaces the session (ASVS 7.2.4) |
| Logout (`DELETE /api/session`) | the row is deleted and the session renewed (ASVS 7.4.1) |
| Inactivity or absolute limit | the row is deleted at its next use, or by the daily purge |
| Password change | every token row of the user is deleted; the calling client receives a copy of its row with a new token and a new CSRF token (ASVS 7.4.3) |
| Role change (`grant_role/3`, `revoke_role/3`, `replace_idp_role_grants/3` with a changed set) | every session row of the user is deleted, so the next sign-in issues a new token |
| User disabled (`disable_user/2`) | every token row of the user is deleted (ASVS 7.4.2) |
| User ends a session (`DELETE /api/me/sessions/:id`, recent second factor) | that row is deleted (ASVS 7.5.2) |
| Admin ends sessions (`end_user_sessions/2`, `end_all_sessions/1`, `Espalier.Release.end_all_sessions/0`) | the rows of one user or of all users are deleted (ASVS 7.4.5) |
| Invitation accepted | every token row of the user is deleted, which makes the link single-use |

`reissue_session/2` replaces a row by a copy with a new token in one
transaction and keeps `expires_at`; task 0005 uses it for the step-up.

### Cookies and CSRF

| Cookie | Attributes | Content |
|---|---|---|
| `__Host-espalier` | `Secure`, `HttpOnly`, `Path=/`, no `Domain`, `SameSite=Strict`, encrypted and signed (`Plug.Session` cookie store with `encryption_salt`) | the session token, the CSRF token, the pending second-factor state, and the WebAuthn ceremony id of task 0005; no personal data |
| `__Host-espalier_tx` | as above with `SameSite=Lax` and `Max-Age=600` | the data of one OIDC flow (task 0006) |

The options live in `EspalierWeb.TransactionCookie`. The CSRF defense has three
layers (README section 6.5): the `x-csrf-token` header on every mutating
request under `/api` (`EspalierWeb.UserAuth.protect_api_from_forgery/2`, which
also rejects a request without the header), the Fetch Metadata plug
`EspalierWeb.Plugs.FetchMetadata` with the `Origin` check when
`Sec-Fetch-Site` is missing, and the `Strict` cookie.
`test/espalier_web/csrf_coverage_test.exs` sends every mutating route a
request without the token.

The development server runs on `http://localhost:5173`. Whether the browsers
used for development store a `Secure` `__Host-` cookie over plain
`http://localhost` is not yet checked in a browser; the check is open (task
0004 Notes, to be done with `make run` and the developer tools of each
browser). Task 0017 checks the cookies on the container behind TLS.

## Abuse protection

### Rate limits

`Espalier.RateLimit` (Hammer 7.5, ETS backend, `:fix_window_per_key`)
counts per key. Each window starts at the first hit of its key. A denial
answers 429 with `retry-after` in seconds and `{"error":"rate_limited"}` and
logs `excess_rate_limit_exceeded`.

| Bucket | Window | Limit | Key | Routes |
|---|---|---|---|---|
| `auth_ip` | 1 minute | 30 | client IP (IPv6 reduced to /64) | `POST /api/auth/password`, `POST /api/auth/invitations/accept` |
| `password_account` | 15 minutes | 10 | keyed hash of the normalized address | `POST /api/auth/password` |
| `invitation_ip` | 15 minutes | 10 | client IP | `POST /api/auth/invitations` |
| `invitation_target` | 1 hour | 3 | keyed hash of the normalized address | `POST /api/auth/invitations` |
| `demo_ip` | 1 minute | 10 | client IP | `POST /api/auth/demo` |
| `account_change` | 15 minutes | 10 | keyed hash of the user id | `PUT /api/me/password`, `PUT /api/me/email` |

Account keys are HMAC-SHA256 under a key derived once at boot from
`SECRET_KEY_BASE`, so the limiter holds no address. Known and unknown
addresses share the same buckets, so a 429 reveals nothing about an account.
The client IP comes from `X-Forwarded-For` only when the peer lies in
`TRUSTED_PROXIES` (`EspalierWeb.Plugs.TrustedProxy`, rightmost entry). The ETS
backend counts per node; the compose files run one node, and several nodes
would need a shared backend such as `hammer_backend_redis`.

### Failure counters

`Espalier.Accounts.FailureCounters` keeps one row per user and authenticator
in `failure_counters` (README section 6.10):

- From the fifth consecutive failure, the authenticator is locked for
  `min(30 * 2^(n - 5), 3600)` seconds after failure `n`: 30 seconds after the
  fifth, 60 after the sixth, 960 after the tenth, and one hour from the
  twelfth. Reaching 5 logs `authn_login_fail_max`.
- The fiftieth failure disables the authenticator and logs `authn_login_lock`.
  The limit stays below the NIST limit of 100. Only a completed recovery
  (task 0005) or an admin (task 0015) clears `disabled_at`.
- An attempt against a locked or disabled authenticator is rejected without
  verification and without counting, with the same answer as a wrong password.
- A success resets the count and the lock. A success after five or more
  failures sends the mail `failed_attempts` and logs
  `authn_login_successafterfail`.

Protection against malicious lockout: the counters lock one authenticator,
never the account. A locked password leaves passkey sign-in (task 0005)
available, and the lock lasts at most one hour until the disable limit.

## Passwords

`Espalier.Accounts.PasswordPolicy` checks every new password in
`Espalier.Accounts.User.password_changeset/3`:

- **Normalization.** `PasswordPolicy.prepare/1` normalizes every password to
  Unicode NFC with `String.normalize(password, :nfc)` before the length check,
  the blocklist checks, the breached-password check, the Argon2id hash and the
  verification. NIST SP 800-63B-4 section 3.1.1.2 asks verifiers that accept
  Unicode to apply NFC before hashing, so that a password verifies in the same
  way on keyboards and devices that produce different Unicode forms of the
  same characters. ASVS 5.0.0 6.2.8 asks for verification exactly as received;
  README section 15, decision D12, follows NIST, and `asvs-l2.md` records the
  deviation. Directory passwords never pass through this module and go to the
  LDAP server unchanged (task 0007 step 8).
- **Length.** 15 to 128 code points, counted after normalization
  (`too_short`, `too_long`). Up to 128 code points are accepted (ASVS 6.2.9).
- **Common passwords.** The lowercase password must not be in
  `priv/security/common-passwords.txt` (`common`). The list holds 10,898
  entries of 15 or more code points; `priv/security/README.md` names its
  source, license, retrieval date and filter command.
- **Context words.** The letters of the password alone (digits, whitespace
  and punctuation removed) must not equal a word of
  `priv/security/context-words.txt` or of `PASSWORD_CONTEXT_WORDS`, where an
  operator adds the words of the organization; and the password must not
  contain the local part of the user's address or the display name, each when
  4 or more code points long (`context`). Both sides are compared in NFC and
  lower case.
- **Breached passwords.** With `PASSWORD_BREACH_CHECK=hibp`, the first five
  hex characters of the SHA-1 of the normalized password go to the Pwned
  Passwords range API with padding (`breached`). The default is `off`
  (decision D10). When the API is unreachable, the bundled lists still apply
  and `breach_check_unavailable` is logged.
- No composition rule exists, no password expires, and no password hint or
  secret question exists (ASVS 6.2.5, 6.2.10, 6.4.2).

Users change the password with `PUT /api/me/password` and both the current
and the new password (ASVS 6.2.2, 6.2.3); a wrong current password counts as
a password failure.

## Enumeration

Sign-in, invitation request and e-mail change answer with the same body,
status and timing for known and unknown accounts (ASVS 6.3.8):

- `POST /api/auth/password` answers the same 401 `invalid_credentials` for a
  wrong password, an unknown address, a password over 128 code points, a
  locked counter and a stored value that is no Argon2 hash. Every branch runs
  one Argon2 verification; branches without a usable hash run
  `Argon2.no_user_verify/0`.
- `POST /api/auth/invitations` and `PUT /api/me/email` always answer 202.
  Every request causes one lookup and one job insert (an invitation, a
  `signup` job, a `change_email` job or the no-op job `none`), and every mail
  goes out through Oban, so the answer does not wait for SMTP.
- `test/espalier_web/enumeration_timing_test.exs` (`mix test --only timing`)
  sends 40 sign-ins with the production Argon2 parameters and asserts that
  the medians for known and unknown addresses differ by less than 25 percent.

## Notifications

| Mail | Trigger | Recipient |
|---|---|---|
| `invitation` | invitation by an admin, a release function or the bootstrap; a request with `SIGNUP=invite` or `domain` | the invited address; the link `/invite#token=` lives 10 minutes |
| `change_email` | `PUT /api/me/email` | the new address; the link `/account/email/confirm#token=` lives 10 minutes |
| `email_changed` | confirmed e-mail change | the old address (ASVS 6.3.7) |
| `password_changed` | password change | the account (ASVS 6.3.7) |
| `failed_attempts` | password sign-in after five or more failures | the account (ASVS 6.3.5) |

Tokens travel in the URL fragment, so they reach neither the server log nor
the `Referer` header. Users without an address receive no mail. Production
sends over SMTP with STARTTLS (`tls: :always`), authentication and certificate
verification (`verify: :verify_peer` with the system CA store and server name
indication, ASVS 12.3.1). Without `SMTP_HOST`, a production instance sends no
mail: `Espalier.Mailer.DisabledAdapter` refuses every delivery, and the boot
logs a warning.

## Bootstrap admin and release functions

`Espalier.Accounts.Bootstrap` runs at every boot for the addresses in
`BOOTSTRAP_ADMIN_EMAILS`. No default account exists (ASVS 6.3.2).

- An unknown address becomes a local user with a `manual` grant `admin` and
  an invitation; with `LOCAL_ACCOUNTS=false` it is skipped with a warning.
- A known local account (active, no external identity, which also excludes
  demo users) receives the grant when it lacks it.
- Every other known account, a disabled one or one that holds an external
  identity, receives no grant: the boot logs a warning with the user id. An
  e-mail claim of an identity provider therefore never grants `admin`
  (README section 6.2, rule 3).
- The bootstrap runs at every boot, so a local admin whose grant was revoked
  receives it again at the next boot while the address stays in
  `BOOTSTRAP_ADMIN_EMAILS`.

An operator grants a role to a federated account, or to any account, with
`bin/espalier eval 'Espalier.Release.grant_role("admin", "a@example.org")'`,
which is an explicit operator action. `Espalier.Release.invite_user/1` invites
an address or resends an invitation, and `Espalier.Release.end_all_sessions/0`
ends every session. These functions insert jobs without processing them; the
running application sends the mails.

## Roles and checks

| Role | Granted by | Checked by |
|---|---|---|
| `learner` | every signed-in user, without a stored grant | `require_authenticated_user/2` |
| `facilitator`, `author`, `registrar`, `analyst`, `admin` | `manual` grants (admins, release functions, bootstrap) and `idp_claim` grants (tasks 0006, 0007) | the router pipelines of the same names (`require_authenticated_user/2` and `require_role/2`), and the context functions, which take the scope as first argument |

Every role-bound route runs its pipeline on the server, and a missing role
answers 403 `forbidden` and logs `authz_fail` (ASVS 8.2.1, 8.3.1). The
administrative context functions (`invite_user/2`, `resend_invitation/2`,
`grant_role/3`, `revoke_role/3`, `disable_user/2`, `end_user_sessions/2`,
`end_all_sessions/1`, the API client functions and
`Espalier.Audit.list_events/2`) return `{:error, :forbidden}` without the role
`admin`. `Espalier.Accounts.Scope.system/0` holds `admin` for release
functions and the boot task; no request reaches it. Demo users hold only
`learner`. A change of the role grants of a user ends every session of that
user.

## Argon2 parameters

Passwords are hashed with Argon2id (`argon2_elixir` 4.1.3) with
`argon2_type: 2`, `t_cost: 2`, `m_cost: 16` (64 MiB) and `parallelism: 1`
(ASVS 11.4.2). `parallelism: 1` keeps the vendored C code off its thread
creation path, which upstream issue #73 reports failing on this OTP version.
The OWASP Password Storage Cheat Sheet minimum for Argon2id is 19 MiB with
`t=2` and `p=1`; the floor of this platform is `m_cost: 15` (32 MiB).

`make argon2-bench` runs `scripts/argon2_bench.exs` inside the production
image. The moduledoc of `Argon2.Stats` in argon2_elixir 4.1.3 names 500
milliseconds as the time target and attributes it to the Argon2 draft
guidelines. Measurement on 2026-10-08, image `espalier:latest` on a host with
16 CPU cores and 16 dirty CPU schedulers:

| Measurement | Result |
|---|---|
| One hash (`Argon2.Stats.report/1`) | 0.09 seconds |
| 200 verifications, at most 64 at a time | 0 errors |
| Median of one verification under that load | 880.4 ms |
| 95th percentile under that load | 929.6 ms |

One hash takes less than the target of 500 milliseconds, so `t_cost: 2,
m_cost: 16` stays. The times under load include the wait for a free dirty CPU
scheduler: 64 concurrent verifications share 16 schedulers. Concurrent hashes
run on the dirty CPU schedulers, so memory peaks at about their number times
64 MiB, 1 GiB on this host. The container memory limit must leave room for
that peak plus the memory of the node; on a host with fewer cores the peak is
lower, because the node starts one dirty CPU scheduler per core.
