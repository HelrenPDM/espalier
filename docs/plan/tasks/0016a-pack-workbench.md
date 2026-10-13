# 0016a: Pack workbench

> Milestone: M5 Administration, Depends on: 0015, 0016

## Context to read first
- `docs/plan/README.md`: section 1 (WYSIWYG authoring stays out of scope), principles 5 and 10, and sections 5 (contexts and scopes), 6.4 (`require_recent_auth` for every admin change), 6.5 (the CSP with `style-src 'self'` and the Trusted Types header in report-only mode), 6.10 (error codes), 6.12 (OpenAPI operations per task), 8 (rows "Administration", "Pack workbench" and "Exports"), 9 (admin area and UI conventions), 11 (content packs), 13 (quality gates) and 15 (decisions D16 and D18).
- `docs/plan/tasks/0008-catalog-content-packs.md`: the pack format (step 5), the loader with its line index (step 6), the directive splitter (step 7), the validator (step 8), the importer and the normalized map (step 9), `mix espalier.validate` (step 11), `Espalier.Catalog.Alignment` (step 13), and the section "Addendum: implementation": the loader limits (`Loader.max_file_bytes/0`, `max_pack_bytes/0`, `parse_budget/0`), `Loader.pack_meta/1`, `Validator.run/1` with its `payload`, and `Report.stored/2`.
- `docs/plan/tasks/0015-admin-area.md`: the pipelines `:author`, `:author_write` and `:pack_upload` (steps 1 and 7), the admin navigation with the step-up dialog (step 5), the pack upload with `EspalierWeb.PackMultipart` and `Espalier.Catalog.Pack.Archive` and the pack view with `alignment` (step 7), the OpenAPI schemas (step 10), the packs page with its alignment section, preview and publish dialog (step 11), the parameterized route test (step 19), `createStaffUser` and `GET /api/dev/e2e/demo-pack.zip` (step 20), and the section "Addendum: implementation": `Archive.with_extracted/3` and the archive report, `Catalog.import_pack/2` with the audit event `pack.imported` in the transaction of the import, `require_multipart/2`, `ConnCase.upload_request/4`, and the pack root in one top-level directory of an archive.
- `docs/plan/tasks/0016-scorm-export.md`: `Payload.build/1` (step 1), the table `exports` created with `--no-scope` and its statement on protected columns (step 6), the download with `send_download/3` (step 10), the pack writer (step 12), the round-trip tests (step 13), and the section "Addendum: implementation": `PackWriter.write/2` reads the payload under `pg_advisory_xact_lock_shared(hashtext(<program slug>))` with the timeout of the publisher plus one minute, the module directories `modules/<number>-<slug>/`, and `write_payload/2`.
- `docs/plan/tasks/0004-accounts-sessions.md`, steps 11, 32, 33, 36, 38, 42, 44 and 45: `audit_events.actor_id` with `on_delete: :nilify_all`, the role pipelines, `require_recent_auth/2`, `FallbackController`, `Espalier.Audit.record/4`, the ownership table, the ConnCase helpers (`log_in_user/3`, `override_session/2`, `with_csrf_token/1`) and the CSRF coverage test.
- `docs/plan/tasks/0011-account-ui.md`: `src/api/stepUp.ts` and the API client middleware that opens the step-up dialog on 403 `reauth_required` and repeats the request once.
- The code as it stands after 0016: `lib/espalier/catalog/pack/{loader,archive,importer,validator,report,line_index}.ex`, `lib/espalier/catalog.ex` (`import_pack/2`, `publish_pack/2`), `lib/espalier/interop/{payload,pack_writer}.ex`, `lib/espalier_web/controllers/admin/{pack_controller,pack_json}.ex`, `lib/espalier_web/schemas/admin/pack_import.ex`, `lib/espalier_web/router.ex`, `lib/espalier_web/plugs/security_headers.ex`, `frontend/src/admin/packs/*`, `frontend/src/api/admin/packs.ts`, `frontend/src/admin/sections.ts` and `frontend/src/app/{router,lazyPages}.tsx`.
- `docs/security/asvs-l2.md`, `test/docs/asvs_matrix_test.exs`, `test/espalier_web/controllers/admin/admin_routes_test.exs` and `test/espalier_web/api_spec_test.exs`.
- The documentation of the installed CodeMirror 6 release: the system guide (styles through `style-mod` and the facet `EditorView.cspNonce`), the example on tab handling, and the notes on accessibility.

## Goal
Authors edit the YAML and Markdown files of a content pack in the admin area.
A draft starts from a published program, from an import with a payload, from
an uploaded zip archive or from an empty skeleton. The draft page shows the
files in a tree and one file in an editor, and it saves a file with
optimistic locking. A check runs the loader and the validator of 0008 on the
draft without saving it: the report names file and line as
`mix espalier.validate` prints them, a link opens the file at that line, and
the alignment matrix appears as on the pack page. "Create import" turns the
saved draft into a `PackImport` through the importer of 0008, and the pack
page of 0015 takes over with report, alignment, diff, preview and publish. A
draft downloads as a zip archive in the pack layout. Content packs stay the
only import and export format, so `mix espalier.validate`,
`mix espalier.import`, `mix espalier.export` and the Git workflows of an
organization read and write the same files as the workbench.

## Scope
- In: The task adds the tables `pack_drafts` and `pack_draft_files` and the context `Espalier.Workbench` with the limits and path rules of a draft, the four starting points, the check, the import from a draft and the download.
- In: It adds `PackWriter.render/1`, `PackWriter.render_program/1` and `PackWriter.slug/1`, `Archive.pack_root/1`, `Loader.pack_meta_text/1`, the option `audit:` of `Catalog.import_pack/3`, and the schema `AdminPackAlignment`, which the pack view and the check share.
- In: It adds the workbench routes with their OpenApiSpex operations, the audit events `pack_draft.created` and `pack_draft.deleted`, the editor spike, the pages `/admin/workbench` and `/admin/workbench/:id`, the button "Edit in the workbench" on the pack page, and the guide `docs/guides/pack-workbench.md`.
- Out: WYSIWYG editing and form editors for pack files (README section 1), collaborative real-time editing (two authors who change one draft receive 409 `stale_draft`), and Git integration in the server (a draft keeps no history; the zip download and the repository of the organization carry it).
- Out: The rename of a module directory in one step, a preview of a draft without an import (the preview of the pack page runs on the import), and any change of the CSP or of the Trusted Types header of README section 6.5.
- Out: The pack format, the loader, the validator, the alignment checks and the importer (0008); the pack page with diff, preview and publish (0015); the pack writer and the payload builder (0016); the guide `content-packs.md` (0017), which links the guide of this task.

## Security requirements
This list holds exactly the rows whose `Task` column names this task, as the ownership table of 0004 step 42 assigns them (README section 15, decision D16). A row marked "extends the row of" belongs to the task named there, and this task adds its code and test to that row.
- 2.1.1 (extends the row of 0009): every workbench route has an OpenApiSpex operation with its request and response schemas, and the descriptions of the file routes and of the upload name the limits of step 3 (step 9).
- 2.1.3 (extends the row of 0004): this task sets the draft limits of step 3 (2,000 files, 1 MiB per file, five times `PACK_UPLOAD_MAX_MB` per draft, 50 drafts, 2 parallel checks and imports), the OpenAPI document names them, and `docs/guides/pack-workbench.md` documents them (steps 3, 9 and 17).
- 2.2.1 (extends the row of 0009): every workbench route validates its input with `CastAndValidate`, and the context checks every path against the path rules and every content against the content rules of step 3 before it stores them (steps 3 and 9).
- 2.3.2 (extends the row of 0004): the context enforces the limits of a draft under a row lock on the draft and the number of drafts under a transaction-scoped advisory lock, and a change beyond a limit answers 409 or 422 as step 9 lists (steps 3, 4 and 5).
- 2.3.3 (extends the row of 0004): a new draft with its files and its audit event, each file change with the increment of `lock_version`, and the deletion of a draft with its audit event each run in one `Repo.transact/1`, and the import from a draft writes the import and `pack.imported` in the one transaction of `Catalog.import_pack/3` (steps 4, 5, 7 and 10).
- 3.2.2 (extends the row of 0010): the editor, the file tree and the check report show file content, paths and messages as text: React text nodes, the value of a `<textarea>` or the text nodes of the CodeMirror view, and no `dangerouslySetInnerHTML` (steps 1 and 13).
- 5.1.1 (extends the row of 0015): the operations of `POST /api/admin/pack-draft-uploads` and of the file routes document the accepted archive, the file names and extensions of the pack layout and the sizes of step 3, and the guide repeats them (steps 9 and 17).
- 5.2.1 (extends the row of 0015): the upload of a draft reads its body only in the pipeline `:pack_upload`, behind `:author_write` and up to `PACK_UPLOAD_MAX_MB` (413 above it), and a file content above 1 MiB answers 422 (steps 3, 5 and 9).
- 5.2.2 (extends the row of 0015): the path rules admit only the names and the extensions `.yaml` and `.md` of the pack layout, the start from an archive keeps only such files and lists every other path as skipped, and every stored content is UTF-8 text without U+0000 (steps 3 and 5).
- 5.2.3 (extends the row of 0015): the start from an archive runs `Archive.with_extracted/3` with the limits of the pack upload before it reads any file (step 5).
- 5.3.2 (extends the row of 0015): a path passes the path rules of step 3 before it is stored and again before it is joined with a new directory below `System.tmp_dir!/0`, which an `after` block removes, and no request names a path on the file system of the server (steps 3, 6 and 7).
- 5.4.1 (extends the row of 0016): the download of a draft carries the file name `<pack key>-draft.zip`, or `pack-draft.zip` without a usable pack key, and no request parameter names a file (step 8).
- 5.4.2 (extends the row of 0016): the generated name goes to `Phoenix.Controller.send_download/3`, which encodes it for `content-disposition` (step 8).
- 15.2.2 (extends the row of 0004): the draft limits bound the storage of a draft and the memory of a check, an import and a download, the check and the import run the loader with its time and memory budget (0008), at most `max_parallel_checks/0` of them run at once and a request beyond that answers 429 `checks_busy`, and every temporary directory is removed in an `after` block (steps 3, 6, 7 and 8).
- 15.3.3 (extends the row of 0009): every request schema sets `additionalProperties: false`, the changesets cast `path` and `content` only, and the context alone sets `created_by_id`, `lock_version`, `title` and `pack_key` (steps 2 and 9).

The workbench routes also rely on the controls that the rows 7.5.1, 8.2.1, 14.2.2, 14.3.2, 1.5.2 and 3.5.1 record for 0004, 0008 and 0015:
- The GET routes and the check run in `[:api, :author]`, and every other POST, PUT, PATCH and DELETE route runs in `[:api, :author_write]`, so that a change needs a second factor from the last 10 minutes (README section 6.4). A request without a session answers 401 `unauthenticated`, a learner gets 403 `forbidden`, and a change without a recent second factor gets 403 `reauth_required`. The context functions of step 4 return `{:error, :forbidden}` for a scope without the role `author`.
- Every answer under `/api/admin` carries `cache-control: no-store`, which covers file content and the payload of an import.
- The check and the import parse the content of a draft with the loader of 0008, which creates no atoms and bounds nodes, nesting, strings and time.
- The CSRF coverage test of 0004 selects every mutating route from the router, so it covers the workbench routes without a change.

## Steps
1. **Editor spike.** Decide the editor before the SPA steps. In both outcomes the component `PackFileEditor` in `frontend/src/admin/workbench/PackFileEditor.tsx` has the props `value`, `onChange(value)`, `language` (`"yaml"` or `"markdown"`), `label`, `onSave()`, `onCursor(line, column)` and `goTo` (`{line}` or `null`; a new object moves the cursor to the start of that line and scrolls it into view), so that steps 13 and 15 do not depend on the outcome.
   - Packages: install `@codemirror/state`, `@codemirror/view`, `@codemirror/commands`, `@codemirror/language`, `@codemirror/lang-yaml` and `@codemirror/lang-markdown` with `npm --prefix frontend install --save-exact`, each in its current release. Check with `npm --prefix frontend ls --all` and the `license` field of every installed package below them, `style-mod` and the `@lezer/*` packages included, that each carries the MIT license (assumption: the CodeMirror 6 packages are MIT; verify). Write `PackFileEditor` with an `EditorView`, the language of the file, line numbers, the default keymap and a binding of `Mod-s` to `onSave`.
   - CSP: read `StyleModule.mount` in the installed `style-mod`. Assumption to verify: it adds its rules through a constructed `CSSStyleSheet` in `document.adoptedStyleSheets` where the browser supports it and through a `<style>` element otherwise, and `EditorView.cspNonce` only sets the nonce of that element. The Vite dev server sends no CSP and injects style elements, so the check runs on a build: the harness `frontend/e2e/workbench/harness/index.html` with `main.tsx` renders `PackFileEditor` once with a YAML text and once with a Markdown text, and `frontend/e2e/workbench/editor-csp.spec.ts` builds it with the `build()` function of Vite and the plugins of `vite.config.ts` into a temporary directory and serves it with a Node `http` server that sends `content-security-policy` and `content-security-policy-report-only` as `GET /health` returns them from Phoenix through the Vite proxy, so the values come from `EspalierWeb.Plugs.SecurityHeaders` without a copy. An init script collects every `securitypolicyviolation` event. The spec opens both editors, types, selects, undoes and moves through lines, and passes when the page records no event and no console message about a policy and a highlighted token of the YAML text has a computed color other than that of plain text.
   - Trusted Types: the same run records no event whose `violatedDirective` is `require-trusted-types-for`, the report-only header of README section 6.5.
   - Accessibility: the content element of the editor has the role `textbox`, `aria-multiline="true"` and the accessible name of `label`. The keymap binds no Tab (no `indentWithTab`), so Tab and Shift+Tab move the focus out of the editor and never trap it, and `Mod-]` and `Mod-[` of `defaultKeymap` indent and dedent the selected lines (assumption: both are in `defaultKeymap` of `@codemirror/commands`; verify). axe reports no violation on the harness. The maintainer moves through the lines of a YAML file with a screen reader (NVDA on Windows or Orca on Linux) and hears the content of each line.
   - Outcome: when all checks pass, the editor is CodeMirror 6. When a check fails, remove the packages and write `PackFileEditor` as a `<textarea>` with the classes `font-mono` and `whitespace-pre`, `wrap="off"`, `spellCheck={false}` and `autoCapitalize="off"`, with a column of line numbers beside it that carries `aria-hidden="true"`, holds one number per line of the value and follows the scroll position of the textarea. Tab keeps its browser behavior there, and Ctrl+S and Cmd+S call `onSave`. The harness spec stays in `make e2e` in both outcomes.
   - The CSP is never loosened: `EspalierWeb.Plugs.SecurityHeaders.headers/0` keeps its values byte for byte, and `test/espalier_web/plugs/security_headers_test.exs` keeps its expected CSP. The section "Addendum: implementation" of this spec records the outcome with the installed versions, the result of each check, the screen reader with its version, and the reason of a failed check. When CodeMirror passes, add it to the row "Frontend libraries" of README section 3.
2. **Tables.** Run `nix-shell --run "mix phx.gen.context Workbench PackDraft pack_drafts title:string pack_key:string lock_version:integer created_by_id:references:users --no-scope"` and then `nix-shell --run "mix phx.gen.schema Workbench.PackDraftFile pack_draft_files pack_draft_id:references:pack_drafts path:string content:text --no-scope"`. A draft is a working copy of an author, as an export is an administrative record in 0016 step 6, and it belongs to no learner record. Both commands therefore pass `--no-scope`: with the default scope of 0004, the generators add a `user_id` column and a scope-taking changeset themselves. Add no `user_id` column by hand.
   - Migration of `pack_drafts`: `null: false` on `title` and `lock_version`, `default: 1` on `lock_version`, `pack_key` nullable, and `on_delete: :nilify_all` on `created_by_id`, as 0004 step 11 does for `audit_events.actor_id`, with the index that the generator writes.
   - Migration of `pack_draft_files`: `null: false` on `pack_draft_id`, `path` and `content`, `on_delete: :delete_all` on `pack_draft_id`, and a unique index on `(pack_draft_id, path)` that replaces the generated index on `pack_draft_id`. `path` keeps the `varchar(255)` of `:string`, the length bound of step 3.
   - Schemas: `PackDraft` has `has_many :files` and keeps `created_by_id` as a plain field, as `Export` keeps `requested_by_id` (0016 addendum). `PackDraftFile` belongs to its draft and has `changeset/2`, which casts `path` and `content` only and carries `unique_constraint([:pack_draft_id, :path])`. `title`, `pack_key`, `lock_version` and `created_by_id` are set by the context on the struct or in its queries, never cast from a request (ASVS 15.3.3).
   - The functions of step 4 replace the output of `phx.gen.context` in `lib/espalier/workbench.ex`, and its generated test and fixture are removed, as the addendum of 0016 records for `Espalier.Interop`.
   - Protected columns: the tables hold no encrypted and no keyed-hash column. This task therefore writes no rotation-only schema `Espalier.Crypto.Rotation.<Table>` in `lib/espalier/crypto/rotation/`, registers none in `Espalier.Crypto.Rotation.schemas/0`, and adds no row to `docs/security/crypto-inventory.md`. Neither schema declares a Cloak field, so the assertion of 0003 that `uncovered(SchemaRules.app_schemas(), Rotation.schemas())` returns `[]` and the check of `inventory_test.exs` hold with them. A draft holds course content, the data class of the catalog tables and of `pack_imports.payload` and `report` (0008, 0015), which store the same content as plain text. It holds no account data of the users of the platform, the class that `AGENTS.md` and README section 6.9 encrypt, and the guide of step 17 states that a pack, like the pack repository of an organization, is no place for personal data of learners or staff.
3. **Limits and path rules.** `Espalier.Workbench` exposes the limits as functions, and the operations of step 9 and the guide of step 17 name their values:
   - `max_files/0`: `Espalier.Catalog.Pack.Archive.max_entries/0`, 2,000 files per draft.
   - `max_file_bytes/0`: `Espalier.Catalog.Pack.Loader.max_file_bytes/0`, 1,048,576 bytes of UTF-8 per file, the size above which the loader rejects a file.
   - `max_draft_bytes/0`: five times the upload limit, `5 * Application.get_env(:espalier, :pack_upload_max_mb, 20) * 1_048_576` (104,857,600 bytes with the default), which equals the bound on the declared sizes of an uploaded archive in `Archive`. The context reads the setting of `PACK_UPLOAD_MAX_MB` directly, so that `Espalier.Workbench` does not depend on `EspalierWeb.PackMultipart`; a test asserts that the value equals `5 * PackMultipart.max_bytes()`. The bytes of a draft are the sum of `byte_size/1` over the contents of its files.
   - `max_drafts/0`: 50 drafts in total, from `config :espalier, :pack_drafts, max_drafts: 50` in `config/config.exs`. A function that reads the value raises `ArgumentError` for a value that is no positive integer.
   - `max_parallel_checks/0`: 2 checks and imports from drafts at once per node, from `config :espalier, :pack_drafts, max_parallel_checks: 2`, read in the same way (step 6).
   - Content rules: a content is a string of valid UTF-8 (JSON strings arrive as UTF-8, and the start from an archive checks it), holds no U+0000, which a PostgreSQL `text` column cannot store, and has at most `max_file_bytes/0` bytes. Other control characters are stored, and the check of step 6 reports them with line and column, as the loader does.
   - Path rules: `Espalier.Workbench.Paths.check(path)` returns `:ok` or `{:error, :invalid_path}`. A path is valid UTF-8 of 1 to 255 bytes, holds no U+0000 and no backslash, does not start with `/` or a drive letter, and holds no empty, `.` or `..` component when it is split at `/`. It then names a file that the loader of 0008 reads, one of exactly three forms: a name of `Loader.top_files/0` (`pack.yaml`, `sources.yaml`, `glossary.yaml`, `segments.yaml`, `stations.yaml`, `feedback.yaml`, `qualifications.yaml`, `formats.yaml`); `modules/<dir>/<name>` with a name of `Loader.module_files/0` (`module.yaml`, `objectives.yaml`, `rules.yaml`, `items.yaml`, `assessment.yaml`); or `modules/<dir>/lessons/<key>.md`. `<dir>` and `<key>` satisfy `Espalier.Catalog.Pack.Schema.Cast.key?/1`, the key format that the loader applies to module directories and lesson keys (0008 addendum). The module checks the general rules before the layout forms, so that they hold for any form a later task adds. In the layout no path names a directory of another path, so no file of a draft lies below a file of the same draft.
   - `Paths.language(path)` returns `:yaml` for a path that ends in `.yaml` and `:markdown` for one that ends in `.md`.
4. **Context.** `Espalier.Workbench` takes the scope first in every public function and returns `{:error, :forbidden}` for a scope without the role `author`, as `Espalier.Catalog.import_pack/2` does (0015 addendum). An unknown or malformed id answers `{:error, :not_found}`.
   - Reads: `list_drafts(scope)` returns the drafts, newest `updated_at` first, each with `file_count` and `bytes` from one aggregate query and no content. `get_draft(scope, id)` returns the draft with its files ordered by path, each with id, path, `bytes` (`octet_length(content)`) and `updated_at` and without content. `get_file(scope, draft_id, file_id)` returns the draft and the file with its content; a file of another draft answers `:not_found`.
   - File changes: `create_file(scope, draft_id, %{path, content}, lock_version)`, `update_file(scope, draft_id, file_id, content, lock_version)`, `rename_file(scope, draft_id, file_id, path, lock_version)` and `delete_file(scope, draft_id, file_id, lock_version)`. Each runs in one `Repo.transact/1`: it locks the draft row with `FOR UPDATE`, answers `{:error, {:stale_draft, current}}` when `lock_version` differs from the stored value, checks the path rules and the content rules of step 3, counts the files and sums the bytes of the draft after the change, answers `{:error, :too_many_files}` above `max_files/0` and `{:error, :draft_too_large}` above `max_draft_bytes/0`, writes the file row, and sets `lock_version` to the stored value plus one and `updated_at` to now. The row lock orders all changes of one draft, so two requests with the same `lock_version` give one change and one `stale_draft`. A path that the draft holds already answers `{:error, :path_taken}` through the unique constraint; an invalid path answers `{:error, :invalid_path}`, a content above the limit `{:error, :file_too_large}`, and a content with U+0000 `{:error, :nul_character}`. Each function returns `{:ok, draft}` with the draft as `get_draft/2` returns it.
   - Title and pack key: a change that writes the content of `pack.yaml` (a create, an update, or a rename to `pack.yaml`, which reads the stored content first) parses that content before the transaction with `Loader.pack_meta_text/1` of step 5, so that no parse runs while the row lock is held, and stores in the transaction of the change `title` from its `title` and `pack_key` from its `key`, each when it is a string of 1 to 255 characters without U+0000. A missing or unusable `title` keeps the stored title, and a missing or unusable `key` sets `pack_key` to `nil`. A change that removes `pack.yaml` (a delete, or a rename away from it) sets `pack_key` to `nil`. A change of the same draft between the parse and the transaction answers `stale_draft` through the lock check, so the stored title and key always belong to the stored `pack.yaml`.
   - `delete_draft(scope, id)` deletes the draft, whose files go with it through `on_delete: :delete_all`, and writes the audit event `pack_draft.deleted` in the same `Repo.transact/1`.
   - The creators of step 5, the check of step 6, the import of step 7 and the download of step 8 complete the context.
5. **Starting points.** `create_draft(scope, source, files, attrs)` (private) receives a list of `{path, content}`, checks every path with the path rules and every content with the content rules, and applies `max_files/0` and `max_draft_bytes/0`. In one `Repo.transact/1`, which first takes `pg_advisory_xact_lock(hashtext('espalier.pack_drafts'))`, so that concurrent creations count and insert one after the other, it answers `{:error, :draft_limit}` when `max_drafts/0` drafts exist, and otherwise inserts the draft with `title`, `pack_key`, `lock_version` 1 and `created_by_id` from the scope, inserts the files with `Repo.insert_all/3` in chunks below the parameter limit of PostgreSQL and of at most 8 MiB of content each, as the publisher inserts its rows (0008 addendum), and writes the audit event `pack_draft.created`. `title` and `pack_key` come from `pack.yaml` of the files as step 4 describes; without a usable title, `title` is the file name of an uploaded archive without `.zip` (shortened to 255 characters, without U+0000), and otherwise "Untitled draft". The public creators answer `{:ok, draft}`:
   - Writer functions: in `Espalier.Interop.PackWriter`, the private `files/1` becomes `render(payload)`, which returns the list of `{relative path, content}` that `write_payload/2` writes; `render_program(program)` reads the payload of a published program in the transaction of `write/2`, under `pg_advisory_xact_lock_shared(hashtext(<program slug>))` and with its timeout (0016 addendum), and returns `{:ok, files}` or `{:error, :not_published}`; and the private `slug/1` of the module directories becomes public. `write/2` and `write_payload/2` call these functions, so the files of a draft equal the files that `mix espalier.export` writes for the same payload.
   - Empty skeleton, `create_empty(scope, name)`: `Espalier.Workbench.Skeleton.payload(name)` returns a normalized map in the shape of 0008 step 9, and `PackWriter.render/1` writes its files. The pack `title` is `name`, and the pack `key` is `PackWriter.slug(name)`, or `new-pack` when the slug is empty. For the name "New pack", the skeleton holds exactly these six files, the output of `PackWriter.render/1` for that payload, which pass `mix espalier.validate` and `mix espalier.alignment` with no error and no warning (checked on 2026-10-13 against the code after 0016):

     `pack.yaml`
     ```yaml
     schema: 1
     key: new-pack
     title: New pack
     locale: en
     license: CC0-1.0
     version: "0.1.0"
     alignment: strict
     ```
     `stations.yaml`
     ```yaml
     - kind: overview
       title: Overview
       config:
         intro: Replace this introduction with the purpose of the pack.
     - kind: module
       title: First module
       module: 1
       config: {}
     ```
     `modules/01-first-module/module.yaml`
     ```yaml
     number: 1
     title: First module
     summary: Replace this summary with what learners do in the module.
     phases:
       - understand
     domains: []
     single_path: false
     refresher_unit: false
     ```
     `modules/01-first-module/objectives.yaml`
     ```yaml
     - key: m1-subject
       statement: Learners can name the subject of this module.
       area: subject
       depth: know
       phase: understand
       taught_in:
         - 01-first-lesson
     - key: m1-method
       statement: Learners can name the method that this module practises.
       area: method
       depth: know
       phase: understand
       taught_in:
         - 01-first-lesson
     - key: m1-self
       statement: Learners can name what this module asks of their own work.
       area: self
       depth: know
       phase: understand
       taught_in:
         - 01-first-lesson
     - key: m1-social
       statement: Learners can name what this module asks of their work with others.
       area: social
       depth: know
       phase: understand
       taught_in:
         - 01-first-lesson
     ```
     `modules/01-first-module/items.yaml`
     ```yaml
     - key: m1-first-question
       kind: single_choice
       lesson: 01-first-lesson
       stem: Replace this question with a question on the first lesson.
       core: false
       phase: understand
       provenance: invented
       objectives:
         - m1-method
         - m1-self
         - m1-social
         - m1-subject
       rules: []
       reveals: []
       options:
         - key: a
           label: The correct answer
           correct: true
           feedback: Replace this feedback.
         - key: b
           label: A wrong answer
           correct: false
           feedback: Replace this feedback.
     ```

     `modules/01-first-module/lessons/01-first-lesson.md`
     ```markdown
     ---
     title: First lesson
     position: 1
     ---

     :::text{provenance=invented}
     Replace this text with the first lesson.
     :::
     ```
     The one item provides evidence for all four objectives, so the skeleton passes the strict alignment checks with one module; the guide of step 17 tells the author to replace it with evidence that fits each objective.
   - Published program, `create_from_program(scope, slug)`: a program whose slug is unknown or whose status is not `published` answers `{:error, :not_found}`; otherwise the files of `PackWriter.render_program/1`, so the draft holds one published version even while a publish of the same pack runs. Its module directories are those of the writer, for example `modules/01-how-language-models-work/` for module 1 of the demo pack (0016 addendum).
   - Import, `create_from_import(scope, import_id)`: an import with a stored payload (status `validated` or `published`) gives the files of `PackWriter.render/1` on its payload; a `failed` import holds no payload (0008 step 9) and answers `{:error, :no_payload}`. The author of a failed upload starts a draft from the same archive.
   - Upload, `create_from_upload(scope, upload_path, filename, max_bytes)`: `filename` is the file name that the client sent, used only for the title fallback of step 5 after everything up to the last `/` or `\` is cut off. `Archive.with_extracted(upload_path, max_bytes, fun)` checks and extracts the archive with the limits of 0015, and `fun` reads the pack in `Archive.pack_root(dir)`, the private `pack_root/1` of `EspalierWeb.Admin.PackController` moved to `Espalier.Catalog.Pack.Archive` and used by both, so that the pack sits at the root of the archive or in its one top-level directory. `Espalier.Workbench.DraftDir.read_pack(root)` walks the root with `File.lstat/1`, takes every regular file whose path relative to the root passes the path rules, and lists every other file in `skipped`, sorted, at most 100 paths and then a count. It rejects the archive with one report entry per file in the shape of the archive report (`file`, `line` `nil`, `message`) for a kept file above `max_file_bytes/0`, a file that is no valid UTF-8 and a file with U+0000, and with one entry at `.` when no file passes the path rules. The creator answers `{:ok, draft, skipped}` or `{:error, entries}`. `Archive` rejects every symbolic link before the extraction (0015 step 7), so the walk meets regular files and directories only.
   - `Loader.pack_meta/1` also returns `title`, and `Loader.pack_meta_text(text)` applies the same parse to the text of a `pack.yaml` with the budget of `parse_budget/0` and returns `%{key: ..., version: ..., title: ...}` with `nil` for a member that is no string.
6. **Check without saving.** `check_draft(scope, id, overlay)` reads the files and the `lock_version` of the draft in one query. `overlay` is `nil` or `%{file_id, content}`: the unsaved content of one file of the draft, which replaces the stored content of that file for this check only. The overlay passes the content rules (422 as step 4 lists), a `file_id` of another draft answers `{:error, :not_found}`, and the bytes after the overlay stay within `max_draft_bytes/0` (`{:error, :draft_too_large}`).
   - `Espalier.Workbench.DraftDir.with_dir(files, fun)` creates a new directory `espalier-draft-<random>` below `System.tmp_dir!/0` (12 random bytes in URL-safe Base64, as `Archive` names its directories), checks each path with the path rules again, writes each file with `File.write/2` below that directory, runs `fun` on it and removes it in an `after` block, also when `fun` raises. The second check of the path rules keeps every write inside the directory also for a row that reached the table by another way than the context (ASVS 5.3.2).
   - Inside `with_dir/2` the check runs `Loader.load/1` and, when the pack loads, `Validator.run/1`, the two calls of `mix espalier.validate` and of the importer. It returns `lock_version` (the version it checked), `report` as `Report.stored(errors, warnings)` (with the loader errors and empty warnings when the pack does not load), and `alignment`: `mode` and `matrix` from the `payload` of `Validator.run/1` (`Alignment.matrix/1`) and `nil` without one, and `errors` and `warnings` as the report entries that carry `check`. `Validator.run/1` returns a payload whenever the checks before the alignment report no error (0008 addendum), so the matrix appears also while an alignment check reports an error in `strict` mode; the pack view of 0015 shows no matrix for such an import, because a `failed` import stores no payload.
   - Extract the part `alignment` of `PackJSON.show/1` into `PackJSON.alignment(payload, report)`, which the pack view and the check view both call, so that the members and the selection of the alignment entries stay one implementation.
   - For the same files, `Report.report_lines/1` of the check answer equals the lines that `mix espalier.validate` prints (`Report.lines/2` of the errors and warnings of the loader and `Validator.validate/1`), as long as neither list reaches the bound of 1,000 entries of `Report.stored/2`. The check stores nothing: it changes no row, and it leaves no directory behind.
   - The check runs the loader with its time and memory budget of 0008 (60 seconds per pack, and 10 seconds and 256 MiB per YAML text by default), the cost of a pack upload of 0015, which runs behind `:author_write`. At most `max_parallel_checks/0` checks and imports from drafts run at once on a node: 2 by default, from `config :espalier, :pack_drafts, max_parallel_checks: 2`, read as `max_drafts/0` is. `Espalier.Workbench.CheckLimiter` admits a check or an import only while a slot is free (for example through a `Task.Supervisor` under the application supervisor with `max_children` set to that value, whose `start_child/2` answers `{:error, :max_children}` when every slot is taken), and a request without a free slot answers `{:error, :checks_busy}` at once, without a queue. The caller awaits its task for the loader budget plus 10 seconds and shuts it down after that.
7. **Import from a draft.** `import_draft(scope, id, lock_version)` reads the files and the `lock_version` of the draft in one query, answers `{:error, {:stale_draft, current}}` when `lock_version` differs, writes the files with `DraftDir.with_dir/2` and runs `Catalog.import_pack(scope, dir, audit: %{pack_draft_id: id})` inside it, in a slot of `CheckLimiter` as the check of step 6 does.
   - `Catalog.import_pack/3` is `import_pack/2` with the option `audit:`, a map that it merges into the details of the audit event `pack.imported`. The importer runs outside the transaction and the import row and its audit event in one `Repo.transact/1`, as the addendum of 0015 requires, so the audit event names the draft of the import.
   - The answer is the import, `validated` or `failed`, as for an upload of the same files. The draft stays after the import, so the author can change it and import it again, and deletes it when the work is done.
8. **Download.** `download(scope, id)` reads the files and builds the archive with `:zip.create(~c"draft.zip", entries, [:memory])`, one entry `{String.to_charlist(path), content}` per file in path order, so that the pack sits at the root of the archive and the archive passes `POST /api/admin/packs`, `mix espalier.validate` and `mix espalier.import` after extraction. The paths of the layout are ASCII, so the charlist holds the bytes of the path. The download name is `<pack key>-draft.zip` when `pack_key` satisfies `Cast.key?/1` and has at most 200 characters, and `pack-draft.zip` otherwise. The archive is built in memory, and `max_draft_bytes/0` bounds its size.
9. **Routes and OpenAPI.** `EspalierWeb.Admin.PackDraftController` and `EspalierWeb.Admin.PackDraftFileController` serve the routes of README section 8 (row "Pack workbench", role `author`), in three router scopes under `"/api/admin"`, as 0015 step 1 and 0016 step 10 split their routes:

   | Route | Pipelines | Answer |
   |---|---|---|
   | `GET /api/admin/pack-drafts` | `[:api, :author]` | 200 `{data: [draft]}`, newest first |
   | `GET /api/admin/pack-drafts/:id` | `[:api, :author]` | 200 draft with its files |
   | `GET /api/admin/pack-drafts/:id/files/:file_id` | `[:api, :author]` | 200 file with `content` and the `lock_version` of the draft |
   | `GET /api/admin/pack-drafts/:id/download` | `[:api, :author]` | 200 `application/zip` |
   | `POST /api/admin/pack-drafts/:id/check` | `[:api, :author]` | 200 check |
   | `POST /api/admin/pack-drafts` | `[:api, :author_write]` | 201 draft |
   | `POST /api/admin/pack-draft-uploads` | `[:api, :author_write, :pack_upload]` | 201 draft with `skipped` |
   | `DELETE /api/admin/pack-drafts/:id` | `[:api, :author_write]` | 204 |
   | `POST /api/admin/pack-drafts/:id/files` | `[:api, :author_write]` | 201 draft |
   | `PUT /api/admin/pack-drafts/:id/files/:file_id` | `[:api, :author_write]` | 200 draft |
   | `PATCH /api/admin/pack-drafts/:id/files/:file_id` | `[:api, :author_write]` | 200 draft |
   | `DELETE /api/admin/pack-drafts/:id/files/:file_id?lock_version=<n>` | `[:api, :author_write]` | 200 draft |
   | `POST /api/admin/pack-drafts/:id/imports` | `[:api, :author_write]` | 201 import with `location` `/api/admin/packs/:id` |

   - The check writes and removes a temporary directory and changes no state, so it runs in `[:api, :author]`, as `POST /api/admin/user-lookups` runs in `[:api, :admin]` (0015 step 4); it carries a content in its body, which a query string cannot hold. Every other POST, PUT, PATCH and DELETE route needs a second factor from the last 10 minutes (README section 6.4), and the step-up dialog repeats the request (step 13).
   - Bodies: `POST /api/admin/pack-drafts` takes `{source, name?, program_slug?, pack_import_id?}` with `source` one of `empty`, `program` and `import`; `name` (1 to 255 characters) belongs to `empty` and is required there, `program_slug` (a key of 1 to 255 characters) to `program`, and `pack_import_id` (a UUID) to `import`. A missing member answers 422 `validation_failed` with `["required"]` and a member of another source with `["not_allowed"]` in `fields`. The upload is `multipart/form-data` with the binary field `file`, as for `POST /api/admin/packs`. A file create takes `{path, content, lock_version}`, an update `{content, lock_version}`, a rename `{path, lock_version}`, the delete of a file the query parameter `lock_version`, the check `{file_id?, content?}` (both or neither) and the import `{lock_version}`. `content` has `maxLength` 1,048,576 in the schema, and the context checks the bytes; `path` has `maxLength` 255; `lock_version` is an integer of at least 1. A content of 1 MiB fits the default body limit of `Plug.Parsers` in the endpoint, which sets no `length` (8,000,000 bytes), also with the escapes of JSON.
   - Views in `EspalierWeb.Admin.PackDraftJSON`: a draft carries `id`, `title`, `pack_key`, `lock_version`, `inserted_at`, `updated_at`, `usage` (`files`, `bytes`), `limits` (`files`, `file_bytes`, `draft_bytes`) and, in the single view, `files` (`id`, `path`, `bytes`, `updated_at`); the list carries no `files`. A file carries `id`, `path`, `content`, `bytes`, `updated_at` and `lock_version`. The check carries `lock_version`, `report` and `alignment`. The upload answer adds `skipped` (`paths`, `omitted`). The import answer is `PackJSON.show/1`.
   - Error codes, added to `EspalierWeb.FallbackController` and its moduledoc: 409 `stale_draft` with the member `lock_version` (the stored version), which the controller renders itself as `PackController` renders `alignment_errors`; 409 `path_taken`, `too_many_files`, `draft_too_large`, `draft_limit` and `no_payload`; 429 `checks_busy` with `retry-after: 5` when `CheckLimiter` has no free slot for a check or an import; 422 `validation_failed` with `fields.path` `["invalid_path"]`, `fields.content` `["too_large"]` or `["nul_character"]`; 422 `archive_rejected` with the report for a rejected archive (0015 addendum) and for the entries of `read_pack/1`; 413 `request_too_large` and 415 `unsupported_media_type` on the upload; 404 for an unknown draft, file, program or import. A malformed id answers 422 `validation_failed`, like every `:id` route with `Fields.uuid()`.
   - Add an OpenApiSpex operation with `CastAndValidate` to each route, with request schemas that set `additionalProperties: false` and the limits above (ASVS 15.3.3), named `AdminPackDraft`, `AdminPackDraftList`, `AdminPackDraftRequest`, `AdminPackDraftUpload`, `AdminPackDraftFile`, `AdminPackDraftFileRequest`, `AdminPackDraftFileUpdate`, `AdminPackDraftRename`, `AdminPackDraftCheckRequest`, `AdminPackDraftCheck`, `AdminPackDraftImportRequest` and `AdminStaleDraft`. Move the inline `alignment` object of `AdminPackImport` into the schema `AdminPackAlignment` in `lib/espalier_web/schemas/admin/pack_alignment.ex`, which `AdminPackImport` and `AdminPackDraftCheck` both reference. The descriptions of the upload, the file create and the file update name the limits of step 3. Run `make api-types` and commit `frontend/openapi.json` and `frontend/src/api/schema.d.ts`.
   - The upload action reads `conn.body_params` as `PackController.create/2` does, so a text part named `file` answers 422 `validation_failed` (0015 addendum), matches `%Plug.Upload{path: path, filename: filename}` and runs `Workbench.create_from_upload(scope, path, filename, PackMultipart.max_bytes())`.
   - Test changes outside this task's files: `test/espalier_web/controllers/admin/admin_routes_test.exs` admits `POST /api/admin/pack-drafts/:id/check` in `:author` as the second POST route without a write pipeline next to the user lookup, admits `:pack_upload` for `POST /api/admin/pack-draft-uploads` with `[:api, :author_write, :pack_upload]`, sends that route the multipart body of the pack upload in `send_route/3`, holds a body in `@post_bodies` for every new JSON POST route, and leaves both upload routes out of the test of extra members. `test/espalier_web/api_spec_test.exs` lists the new routes in `@routes`, the download in `@binary_answers`, and the request schemas of the POST, PUT and PATCH routes in a test like the one of 0016.
10. **Audit and logging.** `pack_draft.created` (subject the draft; details `source`, `pack_key`, `file_count`, and `program_slug` or `pack_import_id` where the source names one) and `pack_draft.deleted` (details `pack_key` and `file_count`), each with `Espalier.Audit.record/4` in the transaction of its change, and `pack.imported` with `pack_draft_id` for an import from a draft (step 7).
    - File changes write no audit event. A draft changes no catalog row, no learner record and no account; every content that reaches learners passes `pack.imported` with the draft id and `pack.published` with their actors; and an event per save would record the working rhythm of an author in `audit_events`, which principle 3 of README section 2 (data minimization) speaks against. `updated_at` and `lock_version` of the draft show that it changed.
    - Add both actions to the column `action` in `docs/security/logging.md` ("since task 0016a") and to the action list of `frontend/src/admin/audit/AuditPage.tsx`, and state there that `pack.imported` names `pack_draft_id` for an import from a draft.
    - Add the component `Workbench` to `docs/architecture/context.puml` with its arrows to `Catalog`, `Interop` and `Audit`, in the change that adds the code (AGENTS.md).
11. **API hooks.** `frontend/src/api/admin/workbench.ts` holds the query hooks of the routes of step 9 with the generated types and the API client of 0010 through `useApiClient()`, as `src/api/admin/packs.ts` does: `useDrafts()`, `useDraft(id)`, `useDraftFile(id, fileId)`, `useCreateDraft()`, `useUploadDraft()` (the `FormData` serializer of `useUploadPack`), `useDeleteDraft()`, `useCreateFile(id)`, `useSaveFile(id)`, `useRenameFile(id)`, `useDeleteFile(id)`, `useCheckDraft(id)`, `useImportDraft(id)` and the download URL. Every change hook writes the returned draft into the cache of `useDraft(id)`, so the page always holds the newest `lock_version`. `staleDraft(error)` returns the `lock_version` of a 409 `stale_draft` and `null` otherwise.
12. **Workbench page.** `frontend/src/admin/workbench/WorkbenchPage.tsx` serves `/admin/workbench` as a lazy page of `src/app/lazyPages.tsx` behind `RequireRole anyOf={["author"]}`, and the section `workbench` appears in `ADMIN_SECTIONS` of `src/admin/sections.ts` between `packs` and `exports`, with its label in the navigation.
    - The page lists the drafts with title, pack key, number of files, size and the time of the last change, each with a link to `/admin/workbench/:id`, a download link and "Delete" with a confirmation dialog (`ConfirmDialog` of `src/app/`).
    - It offers the four starting points: "Empty pack" with a name field; "Published program" with a choice of the programs of `GET /api/programs` (0009); "Zip archive" with a file input, which shows the report of an `archive_rejected` answer with `ReportEntryList` of `src/admin/packs/findings.tsx` and, after a success, the skipped paths; and, on the pack page `/admin/packs/:id` of an import with status `validated` or `published`, the button "Edit in the workbench", which creates a draft from that import. Each start moves to the new draft. A 409 `draft_limit` shows a sentence with the limit and the advice to delete a draft.
13. **Draft page.** `frontend/src/admin/workbench/DraftPage.tsx` serves `/admin/workbench/:id` as a lazy page, so that the editor loads only there. It shows the title as heading, a breadcrumb trail (`Breadcrumbs` of `src/app/`) from the workbench to the draft, the pack key and the usage against the limits.
    - File tree (`FileTree.tsx`): a `nav` with the accessible name "Files of the draft" and nested lists of directories and files, sorted by path, where each file is a button and the open file carries `aria-current="true"` and the unsaved marker. "Add file" opens a dialog that builds a path from a choice (a file at the root, a file of a module directory, or a lesson with its key) and shows `invalid_path` and `path_taken` at the path field; a new lesson starts with front matter (`title`, `position`) and one `text` block, and a new YAML file starts empty. Each file has "Rename" and "Delete" in a menu (Headless UI `Menu`), with a dialog each. The tree uses lists and buttons without the ARIA `tree` role, so Tab and the arrow keys keep their plain behavior.
    - Editor: `PackFileEditor` of step 1 with the label "Content of <path>" and the language of `Paths.language/1` mirrored in `src/admin/workbench/paths.ts` (the extension of the path). A status line next to the editor shows "Line <n>, column <m>" from `onCursor`. A change sets the unsaved marker on the file and in the heading of the editor ("Unsaved changes").
    - Save: the button "Save", Ctrl+S and Cmd+S send `PUT` with the content and the `lock_version` of the cached draft. While a save runs, the button is disabled. After a success the marker goes, and a live region with `role="status"` announces "Saved <path>". Opening another file or leaving the page while the open file has unsaved changes asks first: a dialog offers "Save", "Discard" and "Cancel", `useBlocker` of React Router guards the navigation within the SPA (the router is a data router from `createBrowserRouter`), and a `beforeunload` handler guards a reload or a closed tab.
    - Conflict: a 409 `stale_draft` opens a dialog that states that the draft changed since it was opened and offers "Load the stored version", which reads the file and the draft again and replaces the content in the editor, and "Keep my version", which takes the `lock_version` of the answer and keeps the text in the editor, unsaved, so that the next save replaces the stored version; the dialog says so. A file that another session deleted answers 404 on the save, and the page reads the draft again and states it.
    - Step-up: a 403 `reauth_required` on any change opens the step-up dialog through the API client middleware of 0011, which repeats the request once after a successful step-up (0015 step 5). The page adds no code of its own for it.
    - Check: the button "Check" sends the open file as overlay when it has unsaved changes, and nothing otherwise. The section "Check report" shows the errors and the warnings of `report` with file, line and message, the closing entries of `Report.stored/2` as their message alone, and the headings carry the counts. An entry whose `file` names a file of the draft is a button that opens the file and moves the cursor to its line through `goTo`; an entry on `.` or on a directory shows its path as text. The live region announces "Check finished: <n> errors, <m> warnings". When the draft changed since the check (`lock_version` of the answer below the cached one, or a later edit of the open file), the section states that the report belongs to an earlier state.
    - Alignment: `AlignmentSection` of `src/admin/packs/AlignmentSection.tsx` renders `alignment` of the check, whose type is now `AdminPackAlignment` for both pages. `ReportEntryList` and `AlignmentFindingList` of `findings.tsx` take an optional `onOpen(file, line)`, with which the draft page turns the file of an entry into the button above; the pack page passes none and keeps its rendering.
    - Import: "Create import" is disabled while the open file has unsaved changes, sends `POST .../imports` with the cached `lock_version`, and moves to `/admin/packs/:id` of the answer, where the pack page of 0015 takes over. A 409 `stale_draft` opens the conflict dialog. A link to `GET .../download` offers the zip.
    - Accessibility and language: every control has a visible label, a closed dialog returns the focus to the control that opened it (Headless UI `Dialog`), the editor and the tree are reachable and leavable by keyboard (step 1), and the live region announces save, check and import. Every string exists in `en.json` and `de.json` under `admin.workbench.*`.
14. **ExUnit tests.**
    - Schemas and limits (`test/espalier/workbench_test.exs`): `max_draft_bytes/0` equals `5 * PackMultipart.max_bytes()` with the default and with `put_setting(:pack_upload_max_mb, 1)`; a file of exactly `max_file_bytes/0` bytes is stored and one byte more answers `:file_too_large`; a content with U+0000 answers `:nul_character`; the 2,001st file answers `:too_many_files`; a content that takes the draft above `max_draft_bytes/0` answers `:draft_too_large` (with the upload limit set to 1 MB for the test); the 51st draft answers `:draft_limit`; two concurrent creations at `max_drafts/0` minus one drafts give one draft and one `:draft_limit` (each creation through `Ecto.Adapters.SQL.Sandbox.unboxed_run/2` on a connection of its own in a synchronous module, as `test/espalier/credentials/lock_order_test.exs` does, which deletes its committed rows on exit, because the shared sandbox mode runs both transactions on one connection); `max_drafts/0` raises for 0 and for a string; a deleted user leaves the draft with `created_by_id` `nil`; the deletion of a draft deletes its files.
    - Path rules (`test/espalier/workbench/paths_test.exs`): every top file, every module file and a lesson pass; `../pack.yaml`, `/pack.yaml`, `C:pack.yaml`, `modules\\a\\module.yaml`, `modules/a/../b/module.yaml`, `modules/./a/module.yaml`, `modules//a/module.yaml`, a path with U+0000, a path of 256 bytes, an invalid UTF-8 binary, `README.md`, `modules/a/notes.yaml`, `modules/A/module.yaml`, `modules/a/lessons/x.txt`, `modules/a/lessons/x/y.md` and `modules/a/lessons/-x.md` are each rejected.
    - Optimistic locking: two updates with the same `lock_version` give one `{:ok, _}` and one `{:error, {:stale_draft, 2}}`, and the stored content is that of the first; two concurrent updates with the same `lock_version` give the same outcome, each through `Ecto.Adapters.SQL.Sandbox.unboxed_run/2` on a connection of its own in a synchronous module, as `test/espalier/credentials/lock_order_test.exs` does, because the shared sandbox mode runs both transactions on one connection and cannot show the row lock; a rename to the path of another file answers `:path_taken` and leaves `lock_version` unchanged; a save of `pack.yaml` updates `title` and `pack_key`, and its deletion sets `pack_key` to `nil`.
    - Check: for a copy of `content/demo` in a draft, and for fixtures with a YAML syntax error, a validator error, an alignment error in `strict` mode and a check 4 warning, `Report.report_lines/1` of the check equals `Report.lines/2` of `Loader.load/1` and `Validator.validate/1` on a directory with the same files. The draft with the alignment error returns a matrix of 12 rows per module and the error in `alignment.errors`. An overlay changes the report and leaves the stored content, `lock_version` and `updated_at` unchanged, and no directory with the prefix `espalier-draft-` remains below `System.tmp_dir!/0` after a check, also after a check whose function raises. With `max_parallel_checks` set to 1 and a task that holds the slot, a check and an import answer `{:error, :checks_busy}` without waiting, and once the task ends, a check runs; the controller test answers 429 `checks_busy` with `retry-after: 5`.
    - Import from a draft: the import of a draft with the files of `content/demo` has the status, the report and the payload of `POST /api/admin/packs` with a zip of the same files, and its `pack.imported` event carries `pack_draft_id`; a stale `lock_version` answers 409 `stale_draft` and creates no import.
    - Starting points: the skeleton for "New pack" holds the six files of step 5 byte for byte and passes the check with no entry; for a name of symbols only the key is `new-pack`. The start from the published demo program holds the files of `PackWriter.render_program/1`, and its import has a payload equal to `Payload.build(program)` (the round trip program, draft, import). The start from a `validated` import holds `PackWriter.render/1` of its payload, and the start from a `failed` import answers 409 `no_payload`. The start from a zip of `content/demo` in one top-level directory with an extra `README.md` holds the files of `content/demo` byte for byte and lists `README.md` as skipped; a zip with a lesson that is no UTF-8 and a zip with a lesson above 1 MiB answer 422 `archive_rejected` with an entry on that file; a zip that `Archive` rejects (an entry `../../etc/passwd`) answers 422 `archive_rejected`; a zip without any file of the layout answers 422 with the entry on `.`.
    - Download: the zip of a draft lists exactly the paths of its files with their contents (`:zip.unzip/2` with `:memory`), carries `content-disposition` with `new-pack-draft.zip` for the skeleton and `pack-draft.zip` for a draft whose `pack.yaml` has no usable key, `content-type: application/zip` and `cache-control: no-store`.
    - Routes: the parameterized route test of 0015 step 19, extended as step 9 states, covers every new route: 401 without a session, 403 `forbidden` for a learner, 403 `reauth_required` with `mfa_at` 11 minutes back on every route in `:author_write`, and no recent second factor for the GET routes and the check. Controller tests show every answer of step 9, each `POST`, `PUT`, `PATCH` and `DELETE` with a CSRF token from `with_csrf_token/1`. The CSRF coverage test of 0004 step 45 covers the new mutating routes without a change. The API spec test lists the routes and schemas of step 9 and passes.
    - The audit events of step 10 are written with actor and subject, and a file save writes no event.
15. **Vitest tests.**
    - `WorkbenchPage.test.tsx`: the list, each starting point with the request it sends, the report of `archive_rejected`, the skipped paths, the notice on `draft_limit`, and no axe violation. `guards.test.tsx` expects the author navigation Packs, Workbench, Exports.
    - `DraftPage.test.tsx`: the tree groups the files by directory and marks the open file; an edit sets the marker; Ctrl+S sends `PUT` with the cached `lock_version`, clears the marker and announces the save; a 409 `stale_draft` opens the dialog, "Load the stored version" replaces the text and "Keep my version" keeps it with the new `lock_version` in the next request; a 403 `reauth_required` on a save calls the handler of `setStepUpHandler` and repeats the `PUT` once; the add, rename and delete dialogs send their requests and show `invalid_path` and `path_taken` at the field; the check sends the overlay of an unsaved file, lists the entries with their counts, and an entry button opens its file with the cursor status at its line; the alignment section renders the matrix of the check answer; "Create import" is disabled with unsaved changes and moves to `/admin/packs/:id` after the import; leaving the page with unsaved changes asks first; axe reports no violation.
    - `PackFileEditor.test.tsx`: the accessible name, Tab moves the focus to the next control, `goTo` moves the cursor status to the line, and `onSave` runs on Ctrl+S. For the textarea outcome it also checks one line number per line and `aria-hidden` on the column. When the CodeMirror view cannot be driven in jsdom (assumption: verify in the spike), the page tests replace `PackFileEditor` with a textarea stub through `vi.mock`, the editor test keeps the checks that jsdom supports, and the Playwright tests of steps 1 and 16 cover the rest.
16. **Playwright** (`frontend/e2e/admin/workbench.spec.ts`, Chromium, with `make services-up` and `make run`):
    - An author from `createStaffUser(browser, "author")` creates a draft from the published demo program on `/admin/workbench`. In `modules/02-checking-the-output/objectives.yaml` (the directory that the writer gives module 2 of the demo pack), the spec sets `depth` of `m2-method-release-check` to `deep`, saves with Ctrl+S, checks, and finds the error on that file at the line of the changed `depth` (the validator names the line of the field); the entry opens the file with the cursor status at that line.
    - It restores `depth: apply`, changes the statement of `m2-method-release-check`, saves and checks: the report holds no error, and the alignment section shows 24 rows over two tables.
    - After `POST /api/dev/e2e/age-recent-auth` (0011), the next save opens the step-up dialog, which completes with the passkey and repeats the save.
    - "Create import" leads to the pack page; its publish dialog lists `m2-method-release-check` as a changed learning objective with the field `statement`, the preview of module 2 shows the new statement in the objectives of the module station, and the publish succeeds.
    - axe reports no violation on `/admin/workbench` and on the draft page. At its end the spec deletes the draft, and it restores the demo program by uploading `GET /api/dev/e2e/demo-pack.zip` and publishing it, as `packs.spec.ts` does. The changed objective belongs to module 2, whose statements no other spec reads from the live program, so specs that run in parallel see the statements they expect.
17. **Guide.** Write `docs/guides/pack-workbench.md`: the starting points, the file tree and the layout that the path rules admit, saving and the conflict dialog, the check with its report and matrix and its sameness with `mix espalier.validate`, the import and the hand-over to the pack page, the download and the way back into a Git repository (unzip into the pack directory and commit), the keyboard operation of the editor (Tab leaves the editor; `Mod-]` and `Mod-[` indent in the CodeMirror outcome), the limits of step 3, the recent second factor for every change, the skeleton and the advice to replace its single item with evidence that fits each objective, and the statement that a draft holds course content in the database as the catalog does, so that a pack, like the pack repository of an organization, is no place for personal data of learners or staff. 0017 links this guide from `docs/guides/content-packs.md`, so the content pack guide keeps one description of the pack format.
18. **Verification matrix.** Add the code and the tests of this task to every row of `docs/security/asvs-l2.md` that the section "Security requirements" lists, with the steps that the section names for each row, and state in `Notes` what this task delivers. Set each row to `verified` when every task it names has added its code and test; the rows 2.1.1, 2.1.3 and 5.1.1 stay `open` until 0017 adds its guide.

## Deliverables
- `lib/espalier/workbench.ex` and `lib/espalier/workbench/{pack_draft,pack_draft_file,paths,skeleton,draft_dir}.ex`, the migrations of `pack_drafts` and `pack_draft_files`, and `config :espalier, :pack_drafts` in `config/config.exs`.
- `PackWriter.render/1`, `render_program/1` and the public `slug/1`, `Archive.pack_root/1`, `Loader.pack_meta_text/1` and `title` in `pack_meta/1`, `Catalog.import_pack/3`, and `PackJSON.alignment/2`.
- `EspalierWeb.Admin.PackDraftController`, `PackDraftFileController` and `PackDraftJSON`, the routes in `[:api, :author]`, `[:api, :author_write]` and `[:api, :author_write, :pack_upload]`, the schemas of step 9 with `AdminPackAlignment`, the error codes in `FallbackController`, and the regenerated `frontend/openapi.json` and `frontend/src/api/schema.d.ts`.
- `frontend/src/api/admin/workbench.ts`, `frontend/src/admin/workbench/{WorkbenchPage,DraftPage,FileTree,PackFileEditor}.tsx` and `paths.ts` with their tests, the section in `sections.ts`, the routes in `router.tsx` and `lazyPages.tsx`, the button on the pack page, the `onOpen` prop of `findings.tsx`, and the keys in `en.json` and `de.json`; the CodeMirror packages in `frontend/package.json` and `package-lock.json` when the spike passes.
- `frontend/e2e/admin/workbench.spec.ts`, `frontend/e2e/workbench/editor-csp.spec.ts` and its harness.
- `docs/guides/pack-workbench.md`, the actions in `docs/security/logging.md`, the component in `docs/architecture/context.puml`, the outcome of the spike in the section "Addendum: implementation" of this spec, and the rows of the section "Security requirements" in `docs/security/asvs-l2.md` with the code and the tests of this task (step 18).

## Acceptance
- [ ] `make check` and `make e2e` pass, including `workbench.spec.ts` and `editor-csp.spec.ts`.
- [ ] The section "Addendum: implementation" records the outcome of the spike with the versions, the result of each check of step 1 and the screen reader, and `git diff` of the change shows no change of `lib/espalier_web/plugs/security_headers.ex` and of the expected CSP in its test.
- [ ] `grep -l user_id` over the migrations of `pack_drafts` and `pack_draft_files` prints nothing, this task adds no file under `lib/espalier/crypto/rotation/` and no row to `docs/security/crypto-inventory.md`, and the tests in `test/espalier/crypto/` (0003) pass.
- [ ] The skeleton for the name "New pack" holds the six files of step 5, and `nix-shell --run "mix espalier.validate <dir>"` and `nix-shell --run "mix espalier.alignment <dir>"` on its download, unzipped, print no error and no warning.
- [ ] For a draft with the files of `content/demo`, the check report prints the same lines as `nix-shell --run "mix espalier.validate content/demo"` (the check tests of step 14), and a draft with an error shows the file and the line, whose link opens the file at that line (`workbench.spec.ts`).
- [ ] The round trip from the published demo program to a draft and an import gives a payload equal to `Payload.build(program)`, and the import of a draft equals the upload of a zip of the same files in status, report and payload.
- [ ] Two saves with the same `lock_version` give one success and one 409 `stale_draft`, and the draft page offers to load the stored version or to keep the text.
- [ ] Every workbench route answers 401 without a session and 403 `forbidden` for a learner, every route in `:author_write` answers 403 `reauth_required` when the last second factor is older than 10 minutes, and the GET routes and the check answer without a recent second factor (the parameterized route test of 0015 step 19).
- [ ] The path rules reject every path of the path tests of step 14, the limits of step 3 answer as step 9 lists, and no directory `espalier-draft-*` remains below `System.tmp_dir!/0` after the tests.
- [ ] The download of the skeleton carries `content-disposition` with `new-pack-draft.zip` and `content-type: application/zip`.
- [ ] `docs/security/logging.md` and the audit page name `pack_draft.created` and `pack_draft.deleted`, and a file save writes no audit event.
- [ ] axe reports no violation on `/admin/workbench` and on the draft page, Tab leaves the editor, and the live region announces save, check and import.
- [ ] The rows of `docs/security/asvs-l2.md` that the section "Security requirements" lists name the code and the tests of this task.

## Notes
- README section 1 keeps WYSIWYG authoring out of scope. The maintainer decided after 0016 that authors edit the files of a content pack in the browser (README section 15, decision D18), so the files that Git, `mix espalier.import` and `mix espalier.export` handle stay the one format of content.
- The task runs before 0017, whose content pack guide links the guide of this task. It depends on 0015 for the pipelines, the archive checks, the pack page and the route test, and on 0016 for the pack writer and the shared advisory lock.
- `Espalier.Workbench` is a context of its own. It reads through `Espalier.Catalog` and writes files through `Espalier.Interop.PackWriter`, and `Espalier.Interop` depends on `Espalier.Catalog`; drafts inside `Espalier.Catalog` would make the two contexts depend on each other.
- The draft limits follow the upload: 2,000 files as the archive entries, 1 MiB per file as the loader, and five times `PACK_UPLOAD_MAX_MB` as the declared sizes of an archive. The limit of 50 drafts is a decision of this spec; `config :espalier, :pack_drafts, max_drafts:` changes it.
- A draft whose `pack.yaml` names the key of a published program updates that program at its publish. The diff of the pack page lists every added, changed and archived key before the publish (0015 step 7).
- `created_by_id` records who started a draft. The routes check the role only, so every author reads and changes every draft, as every author reads every import and export (0016 addendum).
- The editor shows text and runs no code from the content. The Markdown of a lesson is rendered only in the preview of the pack page, through the renderer of the player (0012, row 1.3.5).

## Addendum: implementation
The implementation departs from the steps above in the points below, and later
tasks rely on the implemented form.

- Editor spike (step 1): the outcome is CodeMirror 6 with
  `@codemirror/state` 6.7.6, `@codemirror/view` 6.43.13,
  `@codemirror/commands` 6.11.1, `@codemirror/language` 6.12.4,
  `@codemirror/lang-yaml` 6.1.3, `@codemirror/lang-markdown` 6.5.2 and
  `@lezer/highlight` 1.2.5, which the highlight style imports directly. All
  23 packages below them carry the MIT license (`style-mod` 4.1.4,
  `w3c-keyname` 2.2.8, `crelt` 1.0.7, `@marijn/find-cluster-break` 1.0.4,
  the `@lezer/*` and the further `@codemirror/*` packages of the language
  modes). The assumption on `style-mod` does not hold:
  `StyleModule.mount` adopts a constructed `CSSStyleSheet` only for a root
  without `head`, a shadow root, and gives a document a `<style>` element
  filled through `textContent`, which `style-src 'self'` blocks
  (`style-src-elem`, one violation per page, and the base theme is missing);
  `EditorView.cspNonce` only sets the nonce of that element. `PackFileEditor`
  therefore mounts the view in an open shadow root of its frame, where the
  styles arrive as a constructed stylesheet, and takes its colors from CSS
  custom properties that the frame sets with Tailwind classes for both
  themes. The CSP and the Trusted Types header stay unchanged. Under the
  headers of `GET /health`, Chromium (Playwright 1.59.1) records no
  `securitypolicyviolation` event and no console message about a policy,
  also none for `require-trusted-types-for`, while both editors are typed
  in, selected, undone and moved through; a YAML key has another computed
  color than plain text; the content element has the role `textbox`,
  `aria-multiline="true"` and the accessible name of `label`; Tab and
  Shift+Tab move the focus out of the editor; `Mod-]` and `Mod-[`
  (`indentMore` and `indentLess` of `defaultKeymap`) indent and dedent the
  selected lines; and axe reports no violation in the light and the dark
  theme, inside the shadow roots too. The screen reader check with NVDA or
  Orca is open for the maintainer. Further details of the shadow root:
  `delegatesFocus: true` and a `focusin` listener move a focus that lands on
  the host or the scroller to the content element, so a dialog that closes
  returns the focus into the editor (Headless UI records the host); the
  content element carries `tabindex="0"`, because axe does not count the
  contenteditable element as focusable content of the scrollable region
  (`scrollable-region-focusable`) and CodeMirror takes the scroller out of
  the tab order; the name comes from `aria-label` inside the shadow root,
  which an `aria-labelledby` outside cannot reach. The harness of
  `editor-csp.spec.ts` renders a third editor taller than its frame, and its
  Ctrl+S opens a dialog. `PackFileEditor` has the further optional prop
  `readOnly`, which the draft page sets while it loads the stored version
  after a conflict, and it keeps CRLF line endings: a value with `\r\n` sets
  `EditorState.lineSeparator`, and `onChange` reports `state.sliceDoc()`. In
  jsdom the Vitest tests query inside the shadow root, cannot follow a Tab
  move (Playwright covers it) and stub `document.execCommand`, which
  CodeMirror calls on the Safari path that the jsdom vendor string selects.
  A run in Firefox and WebKit outside `make e2e` recorded no violation;
  WebKit in Playwright reports a Mac platform, so `Mod` is Cmd there.
- Path rules (step 3): a path holds 1 to 527 bytes, and no component of it
  more than 255 bytes, the longest file or directory name that common file
  systems hold. The bound of 255 bytes for the whole path rejected files of
  valid packs: the validator admits lesson keys and module directories of up
  to 255 characters, a start from such an import or program answered
  `invalid_path`, and an archive start skipped the lesson, so that its
  import could archive it at the publish. `path` is `varchar(527)`, the
  request schemas set `maxLength: 527`, and `Paths.max_component_bytes/0`
  names the bound of a component.
- Content rules (steps 3 and 4): `Workbench.check_content/1` also answers
  `:invalid_encoding` (422 `fields.content` `["invalid_encoding"]`) for a
  content that is no valid UTF-8, which JSON cannot carry, so that the
  context functions check it for every caller.
- Names and titles (steps 5 and 9): the request schema counts `name` in
  graphemes and the `varchar(255)` columns count code points, so
  `create_empty/2` answers 422 `fields.name` `["max_length"]` for a name of
  more than 255 code points, and the title from an upload file name keeps at
  most 255 code points; `.zip` is removed in any letter case.
- Limits (step 4): a change that adds no file passes the file limit and a
  change that adds no byte passes the byte limit, so that a draft above a
  lowered limit can still shrink.
- File changes (step 4): an update reads the `lock_version` of the draft
  together with the path of the file in one statement before it parses
  `pack.yaml`, and a rename to `pack.yaml` also reads the stored content
  there; a `lock_version` that differs answers `stale_draft` before any
  parse, so the parse and the transaction see the same version. A new path
  is checked against the draft under the row lock, and the unique index
  stays as a second barrier.
- Check limiter (steps 6 to 8): `Espalier.Workbench.CheckLimiter` is a
  `GenServer` that grants a slot while fewer than `max_parallel_checks/0`
  slots are taken, reads the setting at each request and monitors each
  holder, so that a holder that dies frees its slot. `await/1` runs the work
  in an unlinked task of `Espalier.Workbench.TaskSupervisor` with a watchdog
  that kills it when the caller dies; an exception of the task is raised
  again in the caller, so that the `after` blocks of the caller remove the
  directory and free the slot. The check, the import and the download read
  the contents of a draft only inside a slot, an import with a stale or
  unknown version answers before it asks for one, and the download also
  takes a slot and answers 429 `checks_busy`, because the draft and its
  archive take up to twice `max_draft_bytes/0` of memory.
- Answers (step 9): `AdminPackDraftUpload` is the multipart request schema of
  the upload, as `AdminPackUpload` is for `POST /api/admin/packs`; the
  upload answers `AdminPackDraft`, whose members `files` and `skipped` are
  optional. `AdminStaleDraft` describes every 409 answer of the workbench
  routes: `stale_draft` with `lock_version`, `draft_limit` with
  `max_drafts`, the configured limit that the SPA names, and the other codes
  without a further member. The starts of a draft answer 201 with `location`
  `/api/admin/pack-drafts/:id`. The import action is named `create_import`,
  because `import` is a special form. The context returns the `payload` of
  the check, and `PackDraftJSON.check/1` renders `alignment` through
  `PackJSON.alignment/2`, so the context does not depend on the web layer.
- Audit (step 10): `pack_draft.created` names the source `upload` for a
  start from an archive.
- Workbench page (step 12): a zip start that skipped paths stays on
  `/admin/workbench` and shows the skipped paths with a link "Open the
  draft"; a start without skipped paths moves to the draft. The pages reuse
  the keys `auth.forms.cancel`, `admin.common.*` and `admin.packs.errors.*`
  for texts that other admin pages share.
- Draft page (step 13): `useDraft` does not refetch on window focus or on
  reconnect, because such a read would take the `lock_version` of a change
  of another session without its content; the change hooks and the conflict
  dialog update the cache. A file query is dropped from the cache when the
  file closes, and the editor takes a text only from a successful read. The
  Check report lists every entry of the report, the alignment findings
  included, so that it shows the lines of `mix espalier.validate`; the
  alignment section shows them again with the matrix. While "Load the
  stored version" runs, the editor is read-only and save and import are
  blocked. A conflict on an add, a rename, a delete or an import opens the
  conflict dialog of a save, and a 404 on a save says whether the file or
  the whole draft is gone.
- Tests (step 14): the test modules that create drafts run synchronously,
  because the sandbox transaction of a test holds the advisory lock of a
  creation until the test ends. The check test points `TMPDIR` at a
  directory of its own, so that the assertion on leftover directories is
  independent of other test runs.
