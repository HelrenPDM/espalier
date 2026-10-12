# SCORM export and pack export

Espalier exports one published module as a SCORM package, which runs the
player in any learning management system (LMS) that supports SCORM 1.2 or
SCORM 2004 4th edition. The package reports completion, success, score and the
status of each learning objective of the module to the LMS. A published
program can also be written back to disk as a content pack with
`mix espalier.export`. README section 11 describes both interfaces, and
[`../architecture/scorm-export.puml`](../architecture/scorm-export.puml) shows
the flow of an export.

## Requesting an export

An export takes one module of a published program and one SCORM version. One
module becomes one SCO, and the package holds the content of the module as it
stands when the export runs. A later publish of the pack changes no package
that was already built.

### The admin page

A person with the role `author` reaches the page `/admin/exports` through the
entry "Exports" in the author section of the admin navigation, next to
"Packs". The author chooses a published program, one of its modules and the
version (SCORM 1.2 or SCORM 2004 4th edition) and requests the export. The
request needs a second factor from the last 10 minutes (README section 6.4).
Without one, the server answers 403 `reauth_required`, the step-up dialog
opens, and the page repeats the request once after a successful step-up.

The page lists the exports requested on it, newest first, and asks for their
status every two seconds while an export is `queued` or `running`. It shows the
download link for an export that is `done` and the error text for one that
`failed`. A finished export is read again when the browser window regains
focus. When that read answers 404, because the retention below has deleted the
export, the entry shows the status "No longer available" with a text that the
server keeps exports for a limited time and in a limited number, the download
link disappears, and the page reads the export no more. No route lists
exports, so the page holds this list itself, and a reload of the page starts
with an empty list. A notice on the page states that
the package contains the answer keys and that the receiving LMS records
results per person, including the status of each learning objective.

### Routes

The routes belong to the row "Exports" of README section 8. Every answer under
`/api/admin` carries `cache-control: no-store`. A request without a session
answers 401 `unauthenticated`, and a person without the role `author` gets 403
`forbidden`.

| Route | Pipelines | Answers |
|---|---|---|
| `POST /api/admin/exports` with `{"module_id", "scorm_version"}` | `[:api, :author_write]` | 202 with the export in status `queued` and a `location` header; 403 `reauth_required` without a second factor from the last 10 minutes; 404 `not_found` for a module that is unknown, archived or part of a program that is not published; 422 `validation_failed` for a `scorm_version` other than `scorm12` and `scorm2004`, a `module_id` that is no UUID, a missing member and an extra member |
| `GET /api/admin/exports/:id` | `[:api, :author]` | 200 with `id`, `module` (`id`, `number`, `title` and the `slug` and `title` of its program), `scorm_version`, `status`, `error`, `inserted_at` and `download_path`, which is set while the status is `done`; 404 for an unknown id and for an export that the retention deleted; 422 `validation_failed` for an id that is no UUID |
| `GET /api/admin/exports/:id/download` | `[:api, :author]` | 200 with the zip as `application/zip` and the file name `<program slug>-module-<number>-<scorm_version>.zip`; 409 `export_not_ready` while the status is `queued`, `running` or `failed`; 404 for an unknown id, for an export that the retention deleted and for a `done` export whose zip is gone; 422 for an id that is no UUID |

The routes check the role and do not compare the requesting author: every
author can read and download every export. The export row names the requesting
author in `requested_by_id`, and the request writes the audit event
`export.requested` with the program slug, the module number and the version.
The download builds the file path from `EXPORT_DIR` and the stored file name
`<id>.zip` only, so no request parameter names a file.

### The export job

`Espalier.Interop.request_export/3` writes the export row, its job and the
audit event in one transaction. The job runs in the Oban queue `exports`,
which has one slot, so concurrent requests wait in status `queued` and run one
after the other. The worker sets the status `running` and reads the content in
one transaction: it checks that the program and the module are still
published and builds the content with `Payload.build/1`, `Payload.module/2`
and the current policy versions. The transaction first reads the program slug
and takes `pg_advisory_xact_lock_shared(hashtext(<program slug>))`. The slug
is the pack key, so this lock conflicts with the exclusive lock
`pg_advisory_xact_lock(hashtext(<pack key>))` that the publisher holds during
a publish of the same pack. A publish of the pack that is running ends before
the read, a publish that starts during the read waits for it, and the package
holds the content of one published version. The timeout of the transaction is
`Espalier.Catalog.Pack.Publisher.transaction_timeout/0` (10 minutes by
default) plus one minute, because the lock can wait for a publish.

After the transaction, the worker builds the package in
`<EXPORT_DIR>/<id>.build/`, zips it into `<id>.zip.part`, renames that file to
`<id>.zip` and sets the status `done`. On any error, an error of the status
changes to `running` and `done` included, it sets `failed`, writes a short
text into `error`, logs the cause with `export failed: export <id>` and
removes the build directory and the partial files. When the change to
`failed` fails as well, the worker logs `export status not set to failed:
export <id>` with the cause, and the job still ends with the error. The export
then stays `queued` or `running` until the sweep below ends it.

Every status change of the worker goes through
`Espalier.Interop.transition_export/3`: one `UPDATE exports ... WHERE id = $1
AND status IN (...) RETURNING *`, which changes the row only while it has one
of the statuses that the worker expects and answers `{:error, :stale}`
otherwise. PostgreSQL checks the condition on the current row version, so of
the worker and the sweep below at most one ends an export.

| Change | When the export has another status |
|---|---|
| `queued` to `running` at the start of the job | The job is cancelled and touches no file. |
| `running` to `done` after the rename to `<id>.zip` | The worker removes `<id>.zip`, `<id>.zip.part` and `<id>.build`, logs `export status not set to done: export <id> is no longer running, package removed` and cancels the job; the export keeps its status. |
| `queued` or `running` to `failed` after an error | The worker logs `export status not set to failed: export <id> is no longer queued or running`; the export keeps its status and its error text. |

After the change to `done`, the worker applies the count rule of the
retention below, with the export it has just finished counted as the newest.
A failure of that step leaves the export `done`, logs `export retention not
applied` with the cause, and the sweep applies the rule again.

The job runs at most 30 minutes (`ExportWorker.build_timeout/0`, the
`timeout/1` callback of `Oban.Worker`). Oban 2.24 starts
`:timer.exit_after/2` with an `Oban.TimeoutError` for the job process when the
job starts. When the time runs out, the exit signal ends the process from
outside: no `rescue` or `catch` of the worker runs, an open read transaction
rolls back with the end of the process that holds its connection, and Oban
records the job as failed and, with one attempt, discards it. The export
keeps the status `queued` or `running` and its partial files until the sweep
below sets it to `failed` and removes them.

| Error text | Cause |
|---|---|
| "The SCORM player build lacks ... Run `npm --prefix frontend run build:scorm` and request the export again." | `scorm.html`, `LICENSE` or `NOTICE` is missing in the player directory; the text names every missing file. |
| "The schema files of SCORM 1.2 are missing. Run `mix espalier.scorm_xsd` and request the export again." (or SCORM 2004 4th edition) | The schema directory of the version holds no file. |
| "The module is no longer published." | The program left the status `published`, or the module was archived, between the request and the job. |
| "Two files of the package would share the path ..." | Two files of the player and schema directories, or one of them and `imsmanifest.xml` or `content.json`, map to the same path in the package. |
| "The package could not be built; the server log names the cause." | Any other error. The server log holds the exception with the export id. |
| "The build was interrupted; request the export again." | The sweep of interrupted exports found the export `queued` or `running` longer than its limit, one hour, after its last change. |

#### Interrupted exports

`Espalier.Interop.StaleExportWorker` ends the exports whose build was
interrupted, for example because the node stopped during a build, because Oban
ended the job after its timeout, or because the change to `failed` failed. The
Oban crontab in `config/config.exs` runs it every 15 minutes in the queue
`default`, with one attempt. With one conditional `UPDATE ... RETURNING id`, it
sets every export in status `queued` or `running` whose `updated_at` lies
longer than `StaleExportWorker.interrupted_after/0` back to `failed`, with the
error text above and `updated_at` set to the current time. For each of exactly
these ids, it logs the warning `export interrupted: export <id> set to failed`
and removes `<EXPORT_DIR>/<id>.build`, `<id>.zip.part` and `<id>.zip`.
Afterwards it applies every rule of the retention below.

The limit is twice the job timeout of the worker and at least one hour, so one
hour with the timeout of 30 minutes; one function derives it from the
timeout, and a test checks that it is longer. The worker sets `running` and
thereby `updated_at` when the build starts, and Oban ends the job after the
timeout, so the export of a job that still runs does not meet the limit, and
the sweep removes no file of a running build. Should a build outlast both,
for example after a pause of the node, the conditional changes above apply:
the build that reaches its end finds its export `failed`, removes its own
package and sets no status. An export that waits longer than the limit in the
queue behind other exports counts as interrupted as well, and its job, when
it runs, finds the export `failed` and is cancelled. The sweep changes no job
row. `config/config.exs` configures no `Oban.Plugins.Lifeline`, so the job row
of a build that a node stop interrupted keeps the state `executing` in
`oban_jobs`.

#### Retention

`config :espalier, :export_retention` in `config/config.exs` bounds the
exports and the packages that the server keeps (`Espalier.Interop.retention/0`,
`Espalier.Interop.prune_exports/1`):

| Setting | Default | Rule |
|---|---|---|
| `max_age_days` | 7 | An export with status `done` or `failed` whose `updated_at` lies more days back is deleted with its files. |
| `max_packages` | 100 | Of the exports with status `done`, the newest `max_packages` by `updated_at`, `inserted_at` and id stay; every older one is deleted with its package. |

An export with status `queued` or `running` is never deleted by these rules.
The worker applies the count rule after each export that reaches `done`, so
`EXPORT_DIR` holds at most `max_packages` packages plus the one of the build
that runs. The sweep applies the age rule, the count rule and the orphan
step every 15 minutes. The orphan step removes the direct entries of
`EXPORT_DIR` named `<uuid>.build`, `<uuid>.zip.part` or `<uuid>.zip` whose id
has no export row. It leaves every other name and every deeper entry in
place, and it removes a symbolic link of such a name as a link, without
following it.

Each rule deletes its rows with one `DELETE ... RETURNING id, file_name` and
removes the files of exactly these rows after the statement has committed:
`<id>.build`, `<id>.zip.part`, `<id>.zip` and the stored file name. A failed
removal logs `export file not removed: <name>, <reason>`, and the orphan step
of the next sweep removes the file, because its row is gone. The deletion
logs `export deleted: export <id>, older than <n> days` or `export deleted:
export <id>, beyond the newest <n> packages`, and the orphan step logs
`export file without export removed: <name>`, each at `info`. A deleted
export answers 404 on `GET /api/admin/exports/:id` and on its download, and
the admin page shows it as no longer available. The count rule applies to
the exports of every author, so a new export can delete the oldest package
that another author requested.

### Prerequisites on the server

| Setting | Default | Content |
|---|---|---|
| `EXPORT_DIR` | `tmp/exports` in development, `tmp/test-exports` in tests | The directory of the packages. A production boot stops while it is unset; `.env.example` names `/data/exports` as an example. The sweep of interrupted exports removes the files of the exports that it sets to `failed`, and the retention deletes the packages of `done` exports beyond `max_packages` or older than `max_age_days` and the files without an export row. The platform writes and deletes only entries named `<id>.build`, `<id>.zip.part` and `<id>.zip` there. |
| `config :espalier, :export_retention` | `max_age_days: 7, max_packages: 100` | The retention of exports, set in `config/config.exs` (section "Retention" above). |
| `config :espalier, :scorm_player_dir` | `priv/scorm_player` of the application | The output of `npm --prefix frontend run build:scorm`. |
| `config :espalier, :scorm_xsd_dir` | `priv/scorm/xsd` of the application | The schema files below `12/` and `2004/`, written by `mix espalier.scorm_xsd`. |

The release image holds the player and the schema files: the `frontend` stage
of the Dockerfile builds the player, the builder stage copies it to
`priv/scorm_player` and runs `mix espalier.scorm_xsd`. In a checkout,
`make setup` fetches the schema files, and `make e2e` fetches them and builds
the player. `config/test.exs` points both directories to stand-ins in
`test/fixtures/scorm_player/` and `test/fixtures/scorm_xsd/`.

## Package contents

Every file lies at the path below, relative to the root of the zip.

| Path | Content |
|---|---|
| `imsmanifest.xml` | The manifest of the version with one organization, one item and one SCO resource (see below). |
| `index.html` | `scorm.html` of the player build under the name that the manifest names as `href`. |
| `assets/player.js`, `assets/player.css` | The player in one script and one stylesheet without hashes, loaded with relative URLs. |
| `LICENSE`, `NOTICE` | The license and the attribution notice of Espalier, copied from the repository root by the player build. |
| `content.json` | The content of the module (see below). |
| The schema files of the version | The XML schema files that the manifest names, at the package root (see below). |

### The manifest

`Espalier.Interop.manifest/2` renders `imsmanifest.xml` from the fixed EEx
templates `priv/scorm/imsmanifest_12.xml.eex` and
`priv/scorm/imsmanifest_2004.xml.eex`, and every value enters them through
`Espalier.Interop.xml_escape/1`.

| Element | SCORM 1.2 | SCORM 2004 4th edition |
|---|---|---|
| `<schema>` | `ADL SCORM` | `ADL SCORM` |
| `<schemaversion>` | `1.2` | `2004 4th Edition` |
| SCO marker on the resource | `adlcp:scormtype="sco"` | `adlcp:scormType="sco"` |
| Manifest identifier | `espalier-<program slug>-module-<number>` | the same |
| Organization, item and resource identifiers | the manifest identifier with `-organization`, `-item` and `-sco` | the same |
| Titles of the organization and the item | the module title | the same |

The resource has the type `webcontent` and the `href` `index.html`, and it
holds one `file` element for every file of the package except
`imsmanifest.xml`, sorted by path. The manifest declares no objectives
and no sequencing rules: the SCO creates its `cmi.objectives` entries at run
time, which both versions allow for a package without sequencing rules.

### `content.json`

The worker writes `content.json` with `JSON.encode!/1`. Its top-level keys are:

| Key | Content |
|---|---|
| `schema` | `1` |
| `program` | `slug`, `title` and `locale` of the program |
| `module` | The module in the shape of the normalized pack payload: `number`, `title`, `summary`, `phases`, `domains`, `single_path`, `refresher_unit`, `areas_elsewhere`, the `lessons` with their blocks, the `objectives` with `key`, `statement`, `area`, `depth`, `phase`, `domain` and `taught_in`, the `rules`, the `items` with their options, including `correct` and `feedback`, and the `assessments` |
| `glossary` | The glossary terms that blocks of the module reference with `[[term:...]]` |
| `sources` | The sources that the citations of the blocks, rules and items of the module name |
| `formats` | The companion formats that name an objective of the module, with their `objectives` |
| `policies` | For each `placeholder_key` of a block of the module whose policy has a published version: `key`, `number`, `effective_from` and `body` of the version current at the time of the export |

The player renders a block of kind `placeholder` with the policy text of its
entry in `policies`, as the platform does. A key without a published version
keeps the body of the block with the placeholder badge.

### Schema files

| Version | Files at the package root |
|---|---|
| SCORM 1.2 (4 files) | `adlcp_rootv1p2.xsd`, `imscp_rootv1p1p2.xsd`, `imsmd_rootv1p2p1.xsd`, `ims_xml.xsd` |
| SCORM 2004 4th edition (17 files) | `adlcp_v1p3.xsd`, `adlnav_v1p3.xsd`, `adlseq_v1p3.xsd`, `imscp_v1p1.xsd`, `imsss_v1p0.xsd` and its nine parts `imsss_v1p0auxresource.xsd`, `imsss_v1p0control.xsd`, `imsss_v1p0delivery.xsd`, `imsss_v1p0limit.xsd`, `imsss_v1p0objective.xsd`, `imsss_v1p0random.xsd`, `imsss_v1p0rollup.xsd`, `imsss_v1p0seqrule.xsd`, `imsss_v1p0util.xsd`, and `xml.xsd`, `XMLSchema.dtd`, `datatypes.dtd` |

The repository does not hold these files. The IMS files and
`adlcp_rootv1p2.xsd` carry no license grant that clearly covers
redistribution in an open-source repository, so the organization that runs
Espalier fetches them when it builds the release, and its packages carry them
unmodified. [`priv/scorm/xsd/SOURCE.md`](../../priv/scorm/xsd/SOURCE.md)
names the two archives (the schema definition files that Rustici Software
publishes on scorm.com), the retrieval date and the license terms of each
file.

```sh
nix-shell --run "mix espalier.scorm_xsd"
nix-shell --run "mix espalier.scorm_xsd --dir path/to/xsd"
```

The task fetches each archive over HTTPS, checks it and every file taken from
it against the SHA-256 that `Espalier.Interop.SchemaFiles` pins, and writes the
files to `priv/scorm/xsd/12/` and `priv/scorm/xsd/2004/`, which git ignores. A
version whose files already match is left as it is. A failed download or a
changed file prints the cause and exits with status 1, and nothing reaches a
package. `make scorm-xsd`, `make setup`, `make e2e` and the builder stage of
the Dockerfile run the task. The worker fails every export of a version
without its schema files.

### Licenses in the package

The package carries the compiled player, which is a redistribution of Espalier
in object form. Apache-2.0 section 4 requires a copy of the license and of the
attribution notices with it (task 0002, Notes). `LICENSE` and `NOTICE` at the
package root cover the player: `index.html`, `assets/player.js` and
`assets/player.css`. The player build emits both files next to `scorm.html` and
fails when one of them is missing, and the worker refuses a player directory
without them.

The content in `content.json` stays under the license that `pack.yaml` of the
pack declares as an SPDX identifier; the demo pack declares `CC0-1.0`.
`content.json` does not carry that identifier. The schema files keep the terms
that `priv/scorm/xsd/SOURCE.md` lists.

## Run-time behaviour

### The SCORM entry

`index.html` loads `content.json` relative to the page, switches the user
interface to the language of the pack (the primary subtag of its locale when
the i18n files hold it, otherwise English) and sets the document title to the
module title. `startRuntime` in `frontend/src/scorm/boot.ts` then looks for
the LMS API, creates the runtime of the version that it finds and starts it.
The player shows the module station and the glossary in a memory router, so it
never changes the URL of the LMS window.

The discovery looks for `API_1484_11` first and for `API` only when no window
offers it. Each search starts at the window of the SCO, walks up the chain of
`window.parent` and then continues from `window.opener` up its chain. A walk
takes at most 500 parent steps for `API_1484_11`, the limit of the SCORM 2004
discovery algorithm, and 7 for `API`, the limit of SCORM 1.2, and the opener
chain counts its own steps. An object counts as an API only when it has
`Initialize` (2004) or `LMSInitialize` (1.2). The runtime follows the API that
the LMS offers, so the package runs as SCORM 2004 in an LMS that offers both
APIs, whatever the version of its manifest.

The page shows a notice in place of the player in four cases:

- `content.json` is missing or invalid ("Module not available").
- No API is found ("Learning management system required").
- The start of the runtime fails ("Module not started"). The start fails when
  `Initialize("")` or `LMSInitialize("")` does not answer `"true"` or throws.
  After a refused `Initialize`, the SCORM 2004 runtime calls `GetLastError()`,
  and the error code 103 (already initialized) counts as a started session.
  SCORM 1.2 reports a second initialization with the general error 101 only,
  so every refused `LMSInitialize` fails the start. After a failed start, the
  runtime makes no further LMS call, `Terminate` and `LMSFinish` included.
- The browser restores the page from its back/forward cache after the runtime
  ended the LMS session on `pagehide` ("Session ended", with the text "This
  page can no longer save anything. Please open the module again from the
  learning management system."). After a successful start, the entry
  registers a `pageshow` listener (`onRestoredFromCache` in `boot.ts`), and an
  event with `persisted` set replaces the player with this notice.

### Links that leave the package

A navigation of the SCO document fires `pagehide`, on which the runtime ends
the LMS session. Inside the package, a link that leaves the page therefore
opens in a new tab, with `target="_blank"` and `rel="noopener noreferrer"`.
This applies to the title of a source with an `http` or `https` URL and to a
link in Markdown text, such as a block body or the policy text of a
placeholder block, GFM autolinks included. A Markdown link leaves the page
when its `href` is no fragment (`#...`) and resolves against the base URL of
the document to `http` or `https`, so a relative link such as
`/programs/demo` opens in a new tab as well. Fragment links, `mailto:` links
and the links of the router (the back link, the objective chips and the
glossary terms) keep their behaviour. Markdown rendering empties the target of
a link with a scheme other than `http`, `https`, `mailto`, `irc`, `ircs` and
`xmpp` (ASVS 1.2.2), and an empty `href` would reload the SCO document; inside
the package such a link and a link without a target (`[text]()`) therefore
render without `href`.

The React context `ExternalLinkTargetContext` in
`frontend/src/player/externalLinks.ts` carries the target, and `ScormPlayer`
sets it to `"_blank"`. The platform and the admin preview set no target, so
their links open in the current tab: a source link carries
`rel="noopener noreferrer"` without a target, and a Markdown link carries
neither attribute. An LMS that runs the SCO in a sandboxed iframe without
`allow-popups` blocks these links, so a click does nothing; the LMS session
stays open.

### Data model

`Scorm12Runtime` and `Scorm2004Runtime` share `ScormRuntime` in
`frontend/src/runtimes/scorm.ts` and differ in the elements below. Both
evaluate answers in the browser with the evaluator of the player
(`src/player/evaluate.ts`). Each operation writes only the values that
changed and then commits once.

| Event | SCORM 1.2 (`API`) | SCORM 2004 4th edition (`API_1484_11`) |
|---|---|---|
| Start | `LMSInitialize("")`, whose refusal fails the start; reads `cmi.suspend_data` and `cmi.core.lesson_status`; sets `cmi.core.lesson_status` to `incomplete` when the LMS reports `not attempted`; sets `cmi.core.exit`; writes the objective entries; `LMSCommit("")` | `Initialize("")`, whose refusal fails the start unless `GetLastError()` then answers 103; reads `cmi.suspend_data`, `cmi.completion_status` and `cmi.success_status`; sets `cmi.completion_status` to `incomplete` when the LMS reports `not attempted` or `unknown`; sets `cmi.exit`; writes the objective entries; `Commit("")` |
| Item answer | the objective statuses that changed and `cmi.suspend_data`; `LMSCommit("")` | the same; `Commit("")` |
| Exam attempt | `cmi.core.score.raw` (correct answers of the latest attempt), `cmi.core.score.min` (0) and `cmi.core.score.max` (items of its exam); for an exam of more than 100 items, `raw` is the percentage of correct answers rounded to two decimal places and `max` is 100, because the score elements of SCORM 1.2 hold 0 to 100 (110 correct answers of 120 give `91.67` and `100`); `cmi.core.lesson_status` `passed` or `failed`, `cmi.core.exit`, the objective statuses that changed and `cmi.suspend_data`; `LMSCommit("")` | `cmi.score.raw`, `cmi.score.min` (0), `cmi.score.max`, `cmi.score.scaled` (raw divided by max, at most seven decimal places, left out for an exam without items), `cmi.success_status` `passed` or `failed`, `cmi.exit`, the objective statuses that changed and `cmi.suspend_data`; `Commit("")` |
| Module completion | `cmi.core.lesson_status` `completed` while the exams of the module give no outcome, so a module without exam and a module whose exam has no attempt report `completed`; an exam outcome `passed` or `failed` takes precedence, also for an attempt after the completion, and only the suspend data then records the completion; then `cmi.core.exit` and `cmi.suspend_data`; `LMSCommit("")` | `cmi.completion_status` `completed`, with or without exam; `cmi.exit` `normal`; `cmi.suspend_data`; `Commit("")` |
| Exit value | `suspend` while the status is `incomplete` or `failed`, the empty string once it is `passed` or `completed` | `suspend` until the completion status is `completed`, then `normal` |
| Success without exam | (no separate element) | `cmi.success_status` keeps the value of the LMS, `unknown` for a new attempt |
| `pagehide` | the values not yet stored, `cmi.core.session_time` as `HH:MM:SS.SS`, `LMSCommit("")`, `LMSFinish("")` | the values not yet stored, `cmi.session_time` as an ISO 8601 duration such as `PT1H2M3.5S`, `Commit("")`, `Terminate("")` |

With several exams in one module, the status is `passed` once every exam has a
passed attempt, `failed` while any exam has attempts and none of them passed,
and unchanged otherwise; the score follows the latest attempt of any exam.
These two cases are the exam outcomes that take precedence over `completed`
in SCORM 1.2. Where the status stays unchanged, a completed module reports
`completed` in SCORM 1.2, for example when one exam passed and another exam
with `counts_for_credential: false` has no attempt. An exam keeps
`passed` once an attempt passed, also in an earlier session, and the attempt
numbers continue across sessions. A practice item counts as correct once any
of its answers was correct.

The completion of the module follows the platform rule: while an exam of the
module with `counts_for_credential: true` has no passed attempt, the module
station lists the open exams and the module stays open.

A failing LMS call stops nothing in the player, and the next operation writes
a value again that the LMS did not store. Only the explicit save of the
player state reports a failure, so the player shows that the progress was not
saved. The save resolves without an LMS call before the start. After
`pagehide`, which ends the LMS session every time, and after a failed start,
it rejects without an LMS call, so a page that the browser shows again from
its back/forward cache reports that the progress was not saved. Item
answers, exam attempts and the module completion after `pagehide` resolve,
stay in the memory of the page and make no LMS call.

### Objective states

Each learning objective of the module has one state in the package.
`deriveObjectiveStates` in `frontend/src/runtimes/objectives.ts` derives it
from the evidence items in the package. The evidence items of an objective
follow the evidence rule of the platform, limited to the items of the module:
every item that names the objective and is listed by an assessment, and every
other item that names it and whose kind has a correct answer (every kind
except `poll`). An exam item is an item that an assessment of kind `exam`
lists; every other item is a practice item.

| State | Rule | SCORM 1.2 `cmi.objectives.n.status` | SCORM 2004 `cmi.objectives.n.success_status` | SCORM 2004 `cmi.objectives.n.completion_status` |
|---|---|---|---|---|
| `passed` | An assessment that lists an evidence item of the objective has a passed attempt, or a practice evidence item has a correct answer. A passed attempt also counts for an objective whose item was answered wrongly within `max_wrong`. | `passed` | `passed` | `completed` |
| `failed` | The objective is not `passed`, it has at least one evidence item in the package, and every evidence item has an answer. A practice item has an answer once the learner submitted one, and an exam item once an assessment that lists it has an attempt. | `failed` | `failed` | `completed` |
| `incomplete` | Every other objective, including an objective without an evidence item in the package. | `incomplete` | `unknown` | `incomplete` |

The index `n` of an objective is its position among the objectives of the
module, counted from 0, so that a resumed package writes each key at the index
of the first session. At start, the runtime writes `cmi.objectives.n.id` with
the objective key and then the status of the same index, for every objective
in index order; SCORM 2004 accepts the status of an entry only after its id.
After each item answer and each exam attempt, it writes the status of every
objective whose state changed. An item that names an objective of another
module adds no entry, because `cmi.objectives` holds the objectives of the
exported module only.

Attendance at a companion format counts as evidence on the platform only,
where facilitators record attendance certificates. In the package, an
objective whose only evidence is a companion format stays `incomplete`, as
`m1-self-own-responsibility` and `m1-social-team-transparency` of the demo pack
do with the workshop, while the platform can mark it evidenced. The module
station of the package shows the objectives in the state `passed` as evidenced
and adds the status practised from the answered practice items, as on the
platform.

### Suspend data

`frontend/src/runtimes/suspend.ts` encodes the resume state into
`cmi.suspend_data`. The string holds fields separated by `.`:

1. the version `2`;
2. the layout fingerprint of the module, six characters (see below);
3. the path letter, `f` for `full` and `s` for `short` (the first launch
   starts on `full`, because a package has no self-assessment station);
4. the module-completed flag, `1` or `0`. A SCORM 1.2 module whose exams give
   an outcome reports `passed` or `failed` in `cmi.core.lesson_status`, so its
   completion cannot be read back from the LMS;
5. the bitset of the opened explanations;
6. the bitset of the answered practice items;
7. the bitset of the practice items with a correct answer;
8. from this field on, one field per assessment of the module in payload
   order: `0` before the first attempt, otherwise the number of attempts
   followed by the outcome letter, `p` for `passed` (any attempt passed), `c`
   for `failed_core` and `e` for `failed_errors` (the outcome of the latest
   attempt).

A bitset holds six bits per character in the base64url alphabet, with the
first member in the lowest bit of the first character and without trailing
zero characters. Every character of the string is an unreserved character of
RFC 3986. The runtime restores the state at start and then writes the restored
objective states, so the package reports the objective states of the previous
session. With the short path, the explanation `block-1-intro-2` opened,
`choice-practice` answered correctly, `slots-practice` answered and two
attempts of `exam-1` that ended in `failed_errors`, the test fixture of the
runtimes encodes as `2.AUWWl7.s.0.B.D.B.2e`.

The layout fingerprint binds the string to the lists that its bitsets and
assessment fields refer to. It is the 32-bit FNV-1a hash (offset basis
`0x811c9dc5`, prime `0x01000193`) of the UTF-8 bytes of a layout string. That
string lists the item keys in payload order, the ids of the explanation blocks
in the order of the bitset of the opened explanations (`explanationBlockIds`)
and the assessment keys in payload order; the members of a list are joined by
`,` and the three lists by `;`. The hash is written as six base64url digits,
the most significant first. A block id (`block-<module>-<lesson key>-<n>`)
holds the position of the block in its lesson, counted from 1. A module change that alters one of the three lists changes the
fingerprint, for example an item inserted before an existing item, a renamed
or reordered assessment key, or a block inserted before an explanation. A
change that leaves the three lists as they are, such as a new title or stem or
a block after the last explanation of a lesson, keeps the fingerprint.

A string that does not decode for the module restores nothing: another
version, a fingerprint that differs from that of the module, another number of
assessments or a malformed field. The session then starts without the progress
of earlier sessions. The decoder reads version `2` only, so a learner whose
LMS holds suspend data of version `1` from an earlier package also starts
without that progress after the package is updated. In both cases the LMS
keeps the status of the module (`cmi.core.lesson_status`, or
`cmi.completion_status` and `cmi.success_status`), while the runtime writes
every objective entry at start with the state of the empty progress, so an
objective that the LMS recorded as `passed` falls back to `incomplete` (1.2),
or `unknown` with `incomplete` (2004), until the learner provides its
evidence again.

The limit of `cmi.suspend_data` is 4,096 characters in SCORM 1.2 and 64,000
characters in SCORM 2004 4th edition. The encoder refuses a result above 4,096
characters in both versions. The largest module of the demo pack, with every
explanation opened, every item answered correctly and every exam passed,
encodes in fewer than 1,000 characters. When an encoding exceeds the limit,
the runtime writes no suspend data and the save of the player state fails.

## Answer keys and records in the LMS

The package evaluates answers in the browser and therefore contains the answer
keys: `content.json` holds every option with `correct` and `feedback`. Anyone
who can open the package can read them. Exams that count for a credential stay
on the platform (README section 16).

The package contains no anonymous insights and no person-linked data. The
receiving LMS records the learner id, the status, the score, the time and the
status of each learning objective per person. This report is a property of
SCORM and happens outside the platform (README section 11). The platform
stores no status per objective and person; in a package, the state lives in
`cmi.suspend_data` and `cmi.objectives` of the receiving LMS.

## Pack export

`mix espalier.export` writes a published program back to disk as a content
pack in the format of README section 11:

```sh
nix-shell --run "mix espalier.export ai-assistant-basics-demo tmp/pack-out"
nix-shell --run "mix espalier.validate tmp/pack-out"
nix-shell --run "mix espalier.alignment tmp/pack-out"
```

`SLUG` is the `key` of the program's `pack.yaml`. The target directory must be
empty or missing, and a missing directory is created. The task starts the
application without Oban queues, so it runs next to a running development
server. It exits with status 1 and a message on standard error for invalid
arguments, an unknown slug, a program that is not published, a target that is
no directory or a directory that is not empty, and a file that cannot be
written. For a pack with a draft import only, the task reports an unknown
program, because the publisher creates the program row.

`Espalier.Interop.PackWriter.write/2` reads the program again and builds its
payload from the stored row in one transaction, under the same shared lock
and with the same timeout as the export job (see "The export job"), and it
writes the files after the transaction. A publish of the pack that is running
ends before the read, and a program read before a later publish gives the
version published last. A program whose stored status is no longer
`published` answers `{:error, :not_published}` without touching the target
directory.

The output of the demo pack:

```text
tmp/pack-out/
  pack.yaml
  sources.yaml
  glossary.yaml
  segments.yaml
  stations.yaml
  feedback.yaml
  qualifications.yaml
  formats.yaml
  modules/
    01-how-language-models-work/
      module.yaml
      objectives.yaml
      rules.yaml
      items.yaml
      assessment.yaml
      lessons/<lesson key>.md
    02-checking-the-output/
      module.yaml
      objectives.yaml
      rules.yaml
      items.yaml
      lessons/<lesson key>.md
```

- `pack.yaml` always carries `alignment`, with the default `strict` filled in.
  `schema`, `license` and `alignment` come from the import of the pack that was
  published last.
- A module directory is `modules/<number>-<slug of the module title>/`, with
  the number padded to two digits. A list file (`objectives.yaml`,
  `rules.yaml`, `items.yaml`, `assessment.yaml`, and the program files such as
  `sources.yaml` and `formats.yaml`) is written only when its list is not
  empty, and `feedback.yaml` only for a program with a feedback station.
- `module.yaml` carries `areas_elsewhere` when the module names areas, each
  with `where` and `reason`. `objectives.yaml` holds the objectives in position
  order with `key`, `statement`, `area`, `depth`, `phase`, `domain` when it is
  set, and `taught_in`. Entries of `items.yaml` and `formats.yaml` carry
  `objectives` when the list is not empty, in ascending key order.
- A lesson file holds the front matter with `title` and `position` and one
  container directive per block with the attributes `provenance`,
  `collapsed_on`, `cite` and `key` where the block has them.
- A field without value and an empty optional list are left out, and the
  importer fills in the same value. An import of the output therefore gives the
  payload of the program again, and its publish archives no row.
- A string that a YAML reader could take for another type is double-quoted, so
  it reads back as a string: a number, date or time such as `.5`, `1.0.0`,
  `2026-03-01` or `12:30`, the spellings of NaN and infinity of YAML 1.2
  (`.nan`, `.NaN`, `.NAN`, `.inf`, `.Inf` and `.INF`, each also after `-` or
  `+`), a text with a tab, `=` and `<<`.

## Testing a package

### Automated tests

The ExUnit tests build packages from stand-in player and schema files:
`test/espalier/interop/export_worker_test.exs` checks the zip entries, the
manifest against the entries, the license files, the escaped title and the
keys of `content.json`, and `test/espalier/interop/pack_writer_test.exs`
imports the output of the pack writer again. `Espalier.Interop.PublishLockTest`
in the worker test file holds the lock of a publish on its own connection and
checks that an export and a pack write wait for it and hold the version that
it commits, and `test/espalier/interop/stale_export_worker_test.exs` covers
the sweep of interrupted exports and the relation of its limit to the job
timeout. The worker test also plays the sweep during a build with a database
trigger and checks that the build sets no status and leaves no file.
`test/espalier/interop/retention_test.exs` covers the age rule, the count
rule, the orphan step and the conditional status changes, and
`EspalierWeb.Admin.ExportRetentionControllerTest` checks the 404 of both
routes for a deleted export. The Vitest tests in
`frontend/src/runtimes/` run both runtimes against a fake LMS object that
records every call.

`make e2e` fetches the schema files, builds the player and runs Playwright
against `make run`. The spec `frontend/e2e/scorm/scorm.spec.ts` requests the
exports on the admin page as an author, extracts each zip next to the harness
page `frontend/e2e/scorm/lms.html` and serves the directory over HTTP. The
harness loads the LMS API implementation of the npm package `scorm-again`,
creates `window.API` or `window.API_1484_11` according to a query parameter,
records every value that the package sets and embeds `index.html` in an
iframe. The spec walks through module 1 and module 2 for both versions and
asserts the recorded status, score and objective values, and a second run
preloads the saved data and checks the resume.

### Manual LMS test

The manual test imports the packages into one SCORM-capable LMS:

1. Build the player and fetch the schema files with
   `nix-shell --run "npm --prefix frontend run build:scorm"` and
   `nix-shell --run "mix espalier.scorm_xsd"`, or use the release image, which
   holds both.
2. Sign in as an author with a second factor, open `/admin/exports`, request
   module 1 and module 2 of the demo pack in both versions, and download the
   four zips.
3. Import each zip into the LMS as a SCORM 1.2 or SCORM 2004 package, and
   enroll a test learner.
4. Module 1, first session: open the package as the learner, switch to the
   short path, open an explanation, answer one practice item and close the
   package. The module is not complete, so the package leaves the attempt
   suspended (`cmi.core.exit` or `cmi.exit` `suspend`).
5. Open module 1 again: the path and the opened explanation are restored, and
   the objective entries keep their indices and states.
6. In the same session, pass the exam and complete the module. The LMS
   records `passed` with raw score and max score (1.2), and `completed`,
   `passed` and a scaled score between 0 and 1 (2004). The objectives
   `m1-subject-next-word`, `m1-subject-varying-answers` and
   `m1-method-check-claims` record `passed` (1.2), and `passed` with
   `completed` (2004). `m1-self-own-responsibility` and
   `m1-social-team-transparency` record `incomplete` (1.2), and `unknown` with
   `incomplete` (2004). The package now ends the attempt (`cmi.core.exit` `""`
   or `cmi.exit` `normal`), so the next launch starts a new attempt without
   the suspend data, as the LMS decides for a finished attempt.
7. With a second learner, fail the exam of module 1: the LMS records `failed`
   (1.2), and `failed` in the success status (2004).
8. Module 2: answer its three items correctly and complete the module. The
   LMS records `completed` (1.2), and `completed` with the success status
   `unknown` (2004), and each of the three objectives records `passed` (1.2),
   and `passed` with `completed` (2004).

| LMS | Version | Date | SCORM 1.2 | SCORM 2004 4th edition |
|---|---|---|---|---|
| pending | pending | pending | pending | pending |

The manual test is pending. Its record names the LMS, its version, the date of
the test and the result of steps 4 to 8 for each SCORM version.
