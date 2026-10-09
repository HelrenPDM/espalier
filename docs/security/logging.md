# Logging

This document is the log inventory of Espalier (ASVS 16.1.1). The
verification matrix is [`asvs-l2.md`](asvs-l2.md); the account events are
described in [`authentication.md`](authentication.md).

## Destination and format

The application writes its logs to standard output only, which is the one
destination of every log line (ASVS 16.2.3). The container runtime or the
operator's log collector reads them there. Log retention is the operator's
decision; the application keeps no log.

| Environment | Format | Level |
|---|---|---|
| Production | one JSON object per line, `Espalier.Logger.JSONFormatter` as the formatter of the default handler (`config/prod.exs`) | `info` |
| Development | text, `[level] message` | `debug` |
| Test | text; ExUnit captures the lines of each test and prints them only when it fails | `warning` |

A production line holds:

| Key | Content |
|---|---|
| `time` | ISO 8601 in UTC with microseconds, from the timestamp of the log event (ASVS 16.2.2) |
| `level` | `info`, `notice`, `warning` or `error` |
| `message` | the message; for a security event, its name |
| `request_id` | the id of the HTTP request (`Plug.RequestId`) |
| `event`, `user_id`, `session_id`, `ip`, `factor`, `provider`, `reason`, `count`, `account_hash`, `risk_signal`, `credential_ref`, `change`, `exception` | the attributes of a security event |

Only these metadata keys appear. Values that are no string, number, boolean
or atom are written with `inspect/1`. JSON encoding escapes control
characters, so a newline in a message or a value cannot start a new log line
(ASVS 16.4.1).

## Security events

`Espalier.SecurityLog.event/3` writes every security event with the names of
the OWASP Logging Vocabulary (ASVS 16.2.1, 16.3.1 to 16.3.3). It accepts only
the names and attribute keys below and raises `ArgumentError` for any other.
Each event also emits the telemetry event `[:espalier, :security, :event]`
with the attributes and `name`. Failures and rejections log at `warning`,
everything else at `info`.

The attributes answer when (`time`), where (`ip`, `request_id`), who
(`user_id`, or `account_hash` for an identifier that matches no account) and
what (the event name, `factor`, `provider`, `reason`, `count`, `change`,
`risk_signal`, and for the OIDC flows of task 0006 `purpose` (`sign_in`,
`link`, `step_up`) and `trigger` (`front_channel`)). A passkey appears only as `credential_ref`, the first eight
hex characters of the SHA-256 hash of its credential id, and a rescued
exception only by its module in `exception`, never by its message.

| Event | Level | Written by | Attributes |
|---|---|---|---|
| `authn_login_success` | info | `Espalier.Accounts.authenticate_password/3` (password accepted, reason `second_factor_pending`); `EspalierWeb.UserAuth.log_in_user/3` (session opened, factor = the methods joined by `+`); `Espalier.Accounts.Factors.verify/5` and `record_success/5` (a passkey, TOTP or recovery-code verification for a second factor, a passkey sign-in, a recovery verification or a step-up); at `warning` with `risk_signal: "sign_count"` and `credential_ref` when the sign count of a passkey does not increase; `EspalierWeb.Auth.FinishController` after a step-up at an OIDC provider (`factor: "idp_mfa"`, `purpose: "step_up"`) | `user_id`, `session_id`, `ip`, `factor`, `provider`, `reason`, `risk_signal`, `credential_ref`, `purpose` |
| `authn_login_successafterfail` | info | `authenticate_password/3` and `Factors.record_success/5` after five or more failures | `user_id`, `ip`, `factor`, `provider`, `count` |
| `authn_login_fail` | warning | `authenticate_password/3`; `Factors.verify/5` and `Factors.log_failure/2` for every failed passkey, TOTP or recovery-code verification | `user_id` or `account_hash`, `ip`, `factor`, `provider`, `reason` (password: `unknown`, `invalid`, `too_long`, `no_password`, `locked`, `disabled`; second factors: for example `invalid_code`, `challenge_invalid`, `invalid_signature`, `user_not_verified`, `algorithm_not_allowed`, `cross_origin`, `user_handle_mismatch`, `credential_not_owned`, `external_identity`, `counter_locked`, `counter_disabled`, `no_pending_state`, `invalid_token`). `EspalierWeb.OidcController` and `EspalierWeb.Auth.FinishController` for every failed OIDC sign-in, link or step-up, with `provider`, `purpose` and the reason tag of a rule or of an oidcc error (for example `access_denied`, `provider_not_ready`, `endpoint_not_allowed`, `missing_transaction`, `state_not_verified`, `provider_mismatch`, `issuer_mismatch`, `invalid_callback`, `no_matching_key`, `token_expired`, `missing_claim`, `alg_not_allowed`, `tenant_mismatch`, `domain_mismatch`, `groups_overage`, `stale_auth_time`, `amr_single_factor`, `no_account`, `identity_in_use`, `intent_invalid`, `intent_session_mismatch`, `ticket_invalid`, `session_mismatch`) | `user_id` or `account_hash`, `ip`, `factor`, `provider`, `reason`, `purpose` |
| `authn_login_fail_max` | warning | `Espalier.Accounts.FailureCounters` at the fifth failure | `user_id`, `factor`, `count` |
| `authn_login_lock` | warning | `FailureCounters` at the fiftieth failure | `user_id`, `factor`, `count` |
| `authn_password_change` | info | `Espalier.Accounts.update_user_password/3` | `user_id`, `factor`, `provider` |
| `authn_password_change_fail` | warning | `update_user_password/3` | `user_id`, `factor`, `provider` |
| `authn_token_created`, `authn_token_revoked` | info | `create_api_client/2`, `delete_api_client/2` | `reason` |
| `authz_fail` | warning | the plugs of `EspalierWeb.UserAuth` (every 403), `EspalierWeb.OidcIntentController` (an intent without a recent second factor or from a demo session) | `user_id`, `ip`, `reason` (`enrollment_required`, `reauth_required`, `forbidden`) |
| `privilege_permissions_changed` | info | `grant_role/3`, `revoke_role/3`, `replace_idp_role_grants/3` (also at an OIDC sign-in whose role claims change the `idp_claim` grants; the audit event `role.synced` holds the added and removed roles) | `user_id`, `reason` (the audit action) |
| `excess_rate_limit_exceeded` | warning | `EspalierWeb.Plugs.RateLimit` | `ip`, `reason` (the bucket) |
| `excess_sessions_exceeded` | warning | `create_session/2` at the concurrent limit | `user_id`, `session_id` |
| `malicious_csrf` | warning | `protect_api_from_forgery/2` (`reason` absent) and `EspalierWeb.Plugs.FetchMetadata` (`reason` `cross_site_request`) | `ip`, `user_id`, `reason` |
| `session_created` | info | `log_in_user/3` | `user_id`, `session_id`, `ip`, `provider` |
| `session_renewed` | info | `create_session/2` (replaced row of the same user), `reissue_session/2` | `user_id`, `session_id` |
| `session_expired` | info | `get_session_by_token/2` (`idle`, `absolute`), `end_user_sessions/2` (`admin`), `end_all_sessions/1` (`admin_all`) | `user_id`, `session_id`, `reason`, `count` |
| `session_logout` | info | `log_out_user/1` (also for a sign-out that answers with a `logout_url`), `put_pending_second_factor/3`, `delete_session/2`, `create_session/2` (replaced row of another user); `EspalierWeb.OidcController.front_channel_logout/2` for each front-channel request with a `sid`, with the number of ended session rows | `user_id`, `session_id`, `ip`, `reason`; front-channel logout: `provider`, `trigger` (`front_channel`), `count` |
| `user_created` | info | `invite_user/2`, `create_signup_user/1`; `Espalier.Accounts.sign_in_external/2` when it provisions an account | `user_id`, `reason`; provisioning: `user_id`, `provider` |
| `user_updated` | info | `confirm_email_change/3`, `disable_user/2`; `Espalier.Accounts.Factors.notify_change/3` for a factor change; `Espalier.Accounts.link_external_identity/3` for a new link and `sign_in_external/2` for a refreshed address | `user_id`, `reason`; for a factor change `change` (`factor_added`, `factor_removed`, `recovery_codes_regenerated`) and `factor`; for a link or an address `change` (`identity_linked`, `email`) and `provider` |
| `input_validation_fail` | warning | `Espalier.Accounts.Passkeys.ClientData` (rejected `clientDataJSON`), `Espalier.Accounts.Passkeys.WaxCall` (rescued `wax_` exception) | `reason`, `exception` (the module name) |
| `breach_check_unavailable` | warning | `Espalier.Accounts.BreachedPasswords` | none |

`authz_change` and `session_use_after_expire` belong to the vocabulary and
are written by later tasks. Task 0006 adds the attribute keys `purpose` and
`trigger` to the allowlists of `Espalier.SecurityLog` and of the production
formatter (`config/prod.exs`); every value of them is a fixed word. Task 0007
adds its event names and attribute keys together with the events that use
them, and a task whose event records a rejection adds it to the warning
events as well.

An oidcc error term can hold a token or the claims of an ID token, so the log
carries only its reason tag, the first atom of the term
(`Espalier.Identity.Oidc.reason_tag/1`), and every OIDC failure ends in the
`authn_login_fail` event above. A completed OIDC sign-in writes
`session_created` and `authn_login_success` through `log_in_user/3`, with
`provider` and `factor`, for example `oidc+idp_mfa` or `oidc+totp`.

The OWASP Logging Vocabulary has no event for the enrollment of a factor, so
factor changes map to `user_updated` with a `change` attribute. No event of
its own marks a second-factor counter at 5 or 50 failures:
`FailureCounters.record_failure/3` writes `authn_login_fail_max` and
`authn_login_lock` with the `factor` for every kind.

`factor` names one verified factor in the events of a single verification
step, such as `password` in the events of `authenticate_password/3`, and the
methods of the session joined by `+` in the `authn_login_success` event of
`log_in_user/3`, such as `password+totp`. The events of `log_in_user/3` carry
no `methods` and no `strength` attribute. `authn_login_successafterfail` follows a success that resets a
counter of five or more failures, the count at which the failure counter
starts to lock and the `failed_attempts` mail goes out.

## Other logged failures

| Failure | Log | Level |
|---|---|---|
| Unhandled exception in a request | Bandit 1.12.5 logs the exception of every response whose status lies in its HTTP option `log_exceptions_with_status_codes`, `500..599` by default, so the endpoint configuration leaves the option unset; the client receives 500 `{"error":"internal_error"}` without internals (ASVS 16.3.4, 16.5.1) | error |
| Failed mail delivery | `mail delivery failed: job <id>, kind <kind>` from `Espalier.Accounts.MailWorker`, without the address and without the reason of the SMTP client, which can quote the recipient; Oban retries the job up to five attempts | warning |
| Unreachable Pwned Passwords API | the security event `breach_check_unavailable` | warning |
| Password verification error | `password verification failed: <message of argon2_elixir>` from `Espalier.Accounts.User.valid_password?/2`, without the input | error |
| Skipped bootstrap address | `bootstrap admin skipped user <id>: no active local account`, or the skip of an unknown address with `LOCAL_ACCOUNTS=false` | warning |
| Settings at boot | `AUTH_DEMO=true`, `SESSION_MAX_HOURS` above 24, a production instance without `SMTP_HOST`, and every OIDC provider with `AUTH_<KEY>_MFA=idp_trusted` (`Espalier.Identity.Oidc.Supervisor`, README section 6.2, rule 4) | warning |
| Unreachable OIDC provider | `Metadata load failed for issuer <issuer>. Retrying in <n> ms. Error Details: <term>` from the provider worker of oidcc 3.9.0 at each failed discovery or JWKS load; the term holds the HTTP status and the body of the provider's public answer or the transport error, and these requests carry no credential | error |

## What is never logged

- No password, no code, no token (session, invitation, e-mail change, API
  client) and no cookie value. Sessions appear by the id of their row
  (`session_id`), users by their id (ASVS 16.2.5).
- No e-mail address. An identifier that matches no account appears only as
  `account_hash`, the first eight hex characters of its keyed hash
  (`Espalier.RateLimit.account_hash/1`).
- No full `User-Agent` value; the session row keeps the browser and system
  family only.
- Request parameters whose key contains `password`, `current_password`,
  `email`, `token`, `code`, `secret`, `recovery_code`, `totp`, `passkey`,
  `credential`, `response` or `rawId`, and since task 0006 `state`,
  `session_state`, `ticket`, `intent`, `sid` or `id_token`, appear as
  `[FILTERED]` (`config :phoenix, :filter_parameters`), also inside nested
  maps, so TOTP codes, WebAuthn payloads, the authorization response, OIDC
  intents and front-channel `sid` values stay out of the request log
  (ASVS 16.2.5). The member `id` of a WebAuthn response repeats the
  credential id, which is no secret; an entry `"id"` would also filter keys
  such as `user_id`, so the list leaves it out. Task 0009 adds its keys.
- No provider access token, refresh token or ID token, no sign-in ticket and
  no OIDC intent. The callback drops the provider tokens, the ticket travels
  in the URL fragment, and an OIDC error reaches the log only as its reason
  tag. A front-channel logout appears with the provider and the number of
  ended sessions only.
- No TOTP code, recovery code, TOTP secret, WebAuthn challenge or credential
  id. Security events name a passkey by `credential_ref` only, and mails
  carry none of these values.
- No query parameter and no plaintext of an encrypted or hashed column: the
  production Repo runs with `log: false`, and `Espalier.Telemetry.QueryLog`
  logs queries without parameters (task 0003,
  [`crypto-inventory.md`](crypto-inventory.md)).

Development runs at `debug`, where ecto_sql logs queries with their
parameters and the SMTP adapter logs the headers of each mail, recipient
included. Neither appears in production, which runs at `info` with the query
log off.

## Audit events

Administrative actions are also written to the table `audit_events` through
`Espalier.Audit.record/4`:

| Column | Content |
|---|---|
| `action` | `user.invited`, `user.invitation_resent`, `user.signed_up`, `user.disabled`, `role.granted`, `role.revoked`, `role.synced`, `sessions.ended`, `sessions.ended_all`, `api_client.created`, `api_client.deleted` |
| `actor_id` | the acting user; `null` for release functions, the boot task and the `signup` job (`Scope.system/0`) |
| `subject_type`, `subject_id` | the changed record |
| `details` | role names, provider keys and counts; no personal data |
| `at` | UTC time of the action |

Audit events are append-only: the context has no update or delete function
apart from the retention job of task 0014. `Espalier.Audit.list_events/2`
requires the role `admin` and serves the admin area of task 0015.
