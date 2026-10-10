defmodule Espalier.Catalog.Pack.Validator do
  @moduledoc """
  Validates the loaded map of a content pack (task 0008, step 8) and builds
  its normalized map (step 9).

  The validator runs in three stages, and each stage runs only when the
  stages before it report no error:

  1. **Schema.** Every file is cast with the embedded schema of its file type
     under `Espalier.Catalog.Pack.Schema` (positive validation: unknown
     fields, wrong types and missing required fields are errors). `schema`
     of `pack.yaml` must be a supported version; for any other value the
     validator reports the errors of `pack.yaml` only.
  2. **Cross-file checks.** Keys, slugs, numbers and codes are unique in their
     scope; references resolve (`rules`, `reveals`, `lesson`, `cite`,
     `[[term:slug]]`, station `module`, assessment `items`, requirement
     targets, without `qualification_held` cycles); objective references
     resolve (`taught_in`, the `objectives` of items and formats, `domain`);
     `areas_elsewhere` names an existing format or another module; every
     item names a lesson or is listed by an assessment, an exam item names
     no lesson, and an exam with `core_required: true` has a core item;
     `refresher_mode: update_unit` has a module with `refresher_unit: true`;
     and the pack has exactly one `self_assessment` station when
     `segments.yaml` has entries and exactly one `feedback` station when
     `feedback.yaml` exists, and none otherwise.
  3. **Alignment.** `Espalier.Catalog.Alignment.check/1` runs on the
     normalized map, and `alignment_entries/2` places each finding at the
     line of its objective, item or module area.

  Only the alignment produces warnings; every other check reports an error
  in both alignment modes. Every entry has `file` (relative to the pack
  directory), `line` and `message`; an alignment entry also has `check`,
  `module` and `key`. Errors and warnings are sorted by file, line and
  message, and each list passes through `Espalier.Catalog.Pack.Entries.limit/2`:
  at most 100 entries per file and a closing entry for the rest, and every
  string member one line of at most 1,000 characters. The errors of each
  file of the schema stage, of each module and of the glossary references of
  each file are bounded that way as soon as they arise, so that a pack of
  many faulty entries holds no more of them in memory than the report keeps.

  A glossary reference is `[[term:slug]]` or `[[term:slug|label]]` with a
  slug of at most 255 characters and a label of at most 1,000 characters,
  each without `]` and the slug without `|`. A text with more openings
  `[[term:` than such references holds a malformed reference. The scan for
  references and the count of openings take time linear in the length of
  the text.
  """

  alias Espalier.Catalog.Alignment
  alias Espalier.Catalog.Pack.{Entries, LineIndex, Loader, Normalizer}

  alias Espalier.Catalog.Pack.Schema.{
    AreasElsewhere,
    Assessment,
    Block,
    Cast,
    Feedback,
    Format,
    GlossaryTerm,
    Item,
    Lesson,
    Objective,
    Pack,
    PackModule,
    Qualification,
    Rule,
    Segment,
    Source,
    Station
  }

  @top_lists [
    {"sources.yaml", :sources, Source},
    {"glossary.yaml", :glossary, GlossaryTerm},
    {"segments.yaml", :segments, Segment},
    {"stations.yaml", :stations, Station},
    {"qualifications.yaml", :qualifications, Qualification},
    {"formats.yaml", :formats, Format}
  ]

  @module_lists [
    {"objectives.yaml", :objectives, Objective},
    {"rules.yaml", :rules, Rule},
    {"items.yaml", :items, Item},
    {"assessment.yaml", :assessments, Assessment}
  ]

  # The bounds on the slug (255 characters, the length of a slug column) and
  # on the label keep each match attempt short, so that a text of many
  # openings `[[term:` takes linear time instead of quadratic time. The
  # modifier `u` makes the bounds count characters; the loader passes only
  # valid UTF-8.
  @term_regex ~r/\[\[term:([^\]|]{0,255})(?:\|([^\]]{0,1000}))?\]\]/u

  @where_message "`where` must have the form `format:<format key>` or `module:<module number>`"

  @typedoc "An entry of the report."
  @type entry :: %{
          required(:file) => String.t(),
          required(:line) => pos_integer(),
          required(:message) => String.t(),
          optional(:check) => 1..4,
          optional(:module) => integer(),
          optional(:key) => String.t()
        }

  @typedoc "The result of `run/1`."
  @type result :: %{errors: [entry()], warnings: [entry()], payload: map() | nil}

  @doc "Validates the loaded map and returns its errors and warnings."
  @spec validate(Loader.loaded()) :: {[entry()], [entry()]}
  def validate(loaded) do
    %{errors: errors, warnings: warnings} = run(loaded)
    {errors, warnings}
  end

  @doc """
  Validates the loaded map. `payload` is the normalized map whenever the
  checks before the alignment report no error, also when the alignment then
  reports errors; otherwise it is `nil`.
  """
  @spec run(Loader.loaded()) :: result()
  def run(%{files: _files, modules: _modules} = loaded) do
    with {:ok, cast} <- cast(loaded),
         [] <- check(cast) do
      payload = Normalizer.build(cast)
      {errors, warnings} = Alignment.check(payload)

      %{
        errors: loaded |> alignment_entries(errors) |> bounded(:error),
        warnings: loaded |> alignment_entries(warnings) |> bounded(:warning),
        payload: payload
      }
    else
      {:error, errors} -> %{errors: bounded(errors), warnings: [], payload: nil}
      errors when is_list(errors) -> %{errors: bounded(errors), warnings: [], payload: nil}
    end
  end

  @doc """
  Places the findings of `Espalier.Catalog.Alignment.check/1` in the pack.

  A finding on an objective or an item gets the path of `objectives.yaml` or
  `items.yaml` in the directory of the module that the finding names, and
  the line of the entry with the finding's key. A finding on a module area
  gets the path of that module's `module.yaml` and the line of the area in
  `areas_elsewhere`, or line 1 when `areas_elsewhere` does not name the
  area. Each entry keeps `check`, `module`, `key` and `message`.
  """
  @spec alignment_entries(Loader.loaded(), [map()]) :: [entry()]
  def alignment_entries(loaded, findings) do
    Enum.map(findings, fn finding ->
      {file, line} = locate_finding(loaded, finding)

      %{
        file: file,
        line: line,
        message: finding.message,
        check: finding.check,
        module: finding.module,
        key: finding.key
      }
    end)
  end

  defp locate_finding(loaded, %{module: number, file: file, key: key}) do
    case Enum.find(loaded.modules, &(module_number(&1) == number)) do
      nil ->
        {file, 1}

      module_dir ->
        {"modules/#{module_dir.dir}/#{file}",
         finding_line(Map.get(module_dir.files, file), file, key)}
    end
  end

  defp module_number(%{files: %{"module.yaml" => %{data: %{"number" => number}}}}), do: number
  defp module_number(_module_dir), do: nil

  defp finding_line(nil, _file, _key), do: 1

  defp finding_line(%{data: data, lines: lines}, "module.yaml", area) do
    case data do
      %{"areas_elsewhere" => %{^area => _}} -> LineIndex.line(lines, ["areas_elsewhere", area])
      _ -> 1
    end
  end

  defp finding_line(%{data: entries, lines: lines}, _file, key) when is_list(entries) do
    case Enum.find_index(entries, &match?(%{"key" => ^key}, &1)) do
      nil -> 1
      index -> LineIndex.line(lines, [index])
    end
  end

  defp finding_line(_doc, _file, _key), do: 1

  # Stage 1: schema

  defp cast(%{files: files}) when not is_map_key(files, "pack.yaml"),
    do: {:error, [file_error("pack.yaml", "missing file")]}

  defp cast(loaded) do
    pack_doc = Map.fetch!(loaded.files, "pack.yaml")
    {pack, pack_errors} = cast_map(pack_doc, Pack, "`pack.yaml` must hold a map")

    if pack_errors != [] and unsupported_schema?(pack_doc) do
      {:error, pack_errors}
    else
      {top, top_errors} = cast_top(loaded)

      {feedback, feedback_errors} =
        cast_map(
          Map.get(loaded.files, "feedback.yaml"),
          Feedback,
          "`feedback.yaml` must hold a map"
        )

      {modules, module_errors} = loaded.modules |> Enum.map(&cast_module/1) |> unzip()

      case pack_errors ++ top_errors ++ feedback_errors ++ module_errors do
        [] ->
          {:ok,
           Map.merge(top, %{loaded: loaded, pack: pack, feedback: feedback, modules: modules})}

        errors ->
          {:error, errors}
      end
    end
  end

  defp unsupported_schema?(%{data: %{"schema" => version}}) when not is_nil(version),
    do: version not in Pack.supported_schemas()

  defp unsupported_schema?(_doc), do: false

  defp cast_top(loaded) do
    Enum.reduce(@top_lists, {%{}, []}, fn {file, name, schema}, {top, errors} ->
      {entries, more} = cast_list(Map.get(loaded.files, file), schema)
      {Map.put(top, name, entries), errors ++ more}
    end)
  end

  defp cast_module(module_dir) do
    docs = module_dir.files

    {module, module_errors} =
      cast_map(Map.get(docs, "module.yaml"), PackModule, "`module.yaml` must hold a map")

    {lists, list_errors} =
      Enum.reduce(@module_lists, {%{}, []}, fn {file, name, schema}, {lists, errors} ->
        {entries, more} = cast_list(Map.get(docs, file), schema)
        {Map.put(lists, name, entries), errors ++ more}
      end)

    {lessons, lesson_errors} = module_dir.lessons |> Enum.map(&cast_lesson/1) |> unzip()

    cast_module =
      Map.merge(lists, %{dir: module_dir.dir, docs: docs, module: module, lessons: lessons})

    {cast_module, module_errors ++ list_errors ++ lesson_errors}
  end

  defp cast_lesson(lesson) do
    {front, front_errors} = cast_map(lesson.front, Lesson, "the front matter must hold a map")
    {blocks, block_errors} = lesson.blocks |> Enum.map(&cast_block(lesson.file, &1)) |> unzip()

    empty =
      if lesson.blocks == [], do: [file_error(lesson.file, "the lesson has no blocks")], else: []

    # The file name gives `lessons.key`, a varchar(255) column.
    long_key =
      if Cast.fits_column?(lesson.key),
        do: [],
        else: [
          file_error(
            lesson.file,
            "the lesson key must have at most #{Cast.max_length()} characters"
          )
        ]

    cast = %{
      key: lesson.key,
      file: lesson.file,
      front_doc: lesson.front,
      front: front,
      blocks: blocks
    }

    {cast, bounded(front_errors ++ block_errors ++ empty ++ long_key)}
  end

  defp cast_block(file, block) do
    attrs = %{
      "kind" => block.kind,
      "body" => block.body,
      "provenance" => block.provenance,
      "collapsed_on" => block.collapsed_on,
      "cite" => block.cite,
      "placeholder_key" => block.placeholder_key,
      "line" => block.line
    }

    changeset = Block.changeset(%Block{}, attrs)

    if changeset.valid?,
      do: {Ecto.Changeset.apply_changes(changeset), []},
      else:
        {nil,
         Enum.map(Cast.errors(changeset), fn {_path, message} ->
           %{file: file, line: block.line, message: message}
         end)}
  end

  defp cast_map(nil, _schema, _message), do: {nil, []}

  defp cast_map(%{data: data} = doc, schema, _message) when is_map(data) do
    {value, errors} = cast_entry(doc, [], schema, data)
    {value, bounded(errors)}
  end

  defp cast_map(doc, _schema, message), do: {nil, [at(doc, [], message)]}

  defp cast_list(nil, _schema), do: {[], []}

  defp cast_list(%{data: data} = doc, schema) when is_list(data) do
    {entries, errors} =
      data
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} -> cast_entry(doc, [index], schema, entry) end)
      |> unzip()

    {entries, bounded(errors)}
  end

  defp cast_list(doc, _schema),
    do: {[], [file_error(doc.file, "`#{Path.basename(doc.file)}` must hold a list of entries")]}

  defp cast_entry(doc, path, schema, data) do
    changeset = schema.changeset(struct(schema), data)

    if changeset.valid?,
      do: {Ecto.Changeset.apply_changes(changeset), []},
      else:
        {nil,
         Enum.map(Cast.errors(changeset), fn {suffix, message} ->
           at(doc, path ++ suffix, message)
         end)}
  end

  defp unzip(pairs) do
    {values, errors} = Enum.unzip(pairs)
    {values, List.flatten(errors)}
  end

  # Stage 2: cross-file checks

  defp check(cast) do
    ctx = context(cast)

    unique_errors(cast) ++
      Enum.flat_map(cast.modules, &bounded(module_errors(&1, ctx))) ++
      station_errors(cast, ctx) ++
      format_errors(cast, ctx) ++
      qualification_errors(cast, ctx) ++
      term_errors(cast, ctx)
  end

  defp context(cast) do
    %{
      sources: MapSet.new(cast.sources, & &1.key),
      glossary: MapSet.new(cast.glossary, & &1.slug),
      modules: Map.new(cast.modules, &{&1.module.number, &1}),
      objectives: cast.modules |> Enum.flat_map(& &1.objectives) |> MapSet.new(& &1.key),
      assessments: cast.modules |> Enum.flat_map(& &1.assessments) |> Map.new(&{&1.key, &1}),
      formats: Map.new(cast.formats, &{&1.key, &1}),
      qualifications: Map.new(cast.qualifications, &{&1.code, &1})
    }
  end

  ## Uniqueness

  defp unique_errors(cast) do
    top =
      [
        {"sources.yaml", cast.sources, :key, "source key"},
        {"glossary.yaml", cast.glossary, :slug, "glossary slug"},
        {"segments.yaml", cast.segments, :key, "segment key"},
        {"formats.yaml", cast.formats, :key, "format key"},
        {"qualifications.yaml", cast.qualifications, :code, "qualification code"}
      ]
      |> Enum.flat_map(fn {file, entries, field, what} ->
        cast |> top_doc(file) |> located(entries, field) |> duplicates(what)
      end)

    pack_wide =
      [
        {Enum.map(cast.modules, &{&1.module.number, loc(&1.docs["module.yaml"], ["number"])}),
         "module number"},
        {module_located(cast, "objectives.yaml", :objectives), "objective key"},
        {module_located(cast, "items.yaml", :items), "item key"},
        {module_located(cast, "assessment.yaml", :assessments), "assessment key"}
      ]
      |> Enum.flat_map(fn {entries, what} -> duplicates(entries, what) end)

    per_module =
      Enum.flat_map(cast.modules, fn module ->
        rules = module.docs |> Map.get("rules.yaml") |> located(module.rules, :number)

        positions =
          Enum.map(module.lessons, &{&1.front.position, loc(&1.front_doc, ["position"])})

        duplicates(rules, "rule number") ++ duplicates(positions, "lesson position")
      end)

    top ++ pack_wide ++ per_module
  end

  defp module_located(cast, file, name) do
    Enum.flat_map(
      cast.modules,
      &(&1.docs |> Map.get(file) |> located(Map.fetch!(&1, name), :key))
    )
  end

  defp located(_doc, [], _field), do: []

  defp located(doc, entries, field) do
    entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      {Map.fetch!(entry, field), loc(doc, [index, Atom.to_string(field)])}
    end)
  end

  defp duplicates(entries, what) do
    entries
    |> Enum.reduce({[], %{}}, fn {value, loc}, {errors, seen} ->
      case Map.fetch(seen, value) do
        {:ok, first} ->
          message =
            "duplicate #{what} `#{value}`, first used in `#{first.file}` at line #{first.line}"

          {[Map.put(loc, :message, message) | errors], seen}

        :error ->
          {errors, Map.put(seen, value, loc)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  ## Modules

  defp module_errors(module, ctx) do
    item_errors(module, ctx) ++
      rule_errors(module, ctx) ++
      objective_errors(module) ++
      assessment_errors(module) ++
      block_errors(module, ctx) ++
      elsewhere_errors(module, ctx) ++
      item_use_errors(module) ++
      core_errors(module)
  end

  defp item_errors(module, ctx) do
    doc = Map.get(module.docs, "items.yaml")
    lessons = lesson_keys(module)
    rules = MapSet.new(module.rules, & &1.number)

    module.items
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      lesson_errors(doc, index, item.lesson, lessons) ++
        list_ref_errors(
          doc,
          [index, "rules"],
          item.rules,
          rules,
          &"unknown rule `#{&1}` of this module in `rules`"
        ) ++
        list_ref_errors(
          doc,
          [index, "reveals"],
          item.reveals,
          lessons,
          &"unknown lesson `#{&1}` of this module in `reveals`"
        ) ++
        list_ref_errors(
          doc,
          [index, "objectives"],
          item.objectives,
          ctx.objectives,
          &"unknown objective `#{&1}` in `objectives`"
        ) ++
        cite_errors(doc, [index, "cite"], item.cite, ctx)
    end)
  end

  defp lesson_errors(_doc, _index, nil, _lessons), do: []

  defp lesson_errors(doc, index, lesson, lessons) do
    if MapSet.member?(lessons, lesson),
      do: [],
      else: [at(doc, [index, "lesson"], "unknown lesson `#{lesson}` of this module in `lesson`")]
  end

  defp rule_errors(module, ctx) do
    doc = Map.get(module.docs, "rules.yaml")

    module.rules
    |> Enum.with_index()
    |> Enum.flat_map(fn {rule, index} -> cite_errors(doc, [index, "cite"], rule.cite, ctx) end)
  end

  defp objective_errors(module) do
    doc = Map.get(module.docs, "objectives.yaml")
    lessons = lesson_keys(module)
    domains = MapSet.new(module.module.domains || [])

    module.objectives
    |> Enum.with_index()
    |> Enum.flat_map(fn {objective, index} ->
      list_ref_errors(
        doc,
        [index, "taught_in"],
        objective.taught_in,
        lessons,
        &"unknown lesson `#{&1}` of this module in `taught_in`"
      ) ++ domain_errors(doc, index, objective.domain, domains)
    end)
  end

  defp domain_errors(_doc, _index, nil, _domains), do: []

  defp domain_errors(doc, index, domain, domains) do
    if MapSet.member?(domains, domain),
      do: [],
      else: [
        at(doc, [index, "domain"], "`domain` `#{domain}` is not one of the module's `domains`")
      ]
  end

  defp assessment_errors(module) do
    doc = Map.get(module.docs, "assessment.yaml")
    items = MapSet.new(module.items, & &1.key)

    module.assessments
    |> Enum.with_index()
    |> Enum.flat_map(fn {assessment, index} ->
      list_ref_errors(
        doc,
        [index, "items"],
        assessment.items,
        items,
        &"unknown item `#{&1}` of this module in `items`"
      )
    end)
  end

  defp block_errors(module, ctx) do
    for lesson <- module.lessons,
        block <- lesson.blocks,
        cite <- block.cite || [],
        message <- cite_messages(cite, ctx),
        do: %{file: lesson.file, line: block.line, message: message}
  end

  defp elsewhere_errors(%{module: %PackModule{areas_elsewhere: nil}}, _ctx), do: []

  defp elsewhere_errors(%{module: %PackModule{areas_elsewhere: areas}} = module, ctx) do
    doc = Map.get(module.docs, "module.yaml")

    for {area, %{where: where}} <- areas |> Map.take(AreasElsewhere.areas()) |> Enum.sort(),
        message <- where_errors(where, module, ctx),
        do: at(doc, ["areas_elsewhere", Atom.to_string(area), "where"], message)
  end

  defp where_errors("format:" <> key, _module, ctx) do
    if Map.has_key?(ctx.formats, key), do: [], else: ["unknown format `#{key}` in `where`"]
  end

  defp where_errors("module:" <> digits, module, ctx) do
    case Integer.parse(digits) do
      {number, ""} when number == module.module.number ->
        ["`where` names the module's own number `#{number}`"]

      {number, ""} ->
        if Map.has_key?(ctx.modules, number),
          do: [],
          else: ["unknown module `#{number}` in `where`"]

      _ ->
        [@where_message]
    end
  end

  defp where_errors(_where, _module, _ctx), do: [@where_message]

  defp item_use_errors(module) do
    doc = Map.get(module.docs, "items.yaml")
    listed = module.assessments |> Enum.flat_map(& &1.items) |> MapSet.new()

    exams =
      for %{kind: :exam} = exam <- Enum.reverse(module.assessments),
          item <- exam.items,
          into: %{},
          do: {item, exam.key}

    module.items
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      cond do
        Map.has_key?(exams, item.key) and not is_nil(item.lesson) ->
          [
            at(
              doc,
              [index, "lesson"],
              "the item `#{item.key}` of the exam `#{exams[item.key]}` must not name a `lesson`"
            )
          ]

        is_nil(item.lesson) and not MapSet.member?(listed, item.key) ->
          [
            at(
              doc,
              [index],
              "the item `#{item.key}` names no `lesson`, and no assessment lists it"
            )
          ]

        true ->
          []
      end
    end)
  end

  defp core_errors(module) do
    doc = Map.get(module.docs, "assessment.yaml")
    core = for %{core: true, key: key} <- module.items, into: MapSet.new(), do: key

    for {%{kind: :exam, core_required: true} = exam, index} <- Enum.with_index(module.assessments),
        not Enum.any?(exam.items, &MapSet.member?(core, &1)),
        do:
          at(
            doc,
            [index, "core_required"],
            "the exam `#{exam.key}` has `core_required: true` and no core item"
          )
  end

  defp lesson_keys(module), do: MapSet.new(module.lessons, & &1.key)

  ## Top-level files

  defp station_errors(cast, ctx) do
    doc = top_doc(cast, "stations.yaml")

    module_refs =
      for {%{kind: :module, module: number}, index} <- Enum.with_index(cast.stations),
          not Map.has_key?(ctx.modules, number),
          do: at(doc, [index, "module"], "unknown module `#{number}` in `module`")

    module_refs ++
      count_errors(cast, doc, :self_assessment, cast.segments != [], {
        "the pack needs a `self_assessment` station, because `segments.yaml` has entries",
        "a `self_assessment` station needs entries in `segments.yaml`"
      }) ++
      count_errors(cast, doc, :feedback, not is_nil(cast.feedback), {
        "the pack needs a `feedback` station, because `feedback.yaml` exists",
        "a `feedback` station needs `feedback.yaml`"
      })
  end

  defp count_errors(cast, doc, kind, needed?, {missing, unneeded}) do
    found = for {%{kind: ^kind}, index} <- Enum.with_index(cast.stations), do: index

    cond do
      needed? and found == [] ->
        [file_error("stations.yaml", missing)]

      needed? ->
        found
        |> Enum.drop(1)
        |> Enum.map(&at(doc, [&1, "kind"], "the pack has one `#{kind}` station only"))

      true ->
        Enum.map(found, &at(doc, [&1, "kind"], unneeded))
    end
  end

  defp format_errors(cast, ctx) do
    doc = top_doc(cast, "formats.yaml")

    cast.formats
    |> Enum.with_index()
    |> Enum.flat_map(fn {format, index} ->
      list_ref_errors(
        doc,
        [index, "objectives"],
        format.objectives,
        ctx.objectives,
        &"unknown objective `#{&1}` in `objectives`"
      )
    end)
  end

  defp qualification_errors(cast, ctx) do
    doc = top_doc(cast, "qualifications.yaml")
    graph = Map.new(cast.qualifications, &{&1.code, held_codes(&1)})
    refresher_unit? = Enum.any?(cast.modules, & &1.module.refresher_unit)

    cast.qualifications
    |> Enum.with_index()
    |> Enum.flat_map(fn {qualification, index} ->
      requirement_errors(doc, index, qualification, ctx, graph) ++
        refresher_errors(doc, index, qualification, refresher_unit?)
    end)
  end

  defp held_codes(qualification),
    do: for(%{kind: :qualification_held, target: code} <- qualification.requirements, do: code)

  defp requirement_errors(doc, index, qualification, ctx, graph) do
    for {requirement, position} <- Enum.with_index(qualification.requirements),
        message <-
          target_errors(requirement, ctx) ++ cycle_errors(requirement, qualification, graph),
        do: at(doc, [index, "requirements", position, "target"], message)
  end

  defp target_errors(%{kind: :module_completed, target: number}, ctx) do
    if Map.has_key?(ctx.modules, number), do: [], else: ["unknown module `#{number}` in `target`"]
  end

  defp target_errors(%{kind: :assessment_passed, target: key}, ctx) do
    case Map.fetch(ctx.assessments, key) do
      {:ok, %{kind: :exam}} -> []
      {:ok, _practice} -> ["the assessment `#{key}` in `target` is no exam"]
      :error -> ["unknown assessment `#{key}` in `target`"]
    end
  end

  defp target_errors(%{kind: :attendance, target: key}, ctx) do
    case Map.fetch(ctx.formats, key) do
      {:ok, %{attendance_counts: true}} -> []
      {:ok, _format} -> ["the format `#{key}` in `target` has `attendance_counts: false`"]
      :error -> ["unknown format `#{key}` in `target`"]
    end
  end

  defp target_errors(%{kind: :qualification_held, target: code}, ctx) do
    if Map.has_key?(ctx.qualifications, code),
      do: [],
      else: ["unknown qualification `#{code}` in `target`"]
  end

  defp target_errors(%{kind: :policy_acknowledged}, _ctx), do: []

  defp cycle_errors(%{kind: :qualification_held, target: code}, qualification, graph) do
    if reaches?(graph, [code], qualification.code, MapSet.new()),
      do: [
        "the `qualification_held` requirements of `#{qualification.code}` and `#{code}` form a cycle"
      ],
      else: []
  end

  defp cycle_errors(_requirement, _qualification, _graph), do: []

  defp reaches?(_graph, [], _goal, _seen), do: false
  defp reaches?(_graph, [goal | _rest], goal, _seen), do: true

  defp reaches?(graph, [node | rest], goal, seen) do
    if MapSet.member?(seen, node),
      do: reaches?(graph, rest, goal, seen),
      else: reaches?(graph, Map.get(graph, node, []) ++ rest, goal, MapSet.put(seen, node))
  end

  defp refresher_errors(doc, index, %{refresher_mode: :update_unit}, false),
    do: [
      at(
        doc,
        [index, "refresher_mode"],
        "`refresher_mode: update_unit` needs a module with `refresher_unit: true`"
      )
    ]

  defp refresher_errors(_doc, _index, _qualification, _refresher_unit?), do: []

  ## Glossary references

  defp term_errors(cast, ctx) do
    docs =
      Map.values(cast.loaded.files) ++
        Enum.flat_map(cast.modules, fn module ->
          Map.values(module.docs) ++ Enum.map(module.lessons, & &1.front_doc)
        end)

    yaml =
      Enum.flat_map(docs, fn doc ->
        bounded(
          for {path, text} <- strings(doc.data, []),
              message <- term_messages(text, ctx),
              do: at(doc, path, message)
        )
      end)

    blocks =
      for module <- cast.modules,
          lesson <- module.lessons,
          entry <-
            bounded(
              for block <- lesson.blocks,
                  message <- term_messages(block.body, ctx),
                  do: %{file: lesson.file, line: block.line, message: message}
            ),
          do: entry

    yaml ++ blocks
  end

  defp strings(value, path) when is_binary(value), do: [{path, value}]

  defp strings(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} -> strings(entry, path ++ [index]) end)
  end

  defp strings(value, path) when is_map(value),
    do: Enum.flat_map(value, fn {key, entry} -> strings(entry, path ++ [key]) end)

  defp strings(_value, _path), do: []

  defp term_messages(text, ctx) do
    references = Regex.scan(@term_regex, text)
    opened = length(:binary.matches(text, "[[term:"))

    malformed =
      if opened > length(references), do: ["malformed glossary reference `[[term:`"], else: []

    Enum.flat_map(references, &reference_messages(&1, ctx)) ++ malformed
  end

  defp reference_messages([reference, slug | label], ctx) do
    unknown =
      if MapSet.member?(ctx.glossary, slug),
        do: [],
        else: ["unknown glossary term `#{slug}` in `#{reference}`"]

    empty =
      if label != [] and String.trim(hd(label)) == "",
        do: ["empty label in `#{reference}`"],
        else: []

    unknown ++ empty
  end

  ## References

  defp list_ref_errors(doc, path, values, known, message) do
    for {value, index} <- Enum.with_index(values || []),
        not MapSet.member?(known, value),
        do: at(doc, path ++ [index], message.(value))
  end

  defp cite_errors(doc, path, cites, ctx) do
    for {cite, index} <- Enum.with_index(cites || []),
        message <- cite_messages(cite, ctx),
        do: at(doc, path ++ [index], message)
  end

  defp cite_messages(cite, ctx) do
    [source | _locator] = String.split(cite, "#", parts: 2)
    if MapSet.member?(ctx.sources, source), do: [], else: ["unknown source `#{source}` in `cite`"]
  end

  # Entries

  defp top_doc(cast, file), do: Map.get(cast.loaded.files, file)

  defp loc(doc, path), do: %{file: doc.file, line: LineIndex.line(doc.lines, path)}

  defp at(doc, path, message), do: doc |> loc(path) |> Map.put(:message, message)

  defp file_error(file, message), do: %{file: file, line: 1, message: message}

  # Sorts the entries by file, line and message and keeps at most 100 per
  # file. The entries of a single file or module pass through here as soon
  # as they arise, and all of them again at the end of run/1.
  defp bounded(entries, kind \\ :error), do: entries |> Entries.sort() |> Entries.limit(kind)
end
