defmodule Espalier.Catalog.Pack do
  @moduledoc """
  The content pack format: the YAML and Markdown files that define a program.

  A content pack is a directory that holds one program: its metadata, its
  modules, the lessons of each module, the practice items and exams, the
  learning objectives, and the qualifications that a learner can earn. Authors
  write the pack as plain files and keep them in version control. Espalier
  reads a pack with a loader, checks it with a validator, and publishes it to
  the catalog. This page is the entry point to the documentation of the
  format. Each file type has a schema module that lists its fields.

  ## Directory layout

  The loader reads the following files and no others:

  ```text
  my-pack/
    pack.yaml
    sources.yaml
    glossary.yaml
    segments.yaml
    stations.yaml
    feedback.yaml
    qualifications.yaml
    formats.yaml
    modules/
      01-basics/
        module.yaml
        objectives.yaml
        rules.yaml
        items.yaml
        assessment.yaml
        lessons/
          01-first-lesson.md
          02-second-lesson.md
  ```

  Other files in the directory are not read. The directory `modules/` holds
  one directory per module, and the name of a module directory and the name
  of a lesson file without `.md` use the key format described under
  "Conventions". The complete example is the demo pack in `content/demo` of
  the repository.

  ## Files and schema modules

  | File | Module | Required | Holds |
  |---|---|---|---|
  | `pack.yaml` | `Espalier.Catalog.Pack.Schema.Pack` | Yes | The format version, key, title, locale, license, version and alignment mode of the program |
  | `sources.yaml` | `Espalier.Catalog.Pack.Schema.Source` | No | The sources that `cite` entries point to |
  | `glossary.yaml` | `Espalier.Catalog.Pack.Schema.GlossaryTerm` | No | The glossary terms that text references as `[[term:slug]]` |
  | `segments.yaml` | `Espalier.Catalog.Pack.Schema.Segment` | No | The learner segments with their default path |
  | `stations.yaml` | `Espalier.Catalog.Pack.Schema.Station` | No | The stations of the program path |
  | `feedback.yaml` | `Espalier.Catalog.Pack.Schema.Feedback` | No | The introduction and the questions of the `feedback` station |
  | `qualifications.yaml` | `Espalier.Catalog.Pack.Schema.Qualification` | No | The qualifications with their requirements |
  | `formats.yaml` | `Espalier.Catalog.Pack.Schema.Format` | No | The companion formats |
  | `modules/<dir>/module.yaml` | `Espalier.Catalog.Pack.Schema.PackModule` | Yes, per module | The number, title, summary, phases, domains, the required flags `single_path` and `refresher_unit`, and the optional `areas_elsewhere` of a module |
  | `modules/<dir>/objectives.yaml` | `Espalier.Catalog.Pack.Schema.Objective` | No | The learning objectives of a module |
  | `modules/<dir>/rules.yaml` | `Espalier.Catalog.Pack.Schema.Rule` | No | The numbered rules of a module |
  | `modules/<dir>/items.yaml` | `Espalier.Catalog.Pack.Schema.Item` | No | The practice and exam items of a module |
  | `modules/<dir>/assessment.yaml` | `Espalier.Catalog.Pack.Schema.Assessment` | No | The practice sets and exams, each a list of item keys |
  | `modules/<dir>/lessons/<key>.md` (front matter) | `Espalier.Catalog.Pack.Schema.Lesson` | Yes, at least one per module | The title and position of a lesson |
  | `modules/<dir>/lessons/<key>.md` (body) | `Espalier.Catalog.Pack.Schema.Block` | Yes, at least one block per lesson | The blocks of a lesson, split by `Espalier.Catalog.Pack.Directives` |

  The pack needs at least one module directory. Two files depend on others:
  a pack whose `segments.yaml` has entries needs exactly one
  `self_assessment` station, and a pack with a `feedback.yaml` needs exactly
  one `feedback` station. Without entries in `segments.yaml`, or without
  `feedback.yaml`, a station of that kind is an error.

  Entries of a list file use further schema modules for their embedded
  structures: `Espalier.Catalog.Pack.Schema.Requirement`,
  `Espalier.Catalog.Pack.Schema.Question`,
  `Espalier.Catalog.Pack.Schema.QuestionOption`,
  `Espalier.Catalog.Pack.Schema.AreasElsewhere`,
  `Espalier.Catalog.Pack.Schema.Elsewhere`,
  `Espalier.Catalog.Pack.Schema.Option`,
  `Espalier.Catalog.Pack.Schema.Slot`,
  `Espalier.Catalog.Pack.Schema.SlotBuilderConfig`,
  `Espalier.Catalog.Pack.Schema.ChecklistDrillConfig`,
  `Espalier.Catalog.Pack.Schema.ChecklistCheck`,
  `Espalier.Catalog.Pack.Schema.ClassificationConfig`,
  `Espalier.Catalog.Pack.Schema.ClassificationCategory` and
  `Espalier.Catalog.Pack.Schema.ClassificationCase`.

  ## Conventions

  Every file of a pack follows these rules. `Espalier.Catalog.Pack.Schema.Cast`
  implements the checks on values, and `Espalier.Catalog.Pack.Loader`
  implements the checks on files.

  **Strict types, no coercion.** A value must have the type of its field.
  A string is not empty after trimming whitespace and holds no NUL character. An integer is at most
  2,147,483,647. A boolean is `true` or `false`. An enumerated field takes
  one of the values that its error message lists. A list field takes a list,
  and an embedded entry takes a map. YAML strings that look like numbers or
  booleans stay strings, and YAML numbers are never turned into strings, so
  `"1"` is no integer and `1.0` is no string.

  **Quote versions and dates.** The `version` of `pack.yaml` is a string, so
  write `version: "1.0"`. An unquoted `1.0` is a number and fails the type
  check. Dates are strings in the form `YYYY-MM-DD` with a four-digit year,
  for example `edition_date: "2026-03-01"`, and the date must exist.

  **Key format.** Keys, slugs, codes, domains, placeholder keys, module
  directory names and lesson file names match `^[a-z0-9][a-z0-9-]*$` as a
  whole value: lowercase letters, digits and hyphens, starting with a letter
  or a digit.

  **Absent and null.** A field set to `null` counts as absent. An optional
  field may be absent or `null`. A required field that is absent or `null` is
  an error.

  **Unknown fields.** A field name that the schema does not define is an
  error (`unknown field`), at every level of an entry, except inside the free
  mappings `config` of a station and `expected` of a classification item. The cast creates no
  atoms from file content.

  **Limits.** A file holds at most 1 MiB (1,048,576 bytes), and the decoded
  data of the whole pack at most 32 MiB. One YAML text holds at most 50,000
  nodes, nests at most 32 levels deep and holds at most 2 MiB of strings
  after alias expansion. The pack directory holds at most 20,000 entries and
  nests at most 32 levels. A string that the publisher writes to a
  `varchar(255)` column, for example a key, a title, a label, a URL or the
  locator of a citation, has at most 255 characters. The `config` of a
  station holds no float and no integer beyond 9,007,199,254,740,991 in
  either direction. A report keeps at most 100 errors per file.

  **YAML restrictions.** A file holds one YAML document. A duplicate map key,
  a map key that is not a string, a merge key (`<<`) and a type outside the
  YAML core schema are errors. Anchors and aliases are allowed within the
  limits above, except an anchor on a flow collection or on an empty value.

  **UTF-8 and control characters.** Every file is valid UTF-8. A text holds
  no control character other than tab, line feed and carriage return, which
  excludes U+0000 to U+0008, U+000B, U+000C, U+000E to U+001F and U+007F. The
  error names the line and the column of the first one. A YAML escape that
  produces such a character is an error as well.

  **Symbolic links.** The loader rejects every symbolic link and every entry
  that is neither a directory nor a regular file, in the root and in every
  directory, including directories whose files it does not read. Each such
  entry is an error of the load.

  **List order gives position.** Segments, stations, objectives, items,
  options, blocks, companion formats and the items of an assessment keep the
  order of their file. Modules follow `number`, lessons follow `position`
  of their front matter, rules follow `number`, and qualifications follow
  the optional `position` or else the order of their file. Sources,
  assessments and glossary terms are sorted by key or slug.

  **Glossary references.** Any string of any YAML file and any block body may
  reference a glossary term as `[[term:slug]]` or `[[term:slug|label]]`. The
  slug names an entry of `glossary.yaml`. A slug has at most 255 characters,
  a label at most 1,000, and an opening `[[term:` without a closing `]]` is
  an error.

  **Citations.** A `cite` entry is a string of the form `source-key#locator`.
  The part before the first `#` is the `key` of an entry in `sources.yaml`.
  The locator is the text after it, for example `assistant-manual#Chapter 2`,
  and has at most 255 characters. A `quote` block cites at least one source.

  ## How a pack flows

  1. `Espalier.Catalog.Pack.Loader.load/1` reads the directory into a map of
     parsed files with a line index. It applies the rules for files, links,
     encoding and limits. The body of each lesson goes to
     `Espalier.Catalog.Pack.Directives.split/2`, which splits it into blocks.
  2. `Espalier.Catalog.Pack.Validator.run/1` casts every file with its schema
     module, then checks the references between files, then runs the
     alignment checks. A stage runs only when the stages before it report no
     error. The result holds errors, warnings and the normalized map of the
     pack (the payload).
  3. `Espalier.Catalog.Alignment` checks that learning objectives, lessons,
     items and companion formats fit together. The `alignment` field of
     `pack.yaml` (`strict` by default, or `warn`) decides whether checks 1 to
     3 report errors or warnings.
  4. `Espalier.Catalog.Pack.Importer.import/2` runs the loader and the
     validator and stores the outcome as a `PackImport`, with the status
     `validated` or `failed`. `mix espalier.import` and
     `Espalier.Release.import_pack/2` use it through
     `Espalier.Catalog.Pack.Report.run_import/2`. The pack upload of the admin
     area uses `Espalier.Catalog.Pack.Importer.prepare/2`, whose
     changeset `import/2` inserts. `mix espalier.validate` and `mix espalier.alignment` store
     nothing.
  5. `Espalier.Catalog.Pack.Publisher.publish/1` applies the payload of a
     validated import to the catalog tables. Rows with a key are updated in
     place, so republishing a pack with the same `key` updates its program.

  The inverse direction is `Espalier.Interop.PackWriter`, which writes a
  published program back to disk as a pack.

  Four mix tasks run these steps from the command line:

  | Task | Module | What it does |
  |---|---|---|
  | `mix espalier.validate PATH` | `Mix.Tasks.Espalier.Validate` | Loads and validates the pack without a database connection and prints one line per error and warning |
  | `mix espalier.alignment PATH` | `Mix.Tasks.Espalier.Alignment` | Prints the alignment matrix as text, CSV or JSON |
  | `mix espalier.import PATH` | `Mix.Tasks.Espalier.Import` | Imports the pack and publishes it, or keeps it as a draft with `--draft` |
  | `mix espalier.export SLUG PATH` | `Mix.Tasks.Espalier.Export` | Writes a published program as a pack into a new or empty directory |

  ## Cross-file references

  The validator resolves these references after the schema stage. An
  unresolved reference is an error at the line of the referencing value.

  | Reference | Written in | Resolves to |
  |---|---|---|
  | `cite` | `items.yaml`, `rules.yaml`, lesson blocks | The `key` of an entry in `sources.yaml` |
  | `[[term:slug]]` | Any string of any YAML file, any block body | The `slug` of an entry in `glossary.yaml` |
  | `module` of a `module` station | `stations.yaml` | The `number` in a `module.yaml` |
  | `target` of `module_completed` | `qualifications.yaml` | The `number` in a `module.yaml` |
  | `target` of `assessment_passed` | `qualifications.yaml` | The `key` of an exam in an `assessment.yaml` |
  | `target` of `attendance` | `qualifications.yaml` | The `key` of a format with `attendance_counts: true` |
  | `target` of `qualification_held` | `qualifications.yaml` | The `code` of another qualification, without a cycle |
  | `where` of `areas_elsewhere` | `module.yaml` | `format:<format key>` or `module:<number>` of another module |
  | `taught_in` | `objectives.yaml` | Lesson keys of the same module |
  | `domain` | `objectives.yaml` | One of the `domains` of the same module |
  | `objectives` | `items.yaml`, `formats.yaml` | Objective keys of any module of the pack |
  | `lesson`, `reveals` | `items.yaml` | Lesson keys of the same module |
  | `rules` | `items.yaml` | Rule numbers of the same module |
  | `items` | `assessment.yaml` | Item keys of the same module |

  Keys are unique in their scope. Module numbers, objective keys, item keys
  and assessment keys are unique in the pack. Rule numbers and lesson
  positions are unique in their module. The keys of sources, formats and
  segments, the slugs of glossary terms and the codes of qualifications are
  unique in their file.

  The requirement kind `policy_acknowledged` names a policy key that the
  validator does not resolve against the files of the pack.

  ## See also

  * [Content packs](content-packs.md), the reference for every file, field and
    check.
  * [Course YAML building blocks](course-yaml.md), the introduction to the
    files of a course.
  * [Pack workbench](pack-workbench.md), editing the files of a pack in the
    admin area.
  """
end
