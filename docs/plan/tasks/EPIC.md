# Epic: Espalier implementation plan

> Tracker: **GitHub** [`HelrenPDM/espalier`](https://github.com/HelrenPDM/espalier/issues?q=label%3Atask),
> one issue per task spec, label `task`, grouped by the
> [milestones](https://github.com/HelrenPDM/espalier/milestones) M0 to M6.

## What this epic delivers
The platform described in [`../README.md`](../README.md): a Phoenix JSON API
and a Vite/React single-page application with local and federated accounts,
topics built on constructive alignment, credentials, anonymous insights, an
admin area and SCORM export. Section 14 of the plan lists the milestones and
the order of the tasks.

## Tasks (milestone = GitHub milestone, task = issue)

| # | Task | Milestone | Depends on | Issue | Status |
|---|---|---|---|---|---|
| 0001 | [Bootstrap the repository with the standard generators](0001-bootstrap.md) | M0 Foundation | none | [#1](https://github.com/HelrenPDM/espalier/issues/1) (closed) | Done |
| 0002 | [Quality gates, CI and open-source files](0002-quality-ci-oss.md) | M0 Foundation | 0001 | [#2](https://github.com/HelrenPDM/espalier/issues/2) (closed) | Done |
| 0003 | [Encryption at rest with Cloak](0003-encryption-at-rest.md) | M1 Accounts | 0001 | [#3](https://github.com/HelrenPDM/espalier/issues/3) (closed) | Done |
| 0004 | [Accounts and sessions from phx.gen.auth](0004-accounts-sessions.md) | M1 Accounts | 0002, 0003 | [#4](https://github.com/HelrenPDM/espalier/issues/4) (closed) | Done |
| 0004a | [Sync the task specs with task 0004](0004a-spec-sync.md) | M1 Accounts | 0004 | [#18](https://github.com/HelrenPDM/espalier/issues/18) | To do |
| 0005 | [Second factors: passkeys, TOTP and recovery codes](0005-second-factors.md) | M1 Accounts | 0004 | [#5](https://github.com/HelrenPDM/espalier/issues/5) | To do |
| 0006 | [OIDC sign-in with oidcc and the mock provider](0006-oidc.md) | M1 Accounts | 0005 | [#6](https://github.com/HelrenPDM/espalier/issues/6) | To do |
| 0007 | [LDAP and Active Directory sign-in](0007-ldap.md) | M1 Accounts | 0006 | [#7](https://github.com/HelrenPDM/espalier/issues/7) | To do |
| 0008 | [Catalog schemas, content pack importer and demo pack](0008-catalog-content-packs.md) | M2 Content | 0001 | [#8](https://github.com/HelrenPDM/espalier/issues/8) | To do |
| 0009 | [Learner API with OpenAPI](0009-learner-api.md) | M3 Learning | 0004, 0008 | [#9](https://github.com/HelrenPDM/espalier/issues/9) | To do |
| 0010 | [Frontend shell: Tailwind, routing, i18n, API client](0010-frontend-shell.md) | M3 Learning | 0004 | [#10](https://github.com/HelrenPDM/espalier/issues/10) | To do |
| 0011 | [Account UI: sign-in, enrollment, recovery and security settings](0011-account-ui.md) | M3 Learning | 0007, 0009, 0010 | [#11](https://github.com/HelrenPDM/espalier/issues/11) | To do |
| 0012 | [Player and learner UI](0012-player-learner-ui.md) | M3 Learning | 0009, 0010 | [#12](https://github.com/HelrenPDM/espalier/issues/12) | To do |
| 0013 | [Policies, credentials, attendance, refresher and integration API](0013-policies-credentials.md) | M4 Records | 0009, 0010, 0012 | [#13](https://github.com/HelrenPDM/espalier/issues/13) | To do |
| 0014 | [Anonymous insights, reports and retention](0014-insights.md) | M4 Records | 0012, 0013 | [#14](https://github.com/HelrenPDM/espalier/issues/14) | To do |
| 0015 | [Admin area](0015-admin-area.md) | M5 Administration | 0011, 0012, 0013, 0014 | [#15](https://github.com/HelrenPDM/espalier/issues/15) | To do |
| 0016 | [SCORM 1.2 and 2004 export, and pack export](0016-scorm-export.md) | M6 Interop and operations | 0012, 0015 | [#16](https://github.com/HelrenPDM/espalier/issues/16) | To do |
| 0017 | [Production image, guides and hardening](0017-production-hardening.md) | M6 Interop and operations | 0002, 0015, 0016 | [#17](https://github.com/HelrenPDM/espalier/issues/17) | To do |

Status values: `To do`, `In progress`, `Done`. A task is done when it meets
section 13 of the plan (quality gates).

## Keeping the issues in sync
- The spec in this folder is the source of truth, and its issue mirrors it.
  An issue holds the full spec; a spec longer than the GitHub limit of
  65,536 characters continues in comments on its issue.
- Dependencies are recorded on each issue as GitHub "blocked by" relations.
- When a task moves, update its Status here and its issue in the same step:
  close the issue as completed with the commits that deliver it.
- When a spec changes, edit the issue body or its comments to match.
