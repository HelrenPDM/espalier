# Course YAML building blocks

A course in Espalier is a content pack: a directory of YAML and Markdown files,
with an optional folder of media files, that defines one program with its
modules, lessons, practice items, exams, learning objectives and credentials. This chapter introduces the files of a
pack, shows how they refer to each other and follows a pack from an edited
file to a published course. It orients and does not list every field. The
field tables, the limits and every validator message are in
[`content-packs.md`](content-packs.md), which is the reference to read next.

## The pack as the course definition

A pack is plain text, so an organization keeps it in its own Git repository
next to its review process ([plan](../plan/README.md) section 1, goal 5). Four tools read the
same files: `mix espalier.validate`, `mix espalier.import`, the pack upload of
the admin area and the pack workbench. `mix espalier.export` writes a published
program back into this format. The repository ships one pack,
[`content/demo/`](https://github.com/HelrenPDM/espalier/tree/main/content/demo), which uses every file, block kind and
item kind.

Three conventions hold for every file. A key, slug, code, module directory name
and lesson key matches `^[a-z0-9][a-z0-9-]*$`. A field that the schema does
not know is an error, and a value must have the type of its field, so a
version or a date is quoted to be a string. Every block and item shows its
provenance (`invented`, `sourced`, `vendor_statement`, `assumption` or
`placeholder`), which the player renders as a badge (plan section 2,
principle 4). A pack holds course content and no personal data of learners or
staff.

## Directory tree

```text
my-pack/
├── pack.yaml
├── sources.yaml
├── glossary.yaml
├── segments.yaml
├── stations.yaml
├── feedback.yaml
├── qualifications.yaml
├── formats.yaml
├── media/
│   ├── release-checks.svg
│   └── module-1/
│       ├── assistant-demo.webm
│       └── assistant-demo-en.vtt
└── modules/
    └── 01-first-module/
        ├── module.yaml
        ├── objectives.yaml
        ├── rules.yaml
        ├── items.yaml
        ├── assessment.yaml
        └── lessons/
            └── 01-first-lesson.md
```

`Espalier.Catalog.Pack.Loader` reads exactly these names, so a `README.md` in
the pack directory stays unread, and it rejects symbolic links. It keeps the
files below `media/` with their paths and sizes and reads none of them. The
number of a module comes from `number` in `module.yaml`. The name of the module
directory carries no meaning of its own.

## The building blocks

| File | Required | Purpose | Most important fields |
|---|---|---|---|
| `pack.yaml` | yes | The program | `schema` (the integer `1`), `key`, `title`, `locale`, `license` (SPDX expression), `version`, `alignment` (`strict` or `warn`, default `strict`) |
| `sources.yaml` | no | The sources that citations name | `key`, `title`, `publisher`, `edition_date`, `retrieved_on`, `kind` |
| `glossary.yaml` | no | Terms that text references as `[[term:slug]]` | `slug`, `label`, `short_text` |
| `segments.yaml` | no | The answers of the self-assessment station, each preselecting a path | `key`, `label`, `description`, `default_path` (`short` or `full`) |
| `stations.yaml` | no | The journey of the program in file order | `kind`, `title`, `module` (kind `module` only), `config` |
| `feedback.yaml` | no | The questions of the feedback station | `intro`, `questions` |
| `qualifications.yaml` | no | The credentials and the requirements that issue them | `code`, `title`, `audience`, `add_on`, `validity_kind`, `requirements` |
| `formats.yaml` | no | Companion formats that take place outside the platform | `key`, `title`, `description`, `attendance_counts`, `objectives` |
| `modules/<dir>/module.yaml` | yes, in every module directory | The module | `number`, `title`, `summary`, `single_path`, `refresher_unit`, `areas_elsewhere` |
| `modules/<dir>/objectives.yaml` | no | The learning objectives of the module | `key`, `statement`, `area`, `depth`, `phase`, `taught_in` |
| `modules/<dir>/rules.yaml` | no | Rules that item feedback returns and the handbook lists | `number`, `statement`, `action`, `cite` |
| `modules/<dir>/items.yaml` | no | Practice items and exam items | `key`, `kind`, `stem`, `core`, `phase`, `provenance`, `objectives`, `options` or `config` |
| `modules/<dir>/assessment.yaml` | no | Practice assessments and exams | `key`, `kind` (`practice` or `exam`), `counts_for_credential`, `max_wrong`, `core_required`, `items` |
| `modules/<dir>/lessons/<key>.md` | at least one per module | One lesson | Front matter `title` and `position`, then blocks |
| `media/<path>` | no | The images, SVG files, videos and captions that `figure` and `video` blocks name | A path of `media/`, up to three directories and a file name `<key>.<extension>`; the extensions `png`, `jpg`, `jpeg`, `gif`, `webp`, `svg`, `mp4`, `m4v`, `mov`, `webm`, `mkv` and `vtt`; at most 500 files |

The station kinds are `self_assessment`, `overview`, `module`, `credential`,
`companion_formats` and `feedback`. When `segments.yaml` has entries, the pack
has exactly one `self_assessment` station, and without entries it has none. The
same holds for `feedback.yaml` and the `feedback` station.

## How the pieces refer to each other

Files refer to each other by keys, and the validator resolves every reference
and reports a dangling one with file and line.

| Reference | Written as | Resolves to |
|---|---|---|
| `cite` of blocks, rules and items | `source-key#locator` | A `key` in `sources.yaml` |
| Glossary term in any string or block body | `[[term:slug]]` or `[[term:slug\|label]]` | A `slug` in `glossary.yaml` |
| `taught_in` of an objective | Lesson keys | Lessons of the same module |
| `objectives` of an item or a format | Objective keys | Objectives anywhere in the pack |
| `lesson` and `reveals` of an item | A lesson key, lesson keys | Lessons of the same module |
| `rules` of an item | Rule numbers | Rules of the same module |
| `items` of an assessment | Item keys | Items of the same module |
| `module` of a station | A module number | A `number` in a `module.yaml` |
| `src` of a `figure` or `video` block, `poster` and `captions` of a `video` block | A media path | A file below `media/` of the pack |
| `domain` of an objective | A domain name | An entry of `domains` in the `module.yaml` of the objective |
| `requirements` of a qualification | `kind` and `target` | A module number (`module_completed`), an exam key (`assessment_passed`), a format with `attendance_counts: true` (`attendance`), a qualification code (`qualification_held`) or a policy key (`policy_acknowledged`) |

The validator does not resolve a policy key, because policies live in the
database and not in the pack. The relations form this graph:

```text
qualification --requires--> module, exam, attendance format, qualification, policy
station (kind module) ----> module
assessment --lists--------> items
item ---------------------> objectives, rules, lesson, reveals
format -------------------> objectives
objective --taught_in-----> lessons
block --cite--> source      text --[[term:slug]]--> glossary term
figure, video --src, poster, captions--> media file
```

The objective joins teaching and evidence: lessons teach it, and items and
formats show it.

## The lesson file

A lesson is a Markdown file whose name without `.md` is the lesson key. It
starts with a line `---`, the YAML front matter with `title` and `position`
(1 or more, unique in the module), a second line `---`, and a body of container
directives. Each top-level directive becomes one block, in file order. This is
`modules/01-sharing/lessons/01-what-a-link-grants.md` of the example pack
`shared-links-basics`, an invented pack of one module that the section "A
complete example" lists in full:

```markdown
---
title: What a share link grants
position: 1
---

:::text{provenance=invented}
A [[term:share-link|share link]] gives access to every person who holds it.
:::

:::explanation{collapsed_on=short provenance=sourced cite="sharing-manual#Chapter 1"}
The service checks the address of the link and nothing else, unless the sender limits the link to named people or to a date.
:::
```

A line `:::kind{attributes}` opens a block, and a line `:::` closes it. The body
between them is Markdown and must not be empty, except for a `figure` (its
caption) and a `video` (its transcript), and text outside a block is an
error. The block kinds are `text` (running text), `explanation` (can start
collapsed, and items open it through `reveals`), `example`, `case_comparison`
(a comparison of cases, which gives a `classification` item the evidence of
the depth `judge`), `quote` (cites at least one source), `callout` and
`placeholder` (renders the current version of the policy that its `key` names,
and shows its own body with the `placeholder` badge until a version exists),
`figure` (an image or an SVG file with a text alternative and a caption) and
`video` (a video with captions and a transcript). The Markdown image syntax
`![text](address)` is an error in every block body, and a `figure` block takes
its place.

A block takes the attributes `provenance` (required on every kind except
`placeholder`), `collapsed_on`, `cite` and `key` (a policy key, allowed and
required on `placeholder` blocks only). A `figure` block also takes `src`,
`alt`, `decorative` and `size`, and a `video` block `src`, `embed`, `title`,
`poster` and `captions`. The syntax and the rules of each
attribute are in [`content-packs.md`](content-packs.md), section "Lesson
directives".

An explanation starts collapsed on the paths that its `collapsed_on` names, in
a module with `single_path: false`, and open otherwise. No lesson is skipped on
either path (plan section 1, goal 3).

## Item kinds

An item that an assessment of kind `exam` lists is an exam item and names no
lesson. An item that no assessment lists is a practice item and names the lesson
in whose section the player shows it, and an item that a practice assessment
lists may leave `lesson` out. With `core: true`, a wrong answer fails
an exam attempt with `failed_core` (plan section 7, domain rule 5).

| Kind | Answer data | Correct answer |
|---|---|---|
| `single_choice` | `options`, exactly one correct | yes |
| `multiple_choice` | `options`, at least one correct | yes |
| `poll` | `options`, none correct | no |
| `slot_builder` | `config.slots`, each with at least two options | yes |
| `classification` | `config.categories`, `config.cases`, `config.expected` | yes |
| `checklist_drill` | `config.checks`; the answer includes the learner's initials | yes |

Every option has `key`, `label`, `correct` and `feedback`. The answer key and
the feedback stay on the server until the learner submits (plan section 7,
domain rule 4). The `checklist_drill` trains the review of a work item and
stores nothing about real work items (plan section 2, principle 1). An exam
is an entry of `assessment.yaml` that lists item keys of its module, with
`max_wrong` and `core_required`; [`content-packs.md`](content-packs.md) shows
one. The example pack has one practice item in `modules/01-sharing/items.yaml`:

```yaml
- key: m1-who-opens-link
  kind: single_choice
  lesson: 01-what-a-link-grants
  stem: Who can open a file through an unrestricted share link?
  core: false
  phase: understand
  provenance: invented
  objectives: [m1-subject-link-grants, m1-method-limit-link, m1-self-own-files, m1-social-team-rule]
  reveals: [01-what-a-link-grants]
  options:
    - key: anyone-with-link
      label: Everyone who holds the link.
      correct: true
      feedback: Right. The link itself grants the access.
    - key: named-people
      label: Only the people whom the sender named.
      correct: false
      feedback: Named people are a setting that the sender has to choose.
```

## Images, SVG files and videos

A `figure` block shows an image or an SVG file of the folder `media/`, and a
`video` block plays a video file of that folder, an external video file or the
player of a streaming service. This is a lesson excerpt with one block of each
kind. The files `media/release-checks.svg`, `media/module-1/assistant-demo.webm`
and `media/module-1/assistant-demo-en.vtt` belong to the pack:

```markdown
:::figure{src=media/release-checks.svg alt="Four steps from left to right: generated draft, mark the statements, check each source, initials and release" size=medium provenance=invented}
The release checks of a generated notice.
:::

:::video{src=media/module-1/assistant-demo.webm title="A test pattern with a tone" captions="media/module-1/assistant-demo-en.vtt:en" provenance=invented}
A moving test pattern with colour bars and a counter, and a steady tone.
:::
```

The text alternative of a `figure` is required unless the block carries
`decorative=true`. The body of a `figure` is its caption, and the body of a
`video` is its transcript. The validator requires captions or a transcript for
a video file, and a transcript for an embed. An image of an identifiable
person is personal data, and the organization obtains the consent of the person
outside the platform ([`media.md`](media.md), section "People in images and
videos").

The import moves every file that a block names into the media library of the
installation. A background job converts a raster image to WebP and a video to
WebM with VP9 and Opus, rebuilds an SVG file from an allowlist and checks a
captions file, and a program is published only when every file of its import is
converted. The pack page lists the files of an import with their status.
`mix espalier.export` writes the converted files back, so a file that the
source held as `media/photo.jpg` is exported as `media/photo.webp`. The rules
of the folder and of both blocks are in [`content-packs.md`](content-packs.md),
section "Media". [`media.md`](media.md) describes the accepted files, the
limits, the conversion, the hosts of external files and embeds, the malware
scan and the browser support.

## Constructive alignment

Every module declares learning objectives in `objectives.yaml`. Each objective
has a statement (by convention of the form "Learners can ..."), a competence area of the four
CORE areas (`subject`, `method`, `self`, `social`), a depth (`know`, `apply` or
`judge`) and a phase of the five-phase arc (`orient`, `understand`, `apply`,
`anchor`, `update`). `taught_in` lists the lessons that teach it, and the
`objectives` field of items and formats lists what they practise or provide
evidence for. Evidence is an item of an assessment, a practice item whose kind
has a correct answer (every kind except `poll`), or a format with
`attendance_counts: true`. A module covers all four areas with its own
objectives, or it names each missing area in `areas_elsewhere` with a format or
another module that carries an objective of that area.

The validator applies four checks at every import (plan section 7, domain
rule 14): every objective has a teaching lesson and evidence; every item of an
assessment with `counts_for_credential: true` names an objective; every module
covers the four areas; and the kind of the evidence fits the depth. The field `alignment` in `pack.yaml` sets the mode. With `strict`,
which applies when the field is absent, checks 1 to 3 are errors that fail the
import, and check 4 is a warning. With `warn`, all four are warnings, and the
import can be published with them (plan section 2, principle 10).

The kinds of evidence that fit are `single_choice` and `multiple_choice` for
`know`, `slot_builder`, `classification` and `checklist_drill` for `apply`, and
for `judge` a `classification` item with a `case_comparison` block in a teaching
lesson or a companion format ([`content-packs.md`](content-packs.md), section
"Depth and kind of evidence").

The example pack declares one objective per area in
`modules/01-sharing/objectives.yaml`:

```yaml
- key: m1-subject-link-grants
  statement: Learners can explain that a share link gives access to everyone who holds it.
  area: subject
  depth: know
  phase: understand
  taught_in: [01-what-a-link-grants]
- key: m1-method-limit-link
  statement: Learners can name the settings that limit a share link.
  area: method
  depth: know
  phase: understand
  taught_in: [01-what-a-link-grants]
- key: m1-self-own-files
  statement: Learners can name which of their own files they share only with named people.
  area: self
  depth: know
  phase: understand
  taught_in: [01-what-a-link-grants]
- key: m1-social-team-rule
  statement: Learners can name what a team agrees on before it shares files by link.
  area: social
  depth: know
  phase: understand
  taught_in: [01-what-a-link-grants]
```

## Stable keys across versions

The publish of an import upserts every keyed row by its key, so a new version
of a pack keeps the rows that progress, exam attempts and credentials
reference. A changed title, stem or statement under the same key updates the
row, and a changed key archives the row of the old key and creates a row for the
new one. An objective, an item and an assessment can move to another module
without losing their records. The key of each kind and the archive rules are in
[`content-packs.md`](content-packs.md), section "Versioning with stable keys".

## Author workflow

The commands run through `nix-shell --run` in a checkout of Espalier.
[`setup.md`](setup.md) covers the checkout, the `.env` and the database, and
[`tenant-and-authentication.md`](tenant-and-authentication.md), section "Roles
and the first admin", covers how the role `author` is granted.

1. **Edit** the files in the Git repository of the pack, or in the pack
   workbench (step 5).
2. **Validate.** The task needs no database. It prints one line per error and
   then one line per warning, exits with status 1 when an error exists, and
   prints nothing for a pack without a finding.

   ```sh
   nix-shell --run "mix espalier.validate path/to/pack"
   ```

3. **Read the alignment matrix**, one row per module, area and depth. The option
   `--format` takes `text` (default), `csv` or `json`.

   ```sh
   nix-shell --run "mix espalier.alignment path/to/pack"
   ```

4. **Import.** The task needs the database settings, and `nix-shell --run`
   loads no `.env`, so the command sources it first. `--draft` stores the
   import without publishing it, and without `--draft` a validated pack is
   published at once. `make setup` imports the demo pack this way. Without
   `--draft`, the task converts the media files of the pack in its own
   process, with the `ffmpeg` of the development shell, before the publish,
   and a failed file ends the task with exit status 1 without a publish. With
   `--draft` the jobs stay queued for the running server
   ([`media.md`](media.md), section "Import and publish").

   ```sh
   nix-shell --run "set -a; . ./.env; set +a; mix espalier.import path/to/pack --draft"
   ```

5. **Upload or edit** in the admin area. A person with the role `author` uploads
   a zip archive of the pack at `/admin/packs` (`pack.yaml` at the top level
   or in a single folder) or edits the files at `/admin/workbench`. Both lead
   to the pack page `/admin/packs/:id`, as does a draft import from step 4.
6. **Preview and publish** on the pack page. It shows the status (`validated`,
   `failed` or `published`), the report with file and line, the alignment
   matrix and a "Preview" of the player with a preview banner. "Publish" stays
   disabled while the import is not `validated`, while the alignment section
   lists an error and while a media file of the import is not `ready`. Its
   confirmation dialog lists the added, changed and archived keys and the
   added, changed and removed media paths. Upload, publish and every change in
   the workbench need a second factor from the last 10 minutes (plan section
   6.4). The check of a draft in the workbench does not.
7. **Export** a published program back into the pack format, for example to
   start a Git repository from it. The target directory must be empty or
   missing.

   ```sh
   nix-shell --run "set -a; . ./.env; set +a; mix espalier.export my-pack-key tmp/pack-out"
   ```

The workbench starts from an empty skeleton, a published program, an import or
a zip archive. It checks a draft with the loader and validator of
`mix espalier.validate`, hands it to the pack page with "Create import" and
downloads it as a zip archive in the pack layout, with its media files below
`media/`. It holds the captions files as text files and every other media file
as an entry that names an asset of the media library
([`pack-workbench.md`](pack-workbench.md), which also covers the step-up). The
upload accepts at most `PACK_UPLOAD_MAX_MB` megabytes, 20 by default, media
files included. A video above that limit reaches a lesson through the media
library and the workbench, or as an external file
([`content-packs.md`](content-packs.md), section "Media"). In a container release, the
operator mounts the pack directory and calls `Espalier.Release.import_pack/2`;
[`content-packs.md`](content-packs.md), section "In a release", gives the
commands.

## A complete example

The pack `shared-links-basics` has one module, one lesson, four objectives that
cover the four areas and one practice item that serves all four, which keeps
the example small. A real module asks questions that fit each objective. The
lesson, the item and the objectives are shown in the sections above, and the
files below complete the pack:

`pack.yaml`:

```yaml
schema: 1
key: shared-links-basics
title: Sharing files with links
locale: en
license: CC0-1.0
version: "1.0.0"
alignment: strict
```

`sources.yaml`:

```yaml
- key: sharing-manual
  title: Manual of a file sharing service (invented example source)
  publisher: Example publisher (invented)
  url: https://example.org/sharing-manual
  edition_date: "2026-01-15"
  retrieved_on: "2026-06-01"
  kind: other
```

`glossary.yaml`:

```yaml
- slug: share-link
  label: share link
  short_text: A web address that gives access to a file to everyone who holds the address.
```

`stations.yaml`:

```yaml
- kind: overview
  title: Overview
  config:
    intro: This program shows how to share files with links. Its content is invented for this guide.
- kind: module
  title: Sharing a file
  module: 1
```

`modules/01-sharing/module.yaml`:

```yaml
number: 1
title: Sharing a file
summary: What a share link grants, how to limit it and how to agree on its use with a team.
phases: [understand, apply]
single_path: false
refresher_unit: false
```

Together with `objectives.yaml`, `items.yaml` and the lesson, the pack passes
both tasks. `mix espalier.validate` prints nothing and exits with status 0.
`mix espalier.alignment` prints a row for each of the twelve combinations of
area and depth. The rows for the depths `apply` and `judge` hold `-` in every
column except the first three, so only the rows of the depth `know` follow:

```text
module	area	depth	objectives	lessons	evidence	elsewhere
1	subject	know	m1-subject-link-grants	01-what-a-link-grants	item:m1-who-opens-link	-
1	method	know	m1-method-limit-link	01-what-a-link-grants	item:m1-who-opens-link	-
1	self	know	m1-self-own-files	01-what-a-link-grants	item:m1-who-opens-link	-
1	social	know	m1-social-team-rule	01-what-a-link-grants	item:m1-who-opens-link	-
```

If the objective `m1-social-team-rule` is removed from the `objectives` of the
item, the objective has no evidence. In `strict` mode `mix espalier.validate`
then exits with status 1 and prints a line at
`modules/01-sharing/objectives.yaml:19` that starts with "objective
`m1-social-team-rule` has no evidence"; with `alignment: warn`, the line
carries the prefix `warning:` and the exit status is 0. The example has no
qualification and no exam, so it issues no credential.
[`content-packs.md`](content-packs.md) shows `qualifications.yaml`,
`assessment.yaml`, `formats.yaml` and `segments.yaml` in the minimal pack.

## Where to go next

[`content-packs.md`](content-packs.md) is the reference for every field and
message. [`media.md`](media.md) covers the media library and the conversion.
[`pack-workbench.md`](pack-workbench.md) covers editing in the
browser, [`demo-instance.md`](demo-instance.md) a demo instance with the demo
pack, [`self-hosting.md`](self-hosting.md) and
[`operations.md`](operations.md) the import into a production instance, and
[`scorm-export.md`](scorm-export.md) the delivery of a module through a
learning management system. The decisions behind the format are in
[`../plan/README.md`](../plan/README.md), sections 1, 2, 7 and 11.
