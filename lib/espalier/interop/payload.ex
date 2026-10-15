defmodule Espalier.Interop.Payload do
  @moduledoc """
  The content of a published program in the shape of the normalized map of
  a content pack (task 0016, step 1; task 0008, step 9). The SCORM export
  (`Espalier.Interop.ExportWorker`) and the pack writer
  (`Espalier.Interop.PackWriter`) read content through this module only.

  `build/1` reads the live catalog rows of a program. It skips every row
  whose `archived_at` is set and every join row or citation that points to
  such a row or to a row of another program, as `EspalierWeb.CatalogJSON`
  does for the learner views. The map follows the rules of
  `Espalier.Catalog.Pack.Normalizer`: string keys, every field present,
  enum values and dates as strings, positioned lists in position order and
  every other list sorted ascending. The join tables hold no position, so
  the `rules` of an item follow the rule number, the `reveals` of an item
  the lesson key, and the `objectives` of items and formats and the
  `taught_in` of objectives the key, which is the order rule of the
  normalized map. A pack imported from the output of the pack writer
  therefore gives the same payload.

  The fields of `pack.yaml` that no live table holds (`schema`, `license`
  and `alignment`) come from the last `PackImport` with status `published`
  whose `pack_key` equals the slug of the program. `alignment` carries the
  default `strict` filled in, as the normalized map holds it.

  `module/2` cuts the payload of one module out of a payload, in the shape
  of `content.json` of a SCORM package without `schema` and `policies`.
  """

  import Ecto.Query, warn: false

  alias Espalier.Catalog.{
    Assessment,
    AssessmentItem,
    Block,
    Citation,
    CompanionFormat,
    GlossaryTerm,
    Item,
    LearningObjective,
    Lesson,
    Option,
    PackImport,
    Program,
    Qualification,
    Requirement,
    Rule,
    Segment,
    Source,
    Station
  }

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Repo

  # A glossary reference, as `Espalier.Catalog.Pack.Validator` reads it.
  @term_regex ~r/\[\[term:([^\]|]{0,255})(?:\|([^\]]{0,1000}))?\]\]/u

  @typedoc "A payload in the shape of the normalized map of a content pack."
  @type t :: %{required(String.t()) => term()}

  @doc """
  Returns the payload of the live rows of `program`. The caller checks that
  the program is published.
  """
  @spec build(Ecto.Schema.schema()) :: t()
  def build(%Program{id: program_id} = program) do
    pack = pack_fields(program.slug)
    rows = live_rows(program_id)

    %{
      "schema" => pack.schema,
      "key" => program.slug,
      "title" => program.title,
      "locale" => program.locale,
      "license" => pack.license,
      "version" => program.pack_version,
      "alignment" => pack.alignment,
      "sources" => Enum.map(rows.sources, &source/1),
      "glossary" => Enum.map(rows.glossary, &term/1),
      "segments" => Enum.map(rows.segments, &segment/1),
      "stations" => Enum.map(rows.stations, &station(&1, rows)),
      "qualifications" => Enum.map(rows.qualifications, &qualification(&1, rows)),
      "formats" => Enum.map(rows.formats, &format(&1, rows)),
      "modules" => Enum.map(rows.modules, &module_payload(&1, rows))
    }
  end

  @doc """
  Returns the content of module `number` of `payload`: `program` (slug,
  title, locale), `module` (the module with its lessons, rules, items,
  assessments, objectives and `areas_elsewhere`), `glossary` (the terms that
  blocks of the module reference with `[[term:...]]`), `sources` (the
  sources that the citations of its blocks, rules and items name) and
  `formats` (the companion formats that name an objective of the module,
  with their `objectives`), each in the shape of the full payload.

  Raises `ArgumentError` when the payload has no module `number`.
  """
  @spec module(t(), integer()) :: t()
  def module(%{"modules" => modules} = payload, number) when is_integer(number) do
    module =
      Enum.find(modules, &(&1["number"] == number)) ||
        raise ArgumentError, "the payload has no module #{number}"

    objective_keys = MapSet.new(module["objectives"], & &1["key"])
    term_slugs = module |> block_bodies() |> Enum.flat_map(&term_slugs/1) |> MapSet.new()
    source_keys = module |> cites() |> MapSet.new(&source_key/1)

    %{
      "program" => %{
        "slug" => payload["key"],
        "title" => payload["title"],
        "locale" => payload["locale"]
      },
      "module" => module,
      "glossary" => Enum.filter(payload["glossary"], &MapSet.member?(term_slugs, &1["slug"])),
      "sources" => Enum.filter(payload["sources"], &MapSet.member?(source_keys, &1["key"])),
      "formats" =>
        Enum.filter(payload["formats"], fn format ->
          Enum.any?(format["objectives"], &MapSet.member?(objective_keys, &1))
        end)
    }
  end

  ## Module content

  defp block_bodies(module) do
    for lesson <- module["lessons"], block <- lesson["blocks"], do: block["body"] || ""
  end

  defp term_slugs(text) do
    @term_regex
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.map(&hd/1)
  end

  defp cites(module) do
    blocks = for lesson <- module["lessons"], block <- lesson["blocks"], do: block["cite"]
    rules = Enum.map(module["rules"], & &1["cite"])
    items = Enum.map(module["items"], & &1["cite"])
    List.flatten([blocks, rules, items])
  end

  defp source_key(cite), do: cite |> String.split("#", parts: 2) |> hd()

  ## pack.yaml

  defp pack_fields(slug) do
    payload =
      Repo.one(
        from i in PackImport,
          where: i.pack_key == ^slug and i.status == :published,
          order_by: [desc: i.published_at, desc: i.inserted_at, desc: i.id],
          limit: 1,
          select: i.payload
      ) || %{}

    %{
      schema: Map.get(payload, "schema", 1),
      license: Map.get(payload, "license"),
      alignment: Map.get(payload, "alignment") || "strict"
    }
  end

  ## Live rows

  defp live_rows(program_id) do
    modules =
      Repo.all(
        from m in CatalogModule,
          where: m.program_id == ^program_id and is_nil(m.archived_at),
          order_by: m.number
      )

    module_ids = Enum.map(modules, & &1.id)
    lessons = live_children(Lesson, module_ids, [:position, :key])
    rules = live_children(Rule, module_ids, [:number])
    objectives = live_children(LearningObjective, module_ids, [:position, :key])
    items = live_children(Item, module_ids, [:position, :key])
    assessments = live_children(Assessment, module_ids, [:key])
    sources = program_rows(Source, program_id, [:key])
    formats = program_rows(CompanionFormat, program_id, [:position, :key])
    qualifications = program_rows(Qualification, program_id, [:position, :code])

    lesson_keys = keys_by_id(lessons)
    objective_keys = keys_by_id(objectives)
    item_keys = keys_by_id(items)
    source_keys = keys_by_id(sources)
    rule_numbers = Map.new(rules, &{&1.id, &1.number})
    blocks = blocks(Map.keys(lesson_keys))

    %{
      modules: modules,
      module_numbers: Map.new(modules, &{&1.id, &1.number}),
      lessons: lessons,
      lesson_keys: lesson_keys,
      rules: rules,
      objectives: objectives,
      items: items,
      assessments: assessments,
      sources: sources,
      glossary: program_rows(GlossaryTerm, program_id, [:slug]),
      segments: program_rows(Segment, program_id, [:position, :key]),
      stations: stations(program_id),
      formats: formats,
      qualifications: qualifications,
      requirements: requirements(Enum.map(qualifications, & &1.id)),
      blocks: blocks,
      options: options(Map.keys(item_keys)),
      cites: cites_by_parent(program_id, source_keys, Enum.map(blocks, & &1.id)),
      taught_in:
        LearningObjective
        |> linked_ids(:lessons, program_id)
        |> linked(objective_keys, lesson_keys),
      item_objectives:
        Item |> linked_ids(:objectives, program_id) |> linked(item_keys, objective_keys),
      item_rules: Item |> linked_ids(:rules, program_id) |> linked(item_keys, rule_numbers),
      item_reveals: Item |> linked_ids(:reveals, program_id) |> linked(item_keys, lesson_keys),
      format_objectives:
        CompanionFormat
        |> linked_ids(:objectives, program_id)
        |> linked(keys_by_id(formats), objective_keys),
      assessment_items: assessment_items(program_id, keys_by_id(assessments), item_keys)
    }
  end

  defp live_children(_schema, [], _order), do: []

  defp live_children(schema, module_ids, order) do
    Repo.all(
      from r in schema,
        where: r.module_id in ^module_ids and is_nil(r.archived_at),
        order_by: ^order
    )
  end

  defp program_rows(schema, program_id, order) do
    Repo.all(
      from r in schema,
        where: r.program_id == ^program_id and is_nil(r.archived_at),
        order_by: ^order
    )
  end

  defp stations(program_id) do
    Repo.all(from s in Station, where: s.program_id == ^program_id, order_by: s.position)
  end

  defp requirements([]), do: []

  defp requirements(qualification_ids) do
    Repo.all(from r in Requirement, where: r.qualification_id in ^qualification_ids)
  end

  defp blocks([]), do: []

  defp blocks(lesson_ids) do
    Repo.all(
      from b in Block,
        where: b.lesson_id in ^lesson_ids,
        order_by: [b.lesson_id, b.position]
    )
  end

  defp options([]), do: []

  defp options(item_ids) do
    Repo.all(
      from o in Option,
        where: o.item_id in ^item_ids,
        order_by: [o.item_id, o.position]
    )
  end

  # The citations of the blocks, rules and items of the program by parent
  # id, as `source-key#locator` or `source-key`. A citation of an archived
  # source counts for no parent.
  defp cites_by_parent(program_id, source_keys, block_ids) do
    Repo.all(
      from c in Citation,
        left_join: r in assoc(c, :rule),
        left_join: rm in assoc(r, :module),
        left_join: i in assoc(c, :item),
        where:
          c.block_id in ^block_ids or rm.program_id == ^program_id or
            i.program_id == ^program_id,
        select: {c.block_id, c.rule_id, c.item_id, c.source_id, c.locator}
    )
    |> Enum.flat_map(fn {block_id, rule_id, item_id, source_id, locator} ->
      case Map.fetch(source_keys, source_id) do
        {:ok, key} -> [{block_id || rule_id || item_id, cite(key, locator)}]
        :error -> []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp cite(key, nil), do: key
  defp cite(key, locator), do: key <> "#" <> locator

  defp keys_by_id(rows), do: Map.new(rows, &{&1.id, &1.key})

  defp linked_ids(schema, assoc, program_id) do
    Repo.all(
      from owner in schema,
        join: target in assoc(owner, ^assoc),
        where: owner.program_id == ^program_id,
        select: {owner.id, target.id}
    )
  end

  # Join rows by owner id: each owner maps to the values of the targets it
  # points to. A join row counts only when both of its rows are live.
  defp linked(pairs, owners, targets) do
    pairs
    |> Enum.filter(fn {owner, target} ->
      Map.has_key?(owners, owner) and Map.has_key?(targets, target)
    end)
    |> Enum.group_by(&elem(&1, 0), fn {_owner, target} -> Map.fetch!(targets, target) end)
  end

  defp assessment_items(program_id, assessments, items) do
    Repo.all(
      from ai in AssessmentItem,
        join: a in assoc(ai, :assessment),
        where: a.program_id == ^program_id,
        order_by: [ai.assessment_id, ai.position],
        select: {ai.assessment_id, ai.item_id}
    )
    |> linked(assessments, items)
  end

  ## Entries

  defp source(%Source{} = source) do
    %{
      "key" => source.key,
      "title" => source.title,
      "publisher" => source.publisher,
      "url" => source.url,
      "edition_date" => iso_date(source.edition_date),
      "retrieved_on" => iso_date(source.retrieved_on),
      "kind" => enum(source.kind)
    }
  end

  defp term(%GlossaryTerm{} = term),
    do: %{"slug" => term.slug, "label" => term.label, "short_text" => term.short_text}

  defp segment(%Segment{} = segment) do
    %{
      "key" => segment.key,
      "label" => segment.label,
      "description" => segment.description,
      "default_path" => enum(segment.default_path)
    }
  end

  defp station(%Station{} = station, rows) do
    %{
      "kind" => enum(station.kind),
      "title" => station.title,
      "module" =>
        if(station.kind == :module, do: Map.get(rows.module_numbers, station.module_id)),
      "config" => station.config || %{}
    }
  end

  defp qualification(%Qualification{} = qualification, rows) do
    %{
      "code" => qualification.code,
      "title" => qualification.title,
      "audience" => qualification.audience,
      "unlocks" => qualification.unlocks || [],
      "add_on" => qualification.add_on,
      "validity_kind" => enum(qualification.validity_kind),
      "validity_months" => qualification.validity_months,
      "refresher_mode" => enum(qualification.refresher_mode),
      "phases" => enums(qualification.phases),
      "requirements" =>
        rows.requirements
        |> Enum.filter(&(&1.qualification_id == qualification.id))
        |> Enum.map(&%{"kind" => enum(&1.kind), "target" => &1.target_key})
        |> Enum.sort_by(&{&1["kind"], &1["target"]})
    }
  end

  defp format(%CompanionFormat{} = format, rows) do
    %{
      "key" => format.key,
      "title" => format.title,
      "description" => format.description,
      "phases" => enums(format.phases),
      "attendance_counts" => format.attendance_counts,
      "objectives" => sorted_links(rows.format_objectives, format.id)
    }
  end

  defp module_payload(%CatalogModule{} = module, rows) do
    %{
      "number" => module.number,
      "title" => module.title,
      "summary" => module.summary,
      "phases" => enums(module.phases),
      "domains" => module.domains || [],
      "single_path" => module.single_path,
      "refresher_unit" => module.refresher_unit,
      "areas_elsewhere" => module.areas_elsewhere || %{},
      "lessons" => for(l <- rows.lessons, l.module_id == module.id, do: lesson(l, rows)),
      "objectives" => for(o <- rows.objectives, o.module_id == module.id, do: objective(o, rows)),
      "rules" => for(r <- rows.rules, r.module_id == module.id, do: rule(r, rows)),
      "items" => for(i <- rows.items, i.module_id == module.id, do: item(i, rows)),
      "assessments" =>
        for(a <- rows.assessments, a.module_id == module.id, do: assessment(a, rows))
    }
  end

  defp lesson(%Lesson{} = lesson, rows) do
    %{
      "key" => lesson.key,
      "title" => lesson.title,
      "position" => lesson.position,
      "blocks" => for(b <- rows.blocks, b.lesson_id == lesson.id, do: block(b, rows))
    }
  end

  defp block(%Block{} = block, rows) do
    %{
      "kind" => enum(block.kind),
      "body" => block.body,
      "provenance" => enum(block.provenance),
      "collapsed_on" => enums(block.collapsed_on),
      "placeholder_key" => block.placeholder_key,
      "cite" => sorted_links(rows.cites, block.id)
    }
  end

  defp objective(%LearningObjective{} = objective, rows) do
    %{
      "key" => objective.key,
      "statement" => objective.statement,
      "area" => enum(objective.area),
      "depth" => enum(objective.depth),
      "phase" => enum(objective.phase),
      "domain" => objective.domain,
      "taught_in" => sorted_links(rows.taught_in, objective.id)
    }
  end

  defp rule(%Rule{} = rule, rows) do
    %{
      "number" => rule.number,
      "statement" => rule.statement,
      "action" => rule.action,
      "cite" => sorted_links(rows.cites, rule.id)
    }
  end

  defp item(%Item{} = item, rows) do
    %{
      "key" => item.key,
      "kind" => enum(item.kind),
      "lesson" => Map.get(rows.lesson_keys, item.lesson_id),
      "stem" => item.stem,
      "core" => item.core,
      "phase" => enum(item.phase),
      "provenance" => enum(item.provenance),
      "objectives" => sorted_links(rows.item_objectives, item.id),
      "rules" => sorted_links(rows.item_rules, item.id),
      "reveals" => sorted_links(rows.item_reveals, item.id),
      "cite" => sorted_links(rows.cites, item.id),
      "options" => for(o <- rows.options, o.item_id == item.id, do: option(o)),
      "config" => item.config || %{}
    }
  end

  defp option(%Option{} = option) do
    %{
      "key" => option.key,
      "label" => option.label,
      "correct" => option.correct,
      "feedback" => option.feedback
    }
  end

  defp assessment(%Assessment{} = assessment, rows) do
    %{
      "key" => assessment.key,
      "title" => assessment.title,
      "kind" => enum(assessment.kind),
      "counts_for_credential" => assessment.counts_for_credential,
      "max_wrong" => assessment.max_wrong,
      "core_required" => assessment.core_required,
      "items" => Map.get(rows.assessment_items, assessment.id, [])
    }
  end

  ## Values

  # A pair the join table holds twice gives one value.
  defp sorted_links(links, id), do: links |> Map.get(id, []) |> Enum.uniq() |> Enum.sort()

  defp iso_date(nil), do: nil
  defp iso_date(%Date{} = date), do: Date.to_iso8601(date)

  defp enum(nil), do: nil
  defp enum(value) when is_atom(value), do: Atom.to_string(value)

  defp enums(values), do: Enum.map(values || [], &enum/1)
end
