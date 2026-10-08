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
| `event`, `user_id`, `session_id`, `ip`, `factor`, `provider`, `reason`, `count`, `account_hash` | the attributes of a security event |

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
what (the event name, `factor`, `provider`, `reason`, `count`).

| Event | Level | Written by | Attributes |
|---|---|---|---|
| `authn_login_success` | info | `Espalier.Accounts.authenticate_password/3` (password accepted, reason `second_factor_pending`); `EspalierWeb.UserAuth.log_in_user/3` (session opened, factor = the methods joined by `+`) | `user_id`, `session_id`, `ip`, `factor`, `provider`, `reason` |
| `authn_login_successafterfail` | info | `authenticate_password/3` after five or more failures | `user_id`, `ip`, `factor`, `provider`, `count` |
| `authn_login_fail` | warning | `authenticate_password/3` | `user_id` or `account_hash`, `ip`, `factor`, `provider`, `reason` (`unknown`, `invalid`, `too_long`, `no_password`, `locked`, `disabled`) |
| `authn_login_fail_max` | warning | `Espalier.Accounts.FailureCounters` at the fifth failure | `user_id`, `factor`, `count` |
| `authn_login_lock` | warning | `FailureCounters` at the fiftieth failure | `user_id`, `factor`, `count` |
| `authn_password_change` | info | `Espalier.Accounts.update_user_password/3` | `user_id`, `factor`, `provider` |
| `authn_password_change_fail` | warning | `update_user_password/3` | `user_id`, `factor`, `provider` |
| `authn_token_created`, `authn_token_revoked` | info | `create_api_client/2`, `delete_api_client/2` | `reason` |
| `authz_fail` | warning | the plugs of `EspalierWeb.UserAuth` (every 403) | `user_id`, `ip`, `reason` (`enrollment_required`, `reauth_required`, `forbidden`) |
| `privilege_permissions_changed` | info | `grant_role/3`, `revoke_role/3`, `replace_idp_role_grants/3` | `user_id`, `reason` (the audit action) |
| `excess_rate_limit_exceeded` | warning | `EspalierWeb.Plugs.RateLimit` | `ip`, `reason` (the bucket) |
| `excess_sessions_exceeded` | warning | `create_session/2` at the concurrent limit | `user_id`, `session_id` |
| `malicious_csrf` | warning | `protect_api_from_forgery/2` (`reason` absent) and `EspalierWeb.Plugs.FetchMetadata` (`reason` `cross_site_request`) | `ip`, `user_id`, `reason` |
| `session_created` | info | `log_in_user/3` | `user_id`, `session_id`, `ip`, `provider` |
| `session_renewed` | info | `create_session/2` (replaced row of the same user), `reissue_session/2` | `user_id`, `session_id` |
| `session_expired` | info | `get_session_by_token/2` (`idle`, `absolute`), `end_user_sessions/2` (`admin`), `end_all_sessions/1` (`admin_all`) | `user_id`, `session_id`, `reason`, `count` |
| `session_logout` | info | `log_out_user/1`, `put_pending_second_factor/3`, `delete_session/2`, `create_session/2` (replaced row of another user) | `user_id`, `session_id`, `ip`, `reason` |
| `user_created` | info | `invite_user/2`, `create_signup_user/1` | `user_id`, `reason` |
| `user_updated` | info | `confirm_email_change/3`, `disable_user/2` | `user_id`, `reason` |
| `breach_check_unavailable` | warning | `Espalier.Accounts.BreachedPasswords` | none |

`authz_change` and `session_use_after_expire` belong to the vocabulary and
are written by later tasks. Tasks 0005 to 0007 add their event names and
attribute keys to the allowlists of `Espalier.SecurityLog`, together with the
events that use them, and a task whose event records a rejection adds it to
the warning events as well.

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
| Settings at boot | `AUTH_DEMO=true`, `SESSION_MAX_HOURS` above 24, and a production instance without `SMTP_HOST` | warning |

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
  `email`, `token`, `code`, `secret` or `recovery_code` appear as
  `[FILTERED]` (`config :phoenix, :filter_parameters`), also inside nested
  maps. Tasks 0005, 0006 and 0009 add their keys.
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
