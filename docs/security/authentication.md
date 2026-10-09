# Authentication and sessions

This document describes the sign-in pathways, the second factors, the
sessions, the abuse protection and the password rules of tasks 0004, 0005
and 0006 (ASVS 6.1.1 to 6.1.3, 7.1.1 to 7.1.3, 7.6.1 and 8.1.1). The
verification matrix is [`asvs-l2.md`](asvs-l2.md), the log inventory is
[`logging.md`](logging.md), the operator guide for identity providers is
[`../guides/identity-providers.md`](../guides/identity-providers.md), and
the plan is README sections 6.2 to 6.7, 6.10 and 6.11. Task 0007 adds its
pathway to this document. The toolchain check of the passkey
library is [`wax-spike.md`](wax-spike.md).

## Pathways and session strength

Every pathway ends in `EspalierWeb.UserAuth.log_in_user/3`, which calls
`Espalier.Accounts.create_session/2`. That function raises `ArgumentError`
unless `Espalier.Accounts.UserToken.strength_valid?/3` accepts the strength for
the methods of the sign-in, so a password alone never opens a session
(ASVS 6.3.4). README section 6.2 lists every pathway of the platform. A
local account reaches a full session only with a passkey, or with a first
factor and a second factor (ASVS 6.3.3).

| Pathway | Route | First step | Result | Methods | Strength |
|---|---|---|---|---|---|
| Password | `POST /api/auth/password` | Argon2id verification | pending second-factor state in the session cookie, five minutes; no session row | `password` | none until the second factor |
| Second factor | `POST /api/auth/second-factor` | the pending state of a first factor | full session; the row keeps `provider_key` and `idp_sid_hash` of the pending state | the first factor and `totp`, `passkey` or `recovery_code` | `mfa` |
| Passkey (local accounts only) | `POST /api/auth/passkey/options` and `POST /api/auth/passkey` | discoverable WebAuthn credential with user verification | full session | `passkey` | `mfa` |
| Invitation | `POST /api/auth/invitations/accept` | single-use e-mail link, 10 minutes | enrollment session, 30 minutes; it reaches only the `:enrollment` pipeline | `email_code` | `enrollment` |
| Enrollment | `POST /api/me/passkeys`, or `PUT /api/me/password` and `POST /api/me/totp/confirm` | an enrollment session | full session, and ten recovery codes when the user holds none | `email_code` and `passkey` or `totp` | `mfa` |
| Recovery (local accounts only) | `POST /api/auth/recovery/start` and `POST /api/auth/recovery/verify` | a link sent by e-mail, 10 minutes, and a saved recovery code | recovery session, 30 minutes; it reaches only the `:enrollment` pipeline | `recovery_code`, `email_code` | `recovery` |
| Completed recovery | `POST /api/me/passkeys` or `POST /api/me/totp/confirm` | a recovery session | full session, ten new recovery codes, every failure counter cleared | `recovery_code`, `email_code` and `passkey` or `totp` | `mfa` |
| Step-up | `POST /api/me/reauth` | an `mfa` session and a TOTP code or a passkey | the session row is reissued with `mfa_at` now | the method is appended | `mfa` |
| OIDC, `local` mode | `GET /auth/oidc/:provider`, the callback and `POST /api/auth/finish` | the provider sign-in | `{"next": "second_factor"}` with the pending state for an enrolled user, then `POST /api/auth/second-factor`; otherwise an enrollment session, 30 minutes, with `{"next": "enroll_second_factor"}` | `oidc`, then `oidc` and `totp`, `passkey` or `recovery_code` | `enrollment`, then `mfa` |
| OIDC, `idp_trusted` mode | the same routes | the provider sign-in with a multi-factor `amr`, or without `amr` | full session | `oidc`, `idp_mfa` | `mfa` |
| OIDC link | `POST /api/auth/oidc/:provider/intents` (`link`), then the OIDC routes | an `mfa` session with a second factor in the last 10 minutes, and the provider sign-in in the same browser session | the identity is linked at `POST /api/auth/finish`; the session stays | unchanged | `mfa` |
| OIDC step-up (`idp_trusted` only) | `POST /api/auth/oidc/:provider/intents` (`step_up`), then the OIDC routes with `max_age=0` | an `mfa` session of a user with an identity of the provider | the session row is reissued with `mfa_at` now and the provider's `amr` | `idp_mfa` is appended | `mfa` |
| Demo (`AUTH_DEMO=true` only) | `POST /api/auth/demo` | choice of slot 1 to 20 | demo session; the flag `demo` of the session payload marks every page | `demo` | `demo` |

Passkey sign-in serves only accounts without an external identity. A user
with an `external_identities` row signs in through the provider or the
directory and uses a local passkey only as second factor, so the provider or
the directory can still block the account, `idp_claim` grants are replaced at
each sign-in, and the session row carries the `provider_key`. With
`LOCAL_ACCOUNTS=false`, the passkey sign-in and both recovery routes answer
404; the purposes `second_factor` and `reauth` of the passkey options stay
available for federated users with a local passkey.

The strength check accepts:

| Strength | Methods |
|---|---|
| `mfa` | a list with `passkey`, a list with `idp_mfa`, or `totp` or `recovery_code` together with `password`, `oidc` or `ldap`; `[email_code, totp]` only with `completes: :enrollment`, and `[recovery_code, email_code, totp]` only with `completes: :recovery` |
| `enrollment` | exactly `[email_code]`, `[oidc]` or `[ldap]` (the last two for a first federated sign-in without a local factor, tasks 0006 and 0007) |
| `demo` | exactly `[demo]` |
| `recovery` | `recovery_code` and `email_code` |

`completes:` is an attribute of `Espalier.Accounts.Factors.complete_enrollment/3`;
`create_session/2` reads it for the check and stores it in no column. Every
other combination raises `ArgumentError`.

`require_authenticated_user/2` passes the strengths `mfa` and `demo` and
answers 403 `enrollment_required` for `enrollment` and `recovery`.
`require_enrollment_session/2` passes `enrollment`, `recovery` and `mfa` and
answers 403 `forbidden` for `demo`. `require_recent_auth/2` answers 403
`reauth_required` unless the session recorded a second factor (`mfa_at`)
within the last 10 minutes, or the session has the strength `enrollment` or
`recovery`, which reaches only the routes of the `:enrollment` pipeline. It
guards the password change, the e-mail change, the ending of a session and
every factor change (ASVS 7.5.1). A route with both pipelines names
`:enrollment` first, so a request without a session and a demo session halt
before the recent-auth check.

| Pipelines | Routes |
|---|---|
| `:enrollment` | `GET /api/me/security` |
| `:enrollment`, `:recent_auth` | `POST /api/me/passkeys/options`, `POST /api/me/passkeys`, `POST /api/me/totp`, `POST /api/me/totp/confirm`, `PUT /api/me/password` |
| `:authenticated` | `GET /api/me/sessions`, `POST /api/me/reauth` |
| `:authenticated`, `:recent_auth` | `DELETE /api/me/sessions/:id`, `PUT /api/me/email`, `POST /api/me/email/confirm`, `DELETE /api/me/passkeys/:id`, `DELETE /api/me/totp`, `POST /api/me/recovery-codes` |

In an `enrollment` or `recovery` session, `PUT /api/me/password` sets the
password without the current one. Such a session exists only for a user
without a second factor, or after a saved recovery code and a link sent by
e-mail, so a forgotten-password reset never bypasses an enabled second factor
(ASVS 6.4.3).

## OIDC sign-in

Task 0006 adds the sign-in through Microsoft Entra ID, Google Workspace and
any OIDC provider that the operator configures (README section 6.7). The
operator guide [`identity-providers.md`](../guides/identity-providers.md)
lists the variables. The provider sign-in is the first step, and every OIDC
sign-in ends in `log_in_user/3` or `put_pending_second_factor/3` of the local
pathways (ASVS 6.3.4).

### Entry points

These routes are the only OIDC entry points (ASVS 6.3.4):

| Route | Pipeline | Purpose |
|---|---|---|
| `GET /auth/oidc/:provider` | `:oidc_transaction` | starts the authorization request; with `?intent=` a link or a step-up |
| `GET /auth/oidc/:provider/callback` | `:oidc_transaction` | redeems the code, validates the ID token and redirects to `/auth/finish#ticket=` or `/auth/finish?error=` |
| `GET /auth/oidc/:provider/front-channel-logout` | `:oidc_transaction` | ends the sessions of a provider `sid` |
| `POST /api/auth/finish` | `:api` | turns the ticket into the result of the sign-in |
| `POST /api/auth/oidc/:provider/intents` | `:api`, `:authenticated` | creates an intent for a link or a step-up |

`GET /auth/providers` of task 0004 lists the configured providers with `kind`
`redirect` and `start_url` `/auth/oidc/<key>`.

### Flow

1. `authorize` stores the transaction (provider key, purpose, user id, time)
   in the transaction cookie `__Host-espalier_tx` (`SameSite=Lax`, 10
   minutes, encrypted), next to the nonce and the PKCE verifier of
   oidcc_plug, and redirects with PKCE S256, `state`, `nonce` and the scopes
   `openid`, `profile` and `email`. No request carries `prompt=none`
   (ASVS 7.6.2).
2. The callback first binds the response to the transaction of this
   browser: the transaction must exist and `state` must match it. A failure
   up to here keeps the transaction cookie, so a forged cross-site request
   to the callback cannot end a sign-in in progress. The callback then
   checks the provider of the redirect URI, an `error` answer and the RFC
   9207 `iss` parameter where the provider advertises it, redeems the
   code once with the client secret or a `private_key_jwt` assertion, and
   validates the ID token: signature with a key of the configured issuer's
   JWKS, algorithm RS256, PS256 or ES256, `iss`, `aud` equal to the client
   id, `exp` and `nonce`. The provider rules check the tenant (Entra ID), the
   hosted domain (Google) and the groups overage. The access and refresh
   tokens are dropped. The callback creates no session; it stores a 32-byte
   binding in the transaction cookie and redirects to
   `/auth/finish#ticket=<ticket>`, a single-use ticket of 60 seconds.
3. `POST /api/auth/finish` consumes the ticket with the binding of the same
   browser and deletes the transaction cookie. A ticket in another browser
   fails with 401 `ticket_invalid` (ASVS 2.3.1).

### Modes and session strength

| Mode | Provider result | Answer of the finish step | Methods | Strength |
|---|---|---|---|---|
| `local` (default) | any sign-in, user with a passkey or TOTP factor | `{"next": "second_factor"}`; the pending state keeps `provider_key` and the bytes of `idp_sid_hash` | `oidc`, then the second factor | `mfa` after `POST /api/auth/second-factor` |
| `local` | first sign-in without a local factor | `{"next": "enroll_second_factor"}` and an enrollment session, 30 minutes | `oidc` | `enrollment`, then `mfa` after a passkey or TOTP |
| `idp_trusted` | `amr` with a value of `AUTH_<KEY>_MFA_AMR` (default `mfa`), or no `amr` | the session payload | `oidc`, `idp_mfa`; the row stores the provider's `amr` in `idp_amr` | `mfa` |
| `idp_trusted` | `amr` without such a value, for example `["pwd"]` | as in `local` mode | as in `local` mode | as in `local` mode |

A missing `amr` keeps the operator's statement that the provider enforces
multi-factor sign-in (README section 6.2, rule 4), and the boot logs a
warning for every provider in `idp_trusted` mode (ASVS 6.8.4). Entra ID
sends no `amr`, also after a sign-in with MFA (spike of task 0006,
2026-10-09), so for Entra ID that statement, backed by Conditional Access or
security defaults, is the only basis of `idp_trusted` mode. In `local`
mode, whoever passes the provider's sign-in first for a new account binds
the first local factor; the guide states this for operators who switch
provisioning on.

### Linking and step-up

- A link needs an `mfa` session with a second factor in the last 10 minutes
  (403 `reauth_required` otherwise, ASVS 7.5.1) and no identity of the same
  provider (409 `provider_already_linked`). The intent works once, for 5
  minutes, and only in the browser session that created it. The callback
  writes no identity; `POST /api/auth/finish` links it for the account of
  the current session, which must be the account of the ticket, and mails
  `identity_linked`.
- A step-up needs an identity of the provider and `idp_trusted` mode (422
  `step_up_not_available` otherwise); users of `local` providers step up
  with `POST /api/me/reauth`. The authorization request carries `max_age=0`,
  the ID token must carry an `auth_time` from the request on (60 seconds of
  clock skew) and a multi-factor `amr`, and the finish step reissues the
  session row with `mfa_at` now (ASVS 7.2.4).
- Password sign-in, discoverable passkey sign-in and self-service recovery
  serve only accounts without an external identity. After a link, the
  account signs in only through the provider, and its passkeys, TOTP factor
  and recovery codes serve as second factor after the provider sign-in.

### Logout

- Front-channel logout: Entra ID loads `GET /auth/oidc/:provider/front-channel-logout`
  in an iframe. The request carries no platform cookie; every session row of
  the provider whose `idp_sid_hash` equals the keyed hash of `sid` ends. A
  present `iss` must equal the provider's issuer. The answer is always 200
  with an empty body and `Cache-Control: no-store`. The rows of the second
  factor, the enrollment, a step-up and a password change keep the bytes of
  `idp_sid_hash`, so the logout reaches each of them.
- RP-initiated logout: `DELETE /api/session` of an OIDC session answers 200
  with `{"logout_url": ...}` when the provider's discovery document names an
  `end_session_endpoint` on its allowed hosts. The URL carries `client_id`
  and `post_logout_redirect_uri` (`PUBLIC_URL/signed-out`) and no
  `id_token_hint`, because the platform keeps no ID token. Every other
  sign-out, also for Google, answers 204.
- Back-channel logout does not exist, because neither oidcc 3.9.0 nor Entra
  ID offers it (ASVS 10.5.5 does not apply). A provider session therefore
  outlives the platform session and the other way round, except through the
  two paths above (ASVS 7.1.3, 7.6.1).

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
| Second factor, passkey sign-in, recovery verification, completed enrollment or recovery | `log_in_user/3` creates a new row with a new token and deletes the row the cookie held (ASVS 7.2.4) |
| Step-up (`POST /api/me/reauth`) | `EspalierWeb.UserAuth.step_up/2` reissues the row with `mfa_at` now (ASVS 7.2.4) |
| Factor added or removed, completed recovery | the answer carries `other_sessions`, the number of the user's other live sessions, so the SPA offers `DELETE /api/me/sessions/:id` for them (ASVS 7.4.3) |

`reissue_session/2` replaces a row by a copy with a new token in one
transaction and keeps every other column, among them `expires_at`,
`provider_key` and the bytes of `idp_sid_hash`; `step_up/2` uses it.

### Cookies and CSRF

| Cookie | Attributes | Content |
|---|---|---|
| `__Host-espalier` | `Secure`, `HttpOnly`, `Path=/`, no `Domain`, `SameSite=Strict`, encrypted and signed (`Plug.Session` cookie store with `encryption_salt`) | the session token, the CSRF token, the pending second-factor state with its failure count (`pending_second_factor_failures`), and the id of a running WebAuthn ceremony (`webauthn_ceremony`, the id of an `auth_challenges` row); no personal data |
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
| `auth_ip` | 1 minute | 30 | client IP (IPv6 reduced to /64) | `POST /api/auth/password`, `POST /api/auth/invitations/accept`, `POST /api/auth/finish` |
| `password_account` | 15 minutes | 10 | keyed hash of the normalized address | `POST /api/auth/password` |
| `invitation_ip` | 15 minutes | 10 | client IP | `POST /api/auth/invitations` |
| `invitation_target` | 1 hour | 3 | keyed hash of the normalized address | `POST /api/auth/invitations` |
| `demo_ip` | 1 minute | 10 | client IP | `POST /api/auth/demo` |
| `account_change` | 15 minutes | 10 | keyed hash of the user id | `PUT /api/me/password`, `PUT /api/me/email` |
| `passkey_options_ip` | 1 minute | 30 | client IP | `POST /api/auth/passkey/options` |
| `passkey_ip` | 1 minute | 10 | client IP | `POST /api/auth/passkey` |
| `second_factor_ip` | 1 minute | 10 | client IP | `POST /api/auth/second-factor` |
| `second_factor_user` | 1 minute | 10 | keyed hash of the pending user id | `POST /api/auth/second-factor` |
| `recovery_start_ip` | 1 minute | 10 | client IP | `POST /api/auth/recovery/start` |
| `recovery_start_target` | 1 hour | 3 | keyed hash of the normalized address | `POST /api/auth/recovery/start` |
| `recovery_verify_ip` | 1 minute | 10 | client IP | `POST /api/auth/recovery/verify` |
| `recovery_verify_user` | 15 minutes | 10 | keyed hash of the user id that the e-mail token resolves to | `POST /api/auth/recovery/verify` |
| `reauth_user` | 1 minute | 10 | keyed hash of the session user id | `POST /api/me/reauth` |
| `totp_confirm_user` | 1 minute | 10 | keyed hash of the session user id | `POST /api/me/totp/confirm` |
| `oidc_authorize` | 1 minute | 30 | client IP | `GET /auth/oidc/:provider` |
| `oidc_callback` | 1 minute | 30 | client IP | `GET /auth/oidc/:provider/callback` |
| `oidc_intent` | 1 minute | 10 | keyed hash of the session user id | `POST /api/auth/oidc/:provider/intents` |
| `oidc_front_channel` | 1 minute | 60 | client IP | `GET /auth/oidc/:provider/front-channel-logout` |

Account keys are HMAC-SHA256 under a key derived once at boot from
`SECRET_KEY_BASE`, so the limiter holds no address. Known and unknown
addresses share the same buckets, so a 429 reveals nothing about an account.
The client IP comes from `X-Forwarded-For` only when the peer lies in
`TRUSTED_PROXIES` (`EspalierWeb.Plugs.TrustedProxy`, rightmost entry). The ETS
backend counts per node; the compose files run one node, and several nodes
would need a shared backend such as `hammer_backend_redis`.

### Failure counters

`Espalier.Accounts.FailureCounters` keeps one row per user and authenticator
in `failure_counters` (README section 6.10). The kinds are `:password` and
the second factors `:totp`, `:passkey` and `:recovery_code`
(`Espalier.Accounts.Factors.verify/5`):

- From the fifth consecutive failure, the authenticator is locked for
  `min(30 * 2^(n - 5), 3600)` seconds after failure `n`: 30 seconds after the
  fifth, 60 after the sixth, 960 after the tenth, and one hour from the
  twelfth. Reaching 5 logs `authn_login_fail_max`.
- The fiftieth failure disables the authenticator and logs `authn_login_lock`;
  for a second factor it also sends the mail `authenticator_disabled`. The
  limit stays below the NIST limit of 100. Only a completed recovery
  (`FailureCounters.clear_all/1`) or an admin (task 0015) clears
  `disabled_at`. The confirmation of a new TOTP factor in a recovery session
  passes a disabled `:totp` counter, so a recovery can replace that factor.
- An attempt against a locked or disabled authenticator is rejected without
  verification and without counting, with the same answer as a wrong password.
- A success resets the count and the lock. A success after five or more
  failures sends the mail `failed_attempts` and logs
  `authn_login_successafterfail`.

A failure counts only against the user that the request identifies before
any verification: the pending user on `POST /api/auth/second-factor` (also
when the assertion names a credential of another account), the session user
on `POST /api/me/reauth` and `POST /api/me/totp/confirm`, and the user that
the e-mail token resolves to on `POST /api/auth/recovery/verify`.

A failed discoverable passkey sign-in (`POST /api/auth/passkey`) counts only
per IP, in the bucket `passkey_ip`, whatever the reason of the failure, and
never against the owner of the credential. Credential ids are no secret:
`allowCredentials` of the second-factor options lists them to anyone who
holds the password. A valid signature cannot be guessed, so counting a wrong
one against the owner adds no protection, and it would let anyone who knows
a credential id disable the owner's passkeys from rotating addresses.

Protection against malicious lockout: the counters lock one authenticator,
never the account. A locked password leaves passkey sign-in available, and
the lock lasts at most one hour until the disable limit.

## Second factors

The second factors of README section 6.6 live in `Espalier.Accounts.Passkeys`,
`Espalier.Accounts.Totp` and `Espalier.Accounts.RecoveryCodes`; the rules
that combine them live in `Espalier.Accounts.Factors`.

**Passkeys** (`wax_` 0.7.0, [`wax-spike.md`](wax-spike.md)). Registration and
authentication use attestation `"none"`, `user_verification: "required"`, the
relying party id and the exact origin list of `config :espalier, :webauthn`
(in production the host and the origin of `PUBLIC_URL`, which must use
`https`) and 300 seconds. Credentials are discoverable. The application adds
the checks that `wax_` leaves open:

| Check | Module |
|---|---|
| Each challenge is stored in `auth_challenges` with its purpose and its user (or none for a sign-in), lives 300 seconds, and is deleted before it is checked, so it works once | `Espalier.Accounts.Challenges` |
| `clientDataJSON` must have the expected `type`, a base64url `challenge`, an origin of the list, `crossOrigin` absent or `false` and no `topOrigin` (`wax_` issue #60) | `Espalier.Accounts.Passkeys.ClientData` |
| The COSE algorithm of a new credential must be -7, -8 or -257 (`wax_` issue #59, decision D13) | `Espalier.Accounts.Passkeys.Checks.algorithm_allowed?/1` |
| Authenticator data with the backup state set and backup eligibility unset fails | `Checks.backup_flags_valid?/1` |
| The `userHandle` must belong to the owner of the credential; a discoverable sign-in requires it | `Checks.user_handle_valid?/3` |
| A sign count that does not increase is logged as `risk_signal: "sign_count"`; the stored count never decreases | `Checks.sign_count/2` |
| Every `wax_` call is wrapped; a raised exception fails the ceremony and is logged without its message (`wax_` issue #61) | `Espalier.Accounts.Passkeys.WaxCall` |

The WebAuthn user handle is 64 random bytes in `users.webauthn_user_handle`
and holds no personal data.

**TOTP** (`nimble_totp` 1.0.0). A 20-byte secret, encrypted with the closure
type in `totp_factors.secret`, counts once a valid code confirms it.
Verification accepts the current and the previous 30-second step (decision
D15) and stores the matched step in `last_used_step` with a conditional
update, so each code works once (ASVS 6.5.1). Codes are HMAC-SHA-1 values
(decision D14). TOTP is a second factor only, so its enrollment in an
enrollment or recovery session needs a password or an external identity
first (409 `password_required`).

**Recovery codes.** Ten codes of 128 bits each, shown once as 26 base32
characters in groups of four, stored as HMAC-SHA256 under
`Espalier.Accounts.RecoveryCodes.key/0` with `used_at`. Regeneration replaces
every earlier code.

**Factor rules.** A user is enrolled with a passkey, or with a confirmed TOTP
factor together with a password or an external identity. The last remaining
second factor cannot be removed (409 `last_factor`). With
`ADMIN_REQUIRE_PASSKEY=true` (default) the last passkey of an admin cannot be
removed (409 `admin_passkey_required`), and `flags.admin_passkey_required` of
`GET /api/session` marks an admin without a passkey; task 0015 adds the
passkey gate on the admin routes. The value `false` logs a warning at boot.

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
a password failure. Enrollment and recovery sessions set it without the
current one (section "Pathways and session strength").

## Enumeration

Sign-in, invitation request and e-mail change answer with the same body,
status and timing for known and unknown accounts (ASVS 6.3.8):

- `POST /api/auth/password` answers the same 401 `invalid_credentials` for a
  wrong password, an unknown address, a password over 128 code points, a
  locked counter and a stored value that is no Argon2 hash. Every branch runs
  one Argon2 verification; branches without a usable hash run
  `Argon2.no_user_verify/0`.
- `POST /api/auth/invitations`, `PUT /api/me/email` and
  `POST /api/auth/recovery/start` always answer 202. Every request causes one
  lookup and one job insert (an invitation, a `signup` job, a `change_email`
  job, `recovery_instructions`, `recovery_unavailable` or the no-op job
  `none`), and every mail goes out through Oban, so the answer does not wait
  for SMTP.
- Every failure of a second factor, a passkey sign-in, a recovery
  verification and a step-up answers the same 401 `authentication_failed`.
- `test/espalier_web/enumeration_timing_test.exs` (`mix test --only timing`)
  sends 40 sign-ins with the production Argon2 parameters and asserts that
  the medians for known and unknown addresses differ by less than 25 percent.

## Notifications

| Mail | Trigger | Recipient |
|---|---|---|
| `invitation` | invitation by an admin, a release function or the bootstrap; a request with `SIGNUP=invite` or `domain` | the invited address; the link `/invite#token=` lives 10 minutes |
| `change_email` | `PUT /api/me/email` | the new address; the link `/account/email/confirm#token=` lives 10 minutes |
| `email_changed` | confirmed e-mail change; a new verified address from an identity provider at sign-in (task 0006) | the old address (ASVS 6.3.7) |
| `password_changed` | password change | the account (ASVS 6.3.7) |
| `failed_attempts` | sign-in with the password or a second factor after five or more failures of that factor; the mail names the factor | the account (ASVS 6.3.5) |
| `authenticator_disabled` | the fiftieth failure of a second factor | the account (ASVS 6.3.5) |
| `factor_added` | passkey registered, TOTP confirmed | the account (ASVS 6.3.7) |
| `factor_removed` | passkey or TOTP removed, TOTP replaced in a recovery session | the account (ASVS 6.3.7) |
| `recovery_codes_regenerated` | `POST /api/me/recovery-codes` | the account (ASVS 6.3.7) |
| `recovery_used` | a recovery code as second factor, and every recovery verification | the account (ASVS 6.3.7) |
| `recovery_instructions` | `POST /api/auth/recovery/start` for an active local user with unused recovery codes | the account; the link `/recover#token=` lives 10 minutes, only the link of the latest request works, also when its mail jobs run out of order, and the link opens one recovery session |
| `recovery_unavailable` | the same request for an active local user without unused recovery codes | the account; the mail explains the admin-assisted reset (decision D11) and carries no link |
| `identity_linked` | a link of an identity provider at `POST /api/auth/finish` (task 0006) | the account; the mail names the provider and the time |

No mail contains a code, a TOTP secret, a credential id or a session token.

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
