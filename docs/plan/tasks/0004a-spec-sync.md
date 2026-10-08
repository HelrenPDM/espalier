# 0004a: Sync the task specs with task 0004

> Milestone: M1 Accounts, Depends on: 0004

## Context to read first
- Read the section "Addendum: implementation" of `docs/plan/tasks/0004-accounts-sessions.md`: it lists where 0004 departs from its steps, and later specs cite several of these interfaces.
- Read `docs/security/asvs-l2.md` completely: the section `Ownership`, every chapter table and the section `Deviations`. Task 0004 (step 42) extended it with the full Level 1 and Level 2 scan of ASVS 5.0.0. The matrix holds 252 rows: 70 at Level 1, 176 at Level 2 and the 6 selected Level 3 items of README section 6.1. Chapter V17 is not applicable and takes one line without rows.
- Read the section "Security requirements" of every spec from 0003 to 0017, and sections 6.1, 6.3, 6.6, 6.7, 6.11, 13, 14 and 15 of `docs/plan/README.md`.
- Read the section "Keeping the issues in sync" of `docs/plan/tasks/EPIC.md`: every changed spec needs its GitHub issue updated, and specs over 65,536 characters continue in comments that start with "**Spec NNNN, part".

## Goal
Every task spec states the matrix rows it owns or extends, cites the
interfaces of 0004 in their implemented form, and assigns the open checks and
gaps that the matrix scan found. The decisions below are recorded in README
section 15. The GitHub issues mirror the changed specs, and the tasks that
follow 0004 can start from a consistent plan.

## Scope
- In: edits of the specs 0003 to 0017 (for 0004 only step 42 and the section "Security requirements"), of README sections 6, 14 and 15, of `docs/security/asvs-l2.md` (ownership table, rows and the section `Deviations`) and of `docs/plan/tasks/EPIC.md`; the GitHub issue bodies of the changed specs.
- In: a test that compares the `Task` column of the matrix with the "Security requirements" sections of the specs (step 6).
- Out: application code. A spec change that needs code belongs to the task that the spec describes.

## Decisions needed first
The maintainer decides these points before the steps run. Step 1 records each
decision in README section 15.

1. RS256. ASVS 5.0.0 Appendix C lists RSASSA-PKCS1-v1_5 as disallowed. RS256
   is in the ID token allowlist of README section 6.7 and of 0006 (9.1.2 and
   the `quirks/1` overrides), and COSE algorithm -257 is in the passkey list of
   README section 6.6 and of 0005. 0006 step 5 also gives `entra` the
   client-assertion list `token_endpoint_auth_signing_alg_values_supported`
   `["PS256", "RS256"]`, from which oidcc picks the algorithm of the
   `private_key_jwt` assertions (row 11.6.1); the Entra spike of decision D4
   (0006 step 18) shows whether Entra accepts PS256 alone. Check in the
   discovery documents of the providers of 0006
   (`id_token_signing_alg_values_supported`) and in the authenticator support
   of `wax_` where RS256 can be dropped. Options: drop RS256 where a provider
   or authenticator offers another algorithm, or keep it and record a
   deviation row with the reason.
2. SHA-1. ASVS Appendix C rates SHA-1 as legacy. README section 6.3 fixes
   SHA-1 for TOTP (`nimble_totp`, 0005) without a reason. 0004 hashes the
   password with SHA-1 for the Pwned Passwords range request
   (`Espalier.Accounts.BreachedPasswords.check/1`), because the API defines
   that format. Row 11.4.1 is a 0003 row with the status `verified` that names
   only the SHA-256 of `Espalier.Hashed.HMAC`, and row 14.2.3 mentions the
   range request only as data sent to a third party. Options: deviation rows
   for the TOTP use (owned by 0005) and for the range request (owned by 0004),
   or a note on 11.4.1, extended by 0004 and 0005, that names both uses and
   their reasons.
3. Announced deviations. Three specs announce deviations that the ownership
   table does not mark: 0005 (TOTP drift window under 6.5.5, also README
   section 6.6), 0007 (13.2.1, password bind of the service account) and 0011
   (14.2.1, `code`, `state` and the intent in a query string). Decide whether
   the ownership table marks them as deviations, as it marks 6.2.8.
4. Scan rows. 0004 step 42 states that each "Security requirements" section
   lists exactly the rows that the ownership table names for its task. The
   scan added rows outside the ownership table (step 3 lists them). Option A:
   add them to the ownership table and to the specs. Option B: keep the
   ownership table and state in 0004 step 42 that scan rows appear only in the
   matrix. Option A keeps every row traceable from its spec.
5. Proxy hop (12.3.3). The hop from the reverse proxy to the application runs
   over plain HTTP on the compose network; 0017 step 11 and its Notes describe
   that hop in `security.md` and `self-hosting.md`. Options: TLS on that hop
   (0017), or the status `deviation` for row 12.3.3 with an entry in the
   section `Deviations` whose reason is the compose network on one host.

## Steps

### Decisions and interfaces

1. Record the five decisions of the section above in README section 15 as
   decisions D13 to D17, and apply them: the algorithm lists of README
   sections 6.6 and 6.7, 0005 and 0006 (the ID token allowlist and the
   `entra` client-assertion list), the rows and the section `Deviations` of
   `docs/security/asvs-l2.md`, and the ownership table of the matrix and of
   0004 step 42.
2. Bring the citations of 0004 interfaces in line with the addendum of 0004:
   - 0005 step 13: `UserAuth.step_up/2` receives `{:ok, new_token}` from
     `reissue_session/2` and puts it with `UserAuth.put_reissued_session/2`.
     0006 extends `step_up/3` on the corrected 0005 step 13.
   - 0005 step 15 (and every other call of `update_user_password/3`): the
     function returns `{:ok, {user, token}}` or `{:error, changeset}`, where
     `token` is the raw token of the copy of the `keep_session:` row, or `nil`
     without that option, whatever `require_current:` says. It always deletes
     every token row of the user first. In an `enrollment` or `recovery`
     session, `PUT /api/me/password` calls
     `update_user_password(user, attrs, require_current: false, keep_session: session)`
     and puts the returned token with `UserAuth.put_reissued_session/2`, so the
     enrollment session keeps its strength, `expires_at`, `provider_key` and
     `idp_sid_hash`. A current-password error is a changeset error on
     `current_password` (`required`, `invalid`).
   - 0011 steps 1, 3, 12, 15 and 17: `PUT /api/me/password` answers a missing
     or wrong current password with 422 `validation_failed` and
     `fields.current_password: ["required"]` or `["invalid"]`. The error
     helpers, the password section, the strings and `PasswordSection.test.tsx`
     handle these codes.
   - 0005, 0006, 0007: `fetch_pending_second_factor(conn)` returns
     `{:ok, %{user, auth_methods, provider_key, idp_sid_hash, expires_at}}`
     (methods as atoms, `idp_sid_hash` as bytes, `expires_at` as a
     `DateTime`), or `:error` for a missing or expired state and for a user who
     is not active. It returns no conn and deletes nothing;
     `fetch_current_scope_for_user/2` deletes an expired or malformed state.
     `UserToken.method!/1` decodes stored methods.
   - 0005 step 20, 0006 (16.3.1, the event table of step 14, the telemetry
     test of step 17) and 0007 step 21: `log_in_user/3` logs `session_created`
     with `user_id`, `session_id`, `ip` and `provider`, and
     `authn_login_success` with these and `factor`, the methods of the session
     joined by `+`; it logs no `methods` and no `strength`. `log_out_user/1`
     logs `session_logout` with `user_id`, `session_id`, `ip` and the reason
     `user`. `reissue_session/2` logs `session_renewed` with `user_id` and
     `session_id`, and `authenticate_password/3` logs
     `authn_login_successafterfail` when a count of 5 or more is reset. Decide
     in 0005 step 20 whether 0005 extends `log_in_user/3` with `methods` and
     `strength` and what `factor` then means (0005 uses it for the one factor
     just verified), or whether the later specs cite only the attributes that
     0004 writes; align the threshold of `authn_login_successafterfail` in
     0005 with the count of 5. Update `docs/security/logging.md` to match.
   - 0005, 0006, 0007: `SecurityLog.event/3` raises for attribute keys outside
     its allowlist, so each task adds its keys together with its event names,
     and a rejection event (such as `input_validation_fail` of 0005) also goes
     into the list of warning events.
   - 0005 (Scope and step 18), 0006 step 11 (`oidc_intent`): controllers apply
     the user and address buckets with
     `EspalierWeb.Plugs.RateLimit.check_account/3` and continue only when
     `conn.halted` is false. 0007 keeps `Espalier.RateLimit.check_account/2`
     inside its sign-in service and writes the event itself.
   - 0005 steps 18 and 19: `FailureCounters.reset/2` returns the count before
     the reset, so steps 19 and 20 tell from that value whether a success
     follows failures; `record_failure/3` returns `{:ok, counter}`, and step
     19 sends `authenticator_disabled` when `consecutive_failures` has just
     reached 50.
   - 0006 (the step that adds `idp_amr`): `create_session/2` stores only the
     attributes that `UserToken.build_session_token/3` lists, so 0006 adds
     `idp_amr` there; `log_in_user/3` passes attributes through, and
     `reissue_session/2` copies every schema field.
   - 0007 step 18 (enrollment session test): `create_session/2` returns
     `{token, session}`, and the test asserts `session.expires_at`.
   - 0005 (`parameter_filter_test.exs`, step 21 and Acceptance), 0006 (the
     logging test of step 17) and 0013 step 24: Phoenix compiles
     `:filter_parameters` at boot, so these tests read `config/config.exs`
     with `Config.Reader.read!("config/config.exs", env: :test, target: :host)`
     and check `Phoenix.Logger.filter_values/2`, as
     `test/espalier/logging_test.exs` does.
   - 0005, 0006, 0007 tests: security events are asserted through
     `attach_security_events/0` (`Espalier.Test.SecurityEvents`, imported by
     `DataCase` and `ConnCase`). `config/test.exs` keeps the log level at
     `:warning`, so `capture_log/1` sees only warning-level lines; a test that
     needs info-level lines sets `async: false` and uses
     `Logger.put_module_level(Espalier.SecurityLog, :info)` with
     `Logger.delete_module_level/1` in `on_exit/1`.
   - Every spec with a controller test of a mutating `/api` route (0005, 0006,
     0007, 0009, 0013, 0014, 0015, 0016): `api_conn/0` and `next_request/1`
     run the real CSRF check (`plug_skip_csrf_protection` is `false`), so every
     POST, PUT, PATCH and DELETE request carries a token from
     `with_csrf_token/1`, including signed-out requests that expect 401,
     because `protect_api_from_forgery/2` runs before `:authenticated`. A test
     fetches a new token after every sign-in, step-up and password change,
     which rotate it. `put_setting/2` changes an application setting for one
     test; a module that calls it sets `async: false`.
   - 0015 step 8: `Audit.list_events/2` takes only `:action`, `:subject_id`
     and `:limit`, so 0015 adds the `:actor_id` filter and paging, with
     `desc: :id` as the last ordering key, because `at` and `inserted_at`
     have second precision.
   - 0015 step 4: `resend_invitation/2` already writes
     `user.invitation_resent` and returns `:ok`, `{:error, :not_invitable}` or
     `{:error, :forbidden}`; remove its extension from 0015 and map the three
     results to 202, 409 `not_invitable` and 403.
   - 0017 step 4 (`Espalier.BootCheck`): `config/runtime.exs` already stops a
     production boot for a `SECRET_KEY_BASE` shorter than 64 bytes and
     validates the variables of `Espalier.RuntimeConfig`; the boot check
     collects these messages instead of repeating them. `SMTP_HOST` is
     optional, `MAIL_FROM` is required only together with it, and an instance
     without `SMTP_HOST` uses `Espalier.Mailer.DisabledAdapter`. The demo
     profile (`.env.demo.example`, decision D5) needs neither.
   - 0017 guides: name `Espalier.RuntimeConfig` as the parser of the account
     and session variables, the optional SMTP setup with its TLS options, and
     the 64-byte rule of `SECRET_KEY_BASE`.
   - Tasks that add environment variables to `config/runtime.exs` (0005 step 2
     `ADMIN_REQUIRE_PASSKEY`, 0009 step 9 `TRACKING_DETAIL` and
     `INSIGHTS_ORG_UNIT`, 0013 step 2, 0014 step 10, 0015
     `PACK_UPLOAD_MAX_MB`, 0016 step 7 `EXPORT_DIR`): decide whether they
     extend `Espalier.RuntimeConfig` or keep their own parser, and say so in
     the spec. 0005 step 2 reads the WebAuthn `rp_id` and `origins` from the
     `:public_url` of `Espalier.RuntimeConfig` (trimmed, unquoted, without a
     trailing slash), and keeps its own production check for the `https`
     scheme, because `RuntimeConfig` accepts `http`. 0006 and 0007 add no line
     to `config/runtime.exs`; their `AUTH_<KEY>_*` variables go through
     `Espalier.Identity.Config.parse!/2`.

### Matrix rows per task

3. The scan rows below name a task in the `Task` column of
   `docs/security/asvs-l2.md` that the "Security requirements" section of its
   spec does not list (computed on 2026-10-08). Apply decision 4: with option
   A, add each row to the ownership table and to the section of the spec, with
   one sentence on what the task delivers, taken from the `Notes` of the row.

   | Task | Rows |
   |---|---|
   | 0003 | 11.3.1, 11.4.3, 11.6.1 |
   | 0004 | 1.2.2, 1.2.3, 1.3.2, 1.3.7, 1.3.11, 1.5.2, 2.1.3, 2.2.1, 2.2.2, 2.3.1, 2.3.2, 2.3.3, 2.4.1, 4.1.1, 4.1.3, 14.2.2, 14.2.3, 14.3.2, 15.1.3, 15.2.2, 15.3.1, 15.3.2, 15.3.3, 15.3.4 |
   | 0005 | 2.3.1, 11.6.1 |
   | 0006 | 1.3.6, 2.3.1, 9.2.4, 11.4.3, 11.6.1, 13.1.1, 15.3.2 |
   | 0008 | 1.1.1, 1.3.3, 1.5.2, 2.1.2, 2.2.1, 2.2.3, 2.3.3, 5.2.2, 5.3.2 |
   | 0009 | 1.1.1, 1.3.3, 2.1.1, 2.2.1, 2.2.2, 2.3.1, 2.4.1, 15.3.1, 15.3.3, 15.3.5, 15.3.7 |
   | 0010 | 1.1.2, 1.2.1, 1.2.2, 3.7.1, 14.2.3, 15.3.5, 15.3.6 |
   | 0011 | 2.1.1 |
   | 0012 | 1.1.2, 1.2.1, 1.2.2, 1.3.5 |
   | 0013 | 1.2.3, 1.3.6, 2.1.1, 2.2.1, 2.2.3, 2.3.3, 11.4.3, 14.3.2, 15.3.1, 15.3.2, 15.3.3 |
   | 0014 | 2.1.1, 2.2.1, 2.4.1, 15.3.3 |
   | 0015 | 2.1.1, 2.1.3, 2.2.1, 2.3.2, 2.3.3, 5.1.1, 5.2.1, 5.2.2, 5.2.3, 5.3.2, 14.2.2, 14.3.2, 15.2.2, 15.3.1, 15.3.3 |
   | 0016 | 1.1.2, 1.2.1, 1.2.3, 1.3.7, 2.1.1, 2.2.1, 5.3.2, 5.4.1, 5.4.2, 15.2.2, 15.3.3 |
   | 0017 | 1.2.4, 1.3.2, 2.1.1, 2.1.2, 2.1.3, 4.1.1, 4.1.2, 4.1.3, 4.2.1, 5.1.1, 11.6.1, 12.1.2, 12.2.1, 12.2.2, 12.3.3, 13.1.1, 13.2.3, 13.4.3, 14.2.2, 15.1.3, 15.2.3, 15.3.4 |

   Every row that a spec lists already appears in the matrix with that task.
   48 rows have the status `not applicable` with a reason; check each reason
   against the plan once.
4. Correct these rows of the matrix:
   - 11.1.1 (0003): the Notes say that 0017 writes the lifecycle of the
     deployment secrets in `docs/guides/operations.md`; 0017 step 13 writes it
     in `docs/security/key-management.md`, and step 11 links it from
     `operations.md` and `security.md`.
   - 12.3.4: it names 0007 only, but the database connection of 0017 also
     trusts a self-generated CA through `DATABASE_CA_CERT_FILE`; add 0017.
5. Assign the gaps that no spec covers yet, each as a step of the named task
   (or another task the maintainer chooses) with its matrix row:
   - 12.3.3: apply decision 5 in 0017.
   - 1.3.6: webhook URLs have no host or port allowlist (0013).
   - 13.1.1: the connection list of `security.md` (0017) does not include the
     webhook receivers of 0013 (admin-entered `https` URLs) or the Pwned
     Passwords range API of 0004 (0017, with input from 0013 and 0004).
   - 2.4.1: the learner write routes have no rate limits (0009, 0014).
   - 14.3.2: the registrar list, the facilitator lookup and the integration
     API of 0013 set no `cache-control: no-store`, and they return personal
     data outside `/api/session`, `/api/auth/*`, `/api/me/*` and `/api/admin`
     (0013).
   - 14.2.1: the facilitator lookup and the integration API take an e-mail
     address in the query string (0013).
   - 12.1.2, 12.2.2 and 4.2.1: the TLS cipher suites, publicly trusted
     certificates and the protection against request smuggling at the reverse
     proxy are not specified (0017).
   - The browser check of 0004 (Notes and Addendum): whether the browsers used
     for development store the `__Host-espalier` cookie over
     `http://localhost`. It needs the Vite proxy and a browser, so it fits the
     Playwright setup of 0010.
6. Add `test/docs/asvs_matrix_test.exs`, which parses the `Task` column of
   `docs/security/asvs-l2.md` and the "Security requirements" sections of
   `docs/plan/tasks/*.md` (row lists such as "3.3.1 to 3.3.4" expanded) and
   asserts the rule of decision 4. It runs in `make check`.

### Plan and tracking

7. Add 0004a to README section 14 (`docs/plan/tasks/EPIC.md` lists it since
   0004). Set `Depends on` of 0005 to `0004, 0004a` in README section 14, in
   `EPIC.md` and in the header of the 0005 spec. The specs of 0008, 0009 and
   0010 change in this task as well (step 3), so set `Depends on` of these
   tasks to include 0004a in the same places, and change the sentence of
   README section 14 on when 0008 and 0010 can start, unless the maintainer
   lets them start earlier.
8. Update the GitHub issue of every changed spec so that it mirrors the spec
   (EPIC.md, "Keeping the issues in sync"), and record the new dependencies
   on 0004a as GitHub "blocked by" relations. The issue of 0004a carries the
   label `task` and the milestone `M1 Accounts`, and `EPIC.md` links it.

## Deliverables
- README section 15 holds the decisions of this task, and README sections 6.6, 6.7 and 14 reflect them.
- The specs 0003 and 0005 to 0017 cite the interfaces of 0004 as the addendum of 0004 describes them and carry the steps of step 5.
- The specs 0003 to 0017 list their matrix rows under decision 4, and 0004 step 42 holds the ownership table and the rule of decision 4.
- `docs/security/asvs-l2.md` holds the ownership table under decision 4, the corrected rows of step 4 and the decided deviations.
- `test/docs/asvs_matrix_test.exs` exists, and `make check` runs it.
- README section 14 lists 0004a, and the GitHub issues mirror the changed specs.

## Acceptance
- [ ] README section 15 records the five decisions, and the algorithm lists of README sections 6.6 and 6.7 match them.
- [ ] `nix-shell --run "mix test test/docs/asvs_matrix_test.exs"` passes, and removing one row from a "Security requirements" section makes it fail.
- [ ] `grep -n "reissue_session\|update_user_password\|fetch_pending_second_factor\|log_in_user\|check_account" docs/plan/tasks/00[01][0-9]*.md` shows only citations that match the addendum of 0004.
- [ ] Each gap of step 5 is a step of a spec, and the matrix row names that task.
- [ ] `make check` passes.

## Notes
- The row lists of step 3 come from a comparison of the `Task` column of the matrix with the "Security requirements" sections on 2026-10-08, after 0004. The test of step 6 replaces that one-off comparison.
- 15.3.2 (outgoing calls follow no redirects) is owned by 0013 and extended by 0004 and 0006. 0004 already sends the Pwned Passwords range request with `redirect: false`, without a test of its own.
- The interface items of step 2 come from a check of the later specs against the implementation of 0004 on 2026-10-08.
