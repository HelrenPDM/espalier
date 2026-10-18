# What Espalier is for

This chapter orients a reader who meets Espalier for the first time: the
purpose of the platform, the people who use it, its capabilities, what it
leaves to other systems, and how it is built. It names the terms that every
other guide uses and links to the guide that holds the detail of each
capability. The next chapter is [`setup.md`](setup.md), which starts an
instance and shows the first sign-in.

## Purpose

Espalier is an open-source learning platform (Apache-2.0, see
[`LICENSE`](https://github.com/HelrenPDM/espalier/blob/main/LICENSE)) for competence programs that end in a credential.
A credential names the tasks it unlocks and holds no score or rank of the
person (plan section 2, principle 2,
[`../plan/README.md`](../plan/README.md)). The tasks come from the field
`unlocks` of a qualification, and the credential copies that list at issue
time. The credential row holds a status, the issue date, a validity date and
the copied list, and no field for a score or a rank
(`Espalier.Credentials.Credential`). The platform stores per exam attempt its
outcome (`passed`, `failed_core` or `failed_errors`), the number of wrong
answers and the submission time, and no score. With `TRACKING_DETAIL=standard`
it also stores the correctness of each practice answer (section
"Record separation and the data protection settings").

An organization uses the platform for a program in which every learner works
through the same mandatory content and ends with a credential that other
people and systems can rely on, for example a program that qualifies staff to
use a tool or a method. The demo pack in [`content/demo/`](https://github.com/HelrenPDM/espalier/tree/main/content/demo)
is such a program: two modules on working with an AI assistant, an exam in
module 1, a usage policy to acknowledge, the qualification `basics` with a
credential that unlocks two tasks, and the add-on qualification `workshop`,
which needs the credential `basics` and the attendance at a workshop outside
the platform.

The terms below are the ones of the code and of the pack format
([`content-packs.md`](content-packs.md)).

| Term | Meaning |
|---|---|
| Program | The published content of one content pack. Its `slug` is the `key` of `pack.yaml`. |
| Station | One step of the learner journey through a program: `self_assessment`, `overview`, `module`, `credential`, `companion_formats` or `feedback`. |
| Module | A topic of a program, with a number. It holds lessons, learning objectives, rules, items and optionally an exam. |
| Lesson | One Markdown file of a module, made of blocks (`text`, `explanation`, `example`, `case_comparison`, `quote`, `callout`, `placeholder`). |
| Item | A question or task with server-side evaluation: `single_choice`, `multiple_choice`, `slot_builder`, `classification`, `checklist_drill` or `poll`. |
| Assessment | A set of items of one module, of kind `practice` or `exam`. An exam applies a pass rule. |
| Qualification | What a credential is issued for: a code, the unlocked tasks, a validity and the requirements to meet. |
| Format | A companion format: a session that takes place outside the platform, for example a workshop. A facilitator issues attendance certificates for it. |
| Segment and path | The self-assessment station offers segments. A segment preselects the `short` or the `full` path, and the learner can switch. |

## Who uses it

The operating organization installs and configures an instance, chooses the
sign-in pathways, imports content packs and grants roles. One organization
runs one instance. Every signed-in person holds the role `learner`, and the
roles below are added by grants from an administrator or from the claims or
groups of an identity provider (plan section 6.11).

| Role | What the role can do | Where |
|---|---|---|
| `learner` | Works through the stations of a program, answers items, takes exams, acknowledges policy versions, reads the policies and the handbook, holds credentials, and gives anonymous answers (self-assessment, interest in a format, feedback). | The program pages and `/me/credentials` |
| `facilitator` | Looks up persons by e-mail address and issues attendance certificates for a companion format held outside the platform. The answer holds one result per person, and no route lists the certificates a facilitator has issued. | `/admin/attendance` |
| `author` | Uploads content packs, checks them, previews, compares and publishes them, edits packs in the pack workbench, and requests SCORM exports. | `/admin/packs`, `/admin/workbench`, `/admin/exports` |
| `registrar` | Reads the credential list of one qualification, per person. The list is off while `REGISTRAR_ENABLED=false`, and the route then answers 404. | `/admin/registrar` |
| `analyst` | Reads six aggregated reports on the anonymous answers and on the credentials per qualification and status. | `/admin/insights` |
| `admin` | Manages users (invite, disable, end sessions, reset factors), policies and their versions, the approved tool list, role grants, API clients and webhooks, revokes credentials, and reads the audit log. | `/admin/users`, `/admin/policies`, `/admin/approved-tools`, `/admin/roles`, `/admin/api-clients`, `/admin/webhooks`, `/admin/audit` |

Each route checks exactly one role, so the roles do not include one another:
an `admin` who also publishes packs holds `author` as well. Every change that
an `author` or an `admin` makes needs a second factor from the last 10 minutes,
and an `admin` needs a passkey while `ADMIN_REQUIRE_PASSKEY=true`, the
default. The SPA shows each
section only to its role, and the server checks every role again.
[`../security/authentication.md`](../security/authentication.md) documents the
pathways and the session rules.

## Capabilities

### Mandatory content with a short and a full path

Every learner goes through the same lessons. The path changes how the content
starts, and it skips nothing:

- A block can list the paths on which it starts collapsed (`collapsed_on`).
  A block starts collapsed on the paths its `collapsed_on` lists (typically
  `short` on explanation blocks) and open on every other path.
- A module with `single_path: true` ignores the path.
- An item can name lessons whose explanations expand when the answer is wrong
  on the short path (`reveals`).
- The enrollment stores the path and whether the learner chose it. It never
  stores the segment.

### Content packs in Git

A content pack is a directory of YAML and Markdown files. An organization
keeps its packs in its own repository next to its review process, and the
platform imports them:

| Way in | Command or page |
|---|---|
| Command line | `mix espalier.validate PATH`, `mix espalier.alignment PATH`, `mix espalier.import PATH [--draft]` |
| Production image | `Espalier.Release.import_pack/2` through `bin/espalier eval` ([`operations.md`](operations.md)) |
| Admin area | The zip upload on `/admin/packs`, and the pack workbench |

`mix espalier.export SLUG PATH` writes a published program back to disk. The
admin upload and the workbench validate an import and store it as a draft,
which is previewed on the pack page and published explicitly. The command
`mix espalier.import` and `Espalier.Release.import_pack/2` publish at once
unless `--draft` (`draft: true`) keeps the import as a draft. Publishing upserts rows by stable keys (`module.number`,
`item.key`, `objective.key`, `rule.number`, `source.key`) and archives rows
whose keys are missing from the new version, so existing progress stays
intact. Every block and item shows its provenance (`invented`, `sourced`,
`vendor_statement`, `assumption` or `placeholder`) as a badge. The UI exists in
English and German, and the language of the content comes from `locale` in
`pack.yaml`. [`content-packs.md`](content-packs.md) describes the format, and
[`course-yaml.md`](course-yaml.md) introduces its building blocks.

### Constructive alignment

Every module covers the four competence areas of CORE (constructive oriented
research and education), `subject`, `method`, `self` and `social`, with
learning objectives of its own or through `areas_elsewhere` in `module.yaml`,
which names where else an area is covered. Each objective has a depth (`know`, `apply` or `judge`) and a
phase of the five-phase arc (`orient`, `understand`, `apply`, `anchor`,
`update`). It is aligned with the lessons that teach it and with the items,
exams and companion formats that provide evidence for it. The importer checks
this at every import. With the default `alignment: strict` in `pack.yaml`, an
objective without a teaching lesson or without evidence, an exam item that
counts for a credential without an objective, and a module that leaves one of
the four areas uncovered without `areas_elsewhere`, are errors. With `warn`, the same
findings are warnings. `mix espalier.alignment PATH` and the pack page print
the alignment matrix. Learners see the objectives of a module, grouped by
competence area, and the module station shows which objectives have evidence
([`content-packs.md`](content-packs.md), section "Constructive alignment").

### Mandatory formats, attendance, exams and credentials

A qualification lists requirements of five kinds, and the platform issues the
credential when all are met:

| Requirement | Met when |
|---|---|
| `module_completed` | The learner completed the module. |
| `assessment_passed` | The learner passed the exam. A core item answered wrong fails an attempt with `failed_core`, more than `max_wrong` wrong answers fail it with `failed_errors`, and a new attempt is always possible. |
| `policy_acknowledged` | The learner acknowledged the current version of a policy. |
| `attendance` | A facilitator issued an attendance certificate for a format with `attendance_counts: true`. |
| `qualification_held` | The learner holds another qualification of the program. |

A credential has the status `active`, `refresh_due`, `expired` or `revoked`.
A qualification can limit the validity to a number of months
(`validity_kind: months`) and set a refresher mode (`update_unit`, `full_run`
or `test_only`). A daily job at 03:00 UTC moves credentials that have a
validity date to `refresh_due` and `expired`, with the notice period
`CREDENTIAL_NOTICE_DAYS` and the grace period `CREDENTIAL_GRACE_DAYS` (both 30
by default). A credential of a qualification without a validity in months keeps
the status `active` until a policy version with `requires_refresher` or a
revocation changes it ([`content-packs.md`](content-packs.md) describes
`validity_kind`). Publishing a policy version with `requires_refresher`
moves the credentials that depend on that policy to `refresh_due`. An
administrator can revoke a credential.

### Reports with a minimum group size

Learners give three kinds of answers anonymously: the self-assessment, the
vote for a companion format and the feedback. The stored rows carry a date with
day precision, a random key and no user key. A separate participation marker
records that a person has answered, so that each person counts once. The six
reports of the role `analyst` (self-assessment, items, competence, formats,
feedback and credentials) suppress every cell with fewer responses or people
than `INSIGHTS_MIN_GROUP_SIZE` (default 5). The reports cover no enrollments,
module completions, exam attempts, acknowledgements or attendance certificates
(plan section 10).

### SCORM export

An author exports one published module as a SCORM 1.2 or SCORM 2004 4th edition
package on `/admin/exports`. One module becomes one SCO, and the learning
objectives of the module become `cmi.objectives` entries. The package contains
the answer keys, so exams that count for a credential stay on the platform. The
receiving LMS records the results per person, outside Espalier
([`scorm-export.md`](scorm-export.md)).

### Integration API and webhooks

A machine client with the scope `credentials:read` calls
`POST /api/integration/credential-lookups` with a bearer token and receives the
credentials of a person in force, and signed webhooks report the four
credential events `credential.issued`, `credential.refresh_due`,
`credential.expired` and `credential.revoked`. An administrator creates
clients and webhooks in the admin area. The route, the webhook signature and
the allowed target hosts are described in plan section 11,
[`security.md`](security.md) and [`operations.md`](operations.md). Which permission another system binds to a
credential stays a decision of the operating organization (plan section 11).

### Pack workbench

The pack workbench on `/admin/workbench` lets an author edit the YAML and
Markdown files of a content pack in the browser. A draft starts from an empty
pack, a published program, an import or a zip archive. The check runs the
loader and the validator of `mix espalier.validate` and shows the alignment
matrix. "Create import" hands the draft to the pack page, and a draft downloads
as a zip archive, so a pack can move between the workbench and a Git
repository in both directions ([`pack-workbench.md`](pack-workbench.md)).

### Record separation and the data protection settings

The platform keeps records apart by purpose. The anonymous self-assessment, the
acknowledgement of a policy version, the module completion and exam attempt,
and the attendance certificate each have their own table, their own visibility
and their own retention (plan section 2, principle 1). The operating
organization decides with settings how much is recorded per person:

| Variable | Default | Effect |
|---|---|---|
| `TRACKING_DETAIL` | `minimal` | `minimal` keeps practice answers out of the per-person records and the resume state in the browser. `standard` also stores one row per practice answer (correctness and attempt number). Raw answers are never stored per person. |
| `REGISTRAR_ENABLED` | `false` | Enables the per-person credential list of the role `registrar`. |
| `INSIGHTS_MIN_GROUP_SIZE` | `5` | Smallest number of responses or people that a report cell shows. |
| `INSIGHTS_ORG_UNIT` | `false` | Stores the org unit of a user in the anonymous item statistics and in the anonymous self-assessment responses. |
| `RETENTION_ATTEMPTS_DAYS`, `RETENTION_ITEM_RESPONSES_DAYS`, `RETENTION_ANONYMOUS_DAYS`, `RETENTION_AUDIT_DAYS` | unset | An unset variable deletes nothing. A set variable deletes the rows older than that many days. `RETENTION_ATTEMPTS_DAYS` keeps the newest passed attempt that a credential in force depends on. |

Plan section 10 places the legal assessment under the GDPR, the retention
periods and the data protection documentation in a separate workstream, so
these settings ship with data-sparing defaults and without a retention period.
The retention behavior is described in [`operations.md`](operations.md).

## What Espalier does not do

Plan section 1 lists what the platform leaves out. The list reads as follows:

| Not provided | State |
|---|---|
| WYSIWYG authoring | The workbench edits the text files of a pack. Content packs stay the only import and export format (decision D18). |
| SAML | Sign-in uses OIDC, LDAP or Active Directory, and local accounts. |
| SCIM provisioning | Accounts come from invitations, from the first sign-in through an identity provider or, with `SIGNUP=domain`, from self-service sign-up for listed domains. |
| OIDC back-channel logout | Front-channel logout and RP-initiated logout exist. |
| xAPI and cmi5 | SCORM 1.2 and SCORM 2004 are the export targets. |
| Multi-tenancy | One organization runs one instance. |
| Native mobile apps | The SPA is the only client. |
| Gamification that ranks people | A credential holds no score or rank. |

Three further limits follow from the design. The platform stores nothing about
real work items: evidence of a human review at a single work item belongs to
the system where that work happens, and the item kind `checklist_drill` trains
the review without storing real work items. The platform does not grant
permissions in other systems, because an integration reads credentials and
the other system decides what a credential permits. A SCORM package runs the
player in the LMS of the organization and reports to that LMS only.

## Architecture in brief

| Layer | Choice |
|---|---|
| Backend | Elixir/Phoenix JSON API with Bandit. Routes under `/api` return JSON and are described in the OpenAPI document at `/api/openapi`. The routes under `/auth/oidc` handle the browser redirects of OIDC sign-in. |
| Frontend | A Vite/React single-page application in `frontend/`, styled with Tailwind CSS. In production, Phoenix serves it from `priv/static/spa/`. |
| Database | PostgreSQL. Sensitive columns are encrypted at rest with Cloak (AES-256-GCM). |
| Jobs | Oban, with its jobs in the database. Queues: `default`, `mail`, `webhooks` and `exports`. |
| Accounts | Built inside the Phoenix application from Elixir and Erlang libraries (passkeys, TOTP, Argon2id, OIDC client, LDAP client). There is no separate identity server. |
| Session | The server holds the session, and the browser holds one cookie with an opaque token. The SPA never sees a provider token. |
| Deployment | A container image and Docker Compose files, with the reverse proxy in front. |

The diagrams are in [`../architecture/README.md`](https://github.com/HelrenPDM/espalier/blob/main/docs/architecture/README.md),
and the implementation plan with the decisions is
[`../plan/README.md`](../plan/README.md).

## Where to go next

| Goal | Read |
|---|---|
| Start an instance and sign in for the first time | [`setup.md`](setup.md) |
| Understand accounts, organizations, roles and sign-in pathways | [`tenant-and-authentication.md`](tenant-and-authentication.md) |
| Write or read the YAML files of a course | [`course-yaml.md`](course-yaml.md) |
| Run a production instance on one host | [`self-hosting.md`](self-hosting.md) |
| Show Espalier with the demo pack | [`demo-instance.md`](demo-instance.md) |
| Connect Entra ID, Google Workspace, another OIDC provider or a directory | [`identity-providers.md`](identity-providers.md) |
| Review the security settings and every outgoing connection | [`security.md`](security.md) |
| Operate a running instance: logs, jobs, release functions | [`operations.md`](operations.md) |
| Look up every field of the pack format | [`content-packs.md`](content-packs.md) |
| Edit packs in the browser | [`pack-workbench.md`](pack-workbench.md) |
| Deliver a module through an LMS | [`scorm-export.md`](scorm-export.md) |
| See every guide | [`README.md`](https://github.com/HelrenPDM/espalier/blob/main/docs/guides/README.md) |
| Read the decisions and the domain rules | [`../plan/README.md`](../plan/README.md) |
