# Content packs

A content pack holds the course content of one program as YAML and Markdown
files: the program with its stations, sources, glossary, segments,
qualifications and companion formats, and per module its learning objectives,
rules, items, assessments and lessons. Its folder `media/` holds the images,
vector graphics, videos and captions that the lessons show. The pack format is the input of
`mix espalier.validate`, `mix espalier.import`, the pack upload of the admin
area and the pack workbench, and `mix espalier.export` writes it. An
organization keeps its packs in its own Git repository next to its review
process (README section 1, goal 5, and section 11). Task 0008 defines the
format, task 0015 the upload and the pack page, and task 0016a the pack
workbench.

This repository ships one pack, the demo pack in
[`content/demo/`](../../content/demo/). It is the complete example of the
format: it uses every file, every block kind and every item kind, and it
passes every check of this guide without an error or a warning.

The examples in the section "Files" form a minimal pack. Copied into one
directory, they pass `mix espalier.validate` and `mix espalier.alignment` with
no error and no warning. The section "Constructive alignment" quotes excerpts
of `content/demo`, and each excerpt names its file in the demo pack.

## Pack layout

The minimal pack of this guide has the following files:

```text
writing-assistant-basics/
├── pack.yaml
├── sources.yaml
├── glossary.yaml
├── segments.yaml
├── stations.yaml
├── feedback.yaml
├── qualifications.yaml
├── formats.yaml
├── media/
│   ├── next-word.svg
│   ├── release-checks.webm
│   └── release-checks-en.vtt
└── modules/
    └── 01-writing-assistant/
        ├── module.yaml
        ├── objectives.yaml
        ├── rules.yaml
        ├── items.yaml
        ├── assessment.yaml
        └── lessons/
            ├── 01-how-it-writes.md
            ├── 02-prompts-and-checks.md
            └── 03-own-tasks-and-team.md
```

`Espalier.Catalog.Pack.Loader` reads exactly these names:

| Path | Required | Content |
|---|---|---|
| `pack.yaml` | yes | The program: format version, key, title, locale, license, version and alignment mode |
| `sources.yaml` | no | The sources that citations name |
| `glossary.yaml` | no | The glossary terms that Markdown text references |
| `segments.yaml` | no | The segments of the self-assessment station |
| `stations.yaml` | no | The stations of the program in their order |
| `feedback.yaml` | no | The questions of the feedback station |
| `qualifications.yaml` | no | The qualifications with their requirements |
| `formats.yaml` | no | The companion formats |
| `modules/<dir>/module.yaml` | yes, in every module directory | The module |
| `modules/<dir>/objectives.yaml` | no | The learning objectives of the module |
| `modules/<dir>/rules.yaml` | no | The rules of the module |
| `modules/<dir>/items.yaml` | no | The practice items and exam items of the module |
| `modules/<dir>/assessment.yaml` | no | The assessments of the module |
| `modules/<dir>/lessons/<key>.md` | at least one in every module directory | One lesson; the file name without `.md` is the lesson key |
| `media/<path>` | no | The images, SVG files, videos and captions that `figure` and `video` blocks name; the loader checks their paths and sizes and reads none of them (section "Media") |

`modules/` holds at least one module directory, and every lesson holds at
least one block. The name of a module directory and every lesson key follow
the key format below. The module number comes from `number` in `module.yaml`,
so the directory name carries no meaning of its own; `mix espalier.export`
names a directory `<number>-<slug of the module title>` with the number padded
to two digits, or to the digits of the largest module number. The loader
reads no other file, so a `README.md` in the pack directory stays unread, and
it keeps the files below `media/` without reading them. It rejects every
symbolic link in the pack, also inside a directory that it does not read,
every entry that is neither a directory nor a regular file, and every name
that is not valid UTF-8. The pack workbench admits the text files of the
table above and the captions files (`.vtt`) below `media/` as files of a
draft, and holds the other media files as media entries
([`pack-workbench.md`](pack-workbench.md), section "Files and layout").

### Values

The validator casts every file with an embedded Ecto schema of its file type
(`lib/espalier/catalog/pack/schema/`) and validates positively:

- Keys, slugs, codes, domains, placeholder keys, module directory names,
  lesson keys, the directories below `media/` and the names of media files
  without their extension match `^[a-z0-9][a-z0-9-]*$`.
- A field that the schema does not know is an error.
- A value must have the type of its field, and no type is converted: `"1"` is
  no integer, and `1.0` is no string. Quote a version or a date, so that YAML
  reads it as a string.
- Every string is non-empty and holds no U+0000. A YAML `null` counts as
  absent. A string that the publisher writes to a `varchar(255)` column, such
  as a key, a title, a label, a URL or the locator of a citation, holds at most
  255 characters, and an integer lies between the bounds of a PostgreSQL
  `integer`, at most 2,147,483,647.
- Lists are optional unless a table below says otherwise, and a list of keys
  or numbers holds no duplicate. A boolean is required wherever a table below
  marks it so.
- Dates have the form `YYYY-MM-DD`.
- A citation (`cite`) is a list of strings of the form `source-key#locator`,
  for example `assistant-manual#Chapter 2`.
- A text is valid UTF-8 and holds no control character other than tab, line
  feed and carriage return.
- Every string of every file and every block body may reference a glossary
  term as `[[term:slug]]` or `[[term:slug|label]]` (README section 7, domain
  rule 9). The slug has at most 255 characters and the label at most 1,000.
- The entries of a list file keep the order of the file, which gives their
  position. Lessons take their `position` from their front matter, and
  qualifications take it from the optional `position`.

## Files

Each subsection names the path of one file of the minimal pack, lists its
fields and shows the complete file.

### `pack.yaml`

| Field | Required | Value |
|---|---|---|
| `schema` | yes | The format version, the integer `1`. Any other value is an error whose message names the supported versions. |
| `key` | yes | The slug of the program (`programs.slug`) in the key format. An import with the key of an existing program updates that program at its publish. |
| `title` | yes | The title of the program |
| `locale` | yes | A language tag such as `en` or `de-DE` |
| `license` | yes | An SPDX license expression such as `CC0-1.0` or `MIT OR Apache-2.0`, whose ids are on the SPDX License List 3.28.0 (`Espalier.Catalog.Pack.Spdx`) |
| `version` | yes | A string, stored as `programs.pack_version` |
| `alignment` | no | `strict` (the default) or `warn`, see "The alignment mode" |

```yaml
schema: 1
key: writing-assistant-basics
title: Safe use of a writing assistant
locale: en
license: CC0-1.0
version: "1.0.0"
alignment: strict
```

### `sources.yaml`

A source is the target of `cite` entries of blocks, rules and items. README
principle 4 requires the edition date and the retrieval date.

| Field | Required | Value |
|---|---|---|
| `key` | yes | The key that `cite` entries name |
| `title` | yes | The title of the source |
| `publisher` | yes | The publisher |
| `url` | no | An absolute `http` or `https` URL |
| `edition_date` | yes | The date of the edition, `YYYY-MM-DD` |
| `retrieved_on` | yes | The date of retrieval, `YYYY-MM-DD` |
| `kind` | yes | `law`, `guidance`, `vendor`, `study`, `press` or `other` |

```yaml
- key: assistant-manual
  title: Manual of a writing assistant (invented example source)
  publisher: Example publisher (invented)
  url: https://example.org/assistant-manual
  edition_date: "2026-01-15"
  retrieved_on: "2026-06-01"
  kind: other
```

### `glossary.yaml`

The player renders a glossary reference as a button with an accessible short
explanation that links to the glossary entry (README section 7, domain rule
9). Every reference resolves to a `slug` of this file.

| Field | Required | Value |
|---|---|---|
| `slug` | yes | The slug that `[[term:slug]]` names |
| `label` | yes | The term |
| `short_text` | yes | The short explanation |

```yaml
- slug: prompt
  label: prompt
  short_text: The text that tells a writing assistant what it should do.
- slug: source-check
  label: source check
  short_text: The comparison of a generated statement with a reliable source before the statement is used.
```

### `segments.yaml`

The self-assessment station offers the segments, and the chosen segment
preselects the path of the learner (README section 7, domain rule 1). When
this file has entries, the pack has exactly one station of kind
`self_assessment`; without entries, it has none.

| Field | Required | Value |
|---|---|---|
| `key` | yes | The key of the segment |
| `label` | yes | The answer that the learner chooses |
| `description` | yes | The text below the answer |
| `default_path` | yes | `short` or `full` |

```yaml
- key: regular-users
  label: I use a writing assistant every week
  description: You know the assistant and want to check your routine.
  default_path: short
- key: new-users
  label: I have not used a writing assistant yet
  description: You want to learn how the assistant works before you start.
  default_path: full
```

### `stations.yaml`

The stations form the journey of the program in the order of the file.

| Field | Required | Value |
|---|---|---|
| `kind` | yes | `self_assessment`, `overview`, `module`, `credential`, `companion_formats` or `feedback` |
| `title` | yes | The title of the station |
| `module` | for kind `module` | The module number; not allowed on other kinds |
| `config` | see below | A map of strings, integers, booleans, `null`, lists and maps with string keys; no float and no integer beyond 9,007,199,254,740,991 in either direction |

| Kind | `config` |
|---|---|
| `self_assessment` | `question`, the question above the segments (task 0014) |
| `overview`, `credential`, `companion_formats` | `intro`, the text of the station |
| `module` | no entry needed |
| `feedback` | no `intro` and no `questions`; both come from `feedback.yaml` |

The pack has exactly one `feedback` station when `feedback.yaml` exists, and
none otherwise.

```yaml
- kind: self_assessment
  title: Where you start
  config:
    question: How often do you use a writing assistant at work?
- kind: overview
  title: Overview
  config:
    intro: This program shows how to use a writing assistant safely. Its content is invented for this guide.
- kind: module
  title: Working with a writing assistant
  module: 1
- kind: credential
  title: Your credential
  config:
    intro: Complete the module, pass its exam and acknowledge the usage policy to receive the credential.
- kind: companion_formats
  title: Beyond the platform
  config:
    intro: The formats below take place outside the platform.
- kind: feedback
  title: Your feedback
```

### `feedback.yaml`

The questions of the feedback station (README section 7, domain rule 12). The
loader stores `intro` and `questions` in the `config` of the `feedback`
station, where task 0014 reads them.

| Field | Required | Value |
|---|---|---|
| `intro` | yes | The text above the questions |
| `questions` | yes, at least one | Each with `key`, `kind` (`single_choice`, `scale` for the values 1 to 5, or `free_text`), `label` and, for `single_choice` only, at least two `options` with `key` and `label` |

```yaml
intro: Your answers help to improve this program.
questions:
  - key: usefulness
    kind: single_choice
    label: How useful was the program for your work?
    options:
      - key: useful
        label: Useful
      - key: not-useful
        label: Not useful
  - key: clarity
    kind: scale
    label: How clear were the lessons, from 1 (unclear) to 5 (very clear)?
  - key: suggestion
    kind: free_text
    label: What should the program change?
```

### `qualifications.yaml`

A qualification names the tasks that its credential unlocks and the
requirements that issue it (README principle 2 and section 7, domain rules 6
and 7).

| Field | Required | Value |
|---|---|---|
| `code` | yes | The code of the qualification |
| `title` | yes | The title |
| `audience` | yes | The people it addresses |
| `unlocks` | no | The tasks that a holder may do; the credential copies the list at issue time |
| `add_on` | yes | A boolean |
| `validity_kind` | yes | `none`, `months` or `event` |
| `validity_months` | with `validity_kind: months` only | An integer above 0 |
| `refresher_mode` | with `months` and `event`; not allowed with `none` | `update_unit` (the module with `refresher_unit: true`, which the pack then needs), `full_run` (a full run of all requirements) or `test_only` (the exam alone) |
| `phases` | no | Phases of the five-phase arc: `orient`, `understand`, `apply`, `anchor`, `update` |
| `position` | no | An integer of 1 or more that orders the qualifications for display and means nothing else. Either every entry sets it or none does, and no value appears twice. |
| `requirements` | yes, at least one | Each with `kind` and `target`; a requirement appears once per qualification |

| Requirement kind | `target` |
|---|---|
| `module_completed` | A module number, as a YAML integer |
| `assessment_passed` | The key of an assessment of kind `exam` |
| `policy_acknowledged` | A policy key in the key format. Policies live in the Policies context of task 0013, so the validator does not resolve the key. |
| `attendance` | The key of a format with `attendance_counts: true` |
| `qualification_held` | The code of a qualification of the pack; these requirements form no cycle |

```yaml
- code: assistant-basics
  title: Writing assistant basics
  audience: Everyone who drafts texts with a writing assistant.
  unlocks:
    - Draft internal texts with an approved writing assistant
  add_on: false
  validity_kind: months
  validity_months: 12
  refresher_mode: full_run
  phases: [understand, apply, anchor]
  requirements:
    - kind: module_completed
      target: 1
    - kind: assessment_passed
      target: module-1-exam
    - kind: policy_acknowledged
      target: usage-policy
- code: team-practice
  title: Writing assistant in the team
  audience: Holders of the credential Writing assistant basics who share texts with a team.
  unlocks:
    - Agree with a team how the use of a writing assistant is marked in shared texts
  add_on: true
  validity_kind: none
  requirements:
    - kind: qualification_held
      target: assistant-basics
    - kind: attendance
      target: team-session
```

### `formats.yaml`

A companion format takes place outside the platform. Learners mark interest in
it, and facilitators issue attendance certificates (README section 7, domain
rule 11).

| Field | Required | Value |
|---|---|---|
| `key` | yes | The key of the format |
| `title` | yes | The title |
| `description` | yes | The description |
| `phases` | no | Phases of the five-phase arc |
| `attendance_counts` | yes | A boolean. With `true`, attendance can satisfy an `attendance` requirement and provides evidence for the objectives of the format. |
| `objectives` | no | Objective keys of the pack that the format anchors or, with `attendance_counts: true`, provides evidence for |

```yaml
- key: team-session
  title: Team session
  description: A session in which a team agrees how the use of a writing assistant is marked in shared texts.
  phases: [anchor]
  attendance_counts: true
  objectives: [m1-social-mark-use]
- key: reference-card
  title: Reference card
  description: A printable card with the release checks.
  phases: [anchor, update]
  attendance_counts: false
  objectives: [m1-method-release-checks]
```

### `modules/01-writing-assistant/module.yaml`

| Field | Required | Value |
|---|---|---|
| `number` | yes | The module number, 1 or more, unique in the pack |
| `title` | yes | The title |
| `summary` | yes | The summary |
| `phases` | no | Phases of the five-phase arc |
| `domains` | no | The content domains of the module in the key format, which objectives name in `domain` |
| `single_path` | yes | A boolean. With `true`, the module ignores the path of the learner (README section 7, domain rule 2). |
| `refresher_unit` | yes | A boolean that marks the module that `refresher_mode: update_unit` uses (README section 7, domain rule 7) |
| `areas_elsewhere` | no | The competence areas that the objectives of the module leave out, see "Areas covered elsewhere" |

```yaml
number: 1
title: Working with a writing assistant
summary: How a writing assistant produces text, how to prompt it and check its draft, and which tasks stay with you.
phases: [orient, understand, apply, anchor]
domains: [drafting]
single_path: false
refresher_unit: false
```

### `modules/01-writing-assistant/objectives.yaml`

The learning objectives of the module. The section "Constructive alignment"
describes the fields.

```yaml
- key: m1-subject-likely-words
  statement: Learners can explain that a writing assistant continues text with likely words.
  area: subject
  depth: know
  phase: understand
  domain: drafting
  taught_in: [01-how-it-writes]
- key: m1-subject-prompt-parts
  statement: Learners can build a prompt from task, context and format.
  area: subject
  depth: apply
  phase: apply
  domain: drafting
  taught_in: [02-prompts-and-checks]
- key: m1-method-release-checks
  statement: Learners can run the release checks on a generated text and confirm them with their initials.
  area: method
  depth: apply
  phase: apply
  taught_in: [02-prompts-and-checks]
- key: m1-self-own-tasks
  statement: Learners can judge which of their own tasks they keep without an assistant.
  area: self
  depth: judge
  phase: anchor
  taught_in: [03-own-tasks-and-team]
- key: m1-social-mark-use
  statement: Learners can agree with their team how the use of an assistant is marked in shared texts.
  area: social
  depth: judge
  phase: anchor
  taught_in: [03-own-tasks-and-team]
```

### `modules/01-writing-assistant/rules.yaml`

A rule pairs a statement with an action. The feedback of an item returns the
rules that the item names (README section 7, domain rule 4), and the handbook
of the program lists every rule (domain rule 10).

| Field | Required | Value |
|---|---|---|
| `number` | yes | The rule number, 1 or more, unique in the module |
| `statement` | yes | The statement |
| `action` | yes | The action that follows from it |
| `cite` | no | Citations, `source-key#locator` |

```yaml
- number: 1
  statement: Generated text follows likely wording and carries no check of its own.
  action: Treat every generated statement as a draft until you have checked it.
  cite: ["assistant-manual#Chapter 2"]
- number: 2
  statement: A generated text is shared only after the release checks.
  action: Run the release checks and confirm them with your initials.
- number: 3
  statement: Judgements about people stay with you.
  action: Keep assessments of people out of a prompt.
```

### `modules/01-writing-assistant/items.yaml`

Practice items and exam items share this file. An item that an assessment of
kind `exam` lists is an exam item; every other item is a practice item. The
section "Item kinds" describes `options` and `config`.

| Field | Required | Value |
|---|---|---|
| `key` | yes | The key of the item, unique in the pack |
| `kind` | yes | `single_choice`, `multiple_choice`, `poll`, `slot_builder`, `classification` or `checklist_drill` |
| `lesson` | for an item that no assessment lists | A lesson key of the module; the player shows the practice item in the section of that lesson. An exam item names no lesson. |
| `stem` | yes | The question or task |
| `core` | yes | A boolean. A wrong answer to a core item fails an exam attempt with `failed_core` (README section 7, domain rule 5). |
| `phase` | yes | A phase of the five-phase arc |
| `provenance` | yes | One of the values of the section "Provenance" |
| `objectives` | no | Objective keys of the pack, see "Objectives of items and formats" |
| `rules` | no | Rule numbers of the module |
| `reveals` | no | Lesson keys of the module whose explanations open after a wrong answer on the short path (README section 7, domain rule 3) |
| `cite` | no | Citations, `source-key#locator` |
| `options` | for `single_choice`, `multiple_choice` and `poll` | The answer options |
| `config` | for `slot_builder`, `classification` and `checklist_drill` | The configuration of the kind |

```yaml
- key: m1-likely-words
  kind: single_choice
  lesson: 01-how-it-writes
  stem: How does a writing assistant produce its answer?
  core: false
  phase: understand
  provenance: invented
  objectives: [m1-subject-likely-words]
  rules: [1]
  reveals: [01-how-it-writes]
  options:
    - key: likely-words
      label: It continues the text with words that are likely to follow.
      correct: true
      feedback: Right. The assistant continues text from learned probabilities.
    - key: checked-facts
      label: It looks up the answer in a list of checked facts.
      correct: false
      feedback: The assistant holds no list of checked facts.
- key: m1-first-task-poll
  kind: poll
  lesson: 01-how-it-writes
  stem: For which task would you use a writing assistant first?
  core: false
  phase: orient
  provenance: invented
  options:
    - key: notices
      label: Short notices
      correct: false
      feedback: Thank you for your answer.
    - key: summaries
      label: Summaries
      correct: false
      feedback: Thank you for your answer.
- key: m1-build-prompt
  kind: slot_builder
  lesson: 02-prompts-and-checks
  stem: Build a prompt for a notice that the team meeting moves to Thursday.
  core: false
  phase: apply
  provenance: invented
  objectives: [m1-subject-prompt-parts]
  config:
    slots:
      - key: task
        label: Task
        options:
          - key: task-clear
            label: Write a notice that the team meeting moves from Tuesday to Thursday.
            correct: true
            feedback: This names what the assistant should write.
          - key: task-vague
            label: Write something about the meeting.
            correct: false
            feedback: This leaves the task open.
      - key: format
        label: Format
        options:
          - key: format-short
            label: Three sentences in plain language.
            correct: true
            feedback: This sets the length and the style.
          - key: format-open
            label: Any length and any style.
            correct: false
            feedback: An open format gives a text that you shorten afterwards.
- key: m1-release-drill
  kind: checklist_drill
  lesson: 02-prompts-and-checks
  stem: Run the release checks on your draft notice and confirm them with your initials.
  core: false
  phase: apply
  provenance: invented
  objectives: [m1-method-release-checks]
  rules: [2]
  config:
    checks:
      - key: facts-checked
        label: Every name, number and date in the draft is checked against a source.
        required: true
      - key: second-reader
        label: A colleague has read the draft.
        required: false
- key: m1-sort-tasks
  kind: classification
  lesson: 03-own-tasks-and-team
  stem: Sort each task by whether an assistant may draft it.
  core: false
  phase: anchor
  provenance: invented
  objectives: [m1-self-own-tasks]
  rules: [3]
  config:
    categories:
      - key: assistant-may-draft
        label: The assistant may draft it
      - key: keep-it
        label: I keep it
    cases:
      - key: case-notice
        text: A notice that a meeting moves to another room.
        feedback: The notice holds no judgement about a person, and you check its facts.
      - key: case-assessment
        text: The assessment of a trainee.
        feedback: An assessment is a judgement about a person and stays with you.
    expected:
      case-notice: assistant-may-draft
      case-assessment: keep-it
- key: m1-exam-likely-words
  kind: single_choice
  stem: What does a fluent answer of a writing assistant tell you about its facts?
  core: true
  phase: anchor
  provenance: invented
  objectives: [m1-subject-likely-words]
  rules: [1]
  options:
    - key: nothing
      label: Nothing. Its statements still need a check.
      correct: true
      feedback: Right. Fluent wording follows from likely words.
    - key: checked
      label: The facts are checked.
      correct: false
      feedback: The assistant checks nothing while it writes.
- key: m1-exam-varying-drafts
  kind: multiple_choice
  stem: You send the same prompt twice and receive two drafts. Which statements are true?
  core: false
  phase: anchor
  provenance: invented
  objectives: [m1-subject-likely-words]
  options:
    - key: both-fluent
      label: Both drafts can read well and still differ in their facts.
      correct: true
      feedback: Right. Fluent wording says nothing about the facts.
    - key: expected
      label: Different drafts are expected, because the assistant chooses among likely words.
      correct: true
      feedback: Right. The choice among likely words varies.
    - key: fault
      label: One of the drafts is the result of a technical fault.
      correct: false
      feedback: The variation is part of how the assistant works.
```

### `modules/01-writing-assistant/assessment.yaml`

| Field | Required | Value |
|---|---|---|
| `key` | yes | The key of the assessment, unique in the pack; the target of `assessment_passed` |
| `title` | yes | The title |
| `kind` | yes | `practice` or `exam` |
| `counts_for_credential` | yes | A boolean; every item of an assessment with `true` names an objective (check 2 of "The four checks") |
| `max_wrong` | yes | The number of wrong answers that a passed attempt may hold (README section 7, domain rule 5); for an exam from 0 to the number of its items minus one |
| `core_required` | yes | A boolean. With `true`, the exam holds at least one core item. |
| `items` | yes, at least one | Item keys of the module in order, each once |

```yaml
- key: module-1-exam
  title: Exam of module 1
  kind: exam
  counts_for_credential: true
  max_wrong: 1
  core_required: true
  items:
    - m1-exam-likely-words
    - m1-exam-varying-drafts
```

### Lesson files

A lesson file starts with a line `---`, then the YAML front matter with
`title` and `position` (1 or more, unique in the module), then a line `---`,
then the body of container directives that the section "Lesson directives"
describes. The file name without `.md` is the lesson key.

`modules/01-writing-assistant/lessons/01-how-it-writes.md`:

```markdown
---
title: How a writing assistant writes
position: 1
---

:::text{provenance=invented}
A writing assistant continues a [[term:prompt]] with words that are likely to follow.
:::

:::explanation{collapsed_on=short provenance=sourced cite="assistant-manual#Chapter 2"}
The assistant chooses each next word from probabilities that it learned in training. A fluent sentence therefore says nothing about whether its statements are true.
:::

:::figure{src=media/next-word.svg alt="The words 'The meeting moves to' with three candidates for the next word: Thursday with 0.6, Friday with 0.3 and Monday with 0.1" size=medium provenance=invented}
The assistant continues the sentence with one of the likely words.
:::

:::placeholder{key=input-rules}
Your organization adds its rules for inputs here.
:::
```

`modules/01-writing-assistant/lessons/02-prompts-and-checks.md`:

```markdown
---
title: Prompts and release checks
position: 2
---

:::text{provenance=invented}
A clear prompt names the task, the context and the format.
:::

:::example{provenance=invented}
- **Task:** Write a notice that the team meeting moves from Tuesday to Thursday.
- **Format:** Three sentences in plain language.
:::

:::callout{provenance=invented}
Before you share a generated text, give each name, number and date a [[term:source-check|source check]] and confirm the release checks with your initials.
:::

:::video{src=media/release-checks.webm title="The release checks of a generated notice" captions=media/release-checks-en.vtt:en provenance=invented}
A colleague reads a generated notice about a moved meeting. She checks the date against the calendar and the names against the staff list, and she adds her initials before she shares the notice.
:::
```

`modules/01-writing-assistant/lessons/03-own-tasks-and-team.md`:

```markdown
---
title: Own tasks and shared texts
position: 3
---

:::text{provenance=invented}
Some tasks stay with you, and your team sees where an assistant contributed.
:::

:::case_comparison{provenance=invented}
**Case A**

A colleague lets the assistant draft a notice about a moved meeting and checks the date.

**Case B**

A colleague lets the assistant write the assessment of a trainee.

Case A hands over wording, and the colleague keeps the check. Case B hands over a judgement about a person, which stays with the colleague.
:::

:::quote{provenance=sourced cite="assistant-manual#Chapter 5"}
Mark every shared document that the assistant helped to draft.
:::
```

## Lesson directives

`Espalier.Catalog.Pack.Directives` splits the body of a lesson into blocks
(task 0008, step 7). Each top-level directive becomes one block, and the order
of the directives gives the position of the blocks.

- A line that matches `^:::([a-z_]+)(\{.*\})?\s*$` opens a block of the named
  kind, with its attributes in the braces.
- A line that matches `^:::\s*$` closes the block.
- The lines between become the body of the block, in Markdown, without the
  leading and trailing blank lines. The body must not be empty, except for a
  `figure` (its caption) and a `video` (its transcript).
- Attributes have the form `name=value` or `name="value with spaces"` and are
  separated by spaces.

| Attribute | Value |
|---|---|
| `provenance` | One of the values of the section "Provenance"; required on every kind except `placeholder` |
| `collapsed_on` | The paths on which the block starts collapsed, `short`, `full` or both, separated by commas. The player applies it to `explanation` blocks in a module with `single_path: false` (README section 7, domain rule 2). |
| `cite` | Citations of the form `source-key#locator`, several separated by commas |
| `key` | On `placeholder` blocks only, and required there: the key of the policy whose current version the block renders |
| `src`, `alt`, `decorative`, `size` | On `figure` blocks only: the image and its text alternative (section "Media") |
| `src`, `embed`, `title`, `poster`, `captions` | On `video` blocks only: the video, its title, its poster and its captions (section "Media") |

| Kind | Content |
|---|---|
| `text` | Running text |
| `explanation` | An explanation that can start collapsed and that items open through `reveals` |
| `example` | An example |
| `case_comparison` | A comparison of cases. It gives a `classification` item the evidence kind of the depth `judge` (see "Depth and kind of evidence"). |
| `quote` | A quotation; it cites at least one source |
| `callout` | A highlighted note |
| `placeholder` | Renders the current version of the policy that `key` names. Until a version exists, the block shows its own body with the `placeholder` badge (README section 7, domain rule 8). |
| `figure` | An image or an SVG file of the pack with its text alternative; the body is the caption and may be empty |
| `video` | A video file of the pack, an external video file or the player of a streaming service; the body is the transcript |

Each of the following is an error at its line: an unknown kind, an unknown
attribute, an attribute on a kind that does not admit it (for example
`` attribute `src` is allowed on `figure` and `video` blocks only ``), a
duplicate attribute, a malformed attribute list, a missing `provenance`, a
`placeholder` block without `key` or with a provenance other than
`placeholder`, an opening line inside an open block, a line that starts with
`:::` and neither opens nor closes a block, an unclosed block, and text
outside a block. The splitter keeps the first 100 errors of a lesson body.
The validator then checks the values: the provenance, the paths of
`collapsed_on`, the citations, the key format of `key`, that a `quote` block
cites a source, and the rules of the section "Media". No block body holds
the Markdown image syntax `![text](address)`: the validator answers
`use a figure block for images`, and the player shows such an image as its
text only.

## Media

A pack carries its images, vector graphics, videos and captions in the folder
`media/` at its root, next to `pack.yaml` (task 0018). Two block kinds place
them in a lesson: `figure` shows an image or an SVG file with its text
alternative and a caption, and `video` plays a video with its captions and a
transcript. The import moves every file that a block names into the media
library of the installation, which converts it into its delivery format
before the program can be published; [`media.md`](media.md) describes the
library, the conversion and the player.

### The folder `media/`

A media path is `media/`, then zero to three directories, then a file name
`<key>.<extension>`. Every directory name and the key of the file name follow
the key format, and the extension is one of the lower-case extensions of the
table below. A path holds at most 527 bytes and each of its components at most
255 bytes, as the paths of the pack workbench do. Examples are
`media/next-word.svg` and `media/module-1/release-checks-en.vtt`.

| Kind | Extensions | Delivery format | Largest file |
|---|---|---|---|
| Image | `png`, `jpg`, `jpeg`, `gif`, `webp` | WebP (`.webp`) | `MEDIA_IMAGE_MAX_MB` megabytes of 1,048,576 bytes each, default 20 (20,971,520 bytes) |
| SVG | `svg` | SVG (`.svg`), rebuilt from an allowlist of elements and attributes | 1 MiB (1,048,576 bytes) |
| Video | `mp4`, `m4v`, `mov`, `webm`, `mkv` | WebM with VP9 and Opus (`.webm`) | `MEDIA_VIDEO_MAX_MB` megabytes, default 1024 (1,073,741,824 bytes) |
| Captions | `vtt` | WebVTT (`.vtt`), stored as written | 512 KiB (524,288 bytes) |

The loader keeps every regular file below `media/` with its path and its size
and reads none of them. Each of the following is an error at the path of the
file: a path outside the rules above, such as `media/Photo.PNG` or a file four
directories below `media/`, and a file larger than the limit of its kind. A
pack holds at most 500 media files (`max_pack_media`), and more files give one
error at `media`. A symbolic link below `media/` is rejected, as everywhere in
the pack. A directory `modules/media/` is a module directory as any other, and
a file outside `media/` and the layout stays unread.

The import detects the kind of every referenced file from its leading bytes,
such as `89 50 4E 47 0D 0A 1A 0A` for PNG or `1A 45 DF A3` for WebM and
Matroska, and refuses a file whose signature belongs to no kind of the table
or to another kind than its extension, and an image above 40,000,000 pixels;
each refusal is an error at the path of the file. [`media.md`](media.md),
section "Accepted files", lists every signature.

The upload of a pack in the admin area stays within `PACK_UPLOAD_MAX_MB` with
its media files (section "Upload limits"). A video above that limit reaches a
lesson through the media library and the pack workbench, whose uploads take
files up to `MEDIA_VIDEO_MAX_MB`, or as an external file on a host of
`MEDIA_EXTERNAL_HOSTS`. `mix espalier.import` and
`Espalier.Release.import_pack/2` read the pack directory and apply the limits
per file of the table. The converted files of every import count towards the
storage quota of the installation, `MEDIA_STORAGE_MAX_GB` gigabytes (default
50). `mix espalier.export` writes every media file in its delivery format, so
a pack exported from a program holds `media/photo.webp` where its source held
`media/photo.jpg`, and its blocks name the new path.

### The block `figure`

```markdown
:::figure{src=media/next-word.svg alt="The words 'The meeting moves to' with three candidates for the next word" size=medium provenance=invented}
The assistant continues the sentence with one of the likely words.
:::
```

| Attribute | Value |
|---|---|
| `src` | Required. The media path of an image or an SVG file of the pack. |
| `alt` | The text alternative, which a screen reader reads in place of the image, 1 to 1,000 characters. Required unless the block carries `decorative=true`, and not allowed with it. |
| `decorative` | `true` only. It marks an image that carries no information, such as an ornament, and the player gives it an empty text alternative. |
| `size` | `small`, `medium` or `full`, the width of the figure in the lesson. The default is `full`. |

The body is the caption, in Markdown, and may be empty. The attributes
`provenance`, `collapsed_on` and `cite` apply as to every other kind.

```markdown
:::figure{src=media/divider.svg decorative=true provenance=invented}
:::
```

### The block `video`

```markdown
:::video{src=media/release-checks.webm title="The release checks of a generated notice" poster=media/release-checks-start.png captions="media/release-checks-en.vtt:en,media/release-checks-de.vtt:de" provenance=invented}
A colleague reads a generated notice about a moved meeting. She checks the date against the calendar and the names against the staff list, and she adds her initials before she shares the notice.
:::

:::video{src="https://cdn.example.org/clips/release-checks.mp4" title="The release checks of a generated notice" provenance=invented}
A colleague reads a generated notice about a moved meeting and checks it before she shares it.
:::

:::video{embed="https://player.example.org/embed/release-checks" title="The release checks of a generated notice" provenance=invented}
A colleague reads a generated notice about a moved meeting and checks it before she shares it.
:::
```

| Attribute | Value |
|---|---|
| `src` | The video. Either the media path of a video file of the pack, or an external file: an absolute `https:` URL with a host and without user information, of at most 2,000 characters, whose path ends in `.webm` or `.mp4`. A path that ends in `.m3u8` or `.mpd` names a stream, and the validator answers `streams need an embed player: use embed`. |
| `embed` | The player of a streaming service, which the lesson shows in an iframe: an absolute `https:` URL with a host and without user information, of at most 2,000 characters. |
| `title` | Required, 1 to 255 characters. The player shows it as the label of the block. |
| `poster` | The media path of an image of the pack, which the player shows before the video starts; of an animated image it shows the first frame. Only with `src`. |
| `captions` | One to eight entries `<media path>:<language>`, separated by commas: the path of a captions file with the extension `vtt` and a BCP 47 language tag such as `en` or `pt-BR`. Each language appears once, compared without regard to case, so `pt-BR` and `pt-br` count as one language; the first entry is the default track. Only with `src`; with `embed` the validator answers `captions need a video file: use src`. |

A block has exactly one of `src` and `embed`. The body is the transcript, in
Markdown. A video file needs `captions` or a transcript, and an embed needs a
transcript, because the validator cannot look into the player of another
service. WCAG 2.2 asks for more than the validator can check: captions for
every video with sound (success criterion 1.2.2), a text alternative that
describes the picture as well as the sound, or an audio description (1.2.3),
and an audio description where the picture carries information that the
sound does not (1.2.5). These stay the task of the authors.

The hosts of external files and embeds must appear in the allowlists of the
installation, `MEDIA_EXTERNAL_HOSTS` for `src` and `MEDIA_EMBED_HOSTS` for
`embed`, each a comma-separated list of entries `host` or `host:port`. An
entry without a port admits port 443, the default port of `https`. The
upload in the admin area, the check and the import of the pack workbench and
`mix espalier.import` report every other host as an error at the line of the
block, for example `host cdn.example.org is not in MEDIA_EXTERNAL_HOSTS`.
`mix espalier.validate` runs without the settings of an installation and
skips this check. The browsers of the learners load external files and
embeds; the server fetches neither.

### Checks of the media blocks

Each of the following is an error at the file and the line of the block, in
both alignment modes:

- a media path in `src`, `poster` or `captions` that names no file of the
  folder `media/` (`` the pack holds no media file `media/photo.png` ``), or a
  file of another kind, such as a video in `src` of a figure or an SVG file
  as `poster`;
- a figure without `src`, a figure without `alt` and without
  `decorative=true`, a figure with both, a value of `decorative` other than
  `true`, and an `alt` of more than 1,000 characters;
- a video with both or neither of `src` and `embed`, an external URL that
  breaks the rules above, a missing `title`, a `poster` or `captions` together
  with `embed`, more than eight captions, two captions in one language, a
  video file without captions and transcript, and an embed without
  transcript;
- the Markdown image syntax in the body of any block, which answers
  `use a figure block for images`.

## Provenance

Every statement shows its provenance (README principle 4). A block carries it
in the attribute `provenance`, and an item in the field `provenance`. The
player renders the value as a visible badge, and the preview of the pack page
lists the number of blocks and items per value.

| Value | Badge | Use |
|---|---|---|
| `invented` | Invented | Content written for the pack, such as the cases and items of the demo pack |
| `sourced` | Sourced | Content that rests on a source; `cite` names the source |
| `vendor_statement` | Vendor statement | A statement that a vendor makes about its own product |
| `assumption` | Assumption | An assumption of the authors |
| `placeholder` | Placeholder | Text that the organization replaces. A `placeholder` block always has this provenance, and no other block kind may carry it. |

The validator requires a citation on `quote` blocks only. A source that `cite`
names exists in `sources.yaml` with its edition date and retrieval date.

## Item kinds

| Kind | Answer data | Rules | Correct answer |
|---|---|---|---|
| `single_choice` | `options` | At least two options, exactly one with `correct: true` | yes |
| `multiple_choice` | `options` | At least two options, at least one with `correct: true` | yes |
| `poll` | `options` | At least two options, none with `correct: true` | no |
| `slot_builder` | `config.slots` | At least one slot; each slot has `key`, `label` and at least two `options`, at least one of them correct | yes |
| `classification` | `config.categories`, `config.cases`, `config.expected` | At least two categories with `key` and `label`, at least one case with `key`, `text` and `feedback`, and `expected`, which maps every case key to a category key and names no other case | yes |
| `checklist_drill` | `config.checks` | At least one check with `key`, `label` and `required`, at least one of them with `required: true`. The answer always includes the initials of the learner (task 0009, step 10). | yes |

An option has `key`, `label`, `correct` and `feedback`, all required. The keys
of the options of an item, of the slots, the options of a slot, the
categories, the cases and the checks are unique within their list. A choice
kind and a poll take no `config`, and the other kinds take no `options`. The
items of the minimal pack above show one item of each kind. Whether a kind has
a correct answer decides whether a practice item of that kind provides
evidence (see "Evidence"). The `checklist_drill` trains the human review of a
work item, while the platform stores nothing about real work items (README
principle 1).

## Cross-file checks of the validator

`Espalier.Catalog.Pack.Validator` runs in three stages: the schema of every
file, the cross-file checks, and the alignment checks. Each stage runs only
when the stages before it report no error, so a run after a correction can
report errors of a later stage. The rules for combined data items (ASVS 2.1.2)
are the cross-file checks below and the alignment checks of the section "The
four checks".

| Check | Rule |
|---|---|
| Uniqueness in the pack | Module numbers, item keys, assessment keys and objective keys |
| Uniqueness in a module | Rule numbers and lesson positions |
| Uniqueness in a file | Source keys, glossary slugs, segment keys, format keys and qualification codes |
| References | The `lesson`, `rules` and `reveals` of an item resolve to a lesson and rules of its module; every `cite` to a source key; every glossary reference to a glossary slug; a station `module` to a module number; the `items` of an assessment to items of the same module |
| Requirement targets | A `module_completed` target to a module, an `assessment_passed` target to an assessment of kind `exam`, an `attendance` target to a format with `attendance_counts: true`, and a `qualification_held` target to a qualification of the pack, without a cycle |
| Objective references | Every `taught_in` entry to a lesson of the objective's module, the `objectives` of items and formats to objective keys of the pack, and an objective `domain` to an entry of the `domains` of its module |
| `areas_elsewhere` | `where` names a format of the pack or another module of the pack; a module that names its own number is an error |
| Item use | Every item names a lesson or is listed by an assessment, and an item that an exam lists names no lesson; an exam with `core_required: true` lists a core item |
| Refresher | `refresher_mode: update_unit` needs a module with `refresher_unit: true` |
| Qualification order | `position` on every qualification or on none, each value once |
| Stations | Exactly one `self_assessment` station when `segments.yaml` has entries and none otherwise; exactly one `feedback` station when `feedback.yaml` exists and none otherwise |

A duplicate names the file and the line of its first use. Every entry of the
report has a file relative to the pack directory, a line and a message, and
`mix espalier.validate` prints it in one of two forms:

```text
modules/01-basics/items.yaml:12: message
modules/01-basics/items.yaml:12: warning: message
```

Only the alignment checks produce warnings. The report keeps at most 100
entries per file and closes the rest with one entry such as "and 12 further
errors in this file". The report that an import stores keeps at most 1,000
errors and 1,000 warnings.

## Versioning with stable keys

A pack is versioned in the repository of the organization, and `version` in
`pack.yaml` names the version on the platform (`programs.pack_version`). The
publish of an import applies its payload to the catalog tables in one
transaction (README principle 5). It upserts every keyed row by its key:

| Kind | Key | Unique in |
|---|---|---|
| Program | `key` of `pack.yaml` | the instance |
| Source | `key` | the program |
| Glossary term | `slug` | the program |
| Segment | `key` | the program |
| Companion format | `key` | the program |
| Module | `number` | the program |
| Lesson | lesson key, the file name | the module |
| Rule | `number` | the module |
| Learning objective | `key` | the program |
| Item | `key` | the program |
| Assessment | `key` | the program |
| Qualification | `code` | the program |

A row keeps its id across publishes, so the records that reference it, such as
progress, exam attempts and credentials, stay intact. An item, an assessment
and a learning objective are keyed per program, so they keep their row when
they move to another module. A lesson and a rule are keyed per module. The
publisher sets `archived_at` on every keyed row whose key the new version no
longer holds; the row stays for the records that reference it, and the read
paths for learners skip it. A changed key therefore archives the row of the
old key and creates a new row. A changed title, stem or statement under the
same key updates the row. Blocks, options, citations, requirements, stations
and the join rows have no key and are replaced per parent at every publish.

The pack page lists the added, changed and archived keys per kind before a
publish (see "Pack page, preview and publish"). `mix espalier.export` writes a
published program back to disk in this format
([`scorm-export.md`](scorm-export.md), section "Pack export").

## Validation and publication

### On the command line

```sh
nix-shell --run "mix espalier.validate path/to/pack"
nix-shell --run "mix espalier.alignment path/to/pack"
```

`mix espalier.validate PATH` runs the loader and the validator, the alignment
checks included, without a database connection. It prints one line per error
and then one line per warning in the forms above, and exits with status 1 when
an error exists. Warnings alone leave the exit status at 0. A pack without a
finding prints nothing. `mix espalier.alignment PATH` prints the alignment
matrix (see "The alignment matrix").

```sh
nix-shell --run "set -a; . ./.env; set +a; mix espalier.import path/to/pack --draft"
nix-shell --run "set -a; . ./.env; set +a; mix espalier.import path/to/pack"
```

`mix espalier.import PATH [--draft]` starts the application and runs the
importer of task 0008 without an actor. `nix-shell --run` loads no `.env`, so
the command reads it first, as the Makefile does, for the database settings
such as `DATABASE_PORT`. The task processes no Oban jobs, runs no admin
bootstrap and starts no development server, so it runs next to a running
`make run`. It prints the report in the form of `mix espalier.validate` and
one line with the outcome:

| Outcome | Last line | Exit status |
|---|---|---|
| The pack has errors | `Import <id> failed with <n> errors` | 1 |
| Validated, with `--draft` | `Stored <key> <version> as draft import <id>` | 0 |
| Validated and published | `Published <key> <version> from import <id>` | 0 |
| Validated, the publish failed | `Import <id> was not published: <reason>` | 1 |

A draft import waits on its pack page `/admin/packs/<id>` in the admin area
for the preview and the publish. `make setup` and `make refresh-db` run
`mix espalier.import content/demo`.

### In a release

`Espalier.Release.import_pack/2` does the same as `mix espalier.import` inside
`Ecto.Migrator.with_repo/2`, without starting the application. The image holds
no content pack other than the demo pack, so the operator mounts the pack
directory into the container, read-only:

```sh
docker compose run --rm -v "$PWD/packs/my-pack:/srv/packs/my-pack:ro" app \
  bin/espalier eval 'Espalier.Release.import_pack("/srv/packs/my-pack")'
docker compose run --rm -v "$PWD/packs/my-pack:/srv/packs/my-pack:ro" app \
  bin/espalier eval 'Espalier.Release.import_pack("/srv/packs/my-pack", draft: true)'
```

The function prints the report and the outcome line as the mix task does, and
`draft: true` stops after the draft. `Espalier.Release.seed_demo/0` imports and
publishes the demo pack that the image carries in `priv/demo_pack` and then
seeds the demo policy.

### Upload in the admin area

A person with the role `author` reaches the page `/admin/packs` through the
entry "Packs" in the author section of the admin navigation (task 0015, step
11). The form "Pack archive (zip)" takes a zip archive with `pack.yaml` at its
top level or in a single folder, which the following command gives for a pack
directory `packs/my-pack`:

```sh
(cd packs && zip -qr ../my-pack.zip my-pack)
```

"Upload" sends the archive to `POST /api/admin/packs` as the
`multipart/form-data` field `file`. The upload needs a second factor from the
last 10 minutes (README section 6.4). Without one, the server answers 403
`reauth_required`, the step-up dialog opens, and the page repeats the request
once after a successful step-up. The server checks and extracts the archive as
the section "Upload limits" describes, runs the importer with the author as
actor, and answers 201 with the import. The page then moves to the pack page
of the import.

| Answer | Cause |
|---|---|
| 201 with `id`, `status` and `report` | The archive passed its checks, and the importer stored an import with status `validated` or `failed` |
| 413 `request_too_large` | The body exceeds `PACK_UPLOAD_MAX_MB` |
| 415 `unsupported_media_type` | The body is no `multipart/form-data` |
| 422 `archive_rejected` | The archive failed a check; `report.errors` holds one entry per finding with the entry name (or `.` for the archive) as `file` and no line |
| 422 `validation_failed` | The field `file` holds no file |

### Pack page, preview and publish

The pack page `/admin/packs/:id` shows the status of the import (`validated`,
`failed` or `published`), the validation report with file and line of every
error and warning outside the alignment checks, and the section "Alignment"
(see "The alignment matrix"). For an import with a payload, that is an import
with status `validated` or `published`:

- "Preview" opens `/admin/packs/:id/preview`, the player with
  `StandaloneRuntime` on the payload, with the banner "Preview" and the
  provenance overview, which lists the number of blocks and items per
  provenance value.
- "Edit in the workbench" starts a draft of the pack workbench from the
  import.

"Publish" is disabled while the status differs from `validated` or the
alignment section lists an error, and a sentence next to the button names the
reason. It opens a confirmation dialog that lists the added, changed and
archived keys per kind from `GET /api/admin/packs/:id/diff`, the changed
fields of each changed learning objective, and the number of alignment
warnings. The confirmation sends `POST /api/admin/packs/:id/publish`, which
needs a second factor from the last 10 minutes. The route answers 409
`not_publishable` for an import that is not `validated`. Before it calls the
publisher, it runs the alignment checks of the running release on the stored
payload again and answers 409 `alignment_errors` with the findings when they
report an error, so that a draft stored before an update of the checks stays
out of the live tables. The dialog shows these findings, and the import stays
unpublished.

### Pack workbench

The pack workbench of task 0016a edits the files of a pack in the browser at
`/admin/workbench`. A draft starts from an empty skeleton, a published
program, an import or a zip archive. The check runs the loader and the
validator that `mix espalier.validate` runs and shows the same lines and the
alignment matrix. "Create import" hands the draft to the pack page above, and
a draft downloads as a zip archive in the pack layout. The workbench admits
only the paths of the pack layout and has limits of its own;
[`pack-workbench.md`](pack-workbench.md) describes both.

## Upload limits

The pack upload bounds the size of the request, the archive and its entries
before the importer reads a file (ASVS 2.1.3 and 5.1.1; task 0015, step 7).
`EspalierWeb.PackMultipart` parses the upload, and
`Espalier.Catalog.Pack.Archive` reads the central directory of the archive
itself before it writes any file.

| Limit | Value | Answer beyond it |
|---|---|---|
| Size of the upload | `PACK_UPLOAD_MAX_MB` megabytes of 1,048,576 bytes each, default 20 (20,971,520 bytes); a positive integer that `Espalier.RuntimeConfig` parses at boot | 413 `request_too_large` |
| Entries of the archive | At most 2,000 (`Archive.max_entries/0`) | 422 `archive_rejected` |
| Declared uncompressed sizes | Their sum is at most five times the upload limit, 104,857,600 bytes with the default | 422 `archive_rejected` |

The archive is rejected, with one report entry per finding, for:

- a ZIP64 archive and a multi-disk archive;
- an entry name that is absolute (a leading `/` or `\`, or a drive letter such
  as `C:`), that holds a backslash, a `..` component or a NUL character, or
  that is no valid UTF-8;
- two entries that name the same path once empty and `.` components are
  dropped;
- an entry made on Unix whose external attributes carry the file type of a
  symbolic link (`0o120000`);
- an encrypted entry and an entry compressed with a method other than stored
  or deflated;
- an entry whose extracted size differs from its declared size, or whose
  CRC-32 differs.

The archive extracts into a new directory below the temporary directory of
the system, which the server removes after the import, also after an error. A
deflated entry inflates in chunks, and the extraction stops as soon as the
output of an entry exceeds its declared size, so the disk receives at most the
declared sizes. The pack sits at the root of the archive, or in its one
top-level directory when that directory holds `pack.yaml`.

The media files of a pack count towards the size of the upload and the
declared sizes of the archive. The section "Media" lists the limits per media
file and the number of media files of a pack.

The loader then applies the limits of the pack format, also to a pack that
`mix espalier.validate`, `mix espalier.import` or the workbench reads:

| Limit | Value |
|---|---|
| Entries of the pack directory | 20,000, and directories at most 32 levels deep |
| One file | 1,048,576 bytes |
| One YAML text or front matter | 50,000 nodes, a nesting of at most 32 levels, at most 2 MiB of strings, 10 seconds and 256 MiB of memory for the parse |
| Decoded data of the whole pack | 32 MiB |
| Time of the whole load | 60 seconds; after it, the loader reads no further file |

A pack holds course content, which the catalog tables and the payloads of
imports store as plain text. A pack, like the pack repository of an
organization, is therefore no place for personal data of learners or staff.

## Constructive alignment

Every topic supports constructive alignment (README section 1, goal 8). A
topic is a module. Its learning objectives each have a competence area of the
four CORE areas, a depth and a phase of the five-phase arc, and each objective
is aligned with the lessons that teach it and with the items, exams and
companion formats that provide evidence for it. In a pack with the default
`alignment: strict`, no objective exists without a lesson that teaches it and
evidence that shows it, and no item that counts for a credential exists
without an objective (README principle 10). The validator checks the
alignment at every import with the four checks of README section 7, domain
rule 14, which `Espalier.Catalog.Alignment` implements (task 0008, steps 5
and 13).

### Learning objectives: `objectives.yaml`

`modules/<dir>/objectives.yaml` lists the learning objectives of one module.
The file is optional; a module without it has no objectives.

| Field | Required | Value |
|---|---|---|
| `key` | yes | The key of the objective in the key format, unique in the pack |
| `statement` | yes | A sentence of the form "Learners can ..." |
| `area` | yes | The competence area: `subject`, `method`, `self` or `social` |
| `depth` | yes | `know`, `apply` or `judge` |
| `phase` | yes | The phase of the five-phase arc: `orient`, `understand`, `apply`, `anchor` or `update` |
| `domain` | no | One of the `domains` of the module |
| `taught_in` | no for the schema, at least one for check 1 | Lesson keys of the module that teach the objective |

The example of README section 11, an excerpt of `content/demo`:

```yaml
# modules/01-basics/module.yaml (excerpt of content/demo)
number: 1
domains: [drafting, research]

# modules/01-basics/objectives.yaml (excerpt of content/demo)
- key: m1-subject-varying-answers
  statement: Learners can explain why the same prompt can produce different answers.
  area: subject
  depth: know
  phase: understand
  domain: drafting
  taught_in: [02-second-lesson]
```

### Objectives of items and formats

An item in `items.yaml` lists in `objectives` the objectives that it practises
or provides evidence for. Practice items and exam items both name their
objectives there, because exam items are entries of `items.yaml` as well, and
`assessment.yaml` names only the item keys. A companion format in
`formats.yaml` lists in `objectives` the objectives that it anchors or, with
`attendance_counts: true`, provides evidence for. Objective keys are unique in
the pack, so an item can name an objective of another module; its evidence
then belongs to the module of the objective. The importer sorts both lists by
key.

```yaml
# modules/02-checking/items.yaml (excerpt of content/demo)
- key: m2-release-drill
  kind: checklist_drill
  objectives: [m2-method-release-check]

# formats.yaml (excerpt of content/demo)
- key: workshop
  attendance_counts: true
  objectives: [m1-self-own-responsibility, m1-social-team-transparency]
```

### Areas covered elsewhere: `areas_elsewhere`

A module names in `areas_elsewhere` of its `module.yaml` each competence area
that its own objectives leave out, together with the place where the area is
covered. The key is the area (`subject`, `method`, `self` or `social`), and
the value is a map with two fields:

| Field | Value |
|---|---|
| `where` | `format:<format key>` with a format of the pack, or `module:<module number>` with another module of the pack |
| `reason` | A non-empty text that states what the named place covers |

Module 2 of the demo pack has objectives in `subject` and `method` and names
the workshop for the other two areas:

```yaml
# modules/02-checking/module.yaml (excerpt of content/demo)
number: 2
areas_elsewhere:
  self:
    where: format:workshop
    reason: The workshop practises deciding which of one's own tasks an assistant may support.
  social:
    where: format:workshop
    reason: The workshop practises agreeing in a team how the use of an assistant is made visible.
```

The named place counts for check 3 only when it carries an objective of the
area: a format carries an area when it names an objective with that area,
whether or not its attendance counts, and a module carries an area when it
has an objective with that area. The workshop names
`m1-self-own-responsibility` and `m1-social-team-transparency` of module 1, so
it carries `self` and `social`.

### The alignment mode

`alignment` in `pack.yaml` takes `strict` or `warn`, and `strict` applies
when the field is absent.

| Mode | Checks 1 to 3 | Check 4 | Import and publish |
|---|---|---|---|
| `strict` | Errors | Warnings | A finding of checks 1 to 3 fails the import, and the import cannot be published |
| `warn` | Warnings | Warnings | The import is validated and can be published with its warnings |

A module without `objectives.yaml` fails check 3 for every area that
`areas_elsewhere` does not name. In `strict` mode, every module therefore
declares objectives or names each missing area in `areas_elsewhere`.

### Evidence

Three things provide evidence for an objective:

- an item that names the objective and is listed by an assessment;
- any other item that names the objective and whose kind has a correct
  answer, which is every kind except `poll`, so a `checklist_drill` counts;
- a companion format with `attendance_counts: true` that names the objective.

A format with `attendance_counts: false` that names an objective anchors the
objective and provides no evidence. In the minimal pack, the reference card
anchors `m1-method-release-checks`, and the checklist drill
`m1-release-drill` provides its evidence.

### The four checks

`Espalier.Catalog.Alignment.check/1` applies the four checks of README section
7, domain rule 14. The validator places each finding at the line of the
objective, the item or the area that it names, in the directory of the module
of the finding.

| Check | Rule | Finding on |
|---|---|---|
| 1 | Every objective has at least one lesson in `taught_in` and at least one piece of evidence. Each missing part is one finding. | The objective in `objectives.yaml` |
| 2 | Every item that an assessment with `counts_for_credential: true` lists names at least one objective. | The item in `items.yaml` |
| 3 | Each of the four areas has at least one objective of the module, or `areas_elsewhere` names the area with a place that carries an objective of that area. | The area in `areas_elsewhere` of `module.yaml`, or line 1 of `module.yaml` when `areas_elsewhere` does not name the area |
| 4 | The kind of the evidence fits the depth of the objective: at least one piece of its evidence has a kind of the table in "Depth and kind of evidence". An objective without evidence gets no finding from this check, because check 1 reports it. | The objective in `objectives.yaml` |

The example findings below come from a copy of the demo pack with four
changes, one per check:

1. `objectives: [m2-subject-prompt-parts]` removed from the item
   `m2-prompt-builder` in `modules/02-checking/items.yaml`, so the objective
   has no evidence;
2. `objectives: [m1-subject-next-word]` removed from the exam item
   `m1-exam-confident-answer` in `modules/01-basics/items.yaml`;
3. `where: format:handbook` in place of `where: format:workshop` for the area
   `social` in `modules/02-checking/module.yaml`; the handbook names no
   objective;
4. `depth: judge` in place of `depth: apply` for `m2-method-release-check` in
   `modules/02-checking/objectives.yaml`, whose only evidence is the checklist
   drill.

```sh
cp -r content/demo tmp/demo-changed
# apply the four changes above
nix-shell --run "mix espalier.validate tmp/demo-changed"
```

```text
modules/01-basics/items.yaml:189: item `m1-exam-confident-answer` names no objective in `objectives`, but the assessment `module-1-exam` lists it and counts for a credential
modules/02-checking/module.yaml:12: no objective of module 2 has the area `social`, and `format:handbook` named in `areas_elsewhere` carries no `social` objective
modules/02-checking/objectives.yaml:1: objective `m2-subject-prompt-parts` has no evidence: no item of an assessment, no item with a correct answer and no format with `attendance_counts: true` names it
modules/02-checking/objectives.yaml:13: warning: evidence of objective `m2-method-release-check` has the kinds `checklist_drill`, none of which fits the depth `judge` (`classification_with_case_comparison` or `format`)
```

The pack has no `alignment` field, so `strict` applies: the findings of checks
1 to 3 are errors, the finding of check 4 is a warning, and the task exits
with status 1. Two further forms of findings come from another copy of the
demo pack, with `taught_in: []` for `m2-subject-prompt-parts` and without the
entry `social` in `areas_elsewhere` of module 2. The check 3 finding then sits
at line 1 of `module.yaml`:

```text
modules/02-checking/module.yaml:1: no objective of module 2 has the area `social`, and `areas_elsewhere` does not name the area
modules/02-checking/objectives.yaml:1: objective `m2-subject-prompt-parts` names no teaching lesson in `taught_in`
```

With `alignment: warn` added to `pack.yaml` of the first copy, all four
findings are warnings and the task exits with status 0:

```text
modules/01-basics/items.yaml:189: warning: item `m1-exam-confident-answer` names no objective in `objectives`, but the assessment `module-1-exam` lists it and counts for a credential
modules/02-checking/module.yaml:12: warning: no objective of module 2 has the area `social`, and `format:handbook` named in `areas_elsewhere` carries no `social` objective
modules/02-checking/objectives.yaml:1: warning: objective `m2-subject-prompt-parts` has no evidence: no item of an assessment, no item with a correct answer and no format with `attendance_counts: true` names it
modules/02-checking/objectives.yaml:13: warning: evidence of objective `m2-method-release-check` has the kinds `checklist_drill`, none of which fits the depth `judge` (`classification_with_case_comparison` or `format`)
```

### Depth and kind of evidence

The module attribute `@evidence_for_depth` of `Espalier.Catalog.Alignment`
maps each depth to the kinds of evidence that fit it:

| Depth | Kinds of evidence that fit |
|---|---|
| `know` | `single_choice`, `multiple_choice` |
| `apply` | `slot_builder`, `classification`, `checklist_drill` |
| `judge` | `classification_with_case_comparison`, `format` |

An item of the evidence has its item kind. A `classification` item has the
kind `classification_with_case_comparison` as well when a lesson in the
`taught_in` of the objective holds a `case_comparison` block, so it fits both
`apply` and `judge`. A companion format has the kind `format`. In the minimal
pack, `m1-self-own-tasks` has the depth `judge`, is taught in
`03-own-tasks-and-team` with its `case_comparison` block, and has the
classification item `m1-sort-tasks` as evidence.

### The alignment matrix

```sh
nix-shell --run "mix espalier.alignment content/demo"
nix-shell --run "mix espalier.alignment content/demo --format csv"
nix-shell --run "mix espalier.alignment content/demo --format json"
```

`mix espalier.alignment PATH [--format text|csv|json]` runs the loader and the
validator without a database connection and prints the alignment matrix of
`Espalier.Catalog.Alignment.matrix/1`: one row per module, competence area and
depth, so twelve rows per module, with modules in number order, the areas in
the order `subject`, `method`, `self`, `social` and the depths in the order
`know`, `apply`, `judge`.

| Column | Content |
|---|---|
| `module` | The module number |
| `area` | The competence area |
| `depth` | The depth |
| `objectives` | The keys of the objectives of the module with this area and depth |
| `lessons` | The keys of their teaching lessons |
| `evidence` | Their evidence as `item:<key>` and `format:<key>` |
| `elsewhere` | The `where` of `areas_elsewhere` when the module has no objective in the area |

Each list is sorted and free of duplicates.

| Format | Output |
|---|---|
| `text` (the default) | A header line and one line per row, the fields separated by tab characters, lists joined by commas, and `-` for an empty list or a missing `elsewhere`; then the findings in the form of `mix espalier.validate` |
| `csv` | The header `module,area,depth,objectives,lessons,evidence,elsewhere` and one record per row after RFC 4180, lists joined by a space, each record ended by CRLF; the findings go to standard error |
| `json` | One object with `matrix`, `errors` and `warnings` |

The `text` output for `content/demo`:

```text
module	area	depth	objectives	lessons	evidence	elsewhere
1	subject	know	m1-subject-next-word,m1-subject-varying-answers	01-first-lesson,02-second-lesson	item:m1-exam-confident-answer,item:m1-exam-next-word,item:m1-exam-varying-answers,item:m1-fluent-figure,item:m1-how-models-write,item:m1-why-answers-vary	-
1	subject	apply	-	-	-	-
1	subject	judge	-	-	-	-
1	method	know	m1-method-check-claims	03-third-lesson	item:m1-before-use,item:m1-exam-check-claims	-
1	method	apply	-	-	-	-
1	method	judge	-	-	-	-
1	self	know	-	-	-	-
1	self	apply	-	-	-	-
1	self	judge	m1-self-own-responsibility	03-third-lesson	format:workshop	-
1	social	know	-	-	-	-
1	social	apply	-	-	-	-
1	social	judge	m1-social-team-transparency	03-third-lesson	format:workshop	-
2	subject	know	-	-	-	-
2	subject	apply	m2-subject-prompt-parts	01-first-lesson	item:m2-prompt-builder	-
2	subject	judge	-	-	-	-
2	method	know	-	-	-	-
2	method	apply	m2-method-release-check	02-second-lesson	item:m2-release-drill	-
2	method	judge	m2-method-judge-output	02-second-lesson	item:m2-judge-drafts	-
2	self	know	-	-	-	format:workshop
2	self	apply	-	-	-	format:workshop
2	self	judge	-	-	-	format:workshop
2	social	know	-	-	-	format:workshop
2	social	apply	-	-	-	format:workshop
2	social	judge	-	-	-	format:workshop
```

When the loader or the checks before the alignment report an error, the task
prints the findings without a matrix. An alignment error leaves the matrix in
place, so the matrix of a pack that fails a strict check shows where the
evidence is missing. The task exits with status 1 when an error exists, for an
unknown `--format` value and for invalid arguments, and with status 0
otherwise.

The section "Alignment" of the pack page shows the same matrix for an import
with a stored payload (task 0015, steps 7 and 11). `GET /api/admin/packs/:id`
carries `alignment` with `mode`, `matrix`, `errors` and `warnings`. The page
shows one table per module with the caption "Module `<n>`, mode `<mode>`", the
columns Area, Depth, Objectives, Lessons, Evidence and Elsewhere, and one row
per area and depth. An empty list shows `-`, and an evidence entry keeps its
prefix `item:` or `format:`. Below the tables, "Alignment errors" and
"Alignment warnings" list the findings with file, line, check number, key and
message, with their counts in the headings. A `failed` import stores no
payload, so the section states that the import holds no matrix and lists the
findings alone. For a pack whose only errors come from the alignment checks,
`mix espalier.alignment` and the check of the pack workbench show the matrix.

### Where learners and reports meet the objectives

- **Module station.** A module station opens with the objectives of the topic,
  grouped by competence area, and each item shows the objectives that it
  serves. At module completion, the station shows which objectives have
  evidence (README section 7, domain rule 15). The server derives the status
  `evidenced` from the learner's own records on the evidence linked to the
  objective: a passed attempt of an exam that holds a linked item, an
  attendance certificate for a linked format and, with
  `TRACKING_DETAIL=standard`, a correct practice answer to a linked evidence
  item. The player adds the status `practised` from the practice state, which
  stays in the browser with `TRACKING_DETAIL=minimal` and comes from the
  progress answer with `standard`. No table stores a status per objective and
  person.
- **Competence report.** The competence report of task 0014 on
  `/admin/insights`, for the role `analyst`, groups the statistics of practice
  answers by the competence area and the depth of the objectives that the
  items name, by month, and by org unit when `INSIGHTS_ORG_UNIT=true`. Polls
  stay out, and every cell below `INSIGHTS_MIN_GROUP_SIZE` is suppressed. An
  objective whose only evidence is a companion format appears in no row,
  because no report covers attendance certificates.
- **SCORM export.** The SCORM export of task 0016 writes each objective of
  the exported module to `cmi.objectives` with its key and a state of
  `passed`, `failed` or `incomplete`, derived from the evidence items in the
  package. [`scorm-export.md`](scorm-export.md), section "Objective states",
  describes the mapping for SCORM 1.2 and SCORM 2004.
