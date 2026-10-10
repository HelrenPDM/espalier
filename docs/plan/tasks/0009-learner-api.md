# 0009: Learner API with OpenAPI

> Milestone: M3 Learning, Depends on: 0004, 0004a, 0008

## Context to read first
- Read `docs/plan/README.md`: the intro and goal 8 (constructive alignment per topic), section 2 (principle 10), sections 5 (scopes), 6.10 (errors), 6.12 (shared interfaces and the owners of the OpenAPI operations), 7 (domain rules 1 to 6, 10, 14 and 15), 8 (API outline), 10 (`TRACKING_DETAIL`, `INSIGHTS_ORG_UNIT` and the visibility per role), 12 (`make api-types` and `make check`) and 13 (dependency cooldown).
- Read `docs/plan/tasks/0004-accounts-sessions.md`: step 11 for the scope behaviour of `phx.gen.schema`, step 32 for the `:api` and `:authenticated` pipelines, step 35 for the route table and the session payload, step 36 for the error bodies, step 37 for `:filter_parameters`, step 42 for the ownership table, the section "Addendum: implementation" for `Espalier.RuntimeConfig`, `EspalierWeb.Plugs.RateLimit.check_account/3` and the test helpers of `ConnCase`, and the Notes for the error codes.
- Read `docs/plan/tasks/0008-catalog-content-packs.md`: step 2 for the catalog fields (`Program.status`, `Assessment.kind`, `max_wrong`, `core_required`, `counts_for_credential`, `Item.core`, `Item.config`, `Option.correct`, `Option.feedback`, `CompanionFormat.attendance_counts`, and `key`, `statement`, `area`, `depth`, `phase`, `domain` and `position` of `LearningObjective`), step 3 for the join tables `item_rules`, `item_reveals`, `assessment_items`, `objective_lessons`, `item_objectives` and `format_objectives`, step 4 for `archived_at`, step 5 for the item configuration per kind, step 12 for the objectives of the demo pack, step 13 for the evidence of an objective and for `Espalier.Catalog.Alignment.matrix/1`, and the Notes on learning objectives.
- Read `docs/plan/tasks/0010-frontend-shell.md`: step 4 for `frontend/src/api/paths.ts`, from which every module of the SPA imports the `paths` type and which declares `paths` by hand for `GET /api/session` and `DELETE /api/session` when 0010 runs before this task (0010 never writes `src/api/schema.d.ts`), and step 7 for `toSession`, whose parameter type comes from the generated `paths` of `GET /api/session`.
- Read `docs/architecture/learner-journey.puml`, `docs/architecture/domain-records.puml` (package Person-linked records, and `ItemStat` in package Anonymous insights), `docs/architecture/domain-catalog.puml` (`LearningObjective` with its note and its links to `Lesson`, `Item` and `CompanionFormat`) and `docs/architecture/domain-values.puml` (`CompetenceArea`, `Depth` and `Phase`).

## Goal
A signed-in learner reads a published program, enrolls with a path, answers
practice items with server-side evaluation, takes exams under the pass rule and
completes modules. Answer keys and per-option feedback stay on the server until
the learner submits. Each module view carries the learning objectives of its
topic with the lessons that teach them and the evidence that shows them, and
each item view names the objectives it serves. `GET /api/me/progress` derives
per objective whether the learner's own records show evidence for it, and no
table stores that status. The OpenAPI document at `/api/openapi` describes the
learner routes and the routes of 0004, and the frontend generates its types
from it with `make api-types`.

## Scope
- In: The task adds the Learning schemas (`Enrollment`, `ItemResponse`, `AssessmentAttempt`, `ModuleCompletion`), the anonymous counter `ItemStat`, the evaluator, the pass rule, catalog views without answer keys, the objectives in the module view and the objective keys in the item views, `Espalier.Catalog.objective_links/2`, `Espalier.Learning.ObjectiveStatus` for the objective status in `GET /api/me/progress`, the learner controllers and routes, the stubs `Credentials.evaluate/2` and `Credentials.attended_format_ids/2`, and the variables `TRACKING_DETAIL` and `INSIGHTS_ORG_UNIT`.
- In: It adds `open_api_spex`, `EspalierWeb.ApiSpec`, the OpenAPI operations of the learner routes and of the routes of 0004 (README section 6.12), `make api-types` with its diff check in `make check`, `openapi-typescript` and `openapi-fetch` in `frontend/`, and the re-export of the generated `paths` in `frontend/src/api/paths.ts`.
- Out: The OpenAPI operations of the routes of 0005, 0006 and 0007 belong to 0011, and those of the admin routes to 0015 (README section 6.12). 0013 and 0014 add the operations of their own learner routes in `EspalierWeb.ApiSpec`. Credential logic belongs to 0013, the anonymous insight endpoints and reports to 0014, and the player and learner UI to 0012.
- Out: The objectives in the player and the client-side status `practised` belong to 0012, the attendance certificates and the implementation of `Credentials.attended_format_ids/2` to 0013, the competence report `GET /api/insights/competence` to 0014, and the `cmi.objectives` of the SCORM export to 0016. The alignment checks and the matrix belong to 0008.

## Security requirements
This list holds exactly the rows whose `Task` column names this task, as the ownership table of 0004 step 42 assigns them (README section 15, decision D16). A row marked "extends the row of" belongs to the task named there, and this task adds its code and test to that row.
- 1.1.1 (extended by 0008): `Plug.Parsers` decodes each JSON body once, and `CastAndValidate` validates the decoded value.
- 1.3.3 (extended by 0008): the request schemas of step 3 restrict the type of every member, the length of every string and list member and the values of every member with a fixed set, before a context receives it.
- 2.1.1 (extended by 0011, 0013, 0014, 0015, 0016 and 0017): the OpenAPI document at `/api/openapi` documents the request schemas of the routes of 0004 and of the learner routes (steps 13 and 15).
- 2.2.1 (extended by 0004, 0008, 0013, 0014, 0015 and 0016): every learner request is validated against its schema with `CastAndValidate`.
- 2.2.2 (extended by 0004): validation runs in `CastAndValidate` and in the changesets on the server; the checks of the SPA (0011) serve usability only.
- 2.3.1 (extends the row of 0004): a module completes only after the passed exams that count for a credential, and exam items are evaluated only inside an attempt (step 13).
- 2.4.1 (extends the row of 0004): the write routes of step 13 are limited per user with the buckets `learner_write` and `assessment_attempt`.
- 8.1.2: `docs/security/authentication.md` has a section "Learner data access" that lists, per learner route, the fields a learner reads and writes. Catalog views carry no `correct`, `feedback`, `expected` or `config` member; correctness, option feedback and referenced rules reach a learner only in the response to that learner's own submission. Request bodies carry only the members of step 13. `user_id`, `path_chosen_manually`, `started_at`, `attempt_no`, `answered_on`, `number`, `wrong_count`, `core_failed`, `outcome`, `submitted_at` and `completed_at` are set by the server. No other role reads these rows. The reports of 0014 aggregate only the anonymous rows and count credentials per qualification and status (README section 10). The objective status of `GET /api/me/progress` is computed per request from the attempts, attendance certificates and item responses of the signed-in user, and no table stores it (README section 7, rule 15).
- 8.2.2 (extended by 0013): every learner route sits behind the `:authenticated` pipeline of 0004, so a request without a session answers 401 and an enrollment or recovery session answers 403 `enrollment_required`. Person-linked rows are read and written only through the scope of the signed-in user. An enrollment id of another user answers 404. A program whose status is `draft` or `archived`, and every module, item or assessment with `archived_at` set, answers 404.
- 8.2.3: every request schema sets `additionalProperties: false`, and the changesets cast only the members of step 13. A request with an extra member such as `user_id`, `path_chosen_manually` or `outcome` answers 422 and changes no row.
- 15.3.1 (extends the row of 0004): catalog views carry no answer key and no option feedback before a submission (step 12).
- 15.3.3 (extended by 0004, 0013, 0014, 0015 and 0016): every request schema sets `additionalProperties: false`, and a request with an extra member answers 422.
- 15.3.5 (extended by 0010): `CastAndValidate` casts every member to the type of its schema before a context receives it.
- 15.3.7: each OpenAPI operation declares the location of every parameter, and `CastAndValidate` reads each one from that location.

## Steps

### OpenAPI foundation
1. Add `{:open_api_spex, "~> 3.<minor>"}` and `{:stream_data, "~> 1.<minor>", only: :test}` to `mix.exs`, each with the current minor from `nix-shell --run "mix hex.info open_api_spex"` and `nix-shell --run "mix hex.info stream_data"`, and run `make init`. The seven-day cooldown of README section 13 applies to both.
2. Write `EspalierWeb.ApiSpec` in `lib/espalier_web/api_spec.ex` with `@behaviour OpenApiSpex.OpenApi`. `spec/0` sets the title `Espalier API`, the version from `Mix.Project.config()[:version]`, read into a module attribute at compile time, the paths from `OpenApiSpex.Paths.from_router(EspalierWeb.Router)`, and two security schemes: `session_cookie` (type `apiKey`, `in: cookie`, name `__Host-espalier`) and `csrf_header` (type `apiKey`, `in: header`, name `x-csrf-token`). It ends with `OpenApiSpex.resolve_schema_modules/1`. Add `plug OpenApiSpex.Plug.PutApiSpec, module: EspalierWeb.ApiSpec` as the last plug of the `:api` pipeline of 0004, and serve the document with `get "/openapi", OpenApiSpex.Plug.RenderSpec, []` in the `/api` scope with `pipe_through :api`.
3. Write the shared schemas under `lib/espalier_web/schemas/` with the module prefix `EspalierWeb.Schemas`: `Error` with `error` (string, required) and `fields` (an object of string arrays, optional), which matches `ErrorJSON` and `FallbackController` of 0004, and one module per request and response body of steps 13 and 15. Every request schema sets `additionalProperties: false` and declares the type of every member, `maxLength` for every string member and `maxItems` for every list member, each with the limit that the member needs, and `enum` for every member with a fixed set of values (ASVS 1.3.3).
4. Write `EspalierWeb.CastErrorRenderer`, a plug that turns the errors of `OpenApiSpex.Plug.CastAndValidate` into 422 `{"error":"validation_failed","fields":{"<member>":["<reason>"]}}`, the body that 0004 uses for changeset errors. The member is the first element of the error path, and the reason is the error reason as a string, for example `unexpected_field`. The body never repeats the submitted value. Read the moduledoc of `OpenApiSpex.Plug.CastAndValidate` in the resolved release (`h OpenApiSpex.Plug.CastAndValidate` in `nix-shell --run "iex -S mix"`) for the name of the option that takes a custom renderer, and pass the module through it.

### Learning schemas
5. Generate the tables, each command through `nix-shell --run "..."`. Confirm first that `nix-shell --run "mix help phx.gen.schema"` lists the options `--scope` and `--no-scope`. With the default scope of 0004 (`config :espalier, :scopes`), `phx.gen.context` and `phx.gen.schema` add a `user_id` column, an index on it and a scope argument to the changeset, and they raise when the command also names `user_id` (0004 step 11). The four person-linked tables therefore rely on the scope, and no step adds `user_id` by hand:
   - `mix phx.gen.context Learning Enrollment enrollments program_id:references:programs path:enum:short:full path_chosen_manually:boolean started_at:utc_datetime`
   - `mix phx.gen.schema Learning.ItemResponse item_responses enrollment_id:references:enrollments item_id:references:items correct:boolean attempt_no:integer answered_on:date`
   - `mix phx.gen.schema Learning.AssessmentAttempt assessment_attempts enrollment_id:references:enrollments assessment_id:references:assessments number:integer wrong_count:integer core_failed:boolean outcome:enum:passed:failed_core:failed_errors submitted_at:utc_datetime`
   - `mix phx.gen.schema Learning.ModuleCompletion module_completions enrollment_id:references:enrollments module_id:references:modules completed_at:utc_datetime`

   `ItemStat` is an anonymous row without a user, so its command carries `--no-scope`:
   - `mix phx.gen.schema Insights.ItemStat item_stats item_id:references:items period:date org_unit:string attempts:integer correct:integer --no-scope`
6. Edit the generated migrations before they run:
   - Set `null: false` on every `user_id`, `enrollment_id`, `program_id`, `item_id`, `assessment_id` and `module_id`. Check that `user_id` carries `on_delete: :delete_all`, and set `on_delete: :delete_all` on every `enrollment_id`. The catalog references keep the generated `on_delete: :nothing`, because 0008 archives catalog rows and keeps them.
   - Add the unique indexes `enrollments (user_id, program_id)`, `item_responses (enrollment_id, item_id, attempt_no)`, `assessment_attempts (enrollment_id, assessment_id, number)`, `module_completions (enrollment_id, module_id)`, and `item_stats (item_id, period, org_unit)` with the option `nulls_distinct: false`, so that all rows without an org unit share one counter per item and month. PostgreSQL supports `NULLS NOT DISTINCT` from version 15; check that `h Ecto.Migration.index` in `nix-shell --run "iex -S mix"` lists the option for the resolved ecto_sql.
   - Remove `timestamps()` from `item_responses` and `item_stats`, in the migrations and in the schemas. `answered_on` is then the only time on an item response, and a counter row carries no time beyond its `period`. The note at `SelfAssessmentResponse` in `domain-records.puml` gives the rows of the package Anonymous insights no user key, a random primary key and only a date with day precision.
   - Give `path_chosen_manually` `null: false, default: false`, and give `attempts` and `correct` of `item_stats` `null: false, default: 0`. `period` holds the first day of the month.
7. Schemas and changesets: `Enrollment.path` is `Ecto.Enum, values: [:short, :full]` and `AssessmentAttempt.outcome` is `Ecto.Enum, values: [:passed, :failed_core, :failed_errors]`, as the generator writes them. The enrollment changeset casts `path` from the request; `program_id`, `started_at` and `path_chosen_manually` come from the context functions through `put_change/3`. The changesets of `ItemResponse`, `AssessmentAttempt` and `ModuleCompletion` receive only values that the server computes, and each declares `unique_constraint/3` on its unique index, so that a concurrent duplicate answers 422 `validation_failed` and stores nothing.
8. Protected columns: this task creates no encrypted and no hashed column. It therefore writes no rotation-only schema `Espalier.Crypto.Rotation.<Table>` in `lib/espalier/crypto/rotation/`, registers none in `Espalier.Crypto.Rotation.schemas/0` and adds no row to `docs/security/crypto-inventory.md`, and the tests under `test/espalier/crypto/` of 0003 stay green. `item_stats.org_unit` is a `plain` column in the sense of the inventory: the reports of 0014 group by it in SQL, and it is filled only with `INSIGHTS_ORG_UNIT=true` (README section 10).

### Configuration
9. Add `TRACKING_DETAIL` (`minimal` or `standard`, default `minimal`) and `INSIGHTS_ORG_UNIT` (`true` or `false`, default `false`) to `Espalier.RuntimeConfig.parse!/2` of 0004, which returns them as `learning: [tracking_detail: ..., insights_org_unit: ...]`. `config/runtime.exs` then sets `config :espalier, :learning` in every environment, and any other value stops the boot with a message that names the variable. Add both variables to the table in the moduledoc and their cases to `test/espalier/runtime_config_test.exs`. Add both with their defaults to `.env.example`; 0014 adds the remaining variables of README section 10. Add `"answer"` to the `:filter_parameters` list of 0004 step 37, so that request logs hold no answer. Phoenix filters every parameter key that contains a listed string, which covers `answers` as well.

### Evaluation
10. `Espalier.Learning.Evaluator.evaluate(item, answer)` is a pure function per item kind and returns `%{correct: boolean | nil, option_feedback: [...], rules: [...], reveals: [...]}`:
    - `single_choice` and `multiple_choice`: the answer is correct when the chosen set equals the correct set. After submission, every option carries its feedback, chosen or unchosen.
    - `slot_builder`: the answer maps each slot to an option, and it is correct when every slot has an option flagged correct. Feedback comes per slot.
    - `classification`: the answer maps each case to a category, and it is correct when the mapping equals the expected mapping. Feedback comes per case.
    - `checklist_drill`: the answer is correct when every required check is set and the initials field has 2 to 5 characters.
    - `poll`: `correct` is `nil`, and the result carries no feedback.
    `rules` lists the rules linked through `item_rules`. `reveals` lists the lesson ids of `item_reveals` and is filled only when the answer is wrong; the client decides from the path whether to expand them (README section 7, rule 3).
11. `Espalier.Learning.PassRule.evaluate(results, assessment)` returns `:passed`, `:failed_core` or `:failed_errors` as README section 7, rule 5, defines it. Write property tests with StreamData (`use ExUnitProperties`) for two properties: any wrong core item yields `failed_core`, whatever the number of wrong answers and whatever `core_required` says (README section 7, rule 5, and the note at `Assessment` in `domain-catalog.puml`; in 0008, `core_required` only demands that an exam has a core item); with no core item wrong, the outcome is `passed` exactly when the wrong answers are at most `max_wrong`.

### Catalog views
12. `EspalierWeb.CatalogJSON` renders only programs with status `published` and only modules, lessons, learning objectives, items, rules, assessments and companion formats without `archived_at`:
    - The program carries its stations, its segments (key, label, description, default path), its modules (number, title, summary, phases, `single_path`) and its companion formats (`id`, `key`, `title`, `description`, `phases`, `attendance_counts`, schema `CompanionFormatView`), so that the format evidence of an objective resolves to a title.
    - The module detail carries its lessons, blocks (kind, body, provenance, `collapsed_on`, `placeholder_key`, citations with their source), rules, practice items, the exams with their metadata (`id`, `key`, `title`, `max_wrong`, `counts_for_credential`) and their items, and its objectives.
    - `objectives` holds one entry per learning objective of the module, in `position` order, with the schema `ObjectiveView`: `key`, `statement`, `area` (`subject`, `method`, `self` or `social`), `depth` (`know`, `apply` or `judge`), `phase` (`orient`, `understand`, `apply`, `anchor` or `update`), `domain` (a string or `null`), `lesson_ids` and `evidence`. `lesson_ids` holds the ids of the teaching lessons from `objective_lessons`, in lesson `position` order. `evidence` is a list of entries `{kind, id}` with the schema `ObjectiveEvidence`, where `kind` is `item` or `format`; the items come first, ordered by key, and the formats follow, ordered by key.
    - Evidence follows 0008 step 13. An item linked through `item_objectives` counts when an assessment without `archived_at` lists it or when its kind has a correct answer (every kind except `poll`, so `checklist_drill` counts). A companion format linked through `format_objectives` counts when it has `attendance_counts: true`. A row with `archived_at` set counts for nothing. An item can name an objective of another module (0008 step 8), so an evidence id can point to an item that the view of another module of the program carries.
    - `Espalier.Catalog.objective_links(program_id, opts)` reads the objectives of a program, or of one module with the option `module_id:`, with a fixed number of queries over `learning_objectives`, the three join tables of 0008 step 3, `assessment_items` and the parent rows, whatever the number of objectives. It returns per objective the struct, `lesson_ids`, `item_ids` (the evidence items), `format_ids` (the evidence formats) and `assessment_ids` (the assessments without `archived_at` that list an evidence item). The module view and the objective status of step 13 both read objectives through this function, so that both follow one evidence rule.
    - Items expose `id`, `key`, `kind`, `stem`, `provenance` and `objective_keys` (the sorted keys of their objectives without `archived_at`), options with `key` and `label`, slots with their options, cases and categories without the expected mapping, and checks with `key`, `label` and `required`. The raw `config` of an item is never rendered.
    - The glossary lists slug, label and short text per term.
    A test serializes every demo item, practice and exam, and asserts that the JSON contains none of the keys `correct`, `feedback`, `expected` and `config`.

### Learner routes
13. Controllers and routes, all in the `/api` scope with `pipe_through [:api, :authenticated]`. Each controller has `use OpenApiSpex.ControllerSpecs`, an `operation` per action, and `plug OpenApiSpex.Plug.CastAndValidate` with the renderer of step 4. The context functions take the scope as first argument:
    - `GET /api/programs` lists the published programs with slug, title and locale. `GET /api/programs/:slug`, `GET /api/modules/:id` and `GET /api/programs/:slug/glossary` render the views of step 12. `GET /api/programs/:slug/handbook` returns the rules with statement and action grouped by module, plus the keys of the program's `placeholder` blocks (README section 7, rule 10).
    - `POST /api/enrollments {program_slug, path}` creates the enrollment of the scope user with `started_at` set to now and answers 201. When the enrollment exists, the route answers 200 with it and applies the given path only while `path_chosen_manually` is false, so that the self-assessment of 0014 keeps a manual choice.
    - `PATCH /api/enrollments/:id {path}` sets `path` and `path_chosen_manually: true`.
    - `POST /api/items/:id/responses {answer}` accepts items that belong to no exam; an exam item answers 404, because exam items are evaluated only inside an attempt. The route needs an enrollment of the scope user in the item's program and answers 409 `{"error":"not_enrolled"}` otherwise. It returns the evaluator result. In one transaction it upserts the `ItemStat` of the current month with `on_conflict: [inc: [attempts: 1, correct: c]]`, where `c` is 1 for a correct answer and 0 for any other, and `conflict_target: [:item_id, :period, :org_unit]`, with `org_unit` from the user only when `INSIGHTS_ORG_UNIT=true`. With `TRACKING_DETAIL=standard`, it also inserts an `ItemResponse` with the next `attempt_no` for this enrollment and item and `answered_on` set to today. A poll answer increments `attempts` only and inserts no `ItemResponse`. The answer itself is stored nowhere (README section 10).
    - `POST /api/assessments/:id/attempts {answers}` accepts assessments of kind `exam`. `answers` maps every item id of the exam to an answer, and a missing or unknown item id answers 422 `{"error":"validation_failed","fields":{"answers":["incomplete"]}}`. The route needs the enrollment (409 `not_enrolled` otherwise). It evaluates all items, applies the pass rule, stores the attempt with the next `number`, `wrong_count`, `core_failed`, `outcome` and `submitted_at`, and returns `outcome`, `wrong_count`, `core_failed` and the evaluator result per item. The attempt row holds no answers.
    - `POST /api/modules/:id/completion` needs the enrollment (409 `not_enrolled` otherwise). It answers 200 with `completed_at` when every exam of the module with `counts_for_credential: true` has a passed attempt of the enrollment, and a repeated call answers 200 with the stored row. Otherwise it answers 409 `{"error":"assessments_open","assessments":[{"id": "...", "key": "...", "title": "..."}]}`.
    - The write routes are limited per user (ASVS 2.4.1). Add the buckets `learner_write: {:timer.minutes(1), 120}` and `assessment_attempt: {:timer.minutes(10), 10}` to `config :espalier, :rate_limits` in `config/config.exs` (0004 step 34), and add both keys with `{:timer.minutes(1), 1_000_000}` to the map in `config/test.exs`, which replaces the map of `config/config.exs` as a whole. The actions of `POST /api/enrollments`, `PATCH /api/enrollments/:id`, `POST /api/items/:id/responses` and `POST /api/modules/:id/completion` first call `EspalierWeb.Plugs.RateLimit.check_account(conn, :learner_write, scope.user.id)` of 0004, `POST /api/assessments/:id/attempts` calls it with `:assessment_attempt`, and each action continues only when `conn.halted` is false. A denial answers 429 `rate_limited` with `retry-after` and logs `excess_rate_limit_exceeded` with the bucket in `reason`, and the operations of these routes list the 429 answer with the schema `Error`. The numbers are initial values; README section 6.10 sets none for these buckets.
    - `GET /api/me/progress?program=slug` returns the enrollment (`id`, `path`, `path_chosen_manually`) or `null`, the ids of the completed modules, and per exam the outcome `passed` when any attempt passed and otherwise the outcome of the latest attempt. With `TRACKING_DETAIL=standard`, it adds the ids of the answered items. It also returns `objectives`, a list of entries `{key, status}` with the schema `ObjectiveProgress`, one per learning objective of the program without `archived_at`, ordered by module number and `position`, with `status` `evidenced` or `open` from `Espalier.Learning.objective_status/2` below. The list is present when `enrollment` is `null`, because an attendance certificate belongs to the user and needs no enrollment.
    - `Espalier.Learning.ObjectiveStatus.derive(links, facts)` is a pure function. `links` is the result of `Catalog.objective_links/2` for the program. `facts` holds three sets: `passed_assessment_ids` (the assessments with an attempt of the enrollment whose outcome is `passed`), `attended_format_ids` (from `Espalier.Credentials.attended_format_ids(scope, program)` of step 14) and `correct_item_ids` (the items with an `ItemResponse` of the enrollment whose `correct` is true). An objective is `evidenced` when one of its `assessment_ids` lies in `passed_assessment_ids`, when one of its `format_ids` lies in `attended_format_ids`, or when one of its `item_ids` lies in `correct_item_ids`. Every other objective is `open`.
    - `Espalier.Learning.objective_status(scope, program)` collects the facts through the scope and calls `derive/2`. It reads `item_responses` only with `TRACKING_DETAIL=standard`; with `minimal`, `correct_item_ids` is empty. Without an enrollment, `passed_assessment_ids` and `correct_item_ids` are empty. The SPA adds the status `practised` from its local practice state (0012). No table of this task stores a status per objective and person (README section 7, rule 15).
14. After a passed attempt and after a module completion, call `Espalier.Credentials.evaluate(scope, program)`. In this task, `lib/espalier/credentials.ex` holds the module with `evaluate/2` returning `{:ok, []}` and `attended_format_ids/2` returning `[]`, and 0013 implements both. In 0013, `attended_format_ids/2` returns the ids of the companion formats of the program for which the scope user holds an attendance certificate.

### Operations for the routes of 0004
15. README section 6.12 assigns the OpenAPI operations of the routes of 0004 to this task. Add `use OpenApiSpex.ControllerSpecs` and an `operation` to every action of the route table of 0004 step 35: `GET /auth/providers`, `GET /api/session`, `DELETE /api/session`, `POST /api/auth/password`, `POST /api/auth/invitations`, `POST /api/auth/invitations/accept`, `POST /api/auth/demo`, `GET /api/me/sessions`, `DELETE /api/me/sessions/:id`, `PUT /api/me/password`, `PUT /api/me/email` and `POST /api/me/email/confirm`.
    - Request and response schemas take their member names from the controllers, JSON views and tests of 0004: the payload of `EspalierWeb.SessionJSON` (0004 step 35, with every member, among them `session.provider_key`) becomes the schema `SessionPayload`, the password sign-in answers `{"next":"second_factor"}`, and `PUT /api/me/password` takes `current_password` and `password` (README section 8).
    - The 200 answer of `GET /api/session` names `SessionPayload` under the content type `application/json`. `toSession` of 0010 step 7 takes its parameter type from `paths["/api/session"]["get"]["responses"][200]["content"]["application/json"]`, and `tsc -b` in `make check` confirms that the generated type has this shape.
    - Each operation lists the error statuses its route returns, with the schema `Error` and the codes that the plugs and controllers of 0004 return for that route.
    - The operations describe the routes and add no `CastAndValidate`, so the validation and the error bodies of 0004 stay as they are.
    - `DELETE /api/session` is described with its 204 answer. The 200 answer with `logout_url` comes from 0006, and its operation belongs to 0011 (README section 6.12).
    - `GET /auth/providers` lies outside `/api` and appears in the document all the same, because `OpenApiSpex.Paths.from_router/1` reads every route whose controller defines operations.

### Types for the frontend
16. `make api-types` and the frontend packages:
    - Install in `frontend/`, through `nix-shell --run`, `openapi-fetch` as a dependency and `openapi-typescript` as a dev dependency. 0010 installs `openapi-fetch` only when it is missing.
    - Add the script `"api-types": "openapi-typescript openapi.json -o src/api/schema.d.ts"` to `frontend/package.json`.
    - Read `nix-shell --run "mix help openapi.spec.json"` and use the option names it lists. Add the target
      ```make
      api-types: ## Write frontend/openapi.json and frontend/src/api/schema.d.ts from EspalierWeb.ApiSpec
      	$(NIX) "mix openapi.spec.json --spec EspalierWeb.ApiSpec --pretty=true frontend/openapi.json"
      	$(NIX) "npm --prefix frontend run api-types"
      ```
      When the resolved release offers `--start-app=false`, add it to the first command, so that the target runs without database and keys. The mix task and `GET /api/openapi` both read `EspalierWeb.ApiSpec`, so the file holds the served document.
    - Extend `make check` with the diff check of README section 12: `$(MAKE) api-types`, followed by `git diff --exit-code -- frontend/openapi.json frontend/src/api/schema.d.ts`.
    - Add `openapi.json` to `frontend/.prettierignore`, next to `src/api/schema.d.ts` from 0002.
    - Check that `frontend/src/api/schema.d.ts` is the generated file: after `make api-types` it starts with the header comment that openapi-typescript writes, and it holds `paths` for every route of steps 13 and 15.
    - When 0010 has landed, `frontend/src/api/paths.ts` declares `paths` by hand (0010 step 4). Replace that declaration with `export type { paths } from "./schema";`, so that the file holds the re-export and no declaration of its own. Check that `src/api/client.ts` imports `paths` from `./paths` and that no module of the SPA declares `paths` elsewhere. When 0010 lands after this task, 0010 step 4 writes `paths.ts` with the re-export.
    - Commit `frontend/openapi.json`, `frontend/src/api/schema.d.ts` and, when this step changed it, `frontend/src/api/paths.ts`.

### Tests and documentation
17. Write at least these tests:
    - Evaluator tests per item kind assert correctness, feedback for unchosen options, rules, and `reveals` only on a wrong answer.
    - The view test of step 12 covers every demo item.
    - Controller tests use the test support of 0004: `api_conn/0` and `next_request/1` run the real CSRF check, so every POST, PUT, PATCH and DELETE request carries a token from `with_csrf_token/1`, also the signed-out request that expects 401, because `protect_api_from_forgery/2` runs before `:authenticated`, and a test fetches a new token after a sign-in, which rotates it. `put_setting/2` sets `:learning` for one test, for example `put_setting(:learning, tracking_detail: :standard, insights_org_unit: false)`, and a module that calls it sets `async: false`.
    - Rate limit tests run with `async: false` and `put_rate_limit/2` of 0004: with `put_rate_limit(:learner_write, {:timer.minutes(1), 2})`, the third `POST /api/items/:id/responses` of one user within a minute answers 429 with `retry-after`, and a request of another user passes; with `put_rate_limit(:assessment_attempt, {:timer.minutes(10), 1})`, the second attempt of one user answers 429.
    - `PATCH /api/enrollments/:id` with `path` in the query string and an empty body answers 422 `validation_failed`, because `CastAndValidate` reads `path` from the body only (ASVS 15.3.7), and a string member above its `maxLength` answers 422 as well (ASVS 1.3.3).
    - Controller tests assert that every learner route answers 401 without a session and 403 `enrollment_required` with an enrollment session; that `PATCH /api/enrollments/:id` with the enrollment of another user answers 404; that a body with `user_id`, `path_chosen_manually` or `outcome` answers 422 `validation_failed` and leaves every row unchanged; that an exam item on `POST /api/items/:id/responses` answers 404; that a draft program and an archived module answer 404; that two `POST /api/enrollments` calls leave one row and keep a manual path; and that two answers by users without an org unit leave one `item_stats` row with `attempts` 2.
    - `test/espalier_web/api_spec_test.exs` asserts that `EspalierWeb.ApiSpec.spec().paths` holds an operation for every route of steps 13 and 15 and that every 2xx response other than 204 names a schema. One controller test per learner route checks its JSON body with `OpenApiSpex.TestAssertions.assert_schema/3`. The schemas `ObjectiveView`, `ObjectiveEvidence`, `ObjectiveProgress` and `CompanionFormatView` list the allowed values of `area`, `depth`, `phase`, `kind` and `status` as enums, and the checks of `GET /api/programs/:slug`, `GET /api/modules/:id` and `GET /api/me/progress` cover them.
    - Objective views, with the demo pack: the view of module 1 carries five objectives in `position` order with `area`, `depth`, `phase` and `domain` as in its `objectives.yaml`, and every `lesson_ids` entry is a lesson of module 1. `m1-self-own-responsibility` and `m1-social-team-transparency` each carry the evidence `[{kind: "format", id: <id of workshop>}]`, and `m1-subject-next-word` carries at least one exam item. The view of module 2 carries three objectives, and `m2-method-release-check` carries the `checklist_drill` item. Every exam item carries one objective key, and the poll carries `objective_keys: []`. The program view lists the three companion formats. For every row of `Espalier.Catalog.Alignment.matrix/1` on the demo program, the evidence of the row's objectives in the module views, written as `item:<key>` and `format:<key>`, equals the row's `evidence`. After a second publish of a copy in which `m1-subject-varying-answers` is removed and the items that named it name `m1-subject-next-word`, no module view, no `objective_keys` list and no progress answer names `m1-subject-varying-answers`.
    - `ObjectiveStatus.derive/2`: an objective is `evidenced` through a passed assessment that lists one of its evidence items, through an attended format among its evidence formats, and through a correct item response of one of its evidence items. It stays `open` with three empty sets, when the passed assessment lists none of its evidence items, and when the attended format is missing from its evidence formats.
    - Objective status on `GET /api/me/progress`, with the demo pack and `TRACKING_DETAIL=minimal` unless stated: after `POST /api/enrollments`, all eight objectives are `open`, ordered by module number and `position`. A failed attempt of `module-1-exam` leaves them `open`. A passed attempt sets `m1-subject-next-word`, `m1-subject-varying-answers` and `m1-method-check-claims` to `evidenced` and leaves the other five `open`. A passed attempt of another user leaves every objective of the scope user `open`. With `TRACKING_DETAIL=standard`, a correct answer to the `checklist_drill` item sets `m2-method-release-check` to `evidenced`, and a wrong answer leaves it `open`. With `minimal`, the correct answer leaves it `open`. Without an enrollment, the answer carries `enrollment: null` and eight `open` entries. Evidence through attendance is covered here by `derive/2`; the route test with an attendance certificate needs the table of 0013 and belongs to 0013.
    - A schema test reads `information_schema.columns` and asserts that `item_stats` has no `user_id`, `inserted_at` or `updated_at`, that `item_responses` has no `inserted_at` or `updated_at`, that no table of this task has a column named `answer` or `answers`, and that no table of this task has a column whose name contains `objective`.
18. Write the section "Learner data access" of 8.1.2 in `docs/security/authentication.md`. It also lists the `objectives` of the module view, the `objective_keys` of the item views and the `objectives` of `GET /api/me/progress`, and it states that the objective status is derived per request from the user's own attempts, attendance certificates and, with `TRACKING_DETAIL=standard`, item responses, and that no table stores it. Add the code and the test of this task to every row of `docs/security/asvs-l2.md` that the section "Security requirements" lists, as the ownership table of 0004 step 42 assigns them, and state in `Notes` what this task delivers. Set 8.1.2, 8.2.3 and 15.3.7 to `verified`. Keep 8.2.2 `open`, and state in its `Notes` column that 0013 adds the credential routes. Every other row stays `open` until each task it names has added its code and test.

## Deliverables
- `mix.exs` lists `open_api_spex` and `stream_data`, and `Espalier.RuntimeConfig`, `config/config.exs`, `config/test.exs` and `.env.example` carry the changes of steps 9 and 13.
- Migrations and schemas exist for `enrollments`, `item_responses`, `assessment_attempts`, `module_completions` and `item_stats`, together with `lib/espalier/learning.ex` with `objective_status/2`, `lib/espalier/learning/{enrollment,item_response,assessment_attempt,module_completion,evaluator,pass_rule,objective_status}.ex`, `Espalier.Catalog.objective_links/2` in `lib/espalier/catalog.ex`, `lib/espalier/insights.ex` with the `ItemStat` upsert, `lib/espalier/insights/item_stat.ex` and the stub `lib/espalier/credentials.ex` with `evaluate/2` and `attended_format_ids/2`.
- The web code consists of `lib/espalier_web/api_spec.ex`, `lib/espalier_web/schemas/` (including `ObjectiveView`, `ObjectiveEvidence`, `ObjectiveProgress` and `CompanionFormatView`), `EspalierWeb.CastErrorRenderer`, the learner controllers with `CatalogJSON` and the other JSON views, the routes, and the operations on the controllers of 0004.
- `frontend/openapi.json`, `frontend/src/api/schema.d.ts`, the `api-types` script in `frontend/package.json`, the extended `frontend/.prettierignore`, and the `api-types` target with its diff check in `make check` exist. When 0010 has landed, `frontend/src/api/paths.ts` holds the re-export of step 16.
- `docs/security/authentication.md` has the section "Learner data access", and `docs/security/asvs-l2.md` names code and test in the rows of this task.
- The tests of step 17 exist.

## Acceptance
- [ ] `nix-shell --run "mix test"` passes, including the property tests of the pass rule and the test that no answer key leaves the server before a submission.
- [ ] With the demo pack, an exam attempt with the core item wrong returns `failed_core`, one wrong non-core item returns `passed`, and two wrong non-core items return `failed_errors`.
- [ ] With `TRACKING_DETAIL=minimal`, answering a practice item creates no `item_responses` row and increments `item_stats`. With `standard`, both happen.
- [ ] `POST /api/modules/:id/completion` for module 1 answers 409 `assessments_open` before and 200 after a passed exam.
- [ ] With the demo pack, `GET /api/modules/:id` for module 1 carries five objectives with `area`, `depth`, `phase`, `domain`, `lesson_ids` and `evidence`, and every item of the view carries `objective_keys`.
- [ ] With the demo pack, `GET /api/me/progress?program=ai-assistant-basics-demo` lists eight objectives, all `open` after the enrollment, and `m1-subject-next-word`, `m1-subject-varying-answers` and `m1-method-check-claims` `evidenced` after a passed attempt of `module-1-exam`.
- [ ] With `TRACKING_DETAIL=minimal`, a correct answer to the `checklist_drill` item leaves `m2-method-release-check` `open`. With `standard`, it becomes `evidenced`.
- [ ] For every row of the alignment matrix of the demo program, the evidence in the module views equals the evidence of the row, as the test of step 17 shows.
- [ ] With `make run`, `curl -s localhost:4000/api/openapi | jq -r '.paths | keys[]'` lists every path of steps 13 and 15, with path parameters in the form `{slug}` and `{id}`.
- [ ] With `make run`, `diff <(curl -s localhost:4000/api/openapi | jq -S .) <(jq -S . frontend/openapi.json)` prints nothing.
- [ ] A second run of `make api-types` leaves `git diff --exit-code -- frontend/openapi.json frontend/src/api/schema.d.ts` at exit status 0.
- [ ] When 0010 has landed, `frontend/src/api/paths.ts` holds `export type { paths } from "./schema";` and no declaration of `paths`, `src/api/client.ts` imports `paths` from `./paths`, and `tsc -b` in `make check` compiles `toSession` of 0010 step 7 against the generated type.
- [ ] `nix-shell --run "mix test test/espalier/crypto"` passes.
- [ ] `nix-shell --run "mix test test/espalier_web/csrf_coverage_test.exs"` of 0004 passes and covers the mutating routes of step 13.
- [ ] Every field that `docs/architecture/domain-records.puml` shows for `Enrollment`, `ItemResponse`, `AssessmentAttempt`, `ModuleCompletion` and `ItemStat` exists in the schemas with the type the diagram gives. `ItemStat.period` is a `date` on the first day of the month, as the diagram states.
- [ ] The rows of `docs/security/asvs-l2.md` for the listed requirements name the code and the test.
- [ ] `make check` passes.

## Notes
- The evaluator is the only code that reads `correct`, `feedback` and `expected` values. The views stay free of those fields, so a later change cannot leak them by accident.
- `answered_on` is a date. Person-linked records need no finer time for their purpose.
- A learner sees the feedback of exam items after each attempt, and a new attempt is always possible (README section 7, rule 5). The responses route therefore rejects exam items, so that the exam stays the only place where they are evaluated.
- `GET /api/openapi` is public. It describes the routes of the published source code and holds no data of the instance. ASVS 13.4.5 belongs to 0017 in the ownership table of 0004.
- ASVS 8.2.1 belongs to 0004 in the ownership table of 0004 step 42, extended by 0013, 0014 and 0015. The learner routes of this task use the `:authenticated` pipeline of 0004, and the controller tests of step 17 check its 401 and 403 answers under row 8.2.2.
- 0014 generates its anonymous tables in the context `Espalier.Insights` and appends its functions to `lib/espalier/insights.ex`, which this task creates with the `ItemStat` upsert.
- The routes of 0005, 0006 and 0007 have no operations after this task. 0011 adds them (README section 6.12), and `make api-types` then regenerates both files.
- The objective status is derived on every request from rows that exist for other purposes: exam attempts, attendance certificates and, with `TRACKING_DETAIL=standard`, item responses. With `minimal`, the server status covers exam outcomes and attendance, and the practice state stays in the browser (README section 7, rule 15). The SPA of 0012 derives `practised` from that state and the `objective_keys` of the items.
- A passed attempt counts for every objective that an item of its assessment names, including an item answered wrong within `max_wrong`. The attempt row holds no result per item (step 13), and the outcome `passed` is the evidence that the exam provides.
- `Credentials.attended_format_ids/2` returns `[]` until 0013 creates `attendance_certificates`. Until then, a format provides evidence in the module view and sets no objective to `evidenced`.
- The competence report of 0014 groups the anonymous `item_stats` by the area and depth of the objectives through `item_objectives`, and the SCORM export of 0016 writes the objectives of a module to `cmi.objectives`. Both read the objectives of 0008 directly, and neither adds a column to the tables of this task.

## Addendum: implementation
The implementation departs from the steps above in the points below, and later
tasks rely on the implemented form.

- Dependencies (step 1): `open_api_spex` 3.22.4 and `stream_data` 1.4.0.
  `.formatter.exs` imports the formatter of `open_api_spex`, so `operation`,
  `tags` and `security` stand without parentheses. `stream_data` is a test
  dependency, which `import_deps` cannot name in the development
  environment, so `check all(...)` keeps its parentheses.
- OpenAPI document (steps 2 and 16): `OpenApiSpex.Plug.RenderSpec` serves the
  document without the vendor extensions `x-struct`, `x-validate` and
  `x-parameter-content-parsers`, and `mix openapi.spec.json` writes them by
  default, so `make api-types` passes `--vendor-extensions=false` together
  with `--start-app=false`. `config/dev.exs` sets
  `config :open_api_spex, :cache_adapter, OpenApiSpex.Plug.NoneCache`, so
  that a reloaded controller shows its operation in `GET /api/openapi`.
  `EspalierWeb.ApiSpec.Responses` builds the error answers of every
  operation (schema `Error`, the codes of the route in the description, and
  `retry-after` on 429) and the security requirements `session_cookie` and
  `csrf_header`.
- Schemas (step 3): every module calls `OpenApiSpex.schema/2` with
  `struct?: false, derive?: false`, so `CastAndValidate` hands the
  controllers maps with atom keys for the members of a schema and string
  keys inside the maps `slots`, `cases` and `answers`. Response schemas set
  `additionalProperties: false` and list every member as required unless it
  is optional by design (`answered_item_ids`, the members of a feedback
  entry), so `assert_schema/3` fails on an undocumented member.
  `EspalierWeb.Schemas.Fields` holds the shared member schemas: keys and
  slugs follow the key format of content packs with at most 255 characters;
  the pattern `^[a-z0-9][a-z0-9-]*$(?!\n)` keeps the `$` of PCRE from
  matching before a final line break. OpenAPI 3.0 has no `propertyNames`,
  so the keys of the maps `answers`, `slots` and `cases` are bounded by their
  number and checked against the item before any evaluation.
  The answer bounds are 100 entries per list or map, 16 characters of
  initials, and 200 exam answers; the pack format sets no bound on the
  number of options, slots, cases or checks, so an item with more than 100
  of them cannot be answered. The schemas of the routes of 0004 document
  `email` with at most 160 and `password` and `current_password` with at
  most 128 characters, and `current_password` as optional, because an
  enrollment or recovery session sets the password without it. The 409
  answer of `POST /api/modules/{id}/completion` is `oneOf`
  `AssessmentsOpenError` and `Error`. `POST /api/modules/{id}/completion`
  takes the optional body `EmptyRequest`, so a body with a member answers
  422.
- Cast errors (step 4): the renderer is passed through the option
  `render_error:`. An error without a path (a missing or unsupported
  `content-type`, a body that is no JSON object) has the member `body`.
  `Plug.Parsers` puts a body that is no object under `_json`, and
  `CastAndValidate` 3.22.4 then validates only the value under that key and
  leaves the other members unchecked (`OpenApiSpex.Operation2`), so a body
  object with the member `_json` passed validation and crashed the write
  actions. `EspalierWeb.Plugs.JsonObjectBody` runs before `CastAndValidate`
  in the four controllers with a body and answers 422
  `{"fields":{"body":["invalid_type"]}}` for every body with `_json`.
- Migrations (step 6): besides the references, `path`, `started_at`,
  `attempt_no`, `answered_on`, `number`, `wrong_count`, `outcome`,
  `submitted_at`, `completed_at` and `period` are `NOT NULL`, because the
  server always sets them. A composite unique index replaces the generated
  index on its first column (`enrollments.user_id`, `enrollment_id` of the
  three record tables, `item_stats.item_id`). The help text of
  `mix phx.gen.schema` in Phoenix 1.8.15 does not list `--scope` and
  `--no-scope`; both switches exist in `lib/mix/tasks/phx.gen.schema.ex`.
  The generated create, update, delete and subscribe functions of
  `Espalier.Learning` are replaced by the functions of step 13, and the
  generated test and fixture module by the tests of step 17 and
  `Espalier.LearningFixtures` (the published demo pack and answers built
  from the answer key).
- Schemas (step 7): the generated `*_id` fields are `belongs_to`
  associations (`program`, `enrollment`, `item`, `assessment`, `module`),
  and `user_id` stays a field of the scope. `Espalier.Learning` sets the
  values of `ItemResponse`, `AssessmentAttempt` and `ModuleCompletion`, their
  references included, on the struct, and their changesets cast nothing:
  `changeset/2` puts `user_id` from the scope, checks the required fields and
  declares the unique constraint, so no member of these rows is assignable
  from outside the context (review of PR #24). `ItemStat.changeset/1`
  follows the same form.
- Evaluation (step 10): an answer carries the members `options`
  (`single_choice`, `multiple_choice`, `poll`), `slots` (`slot_builder`),
  `cases` (`classification`), or `checks` and `initials`
  (`checklist_drill`). `Evaluator.validate/2` rejects an answer that uses a
  member of another kind, misses a member of its kind (the answer of a
  checklist drill always includes `initials`, 0008 step 5), or names a key
  that the item does not have; `POST /api/items/{id}/responses` then answers
  422 `{"fields":{"answer":["invalid"]}}`, an exam attempt 422
  `{"fields":{"answers":["invalid"]}}`, and nothing is counted. The initials
  count after trimming. `option_feedback` holds per option `key`,
  `selected`, `correct` (the option is correct) and `feedback`; per slot
  `key`, `choice`, `correct` and the `feedback` of the chosen option; per
  case `key`, `choice`, `expected`, `correct` and `feedback`; per check
  `key`, `selected`, `required` and `correct`. Rules carry `id`, `number`,
  `statement` and `action`.
- Pass rule (step 11): `PassRule.evaluate/2` takes results
  `%{core: boolean, correct: boolean | nil}` (only `false` counts as wrong)
  and requires an integer `max_wrong`; `wrong_count/1` and `core_failed?/1`
  fill the attempt row.
- Catalog views (step 12): `Espalier.Catalog` has the learner reads
  `list_published_programs/0`, `get_published_program/1`, `program_view/1`,
  `module_view/1`, `glossary/1`, `handbook/1`, `learner_item/1`,
  `learner_exam/1`, `learner_module/1`, `credential_exams/1` and
  `objective_keys/1`. A row of an archived module counts as archived, as in
  `Alignment.matrix/1`. The module view lists `practice_items` (the live
  items of the module that no live exam lists) and `exams` (assessments of
  kind `exam`); assessments of kind `practice` are not rendered, and their
  items appear among the practice items. An item carries `lesson_id`
  (`null` for exam items), and rules carry their citations. A station
  carries `question`, `intro` and `questions` (with `key`, `kind`, `label`
  and options) instead of its `config`, so no catalog view has a `config`
  member. `objective_links/2` runs five queries.
- Learner routes (step 13): `POST /api/items/{id}/responses` answers 200,
  `POST /api/assessments/{id}/attempts` 201 with `id`, `assessment_id`,
  `number`, `submitted_at` and the results per item in exam order, and
  `POST /api/modules/{id}/completion` 200. An exam item is an item that a
  live exam lists; an archived exam keeps its join rows and makes no item an
  exam item. The writes of one enrollment lock its row, so attempt and
  response numbers and a concurrent path change do not race; two concurrent
  first enrollments of one user answer 422 `validation_failed` for the
  second. `PATCH /api/enrollments/{id}` also answers 404 for an enrollment
  in a program that is no longer published. The org unit of `item_stats`
  is the user's org unit trimmed and cut to 255 code points
  (`Espalier.Insights.org_unit/1`), because the directory delivers it
  without a length bound and the column is `varchar(255)`; a blank value or
  one with U+0000 counts as no org unit. `FallbackController` maps `not_enrolled`
  (409), `{:answers, code}` and `:invalid_answer` (422) and
  `{:assessments_open, exams}` (409). Per exam, the progress answer lists
  `assessment_id` and `outcome`.
- Operations of 0004 (step 15): `PUT /api/me/password` lies in the
  `:enrollment` pipeline since task 0005, so its operation lists 403
  `forbidden` for demo sessions in place of `enrollment_required`.
- Frontend (step 16): `openapi-typescript` 7.13.0 declares the peer
  dependency `typescript ^5.x`, and the frontend uses TypeScript 6.0. The
  `overrides` entry of `frontend/package.json` gives `openapi-typescript`
  the project's TypeScript, and `tsc -b` compiles the generated file.
  `openapi-fetch` 0.17.0 and `openapi-typescript` were installed with
  `npm install --before` seven days back, because npm offers no cooldown
  setting. Task 0010 has not landed, so `frontend/src/api/paths.ts` does
  not exist yet, and 0010 step 4 writes it with the re-export.
- Tests (step 17): `ConnCase.json_request/5` sends a JSON body with
  `content-type: application/json` through the CSRF check, because
  `Phoenix.ConnTest` sends a map body as `multipart/mixed`, which
  `CastAndValidate` rejects.
- Verification matrix (step 18): 1.1.1, 1.3.3, 2.2.2 and 2.3.1 are
  `verified` as well, because every task they name has landed.
- Acceptance: the `curl` checks ran against a server with
  `PHX_SERVER=true MIX_ENV=test PORT=4100`, because a development server can
  hold port 4000.
