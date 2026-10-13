# 0016: SCORM 1.2 and 2004 export, and pack export

> Milestone: M6 Interop and operations, Depends on: 0012, 0015

## Context to read first
- `docs/plan/README.md`: the intro and goal 8 (constructive alignment per topic), principle 10, and sections 5 (scopes), 6.4 (`require_recent_auth` for every admin change), 6.10 (error codes), 7 (domain rules 14 and 15), 8 (row "Exports"), 9 (runtime adapter), 11 (content packs with the example of `objectives.yaml`, and the SCORM export with its `cmi.objectives` entries) and 12 (the `make check` row and the frontend stage of the Dockerfile).
- `docs/architecture/scorm-export.puml`, `docs/architecture/domain-catalog.puml` (`LearningObjective` and its links to lessons, items and companion formats) and `docs/architecture/domain-values.puml` (`CompetenceArea`, `Depth` and `Phase`).
- `docs/plan/tasks/0012-player-learner-ui.md`, steps 1 to 3, 5, 11 and 15: the `Runtime` interface, the view types, `AssessmentsOpenError`, the navigation of `GlossaryTerm`, the module station with the objectives of the topic and their client-side status `practised`, and the boundary check over `src/player/` and `src/learner/`.
- `docs/plan/tasks/0015-admin-area.md`, steps 1, 5, 9, 19 and 20 and Notes: the pipelines `:author` and `:author_write` and the `no-store` header under `/api/admin`, the admin navigation by role with the step-up dialog on `reauth_required`, the TypeScript evaluator in `src/player/evaluate.ts` and `StandaloneRuntime` on the pack payload with the objectives of its module and item views, the parameterized route test over `/api/admin`, and the Playwright helper `createStaffUser`.
- `docs/plan/tasks/0013-policies-credentials.md`, steps 1, 8, 21 and 23: the Oban queue `exports`, `Policies.current_versions/0`, the `policy` field of placeholder blocks in the catalog views, and `PlaceholderBlock`.
- `docs/plan/tasks/0008-catalog-content-packs.md`, steps 2 to 13: the catalog tables and their migrations, including `learning_objectives` and the join tables `objective_lessons`, `item_objectives` and `format_objectives` (steps 2 to 4), the pack format with `objectives.yaml`, the `objectives` of items and formats, `areas_elsewhere` and the `alignment` setting (step 5), the loader, directive splitter and validator (steps 6 to 8), the importer with `PackImport.payload` (step 9), the publisher (step 10), `mix espalier.validate` (step 11), and `Espalier.Catalog.Alignment` with its evidence rule, `check/1`, `matrix/1` and `mix espalier.alignment` (step 13).
- `docs/plan/tasks/0009-learner-api.md`, steps 4, 12, 13 and 16: `EspalierWeb.CastErrorRenderer`, the read rules for archived rows, the completion rule with the 409 `assessments_open`, the outcome per exam in `GET /api/me/progress`, and `make api-types`. Read in steps 12 and 13 also the companion formats of the program view, the `objectives` of the module view (`ObjectiveView` with `lesson_ids` and `evidence`), the `objective_keys` of the item views, the `objectives` of `GET /api/me/progress` (`ObjectiveProgress`) and `Espalier.Learning.ObjectiveStatus.derive/2`, which marks an objective `evidenced`.
- `docs/plan/tasks/0001-bootstrap.md`, step 16 (the `frontend` stage of the Dockerfile with its working directory `/frontend`), and `docs/plan/tasks/0002-quality-ci-oss.md`, Notes (Apache-2.0 section 4 with `LICENSE` and `NOTICE` for every redistribution in object form).
- `docs/plan/tasks/0004-accounts-sessions.md`, steps 11, 32, 33, 36, 38, 42, 44 and 45: the `audit_events` migration with `actor_id`, the role pipelines, `require_recent_auth/2`, `FallbackController`, `Espalier.Audit.record/4`, the ASVS ownership table, the ConnCase helpers (`log_in_user/3`, `override_session/2`, `with_csrf_token/1`) and the CSRF coverage test.
- SCORM 1.2 run-time API (`LMSInitialize`, `LMSGetValue`, `LMSSetValue`, `LMSCommit`, `LMSFinish`) and SCORM 2004 4th edition run-time API (`Initialize`, `GetValue`, `SetValue`, `Commit`, `Terminate`), with their data model elements for status, score, exit and suspend data, and the content packaging rules of both versions (manifest, `schemaversion`, schema files at the package root).

## Goal
An author exports a published module as a SCORM 1.2 or SCORM 2004 4th edition
package. The package runs the player of 0012 in any SCORM-capable LMS and
reports completion, success and score there. The package shows the learning
objectives of the module, and each objective becomes an entry of
`cmi.objectives` whose status follows from the evidence items in the package. A
published program can also be written back to disk as a content pack that keeps
its objectives, their links to lessons, items and companion formats, the
`areas_elsewhere` of its modules and its `alignment` setting.

## Scope
- In: The task adds the payload builder for published content with the objectives of each module, the second Vite build for the SCORM player, `Scorm12Runtime`, `Scorm2004Runtime`, the derivation of objective states in `src/runtimes/objectives.ts` and the suspend-data encoding.
- In: It adds the `Interop.Export` schema and worker, the manifest templates, the zip and its download, the export routes with their OpenApiSpex operations, the query hooks in `src/api/exports.ts` and the admin export page.
- In: It adds `PackWriter` with `objectives.yaml`, the `objectives` of items and formats, `areas_elsewhere` and the `alignment` setting, `mix espalier.export` and the guide `docs/guides/scorm-export.md`.
- Out: xAPI and cmi5, packages with several SCOs, sequencing rules and objectives declared in the manifest, and the import of SCORM packages stay outside this task. The pipelines `:author` and `:author_write` belong to 0004 and 0015. The alignment checks, the alignment matrix and `mix espalier.alignment` belong to 0008, the objectives of the learner views and the objective status of `GET /api/me/progress` to 0009, and the display of the objectives in the module station to 0012. README section 6.12 assigns the OpenAPI operations of the routes of 0004 and of the learner routes to 0009, and those of the routes of 0005, 0006 and 0007 to 0011. The operations of the export routes belong to this task.

## Security requirements
This list holds exactly the rows whose `Task` column names this task, as the ownership table of 0004 step 42 assigns them (README section 15, decision D16). A row marked "extends the row of" belongs to the task named there, and this task adds its code and test to that row.
- 1.1.2 (extends the row of 0010): an XML escape function in `Espalier.Interop` encodes each text from the content as the last step before the manifest template (step 8).
- 1.2.1 (extends the row of 0010): every text from the content in `imsmanifest.xml` passes through that XML escape function (step 8).
- 1.2.3 (extends the row of 0004): the worker writes `content.json` with `JSON.encode!/1`, so no part of it is assembled from strings (step 9).
- 1.3.7 (extended by 0004): the manifests come from fixed EEx templates in `priv/scorm/`, and content enters them only as escaped values (step 8).
- 2.1.1 (extends the row of 0009): the three export routes have OpenApiSpex operations with their request schemas (step 10).
- 2.2.1 (extends the row of 0009): the export routes validate their input with `CastAndValidate`, and an unknown `scorm_version` answers 422 `validation_failed` (steps 10 and 13).
- 5.3.2 (extends the row of 0015): the download builds its file path from `EXPORT_DIR` and the stored `file_name` only, so a request parameter never names a file (step 10).
- 5.4.1: the download carries the file name `<program slug>-module-<number>-<scorm_version>.zip`, and no request parameter names a file (step 10).
- 5.4.2: the generated name goes to `Phoenix.Controller.send_download/3`, which encodes it for `content-disposition` (step 10).
- 15.2.2 (extends the row of 0004): exports run as Oban jobs in the queue `exports` with one slot, so concurrent requests queue up (step 9).
- 15.3.3 (extends the row of 0009): every request schema sets `additionalProperties: false`, and the controller passes only the fields of its schema to the context (step 10).

The export routes also rely on the controls that the rows 7.5.1 and 8.2.1 record for 0004 and 0015:
- The GET routes run in `[:api, :author]` of 0004 step 32, and `POST /api/admin/exports` runs in `[:api, :author_write]` of 0015 step 1, because README section 6.4 applies `require_recent_auth` to every admin change. A request without a session answers 401 `unauthenticated`, a learner gets 403 `forbidden`, and a POST without a second factor from the last 10 minutes gets 403 `reauth_required`.
- The parameterized route test of 0015 step 19 selects every route under `/api/admin` from the router, so it covers the export routes once they exist. The controller test of step 13 repeats these cases for the three export routes.

## Steps
1. **Payload builder.** `Espalier.Interop.Payload.build(program)` reads the catalog rows of a published program, skips every row whose `archived_at` is set (as `EspalierWeb.CatalogJSON` does in 0009 step 12), and returns the normalized map in the shape that the importer of 0008 step 9 stores in `PackImport.payload`. The `key` of `pack.yaml` becomes `programs.slug` (0008 step 5), and the publisher of 0008 step 10 sets the import and the program to `published` in one transaction. The fields of `pack.yaml` that no live table holds (`schema`, `license` and `alignment`) therefore come from the last `PackImport` with status `published` whose `pack_key` equals the program slug, and `alignment` carries the default `strict` filled in, as the normalized map of 0008 step 9 holds it.
   - Alignment data: the payload carries the `areas_elsewhere` of every module, the objectives of every module from `learning_objectives` in `position` order with `key`, `statement`, `area`, `depth`, `phase`, `domain` and `taught_in` (lesson keys from `objective_lessons`), and the `objectives` of every item and every companion format (objective keys from `item_objectives` and `format_objectives`), in the places where the normalized map of 0008 step 9 holds them. It skips every join row that points to an archived row. An objective without `domain` holds the key `domain` with the value `nil`, which is how the normalized map of 0008 step 9 stores an absent optional `domain`.
   - Order: the join tables hold no position. `Payload.build/1` therefore sorts the lists it reads from them by the order rule of the normalized map in 0008 step 9: the `rules` of an item in ascending rule number, the `reveals` of an item in ascending lesson key, and the `objectives` of items and formats and the `taught_in` of objectives in ascending key order. The importer applies the same rule, so a pack that lists these values in another order yields the same payload.
   - Module: `Payload.module(payload, number)` returns a map with the keys `program` (slug, title, locale), `module` (the module with its lessons, rules, items, assessments, objectives and `areas_elsewhere`), `glossary` (the terms that blocks of the module reference with `[[term:...]]`), `sources` (the sources that its citations name) and `formats` (the companion formats that name an objective of the module, with their `objectives`), each in the shape of the full payload.

   The pack writer and the SCORM worker both read content through this module, so the round-trip test of step 13 also covers the content of a SCORM package.
2. **SCORM entry.** Write `frontend/scorm.html` and `frontend/src/scorm/main.tsx`. `main.tsx` imports `src/styles/app.css`, fetches `content.json` relative to the page, finds the LMS API (`API` for 1.2, `API_1484_11` for 2004) with the discovery algorithm of the standards (walk up `window.parent` within the attempt limit the algorithm names, then try `window.opener`), picks the matching runtime and renders the module station of the player. It imports `ModuleStation` and `GlossaryPage` of 0012 directly and imports no API client. The station map `src/learner/stations/index.ts` stays out of the SCORM entry, because the station components that 0013 and 0014 add to it call the API through query hooks. Components of 0012 that navigate (glossary terms, rule links) run inside a router from `createMemoryRouter` with two routes, `/programs/:slug/stations/:position` for the module station and `/programs/:slug/glossary` for the glossary page (the target of `GlossaryTerm`, 0012 step 5), so the player never changes the URL of the LMS window. `src/scorm/` and `src/runtimes/` lie outside the boundary check of 0012 step 15, and the `grep` over `player.js` in Acceptance confirms that the bundle names no API route. UI strings come from the i18n files of 0010 in the locale of the pack. When neither API is found, the page shows a notice that the package needs an LMS and renders nothing else.
3. **Vite build.** Write `frontend/vite.scorm.config.ts` with the input `scorm.html`, `base: "./"`, `publicDir: false`, `build.outDir: "../priv/scorm_player"`, `emptyOutDir: true` and the React and Tailwind plugins of `vite.config.ts`. The output is one JavaScript file `assets/player.js` and one stylesheet `assets/player.css` without hashes. Set these names and disable code splitting in the build options of the pinned Vite release, so that dynamic imports end up in `player.js`. Add the script `"build:scorm": "vite build --config vite.scorm.config.ts"` to `frontend/package.json`.
   - License files: Apache-2.0 section 4 requires a copy of `LICENSE` (4 a) and of `NOTICE` (4 d) with every redistribution in object form (0002 Notes), and the package carries the compiled player into a third-party LMS. Add an inline plugin to `vite.scorm.config.ts` whose `generateBundle` hook reads `../LICENSE` and `../NOTICE` relative to `frontend/` and emits them with `this.emitFile({type: "asset", fileName, source})` under the fixed names `LICENSE` and `NOTICE`, so that both files lie next to `scorm.html` in `priv/scorm_player/`. The build fails when one of them is missing.
   - Add `npm --prefix frontend run build:scorm` to `make check`, where README section 12 lists it, and to the `frontend` stage of the Dockerfile. The working directory of that stage is `/frontend` (0001 step 16), so add `COPY LICENSE NOTICE /` before the SCORM build, and the plugin finds both files at the same relative path as in the repository. Check that the builder stage copies `priv/scorm_player` from that stage before `mix release`.
   - Extend `make e2e` so that it runs `npm --prefix frontend run build:scorm` before Playwright, because the export worker copies the built player.
   - Check with `git check-ignore priv/scorm_player/scorm.html` that the entry of 0001 step 13 ignores the output.
4. **Runtimes.** `src/runtimes/scorm12.ts` and `src/runtimes/scorm2004.ts` implement `Runtime` on the payload of `content.json`. They reuse the payload-to-view mapping of `StandaloneRuntime` and the evaluator and pass rule in `src/player/evaluate.ts` (0015 step 9). With the objectives in `module` and the formats in `formats`, the mapping gives the program view its companion formats, the module view its objectives with `lesson_ids` and `evidence`, and every item view its `objective_keys`, in the shape of the learner views of 0009 (0015 step 9). The evidence of the module view lists the items of the module and the formats of `content.json`, because items of other modules lie outside the package. `completeModule` follows the platform rule of 0009 step 13: while an exam of the module with `counts_for_credential: true` has no passed attempt, it rejects with `AssessmentsOpenError` of 0012 step 2, which carries the open exams in the shape of the 409 `assessments_open` answer, and the module station of 0012 step 11 lists them by title. The runtimes attach the entry of `policies` in `content.json` to each block of kind `placeholder` as its `policy` field, the field that the catalog views carry on the platform (0013 step 21). `PlaceholderBlock` (0013 step 23) therefore renders the policy text in the package, and a key without a published version keeps the block's own body with the `placeholder` badge.
   - 1.2: on start, call `LMSInitialize("")` and set `cmi.core.lesson_status` to `incomplete` when it is `not attempted`. After an exam attempt, set `cmi.core.score.raw` (correct answers of the latest attempt), `cmi.core.score.min` to 0, `cmi.core.score.max` (number of exam items) and `cmi.core.lesson_status` to `passed` or `failed`. For a module without exam, set `completed` when the learner completes the module. Set `cmi.core.exit` to `suspend` while the status is `incomplete` or `failed`, and to the empty string once it is `passed` or `completed`. Call `LMSCommit("")` after each change and `LMSFinish("")` on `pagehide`. Write the objective entries as the bullet "Objective entries" describes, with `cmi.objectives.n.status` set to the state of the objective (`passed`, `failed` or `incomplete`).
   - 2004: call `Initialize("")`. Set `cmi.completion_status` to `incomplete` at start when the LMS reports `not attempted` or `unknown`, and to `completed` after the module completion. Set `cmi.success_status` to `passed` or `failed` after an exam attempt and leave it `unknown` for a module without exam. Set `cmi.score.raw`, `cmi.score.min`, `cmi.score.max` and `cmi.score.scaled` (raw divided by max). Set `cmi.exit` to `suspend` until the completion status is `completed`, and to `normal` afterwards. Call `Commit("")` after each change and `Terminate("")` on `pagehide`. Write the objective entries as the bullet "Objective entries" describes, with `cmi.objectives.n.success_status` set to `passed`, `failed` or `unknown` for the states `passed`, `failed` and `incomplete`, and `cmi.objectives.n.completion_status` set to `completed` for the states `passed` and `failed` and to `incomplete` for the state `incomplete`.
   - Objective states: `src/runtimes/objectives.ts` exports the pure function `deriveObjectiveStates(content, state)`. It returns, for every objective of `module` in `content.json` in position order, the objective key and one of the states `passed`, `failed` and `incomplete`. The evidence items of an objective follow the evidence rule of 0008 step 13, limited to the items of `content.json`: every item that names the objective and is listed by an assessment, and every other item that names it and whose kind has a correct answer (every kind except `poll`). Companion formats provide no evidence in the package, because attendance certificates are issued on the platform only (0013).
     - `passed`: an assessment that lists an evidence item of the objective has a passed attempt, or a practice evidence item of the objective has a correct answer. This is the rule of `Espalier.Learning.ObjectiveStatus.derive/2` (0009 step 13) for `evidenced` with `TRACKING_DETAIL=standard` and an empty set of attended formats, so a passed attempt also counts for an objective whose item was answered wrongly within `max_wrong`.
     - `failed`: the objective is not `passed`, it has at least one evidence item in the package, and every evidence item has an answer. A practice item has an answer once the learner has submitted one, and an exam item once an assessment that lists it has an attempt.
     - `incomplete`: every other objective, including an objective without an evidence item in the package.
   - Objective entries: the index `n` of an objective in `cmi.objectives` is its position among the objectives of the module, counted from 0, so that a resumed package writes each key at the index of the first session. On start, the runtime writes `cmi.objectives.n.id` with the objective key and then the status of the same index, for every objective in index order. SCORM 2004 accepts the status of an entry only after its id, and the same order serves SCORM 1.2. After each item answer and each exam attempt, the runtime derives the states again, writes the status of every objective whose state changed, and commits once. An item that names an objective of another module adds no entry, because `cmi.objectives` holds the objectives of the exported module only.
   - Objective status in the player: `loadState` returns `evidencedObjectives` (`ResumeState`, 0012 step 1) with the keys whose state from `deriveObjectiveStates` is `passed`. The keys of the states `failed` and `incomplete` stay out of the list. The runtimes fill `answeredItems` and `examOutcomes` of the same state from the decoded suspend data and the answers of the current session, so `objectiveStatus` of 0012 step 11 shows `evidenced` for the keys of the list and adds `practised` from the answered practice items, as it does on the platform.
   - Path: the first launch starts on the `full` path, because a package has no self-assessment station. The path switch of 0012 changes it.
   - Resume: `src/runtimes/suspend.ts` encodes the resume state as a string and decodes it. The string holds a version prefix, the path letter, bitsets for opened explanations, answered items and items with a correct answer, and per assessment of the module the attempt count and the outcome in the form of `GET /api/me/progress` (`passed` when any attempt passed, otherwise the outcome of the latest attempt). `loadState` reads `cmi.suspend_data`, and `saveState` writes it. After a resume, `deriveObjectiveStates` reads the restored bitsets and outcomes, so the package reports the objective states of the previous session.
5. **Suspend-data and objective tests.** A Vitest test asserts that encode and decode are inverse for generated states, that the encoding of the largest module of the demo pack with every explanation opened, every item answered correctly and every exam passed stays below 1,000 characters, and that `encode` throws for a result above 4,096 characters, the limit of `cmi.suspend_data` in SCORM 1.2 (README section 11).
   - `src/runtimes/objectives.test.ts` runs `deriveObjectiveStates` on a small `content.json` fixture with one exam, practice items of several kinds, a `poll`, a format with `attendance_counts: true` and an item that names an objective of another module. It covers each rule of step 4. Every objective starts `incomplete`. A correct answer to a practice evidence item gives `passed`. An answer to a `poll` that names an objective leaves the objective `incomplete`. A failed attempt of the exam gives `failed` to an objective whose evidence items all belong to that exam, and leaves an objective with an unanswered practice evidence item `incomplete`. Wrong answers to every evidence item give `failed`, and a later correct answer gives `passed`. A passed attempt gives `passed` to every objective that an item of the exam names, also when that item was answered wrongly in the attempt. An objective whose only evidence is the format stays `incomplete`. The item that names an objective of another module adds no entry.
   - `src/runtimes/scorm12.test.ts` and `src/runtimes/scorm2004.test.ts` run each runtime against a fake LMS API object that records every call. On start, the runtime writes the id of every objective in position order and writes the status of an index only after its id. After an answer that changes the state of one objective, it writes the status of that objective and of no other objective and then calls `LMSCommit("")` or `Commit("")`. `loadState` returns `evidencedObjectives` with the keys of the objectives in the state `passed` and no other key. A second runtime that decodes the suspend data of the first writes the same keys at the same indices with the states of the first. The 2004 test asserts the pair of `success_status` and `completion_status` for each of the three states.
6. **Export schema.** Run `nix-shell --run "mix phx.gen.context Interop Export exports program_id:references:programs module_id:references:modules scorm_version:enum:scorm12:scorm2004 status:enum:queued:running:done:failed file_name:string error:text requested_by_id:references:users --no-scope"`. An export is an administrative record whose requesting author is an actor reference of its own, as `audit_events.actor_id` is in 0004 step 11, and it belongs to no learner record. The command therefore passes `--no-scope`: with the default scope of 0004, `phx.gen.schema` and `phx.gen.context` add a `user_id` column and a scope-taking changeset themselves. Add no `user_id` column by hand. In the migration, set `on_delete: :nilify_all` on `requested_by_id`, as 0004 step 11 does for `audit_events.actor_id`, and add an index on `inserted_at`.
   - Protected columns: the table holds no encrypted and no keyed-hash column. This task therefore writes no rotation-only schema `Espalier.Crypto.Rotation.<Table>` in `lib/espalier/crypto/rotation/`, registers none in `Espalier.Crypto.Rotation.schemas/0`, and adds no row to `docs/security/crypto-inventory.md`. `Export` declares no Cloak field, so the assertion of 0003 that `uncovered(SchemaRules.app_schemas(), Rotation.schemas())` returns `[]` and the check of `inventory_test.exs` hold with it.
7. **Directories.** Add `EXPORT_DIR` to `Espalier.RuntimeConfig.parse!/2` of 0004 with the key `:export_dir`, so that `config/runtime.exs` reads it in every environment and the boot message names the variable; add it to the table in the moduledoc and its cases to `test/espalier/runtime_config_test.exs`. The default is `tmp/exports` in development and `tmp/test-exports` in tests; check with `git check-ignore tmp/exports/x.zip` that the `.gitignore` from `phx.new` covers both. In production the boot stops with a message when `EXPORT_DIR` is unset; 0017 sets it to `/data/exports` in `compose.yaml`. Add `EXPORT_DIR` with an empty value and a comment to `.env.example`. `config :espalier, :scorm_player_dir` defaults to `Application.app_dir(:espalier, "priv/scorm_player")`.
8. **Manifest templates.** Write EEx templates in `priv/scorm/imsmanifest_12.xml.eex` and `priv/scorm/imsmanifest_2004.xml.eex` with one organization, one item and one SCO resource. The resource names `index.html` (the renamed `scorm.html`) as `href` and lists a `file` element for every player file, for `LICENSE` and `NOTICE` at the package root, for `content.json` and for the schema files. The 1.2 manifest carries `<schema>ADL SCORM</schema>` and `<schemaversion>1.2</schemaversion>` and marks the resource with `adlcp:scormtype="sco"`. The 2004 manifest carries `<schemaversion>2004 4th Edition</schemaversion>` and `adlcp:scormType="sco"`. Every text from the content, such as the module title, passes through an XML escape function in `Espalier.Interop`.
   - Put the schema definition files that each version expects at the package root into `priv/scorm/xsd/12/` and `priv/scorm/xsd/2004/`, taken from the content packaging resources published with the SCORM 1.2 and SCORM 2004 4th edition specifications. Record the download URL, the retrieval date and the license terms in `priv/scorm/xsd/SOURCE.md`. If the terms do not allow redistribution in an open-source repository, stop and report before committing the files.
9. **Worker.** `Espalier.Interop.ExportWorker` uses `use Oban.Worker, queue: :exports, max_attempts: 1`. Check that `config :espalier, Oban` lists the queue `exports`, which 0013 step 1 adds. The job arguments hold the export id only. The worker runs these steps:
   - It sets the status `running` and builds the content with `Payload.build/1` and `Payload.module/2`.
   - It writes `content.json` with `JSON.encode!/1`, with the keys of `Payload.module/2` plus `schema` (value 1) and `policies`, into the build directory `<EXPORT_DIR>/<id>.build/`. `policies` maps each `placeholder_key` of the module's blocks that has a published policy version to the object with `key`, `number`, `effective_from` and `body` of that version from `Policies.current_versions/0` (0013 step 8), the shape of the `policy` field in 0013 step 21. The objectives of the module reach the package through `module`, and the formats that name them through `formats`.
   - It copies the files of `:scorm_player_dir` with `scorm.html` renamed to `index.html`, which puts `LICENSE` and `NOTICE` of step 3 at the package root, copies the schema files of the version, and renders the manifest as `imsmanifest.xml`.
   - It zips the build directory with `:zip.create/3` and the option `cwd` into `<id>.zip.part`, renames that file to `<id>.zip`, removes the build directory, and sets the status `done` and `file_name`.
   - On any error it sets `failed` with a short text in `error`, logs the exception and removes partial files. When `scorm.html`, `LICENSE` or `NOTICE` is missing in `:scorm_player_dir`, the export fails with an error text that names the missing file and `npm --prefix frontend run build:scorm`, so the worker writes no package without the license files.
10. **Endpoints.** `EspalierWeb.Admin.ExportController` serves the routes of README section 8 (row "Exports", role `author`). Split them into two router scopes under `"/api/admin"`, as 0015 step 1 does for its resource routes: the two GET routes in `pipe_through [:api, :author]` (0004 step 32), and `POST /api/admin/exports` in `pipe_through [:api, :author_write]` (0015 step 1), so that the request needs a second factor from the last 10 minutes (README section 6.4).
    - `POST /api/admin/exports {module_id, scorm_version}` creates the export with status `queued` and `requested_by_id` from the scope, inserts the worker job in the same `Ecto.Multi` through `Oban.insert`, writes the audit event `export.requested` with `Espalier.Audit.record/4`, and answers 202 with the export. A module that is unknown, archived or part of an unpublished program answers 404 through the `FallbackController` of 0004 step 36. An unknown version answers 422 `validation_failed` through `CastAndValidate` with `EspalierWeb.CastErrorRenderer` of 0009 step 4.
    - `GET /api/admin/exports/:id` returns id, module, version, status, the error text and, when the status is `done`, the download path.
    - `GET /api/admin/exports/:id/download` sends the zip with `Phoenix.Controller.send_download/3` (`{:file, path}`, the file name `<program slug>-module-<number>-<scorm_version>.zip`, content type `application/zip`). The header extension of 0015 step 1 adds `cache-control: no-store` to the response. The action builds the path from `EXPORT_DIR` and the stored `file_name` only. It answers 409 `export_not_ready` while the status is `queued`, `running` or `failed`, and 404 for an unknown id.
    - Add an OpenApiSpex operation with `CastAndValidate` to each route, as 0009 step 13 does for the learner routes, with request schemas that set `additionalProperties: false` and the limits of 0009 step 3 (ASVS 15.3.3), and run `make api-types` (0009 step 16). Commit the regenerated `frontend/openapi.json` and `frontend/src/api/schema.d.ts`. The `api-types` diff check of `make check` fails when `frontend/src/api/schema.d.ts` lags behind the controllers.
11. **Admin page.** `frontend/src/admin/ExportsPage.tsx` serves `/admin/exports` and appears in the author section of the admin navigation of 0015 step 5, next to Packs. The page calls the API through query hooks in `src/api/exports.ts`, which import the API client `src/api/client.ts` of 0010. The boundary check of 0012 step 15 fails when a file under `src/player/` or `src/learner/` imports `src/api/client.ts`, and this task adds no file to either directory. The author chooses a published module (from `GET /api/programs` and `GET /api/programs/:slug` of 0009) and a version and requests the export. A 403 `reauth_required` on the request opens the step-up dialog through the API client middleware of 0011, which repeats the request once after a successful step-up (0015 step 5). The page lists the exports requested on it and polls `GET /api/admin/exports/:id` every two seconds while the status is `queued` or `running`. It shows the download link for `done` and the error text for `failed`. A notice states that the package contains the answer keys and that the receiving LMS records results per person, including the status of each learning objective. The strings go into `en.json` and `de.json`.
12. **Pack writer.** `Espalier.Interop.PackWriter.write(program, path)` writes `Payload.build(program)` in the pack format of README section 11 and 0008 step 5: `pack.yaml`, the YAML files of the program, and per module `module.yaml`, `objectives.yaml` when the module has objectives, `rules.yaml`, `items.yaml`, `assessment.yaml` and the lesson files.
    - Alignment: `pack.yaml` always carries `alignment`, because the payload holds the value with the default filled in. `module.yaml` carries `areas_elsewhere` when the map is not empty, each area with `where` and `reason`. `objectives.yaml` holds one entry per objective in `position` order, each with `key`, `statement`, `area`, `depth`, `phase`, `domain` when it is set, and `taught_in` with lesson keys. Entries of `items.yaml` and of `formats.yaml` carry `objectives` with objective keys when the list is not empty.
    - Lessons: a lesson file has front matter (`title`, `position`) and one container directive per block with the attributes `provenance`, `collapsed_on`, `cite` and `key` where the block has them.
    - Encoder and mix task: `yaml_elixir` (0008) only reads YAML, so add an encoder. Run `nix-shell --run "mix hex.info ymlr"` and add `{:ymlr, "~> <major>.<minor>"}` with the current release. `mix espalier.export SLUG PATH` calls the writer. It exits with status 1 and a message for a non-empty target directory and for an unknown or unpublished slug.
13. **ExUnit tests.**
    - Worker: for module 1 and both versions, `:zip.list_dir/1` shows `imsmanifest.xml`, `index.html`, `LICENSE`, `NOTICE`, `content.json`, `assets/player.js`, `assets/player.css` and the schema files of the version at the package root. `LICENSE` and `NOTICE` in the zip equal the files of the fixture directory byte for byte. A fixture directory without `NOTICE` gives the status `failed` with an error text that names `NOTICE`. The manifest parses with `:xmerl_scan.string/1`, every `file` element names an entry of the zip, and every entry except `imsmanifest.xml` has a `file` element, `LICENSE` and `NOTICE` included. The top-level keys of `content.json` are exactly `schema`, `program`, `module`, `glossary`, `sources`, `formats` and `policies`, and the options carry their `correct` and `feedback` values. For module 1, `module` holds the five objectives of the demo pack (0008 step 12) in position order with `key`, `statement`, `area`, `depth`, `phase`, `domain` and `taught_in`, every item except the poll names its objective, and `formats` holds `workshop` with its two objectives and no other format. For module 2, `module` holds its three objectives and `areas_elsewhere` with `self` and `social`, and `formats` is empty. The tests point `:scorm_player_dir` to a fixture directory with `scorm.html`, the two asset files, `LICENSE` and `NOTICE`.
    - Controller: a learner gets 403 `forbidden` and a request without a session gets 401 `unauthenticated` on all three routes. An author whose session has `mfa_at` 11 minutes back (`override_session/2` of 0004 step 44) gets 403 `reauth_required` on `POST`, and the same request with `mfa_at` set to now answers 202. An unknown `scorm_version` and a body with an extra member answer 422 `validation_failed`, and an archived module answers 404. The download answers 409 `export_not_ready` before the job ran and, after `perform_job/2` from `Oban.Testing`, answers 200 with `content-type: application/zip`, `cache-control: no-store` and a `content-disposition` with the file name of step 10. Each `POST` carries a CSRF token from `with_csrf_token/1` of 0004.
    - Route coverage: the CSRF coverage test of 0004 step 45 covers `POST /api/admin/exports` without a change, and the parameterized route test of 0015 step 19 includes the three export routes and passes.
    - Round trip: import and publish `content/demo`, write the program with `PackWriter` into a temporary directory, run the validator of 0008 on the output (no errors and no warnings), and import the output with the importer of 0008. Its payload equals `Payload.build(program)` and the payload of the original import. Publishing it sets `archived_at` on no row.
    - Round trip of the alignment: the output of the round trip holds `objectives.yaml` in both module directories, `pack.yaml` carries `alignment: strict`, `module.yaml` of module 2 names `self` and `social` in `areas_elsewhere`, and the entry `workshop` of `formats.yaml` lists its two objectives. `Espalier.Catalog.Alignment.check/1` on the payload of the output returns no error and no warning, and `Alignment.matrix/1` on that payload equals `matrix/1` on the payload of the original import and on the published program.
    - Round trip of the optional fields and the order: a copy of `content/demo` with `alignment: warn` in `pack.yaml`, without the `domain` of `m1-subject-next-word` and with the two `objectives` of the format `workshop` in descending key order passes the same round trip. Its output carries `alignment: warn` and no `domain` for that objective, and `formats.yaml` lists the two objectives of `workshop` in ascending key order. The payload of the original import, `Payload.build(program)` and the payload of the re-import each hold that objective with the key `domain` and the value `nil`.
14. **LMS stub and Playwright.** Install `scorm-again` with `npm install --save-dev --save-exact scorm-again` and `fflate` as a dev dependency. Read the README of the installed `scorm-again` release and note three names: the browser bundle in `node_modules/scorm-again/dist/` that defines `Scorm12API` and `Scorm2004API`, the setting that keeps commits in the browser, and the function that preloads saved CMI data. The harness needs all three.
    - `frontend/e2e/scorm/lms.html` loads that bundle, creates `window.API` or `window.API_1484_11` according to a query parameter, records every value the package sets, and embeds the package's `index.html` in an iframe.
    - `frontend/e2e/scorm/scorm.spec.ts` creates an author with `createStaffUser(browser, "author")` from `frontend/e2e/support/staff.ts` (0015 step 20), whose passkey sign-in provides the recent second factor for `POST /api/admin/exports`, requests the export of module 1 for each version on the export page, waits for `done` and downloads the zip. It extracts the zip with `fflate` into a temporary directory next to `lms.html` and the bundle, and serves that directory with a Node `http` server on a free port.
    - It walks through module 1 with a passing exam and asserts the recorded values: for 1.2 `cmi.core.lesson_status` `passed`, `cmi.core.score.raw` and `cmi.core.score.max`; for 2004 `cmi.completion_status` `completed`, `cmi.success_status` `passed` and `cmi.score.scaled` between 0 and 1. A failing attempt records `failed` in `cmi.core.lesson_status` (1.2) and in `cmi.success_status` (2004).
    - Objectives of module 1: the recorded values hold `cmi.objectives.0.id` to `cmi.objectives.4.id` with the five objective keys of module 1 in position order. After the passing exam, `m1-subject-next-word`, `m1-subject-varying-answers` and `m1-method-check-claims`, which the exam items name, record `passed` in `cmi.objectives.n.status` (1.2), and `passed` in `cmi.objectives.n.success_status` with `completed` in `cmi.objectives.n.completion_status` (2004). `m1-self-own-responsibility` and `m1-social-team-transparency`, whose only evidence is the format `workshop`, record `incomplete` (1.2), and `unknown` with `incomplete` (2004).
    - A second run preloads the saved CMI data, reloads the package and asserts that the opened explanations and the path are restored, and that the package writes each objective key at the index of the first run with the state of the first run.
    - The export of module 2, which has no exam, records `completed` (1.2), and `completed` with `cmi.success_status` `unknown` (2004). It records the three objective keys of module 2 in `cmi.objectives` in position order, and after correct answers to the `slot_builder`, `classification` and `checklist_drill` items each of them records `passed` (1.2), and `passed` with `completed` (2004).
15. **Guide.** Write `docs/guides/scorm-export.md` with the package contents, the statement that `LICENSE` and `NOTICE` at the package root cover the player and that the content of `content.json` stays under the license that `pack.yaml` declares (0002 Notes), the data model mapping of step 4, a table of the objective states with their rule and their values in `cmi.objectives` for both versions, the statement that attendance at a companion format counts as evidence on the platform only, the suspend-data limits (4,096 characters in SCORM 1.2, 64,000 characters in SCORM 2004 4th edition), the answer-key notice, the person-linked report of the receiving LMS (README section 11), `mix espalier.export`, and the way to test a package in an LMS. The guide records the LMS name and version of the manual test in Acceptance.

16. **Verification matrix.** Add the code and the tests of this task to every row of `docs/security/asvs-l2.md` that the section "Security requirements" lists, and state in `Notes` what this task delivers: for 1.1.2, 1.2.1 and 1.3.7 the escape function and the templates of step 8 with the worker tests of step 13, for 1.2.3 the worker of step 9, for 2.1.1, 2.2.1 and 15.3.3 the operations and `CastAndValidate` of step 10, for 5.3.2, 5.4.1 and 5.4.2 the download of step 10 with its controller test, and for 15.2.2 the queue `exports`. Set the rows 5.4.1 and 5.4.2, which name this task only, to `verified` once their tests pass, and every other row when each task it names has added its code and test.

## Deliverables
- `frontend/scorm.html`, `frontend/vite.scorm.config.ts`, `frontend/src/scorm/main.tsx`, `frontend/src/runtimes/{scorm12,scorm2004,suspend,objectives}.ts` with their Vitest tests, `frontend/src/admin/ExportsPage.tsx`, i18n keys in `en.json` and `de.json`, `frontend/e2e/scorm/{lms.html,scorm.spec.ts}`, the query hooks in `frontend/src/api/exports.ts`, the regenerated `frontend/openapi.json` and `frontend/src/api/schema.d.ts`.
- `lib/espalier/interop.ex` and `lib/espalier/interop/**` (`Export`, `Payload`, `ExportWorker`, `PackWriter`), the migration of `exports`, `lib/mix/tasks/espalier.export.ex`, `EspalierWeb.Admin.ExportController` with OpenApiSpex operations and the routes in `[:api, :author]` and `[:api, :author_write]`, `priv/scorm/**` including `xsd/SOURCE.md`.
- The Makefile targets `check` and `e2e`, the frontend stage of the Dockerfile, `EXPORT_DIR` in `Espalier.RuntimeConfig` and `.env.example`, `ymlr` in `mix.exs`.
- The rows of the section "Security requirements" in `docs/security/asvs-l2.md` with the code and the tests of this task (step 16).
- Unit, controller, round-trip and Playwright tests, including the round trip of objectives, `areas_elsewhere` and `alignment`, and `docs/guides/scorm-export.md`.

## Acceptance
- [ ] `make check` and `make e2e` pass, including the SCORM tests for 1.2 and 2004.
- [ ] After `npm --prefix frontend run build:scorm`, `ls priv/scorm_player priv/scorm_player/assets` lists `LICENSE`, `NOTICE`, `assets`, `scorm.html`, `player.css` and `player.js` and no other file, `cmp LICENSE priv/scorm_player/LICENSE` and `cmp NOTICE priv/scorm_player/NOTICE` print nothing, and `grep -c "/api/" priv/scorm_player/assets/player.js` prints 0.
- [ ] The 1.2 package of module 1 reports `passed` with raw score and max score after a passing exam, and `failed` after a failing one.
- [ ] The 2004 package of module 1 reports `completed` and `passed` with `cmi.score.scaled` between 0 and 1.
- [ ] The packages of module 1 write the five objective keys of module 1 to `cmi.objectives` in position order. After a passing exam, the three objectives that the exam items name report `passed` (1.2), and `passed` with `completed` (2004), and the two objectives whose only evidence is the workshop report `incomplete` (1.2), and `unknown` with `incomplete` (2004).
- [ ] The packages of module 2 report `completed` (1.2), and `completed` with `cmi.success_status` `unknown` (2004). After correct answers to its three items, each of its three objectives reports `passed` (1.2), and `passed` with `completed` (2004).
- [ ] A second run with the saved CMI data restores the opened explanations and the path and writes each objective key at the index and with the state of the first run.
- [ ] The suspend-data test passes for the largest module of the demo pack, and the objective tests and runtime tests of step 5 pass.
- [ ] After `make refresh-db`, `nix-shell --run "mix espalier.export ai-assistant-basics-demo tmp/pack-out"` (the key of the demo pack, which 0008 step 5 stores as `programs.slug`) followed by `nix-shell --run "mix espalier.validate tmp/pack-out"` prints no error and no warning, `nix-shell --run "mix espalier.alignment tmp/pack-out"` prints a header and 24 matrix rows and no finding, `ls tmp/pack-out/modules/*/objectives.yaml` lists two files, and the round-trip tests pass.
- [ ] The export routes answer 401 `unauthenticated` without a session and 403 `forbidden` for a learner, and `POST /api/admin/exports` answers 403 `reauth_required` when the session's last second factor is older than 10 minutes (the controller test of step 13 and the parameterized route test of 0015 step 19).
- [ ] `grep -l user_id` over the migration of `exports` prints nothing, this task adds no file under `lib/espalier/crypto/rotation/` and no row to `docs/security/crypto-inventory.md`, and the tests in `test/espalier/crypto/` (0003) pass.
- [ ] The packages import into one SCORM-capable LMS of the maintainer's choice, and the guide records the LMS name, its version and the result.
- [ ] The rows of `docs/security/asvs-l2.md` that the section "Security requirements" lists name the code and the tests of this task.

## Notes
- The dependency on 0015 covers the pipeline `:author_write`, the TypeScript evaluator in `src/player/evaluate.ts`, the payload mapping of `StandaloneRuntime`, the admin navigation, the parameterized route test and the Playwright helper `createStaffUser`. 0004, 0008, 0009, 0011 and 0013 arrive through 0015.
- One module is one SCO. A program export with several SCOs and sequencing is outside this task.
- The package carries the compiled player, a redistribution of the project in object form. Apache-2.0 section 4 therefore requires `LICENSE` and `NOTICE` in it (0002 Notes). Step 3 places both files in the output of the player build, so every package receives them through the copy of `:scorm_player_dir`.
- The package evaluates answers locally and therefore contains the answer keys. Exams that count for a credential stay on the platform (README section 16).
- The package contains no anonymous insights and no person-linked data. The receiving LMS records learner id, status, score, time and the status of each objective per person, which is a property of SCORM (README section 11).
- The package derives objective states from the evidence items it contains. Attendance certificates and the items of other modules lie outside the package, so an objective whose evidence is a companion format, such as `m1-self-own-responsibility` with the workshop, stays `incomplete` in the LMS while the platform can mark it `evidenced`.
- The platform stores no status per objective and person (README domain rule 15). In a package, the state lives in `cmi.suspend_data` and `cmi.objectives` of the receiving LMS.
- The manifest declares no objectives. The SCO creates its `cmi.objectives` entries at run time, which both versions allow for a package without sequencing rules.

## Addendum: implementation
The implementation departs from the steps above in the points below, and later
tasks rely on the implemented form.

- Schema files (step 8): the IMS files and `adlcp_rootv1p2.xsd` carry no
  license grant that clearly covers redistribution in an open-source
  repository. The maintainer decided that the repository holds only
  `priv/scorm/xsd/SOURCE.md`, which names the sources, the retrieval date and
  the terms of every file. `Espalier.Interop.SchemaFiles` and
  `mix espalier.scorm_xsd` fetch two pinned archives, the schema definition
  files that Rustici Software publishes on scorm.com, check each archive and
  every file taken from it by SHA-256, and write them into the git-ignored
  directories `priv/scorm/xsd/12/` (4 files) and `priv/scorm/xsd/2004/` (17
  files: the set without metadata, with `xml.xsd`, the `XMLSchema.dtd` that
  `xml.xsd` names and the `datatypes.dtd` that `XMLSchema.dtd` includes,
  because the `imscp_v1p1.xsd` of that set imports `xml.xsd` from the
  package root). `make scorm-xsd`, `make setup`, `make e2e` and the
  builder stage of the Dockerfile run the task, and the builder stage
  installs `ca-certificates` for the download. `config :espalier,
  :scorm_xsd_dir` names the directory. The worker fails the export of a
  version without its schema files with a text that names
  `mix espalier.scorm_xsd`, and the worker tests use the stand-ins in
  `test/fixtures/scorm_xsd/`.
- Publisher (0008 step 10): the time of a publish is the current second, or
  one second after the last publish of the same pack when that is later, so
  that `published_at` orders the publishes of one pack also within one second
  and `Payload.build/1` reads `schema`, `license` and `alignment` from the
  import published last.
- Payload (step 1): `Payload.build/1` also skips a join row or a citation that
  points to a row of another program, and `Payload.module/2` raises
  `ArgumentError` for a module number that the payload lacks.
- Manifests (step 8): both templates carry `<schema>ADL SCORM</schema>`. The
  manifest identifier is `espalier-<program slug>-module-<number>`; the
  organization, the item and the resource append `-organization`, `-item` and
  `-sco` to it. The resource has the type `webcontent`, and its `file`
  elements follow the path order. Neither manifest declares objectives or
  sequencing. `Espalier.Interop` compiles both templates with
  `EEx.function_from_file/4` and renders them with `manifest/2`, and
  `xml_escape/1` also replaces a code point that XML 1.0 does not admit and
  an invalid UTF-8 sequence with U+FFFD.
- Export schema (step 6): the functions of `Espalier.Interop` replace the
  output of `phx.gen.context`, whose functions, test and fixture are gone.
  `Export` belongs to its program and its module, keeps `requested_by_id` as
  a plain field and has `request_changeset/2`, which casts only
  `scorm_version`, and `status_changeset/2`. The migration sets
  `null: false` on `scorm_version`, `status`, `program_id` and `module_id`
  and keeps `on_delete: :nothing` on the references to the catalog.
- Directories (step 7): `Interop.export_dir/0` expands `EXPORT_DIR` to an
  absolute path, and the worker creates the directory when it is missing.
  The worker applies the defaults of `:scorm_player_dir` and
  `:scorm_xsd_dir` (`priv/scorm_player` and `priv/scorm/xsd` of the
  application), and `config/test.exs` points both to the fixtures in
  `test/fixtures/scorm_player/` and `test/fixtures/scorm_xsd/`.
- Routes (step 10): `POST /api/admin/exports` answers 202 with a `location`
  header, and the export view carries `inserted_at` and the number, title and
  program of the module besides the fields of step 10. A malformed export id
  answers 422 `validation_failed`, like every other `:id` route with
  `Fields.uuid()`, and an unknown id 404. A `done` export whose zip is gone
  answers 404 on the download, and an export that the retention deleted
  answers 404 on both routes. `ExportController` renders the 409
  `export_not_ready` itself, as `PackController` renders `alignment_errors`.
  The routes check the role only, so every author reads and downloads every
  export. The audit event `export.requested` carries `program_slug`,
  `module_number` and `scorm_version`, and the action list of the audit page
  and `docs/security/logging.md` name it.
- Worker (step 9): the worker also fails an export when the program or the
  module is no longer published when the job runs and when two files of the
  package would share one path, and its text names every missing player
  file. Any other error leaves the text "The package could not be built; the
  server log names the cause." A job for an export that is not `queued`, or
  that is gone, is cancelled, so an export runs once. The worker builds
  `policies` itself with the four keys of the `policy` field, `effective_from`
  as an ISO 8601 date, so that `Espalier.Interop` does not depend on
  `EspalierWeb`. It reads the published check of the program and the module
  and the content (`Payload.build/1`, `Payload.module/2` and the current
  policy versions) in one `Repo.transact`, which first reads the program slug
  and takes `pg_advisory_xact_lock_shared(hashtext(<program slug>))`. That
  lock conflicts with the exclusive `pg_advisory_xact_lock(hashtext(pack_key))`
  of the publisher, so a running publish of the same pack ends before the read
  and one that starts waits for it. The transaction timeout is
  `Publisher.transaction_timeout/0` plus one minute (`:infinity` stays
  `:infinity`), and the package files are written after the transaction. The
  status change to `running` lies inside the rescued part, so an exception
  there, in the build or in the change to `done` ends the export as `failed`
  and then removes the partial files. The status changes first, so an
  export whose change to `done` committed although its answer was lost
  stays `done` with its package, and the job ends with `:ok`. When the
  change to `failed` itself fails, the worker logs `export status not set to
  failed: export <id>` with the cause, keeps the files for the sweep, and
  the job still returns `{:error, message}`. Every status change
  goes through `Interop.transition_export/3`, one `UPDATE ... WHERE id = $1
  AND status IN (...) RETURNING *` that answers `{:ok, export}` or
  `{:error, :stale}`; `Export.status_changeset/2` checks the values. A stale
  change from `queued` to `running` cancels the job without touching a
  file; a stale change from `running` to `done` removes `<id>.zip`,
  `<id>.zip.part` and `<id>.build`, logs `export status not set to done:
  export <id> is no longer running, package removed` and cancels the job;
  a stale change from `queued` or `running` to `failed` logs `export status
  not set to failed: export <id> is no longer queued or running`. The
  worker sets the Oban `timeout/1` to `build_timeout/0`, 30 minutes. Oban
  2.24 ends a job after its timeout with an exit signal from
  `:timer.exit_after/2`, which no `rescue` of the worker catches; the export
  then stays `queued` or `running` with its partial files until the sweep
  ends it.
- Interrupted exports (step 9): `Espalier.Interop.StaleExportWorker` (queue
  `default`, `max_attempts: 1`) runs every 15 minutes from the crontab entry
  `{"*/15 * * * *", Espalier.Interop.StaleExportWorker}`. With one
  conditional `UPDATE ... RETURNING id`, it sets every export in status
  `queued` or `running` whose `updated_at` lies longer than
  `interrupted_after/0` back to `failed`, with the error "The build was
  interrupted; request the export again." and `updated_at` set to now, logs
  the warning `export interrupted: export <id> set to failed` per export and
  removes `<EXPORT_DIR>/<id>.build`, `<id>.zip.part` and `<id>.zip` of
  exactly these ids. `interrupted_after/0` is
  `max(2 * ExportWorker.build_timeout(), one hour)`, one hour with the
  timeout of 30 minutes, so the export of a job that still runs does not meet
  it, and the sweep test asserts the relation. An export that waits longer
  than the limit in the queue `exports` counts as interrupted; the job of
  such a queued export is cancelled when it runs, because the export is
  `failed`. A build that should still reach its end after the sweep set its
  export to `failed` removes its package and sets no status, so no `done`
  export without a package arises. Afterwards the sweep runs
  `Interop.prune_exports(:all)`.
- Retention (step 9, ASVS 15.2.2): `config :espalier, :export_retention,
  max_age_days: 7, max_packages: 100` in `config/config.exs`, read by
  `Interop.retention/0`, which raises `ArgumentError` for a value that is no
  positive integer. `Interop.prune_exports(:count)` deletes the `done`
  exports beyond the newest `max_packages` (by `updated_at`, `inserted_at`
  and id; the option `keep: id` ranks one export first), and
  `prune_exports(:all)` first deletes the `done` and `failed` exports whose
  `updated_at` lies more than `max_age_days` back, then applies the count
  rule and removes the orphans, the direct entries of `EXPORT_DIR` named
  `<uuid>.build`, `<uuid>.zip.part` or `<uuid>.zip` without an export row.
  Each rule deletes its rows with one `DELETE ... RETURNING id, file_name`
  and removes their files after the statement, through
  `Interop.remove_export_files/2` with the paths of `Interop.export_paths/1`
  and the stored file name; a failed removal is logged, and the next orphan
  step removes the file. `File.rm_rf/1` removes a symbolic link without
  following it. The worker runs the count rule with `keep:` its export after
  each change to `done` and logs `export retention not applied` when that
  step fails; the export stays `done`. A deleted export answers 404 on
  `GET /api/admin/exports/:id` and on the download.
- Pack writer (step 12): a module directory is `modules/<number>-<slug of
  the module title>/` with the number padded to two digits, and a lesson file
  is `lessons/<key>.md`. A list file is written only when its list is not
  empty, so module 2 gets no `assessment.yaml`, as in `content/demo`. A
  field without value, the empty `areas_elsewhere`, `objectives` and `cite`,
  and the empty `options` or `config` of an item are left out, because the
  normalizer fills in the same values. `ymlr ~> 5.1` encodes the strings, and
  an emitter in `PackWriter` keeps the key order of 0008 step 5 and
  double-quotes a string that a YAML reader could take for another type.
  `write/2` returns `{:ok, version}` with the version of the pack it wrote
  and error tuples (`:not_published`, `:not_empty`, `:not_directory` and
  `{:file, path, reason}`), and `mix espalier.export` prints the written
  version, or each error through `Mix.shell()` with exit status 1; the task creates
  a missing target directory and starts the application without Oban queues.
  `write_payload/2` writes any payload in the shape of the normalized map.
  The writer raises `ArgumentError` for a block body with a line that starts
  with `:::` and for a `cite` entry with a comma or a double quote, which the
  validator of 0008 admits in no pack. A pack with a draft import only has no
  program row, so the task reports an unknown program. `write/2` reads the
  program again and builds its payload from the stored row in one
  `Repo.transact` under the same shared lock and timeout as the worker, reads
  the payload before it checks the target directory, and writes the files
  after the transaction. A program struct read before a second publish
  therefore gives the version published last, and a program whose stored
  status is no longer `published` answers `{:error, :not_published}` without
  touching the path. The emitter also double-quotes the spellings of NaN and
  infinity of YAML 1.2 (`.nan`, `.NaN`, `.NAN`, `.inf`, `.Inf`, `.INF`, each
  also after `-` or `+`).
- SCORM entry (step 2): the memory router holds the route
  `/programs/:slug` with three children: an index route that redirects to
  `stations/1`, because the back link of the glossary names the program page,
  the module station and the glossary. The LMS discovery looks for
  `API_1484_11` first (500 parent steps, then the chain of `window.opener`)
  and then for `API` (7 steps), starts at the window of the SCO itself,
  counts each walk separately and accepts an object only when it has
  `Initialize` or `LMSInitialize`. An LMS that offers both APIs therefore
  runs the package with `Scorm2004Runtime`. `startRuntime` in
  `src/scorm/boot.ts` finds the API, creates the runtime of its version and
  starts it. Besides the notice without an LMS, the page shows a notice for a
  missing or invalid `content.json`, one for a runtime whose start failed,
  which includes an LMS that refuses `Initialize` or `LMSInitialize`, and one
  for a page that the browser restores from the back/forward cache after the
  runtime ended the LMS session on `pagehide` (`sessionEnded`, through the
  `pageshow` listener `onRestoredFromCache` in `boot.ts`, registered after a
  successful start). A link that leaves the page, the title link of a source
  with an http(s) URL or a Markdown link whose `href` is no fragment and
  resolves to `http` or `https`, opens in a new tab with
  `rel="noopener noreferrer"`, because a navigation of the SCO document fires
  `pagehide` and ends the LMS session. The React context
  `ExternalLinkTargetContext` in `src/player/externalLinks.ts` carries the
  target, `ScormPlayer` sets it to `"_blank"`, and the platform and the admin
  preview set none, so their links behave as in 0012. The new file in
  `src/player/` imports no API client, so the boundary check of 0012 step 15
  holds. An LMS that sandboxes the SCO iframe without `allow-popups` blocks
  these links. `scorm.html` carries the title
  "Learning module" without a favicon, and `main.tsx` sets the document title
  to the module title. The UI language is the primary subtag of the pack
  locale when the i18n files hold it, and English otherwise.
- Build (step 3): Vite 8 bundles with Rolldown, so `vite.scorm.config.ts`
  sets the input and the fixed file names in `build.rolldownOptions`
  (`output.codeSplitting: false`) and sets `build.cssCodeSplit: false`; it
  raises `chunkSizeWarningLimit` to 1,024 kB for the one chunk, and
  `tsconfig.node.json` includes the file. The `frontend` stage of the
  Dockerfile builds the player to `/out/scorm_player`, the builder stage
  copies it to `priv/scorm_player`, and `.dockerignore` leaves out the local
  player build and the schema files. `make check` runs `build:scorm` as its
  last step, because the Makefile has no `npm audit` step yet to place it
  before; 0017 appends that step.
- Runtimes (step 4): `Scorm12Runtime` and `Scorm2004Runtime` extend
  `ScormRuntime` in `src/runtimes/scorm.ts`, which composes
  `StandaloneRuntime` on `contentPayload` of `src/runtimes/content.ts` and
  takes the calls and data model elements of each version as a dialect.
  `start()` restores the suspend data and then writes the restored objective
  states, and `loadState` returns the state that the runtime holds. Each item
  answer, exam attempt and module completion writes the values that changed,
  `cmi.suspend_data` included, and commits once; an exam attempt therefore
  also writes `cmi.suspend_data`. `finish()` writes the session time
  (`cmi.core.session_time` or `cmi.session_time`). Attempt numbers continue
  across sessions. With several exams, the status is `passed` when every exam
  has a passed attempt and `failed` when any exam has a failed outcome.
  SCORM 1.2 sets `cmi.core.lesson_status` to `completed` on the module
  completion whenever no exam outcome exists (the module has no exam, or no
  exam has a failed outcome and not every exam has passed), so also for a
  module whose exam has no attempt; an exam outcome takes precedence, also
  for an attempt after the completion. For an exam of more than 100 items, SCORM 1.2 writes the
  percentage of correct answers, rounded to two decimal places, as
  `cmi.core.score.raw` with `cmi.core.score.max` 100, because its score
  elements hold 0 to 100. `cmi.score.scaled` is not written for an exam
  without items. The suspend data holds a module-completed flag, because a
  SCORM 1.2 module with an exam outcome reports `passed` or `failed` in
  `cmi.core.lesson_status`, so its completion cannot be read back from the
  LMS. A practice item counts as correct once any of its answers was correct.
  `start()` throws when `Initialize("")` or `LMSInitialize("")` does not
  answer `"true"` or throws; SCORM 2004 counts the error code 103 of
  `GetLastError()` as a started session. After a failed start the runtime
  makes no further LMS call. A failing LMS call changes nothing in the
  player; only `saveState` rejects, also for an encoding above 4,096
  characters, which the runtime then leaves out of its writes. `saveState`
  resolves without an LMS call before `start()` and rejects without one after
  `finish()` and after a failed start.
- Resume (step 4): the suspend data starts with the version `2` and a layout
  fingerprint of six base64url characters, followed by the path letter, the
  completed flag, the three bitsets and one field per assessment. The
  fingerprint is the 32-bit FNV-1a hash of the UTF-8 bytes of the item keys,
  the explanation block ids of `explanationBlockIds` and the assessment keys,
  each list in order with its members joined by `,` and the lists joined by
  `;`. A string with another fingerprint or of version `1` decodes to `null`
  and restores nothing, so progress that an LMS holds as suspend data of
  version `1` is not restored after an update of the package. The LMS keeps
  the status of the module, and the runtime writes the objective entries
  again from the empty progress.
- Suspend-data test (step 5): the test reads the demo pack through
  `import.meta.glob`, for which `frontend/vite.config.ts` allows
  `../content/demo` in `server.fs.allow`.
- Admin page (step 11): `/admin/exports` preselects the first published
  program and SCORM 1.2. The page holds the exports requested on it in its
  own state, newest first, so a reload starts with an empty list. A 404 on
  the request clears the chosen module and reads the modules of the program
  again. A finished export is read again when the window regains focus. A
  404 on the read of a listed export (`exportRemoved` in
  `src/api/exports.ts`) ends its reads, also on focus, removes its download
  link and shows the status "No longer available" with a text that the
  server keeps exports for a limited time and in a limited number.
