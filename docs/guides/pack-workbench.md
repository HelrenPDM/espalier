# Pack workbench

The pack workbench lets authors edit the YAML and Markdown files of a content
pack in the admin area. A draft holds the files of one pack. The draft page
shows them in a file tree and one file in an editor, saves a file with
optimistic locking, and checks the draft with the loader and the validator
that `mix espalier.validate` runs. "Create import" turns the draft into an
import, and the pack page takes over with report, alignment, diff, preview
and publish. A draft downloads as a zip archive in the pack layout.

Content packs stay the only import and export format (README section 15,
decision D18). The workbench handles the same files that
`mix espalier.validate` and `mix espalier.import` read, that
`mix espalier.export` writes and that the Git repository of an organization
holds, so a pack can move between the workbench and a repository in both
directions. README section 11 describes the pack
format. The workbench offers no WYSIWYG editing and no form editors for pack
files (README section 1).

## Access

A person with the role `author` reaches the page `/admin/workbench` through
the entry "Workbench" in the author section of the admin navigation, between
"Packs" and "Exports". The routes check the role only, so every author reads
and changes every draft. `created_by_id` records who started a draft and
becomes `null` when that account is deleted.

Every change needs a second factor from the last 10 minutes (README section
6.4): starting a draft, uploading an archive, adding, saving, renaming and
deleting a file, deleting a draft and creating an import. Without one, the
server answers 403 `reauth_required`, the step-up dialog opens, and the page
repeats the request once after a successful step-up. The reads, the download
and the check need no recent second factor, because they change no state.

## Starting a draft

The page `/admin/workbench` lists the drafts with title, pack key, number of
files, size and the time of the last change. Each draft has a link to its
page, a download link and "Delete", which asks for a confirmation and then
deletes the draft with its files; the imports created from it stay. The page
offers four starting points, and each start moves to the page of the new
draft. A start from an archive that left files out first lists the skipped
paths with the link "Open the draft".

| Starting point | Where | Files of the draft |
|---|---|---|
| Empty pack | "Empty pack" with a name field | The skeleton below, with the name as pack title |
| Published program | "Published program" with a choice of the published programs | The files that `mix espalier.export` writes for the program |
| Import | "Edit in the workbench" on the pack page `/admin/packs/:id` of an import with status `validated` or `published` | The files of the payload of the import |
| Zip archive | "Zip archive" with a file input | The files of the pack layout in the archive |

The title of a draft is the `title` of its `pack.yaml`, and its pack key is
the `key` of `pack.yaml`. Without a usable title, a draft from an archive
takes the file name of the archive without `.zip`, and every other draft is
called "Untitled draft". Every change that writes `pack.yaml` updates both:
a missing title keeps the stored title, and a missing key clears the pack
key, as does the deletion of `pack.yaml` or its rename to another path.

### The empty pack

The skeleton holds six files, which pass `mix espalier.validate` and
`mix espalier.alignment` with no error and no warning. Its pack `key` is the
slug of the name, or `new-pack` when the name gives no slug, so the name
"New pack" gives the key `new-pack`.

| File | Content |
|---|---|
| `pack.yaml` | `schema: 1`, the key, the name as title, locale `en`, license `CC0-1.0`, version `"0.1.0"` and `alignment: strict` |
| `stations.yaml` | An overview station and the station of module 1 |
| `modules/01-first-module/module.yaml` | Module 1 with the phase `understand` |
| `modules/01-first-module/objectives.yaml` | Four learning objectives, one per competence area (`subject`, `method`, `self`, `social`), each taught in the first lesson |
| `modules/01-first-module/items.yaml` | One single-choice item on the first lesson that names all four objectives |
| `modules/01-first-module/lessons/01-first-lesson.md` | The first lesson with front matter and one `text` block |

The single item provides evidence for all four objectives, so the skeleton
passes the strict alignment checks with one module. It is a placeholder.
Replace it with evidence that fits each objective: items, exams or companion
formats that ask for exactly what each objective states, at its depth and in
its phase.

### A published program

The draft holds the files that `Espalier.Interop.PackWriter.render_program/1`
writes, the same files as `mix espalier.export` for that program. A module
directory is `modules/<number>-<slug of the module title>/`, for example
`modules/01-how-language-models-work/` for module 1 of the demo pack. The
read takes the shared lock of the export, so the draft holds one published
version even while a publish of the same pack runs. A program that is unknown
or not published answers 404.

### An import

A `validated` or `published` import gives the files of the pack writer for
its payload. A `failed` import holds no payload and answers 409
`no_payload`; the author of a failed upload starts a draft from the same
archive instead.

### A zip archive

The upload runs the checks of the pack upload `POST /api/admin/packs`: at
most `PACK_UPLOAD_MAX_MB` (default 20), at most 2,000 entries, declared
uncompressed sizes of at most five times the upload limit, stored or deflated
entries only, and no ZIP64, multi-disk or encrypted archive. An entry with an
absolute name, a backslash, a `..` component, a NUL character or a name that
is no UTF-8, a duplicate name and a symbolic link reject the archive. The
pack sits at the root of the archive, or in its one top-level directory when
that directory holds `pack.yaml`.

The draft keeps every regular file whose path passes the path rules below and
lists every other file as skipped. The page shows the skipped paths, sorted,
at most 100 and then the number of the others. The server rejects the
archive with 422 `archive_rejected` and one report entry per file for a kept
file above 1,048,576 bytes, a kept file that is no valid UTF-8 and a kept
file with the character U+0000, and with one entry at `.` when no file
passes the path rules. The page shows the entries of a rejected archive as
the pack page shows the archive report.

## Files and layout

A path names one file of the pack layout. The path rules first check that a
path is valid UTF-8 of 1 to 527 bytes, holds no U+0000 and no backslash, does
not start with `/` or a drive letter such as `C:`, and holds no empty, `.` or
`..` component and no component of more than 255 bytes between its `/`
separators. 255 bytes is the longest file or directory name that common file
systems hold, so a pack directory holds no longer name either. The path then has exactly one of
three forms:

| Form | Names |
|---|---|
| A file at the root | `pack.yaml`, `sources.yaml`, `glossary.yaml`, `segments.yaml`, `stations.yaml`, `feedback.yaml`, `qualifications.yaml`, `formats.yaml` |
| A file of a module directory, `modules/<dir>/<name>` | `module.yaml`, `objectives.yaml`, `rules.yaml`, `items.yaml`, `assessment.yaml` |
| A lesson, `modules/<dir>/lessons/<key>.md` | any `<key>` |

`<dir>` and `<key>` follow the key format of the loader: a lowercase letter
or a digit first, then lowercase letters, digits and hyphens. The loader
reads exactly these files, so the rules admit no `README.md`, no
`modules/a/notes.yaml`, no `modules/A/module.yaml`, no
`modules/a/lessons/x.txt` and no `modules/a/lessons/x/y.md`. A path outside
the rules answers 422 `validation_failed` with `fields.path`
`["invalid_path"]`, or `["max_length"]` from the request schema for a path
of more than 527 characters, and a path that the draft holds already answers
409 `path_taken`. A file that ends in `.yaml` opens as YAML and a file that
ends in `.md` as Markdown.

### The file tree

The file tree, a navigation region named "Files of the draft", groups the
files by directory, sorted by path. Each file is a button that opens it in
the editor. The open file is marked as current, and a file with unsaved
changes carries the unsaved marker.

"Add file" opens a dialog that builds the path from a choice: a file at the
root, a file of a module directory, or a lesson with its key. The dialog
shows `invalid_path` and `path_taken` at the path field. A new lesson starts
with front matter (`title`, `position`) and one `text` block, and a new YAML
file starts empty. Each file has "Rename" and "Delete" in its menu, each with
a dialog. A directory exists through its files, so the tree shows a module
directory as long as it holds a file. The workbench renames one file at a
time: to rename a module directory, rename each of its files.

## Editing and saving

The editor carries the accessible name "Content of <path>", highlights the
syntax of the file, and has a status line "Line <n>, column <m>" beside it.
The editor shows the text of the file and runs no code from it. A lesson is
rendered only in the preview of the pack page after an import, through the
renderer of the player.

A change sets the unsaved marker on the file in the tree and the words
"Unsaved changes" in the heading of the editor. "Save", Ctrl+S and Cmd+S
send the content with the `lock_version` of the draft as the page last read
it. The button is disabled while a save runs. After a save, the marker goes,
and the page announces "Saved <path>" to screen readers. Opening another file
or leaving the page while the open file has unsaved changes asks first, with
"Save", "Discard" and "Cancel". The browser asks before it reloads the page
or closes the tab with unsaved changes.

A content is valid UTF-8 text of at most 1,048,576 bytes without the
character U+0000, which a PostgreSQL `text` column cannot store. A larger
content answers 422 `validation_failed` with `fields.content` `["too_large"]`,
or `["max_length"]` from the request schema when it holds more than 1,048,576
characters, and a content with U+0000 answers with `["nul_character"]`.
Other control characters are stored, and the check reports them with line
and column, as the loader does. The editor keeps the line endings of a file:
in a file with CRLF line endings, new and pasted lines end in CRLF as well.

### Keyboard operation of the editor

Tab and Shift+Tab move the focus out of the editor to the next or previous
control, so the editor never traps the keyboard focus. The editor is
CodeMirror 6, in which `Mod-]` and `Mod-[` indent and dedent the selected
lines, where `Mod` is Ctrl on Windows and Linux and Cmd on macOS. YAML
allows only spaces for indentation. Ctrl+S and Cmd+S save the file.

### Conflicts

Each draft has a `lock_version`, which every change of one of its files
increments. Every change sends the `lock_version` that it starts from. The
server locks the row of the draft, compares the version, writes the change
and increments the version in one transaction, so of two changes that start
from the same version, one succeeds and the other answers 409 `stale_draft`
with the stored `lock_version`. The workbench offers no real-time editing by
several authors: two authors who change one draft receive `stale_draft`, as
does one author in two browser tabs. The version belongs to the draft, so a
change of any file of the draft, a rename and a deletion included, ends in
the conflict for every other open page of that draft.

On a 409 `stale_draft`, the page opens a dialog that states that the draft
changed since it was opened. It offers two choices:

| Choice | Effect |
|---|---|
| "Load the stored version" | Reads the file and the draft again and replaces the text in the editor with the stored content. The text of the editor is lost. |
| "Keep my version" | Takes the stored `lock_version` and keeps the text in the editor, unsaved. The next save replaces the stored content of the file, also a change that another author saved in between. |

While "Load the stored version" reads the draft and the file, the editor
takes no input, and "Save", Ctrl+S and "Create import" do nothing. When the
file cannot be read, the editor keeps its text, and the next save or import
meets the conflict again.

A save of a file that another session has deleted answers 404, and the page
reads the draft again and states that the file is gone. When the draft
itself is gone, the page states that instead. In both cases the text stays
in the editor, so that it can be copied.

## Checking a draft

"Check" runs the loader and the validator of the pack format on the files of
the draft and stores nothing. When the open file has unsaved changes, the
check uses its text from the editor in place of the stored content, for this
check only. The server writes the files into a new temporary directory,
checks them and removes the directory, also after an error. The check
changes no row, so it runs without a recent second factor.

The section "Check report" lists every line that `mix espalier.validate`
prints, the findings of the alignment checks included: the errors and then
the warnings with file, line and message. Its headings carry the counts that
the page announces. An entry whose file names a file of the draft is a
button that opens the file with the cursor at that line. An entry on `.` or on a directory shows its path as text. The page
announces "Check finished: <n> errors, <m> warnings". When the draft changed
after the check, through a save or through an edit of the open file, the
section states that the report belongs to an earlier state.

### Sameness with `mix espalier.validate`

The check runs `Loader.load/1` and, when the pack loads, `Validator.run/1`,
the loader and the validator that `mix espalier.validate` and the importer
run. For the same files, the report lists the entries that
`mix espalier.validate` prints, one line per entry, in the same order:

```text
modules/01-first-module/items.yaml:12: message
modules/01-first-module/items.yaml:12: warning: message
```

The stored report keeps at most 1,000 errors and 1,000 warnings and replaces
the rest of a longer list with one closing entry such as "and 12 further
errors", which the page shows as its message alone. As long as neither list
reaches 1,000 entries, the lines are equal. To compare, download the draft,
unzip it and run the tasks in a checkout of Espalier:

```sh
unzip -q ~/Downloads/my-pack-draft.zip -d tmp/my-pack
nix-shell --run "mix espalier.validate tmp/my-pack"
nix-shell --run "mix espalier.alignment tmp/my-pack"
```

### The alignment matrix

Below the report, the page shows the alignment section of the pack page: the
alignment mode of `pack.yaml`, the matrix with one row per module,
competence area and depth, and the findings of the alignment checks again,
which the report lists among its lines. The
check returns the matrix whenever the checks before the alignment checks
report no error. The matrix therefore also appears while an alignment check
reports an error in `strict` mode, which helps to find the missing evidence.
The pack page shows no matrix for such an import, because a `failed` import
stores no payload.

### Time, memory and parallel checks

The check runs the loader with its budget of the pack format: 60 seconds per
pack, and 10 seconds and 256 MiB per YAML text by default. At most two checks
and imports from drafts run at once on a node. Another one answers 429
`checks_busy` with `retry-after: 5` at once, without a queue; the author
repeats the check after a few seconds.

## Import and the pack page

"Create import" turns the saved draft into an import. The button is disabled
while the open file has unsaved changes, so the import holds what the
author sees. It sends the `lock_version` of the draft as the page last read
it, and a draft that changed since then answers 409 `stale_draft` and opens
the conflict dialog. The server writes the files into a temporary directory
and runs the importer of the pack format on them, as an upload of a zip
archive with the same files would. The import has the status `validated` or
`failed` with the same report and payload as that upload, and its audit
event `pack.imported` names the draft in `pack_draft_id`.

The page then moves to `/admin/packs/:id`, the pack page of the import, which
shows the report, the alignment, the diff against the published program, the
preview and the publish dialog. The draft stays after the import: the author
can change it and import it again, and deletes it when the work is done.

A draft whose `pack.yaml` names the key of a published program updates that
program at its publish. The diff of the pack page lists every added, changed
and archived key before the publish. A key that no program carries yet
creates a new program at the publish.

## Download and the way back into Git

The download link of a draft returns a zip archive with the files of the
draft in path order and the pack at the root of the archive. Its file name
is `<pack key>-draft.zip`, for example `new-pack-draft.zip`, and
`pack-draft.zip` when the pack key is missing, longer than 200 characters or
outside the key format. The archive passes `POST /api/admin/packs`, and after
extraction `mix espalier.validate` and `mix espalier.import`. The server
builds the archive in memory, so a download takes one of the slots of the
checks and imports and answers 429 `checks_busy` while every slot is taken.

A draft keeps no history. The repository of the organization keeps it. To
take a draft back into a Git repository, replace the pack directory with the
content of the archive, review the changes and commit:

```sh
cd path/to/pack-repository
rm -r packs/my-pack
unzip -q ~/Downloads/my-pack-draft.zip -d packs/my-pack
git status
git add -A packs/my-pack
git commit -m "Update my-pack from the pack workbench"
```

Replacing the directory, in place of unzipping over it, removes the files
that the draft deleted or renamed. The archive holds only the files of the
pack layout, so a file of another kind in the pack directory, such as a
`README.md`, shows as deleted in `git status` and has to be restored before
`git add`, for example with `git restore packs/my-pack/README.md`.

The way into the workbench runs in the other direction: zip the pack
directory, for example with `(cd packs && zip -qr ../my-pack.zip my-pack)`,
and start a draft from the zip archive, or open the pack page of an import
and choose "Edit in the workbench".

## Limits

`Espalier.Workbench` holds the limits of a draft. The OpenAPI operations of
the upload and of the file routes name them.

| Limit | Value | Setting | Answer beyond it |
|---|---|---|---|
| Files per draft | 2,000, the entries of an archive (`max_files/0`) | none | 409 `too_many_files` |
| Bytes per file | 1,048,576, the file limit of the loader (`max_file_bytes/0`) | none | 422 `validation_failed` at `fields.content` |
| Bytes per draft, the sum of the bytes of its files | five times `PACK_UPLOAD_MAX_MB`, 104,857,600 bytes with the default of 20 (`max_draft_bytes/0`) | `PACK_UPLOAD_MAX_MB` | 409 `draft_too_large` |
| Drafts | 50 (`max_drafts/0`) | `config :espalier, :pack_drafts, max_drafts:` in `config/config.exs` | 409 `draft_limit` |
| Checks, imports and downloads of drafts at once per node | 2 (`max_parallel_checks/0`) | `config :espalier, :pack_drafts, max_parallel_checks:` in `config/config.exs` | 429 `checks_busy` with `retry-after: 5` |
| Bytes per path | 527, and 255 per component | none | 422 `validation_failed` at `fields.path` |
| Upload of an archive | `PACK_UPLOAD_MAX_MB` (default 20) | `PACK_UPLOAD_MAX_MB` | 413 `request_too_large` |

The two settings of `:pack_drafts` take positive integers; any other value
raises `ArgumentError` at the request that reads it. The limits apply to the
draft after a change. A change that adds no file and no byte passes, so a
draft above a lowered limit can still shrink. On a 409 `draft_limit`, the
workbench page states the limit and advises to delete a draft.

## Routes

The routes belong to the row "Pack workbench" of README section 8. The
OpenAPI document at `GET /api/openapi` holds the request and response schemas
of every route. Every answer under `/api/admin` carries
`cache-control: no-store`. A request without a session answers 401
`unauthenticated`, and a person without the role `author` gets 403
`forbidden`.

| Route | Pipelines | Answer |
|---|---|---|
| `GET /api/admin/pack-drafts` | `[:api, :author]` | 200 `{data: [draft]}`, newest change first |
| `GET /api/admin/pack-drafts/:id` | `[:api, :author]` | 200 the draft with its files, without content |
| `GET /api/admin/pack-drafts/:id/files/:file_id` | `[:api, :author]` | 200 the file with `content` and the `lock_version` of the draft |
| `GET /api/admin/pack-drafts/:id/download` | `[:api, :author]` | 200 `application/zip` |
| `POST /api/admin/pack-drafts/:id/check` with `{file_id?, content?}` (both or neither) | `[:api, :author]` | 200 `lock_version`, `report` and `alignment` |
| `POST /api/admin/pack-drafts` with `{source, name?, program_slug?, pack_import_id?}` | `[:api, :author_write]` | 201 the draft |
| `POST /api/admin/pack-draft-uploads` with the `multipart/form-data` field `file` | `[:api, :author_write, :pack_upload]` | 201 the draft with `skipped` (`paths`, `omitted`) |
| `DELETE /api/admin/pack-drafts/:id` | `[:api, :author_write]` | 204 |
| `POST /api/admin/pack-drafts/:id/files` with `{path, content, lock_version}` | `[:api, :author_write]` | 201 the draft |
| `PUT /api/admin/pack-drafts/:id/files/:file_id` with `{content, lock_version}` | `[:api, :author_write]` | 200 the draft |
| `PATCH /api/admin/pack-drafts/:id/files/:file_id` with `{path, lock_version}` | `[:api, :author_write]` | 200 the draft |
| `DELETE /api/admin/pack-drafts/:id/files/:file_id?lock_version=<n>` | `[:api, :author_write]` | 200 the draft |
| `POST /api/admin/pack-drafts/:id/imports` with `{lock_version}` | `[:api, :author_write]` | 201 the import, with `location` `/api/admin/packs/:id` |

`source` is `empty` with `name` (1 to 255 characters), `program` with
`program_slug`, or `import` with `pack_import_id`. A missing member of the
source answers 422 `validation_failed` with `["required"]`, and a member of
another source with `["not_allowed"]`. Every request schema rejects an extra
member with 422 `validation_failed`, and an id that is no UUID answers 422 as
well. A draft carries its `usage` (`files`, `bytes`) and the `limits`
(`files`, `file_bytes`, `draft_bytes`). Beyond the answers above, the routes
answer 404 for an unknown draft, file, program or import, 409 `stale_draft`
with `lock_version`, `path_taken`, `too_many_files`, `draft_too_large`,
`draft_limit` and `no_payload`, 422 `archive_rejected` for a rejected
archive, 413 `request_too_large` and 415 `unsupported_media_type` on the
upload, and 429 `checks_busy` on the check and the import.

## Data and records

A draft holds course content in the database, in the tables `pack_drafts`
and `pack_draft_files`, as plain text, as the catalog tables and the payloads
of imports do. A pack, like the pack repository of an organization, is
therefore no place for personal data of learners or staff.

The workbench writes two audit events, each in the transaction of its
change, with the acting author as actor and the draft as subject:

| Action | Details |
|---|---|
| `pack_draft.created` | `source` (`empty`, `program`, `import` or `upload`), `pack_key`, `file_count`, and `program_slug` or `pack_import_id` for a start from a program or an import |
| `pack_draft.deleted` | `pack_key`, `file_count` |

An import from a draft writes `pack.imported` with `pack_draft_id`. A save,
a new file, a rename and the deletion of a file write no audit event: a
draft changes no catalog row, no learner record and no account, every
content that reaches learners passes `pack.imported` and `pack.published`
with their actors, and an event per save would record the working rhythm of
an author (README section 2, data minimization). `updated_at` and
`lock_version` of the draft show that it changed.
[`../security/logging.md`](../security/logging.md) lists every audit action.
