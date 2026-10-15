defmodule Espalier.Catalog.Pack.Diff do
  @moduledoc """
  Compares the payload of a `PackImport` with the live tables of the program
  whose `slug` equals the pack key (task 0015, step 7) and lists the added,
  changed and archived keys per keyed kind of task 0008: modules, lessons,
  learning objectives, items, rules, assessments, qualifications, formats,
  sources, segments and glossary terms.

  Without such a program, every key of the payload is `added`. Live rows
  with `archived_at` set count as absent: a key that the payload holds again
  is `added`, and a key whose row is archived already is not `archived`. A
  key is `changed` when a value of the payload differs from its live row.
  Both sides pass through the Ecto type of each field, the cast that the
  publisher applies (`Espalier.Catalog.Pack.Publisher`), so that the
  comparison sees the values as the tables hold them; positions are the
  places in the payload lists, as the publisher writes them.

  Keys: a module by its number, a lesson as `<module number>/<lesson key>`
  and a rule as `<module number>/<rule number>`, because both are keyed per
  module; every other kind by its key, a qualification by its code and a
  glossary term by its slug.

  Besides the fields of its row, a key is compared by the values that the
  payload nests below it and that the publisher writes into rows of their
  own: a lesson by its blocks with their citations, an item by its options
  (with the correct answers), the numbers of its rules, the keys of the
  lessons it reveals and its citations, a rule by its citations, an
  assessment by the keys of its items in order, and a qualification by its
  requirements. An item is also compared by the number of its module, the
  key of its lesson and the sorted set of its objective keys (its
  `item_objectives` rows), a format by the sorted set of its objective keys
  (`format_objectives`), and a module by its `areas_elsewhere`. A learning
  objective is compared by `statement`, `area`, `depth`, `phase`, `domain`,
  `position`, the number of its module (`module`), the lesson keys of
  `taught_in` against its `objective_lessons` rows (`taught_in`), and the
  keys of the items and formats that name it against its `item_objectives`
  and `format_objectives` rows (`items` and `formats`). Every set is compared
  sorted, and a join row that points to an archived row counts as absent.
  The entry of `learning_objectives` also carries `changed_fields`, a map
  from every changed key to the sorted names of the fields that differ.
  """

  import Ecto.Query

  alias Ecto.Changeset

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
    Program,
    Qualification,
    Requirement,
    Rule,
    Segment,
    Source
  }

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Repo

  @kinds [
    :modules,
    :lessons,
    :learning_objectives,
    :items,
    :rules,
    :assessments,
    :qualifications,
    :formats,
    :sources,
    :segments,
    :glossary_terms
  ]

  @module_fields [
    :title,
    :summary,
    :phases,
    :domains,
    :single_path,
    :refresher_unit,
    :areas_elsewhere
  ]
  @lesson_fields [:position, :title]
  @rule_fields [:statement, :action]
  @objective_fields [:statement, :area, :depth, :phase, :domain, :position]
  @item_fields [:kind, :stem, :core, :phase, :provenance, :config, :position]
  @assessment_fields [:title, :kind, :counts_for_credential, :max_wrong, :core_required]
  @qualification_fields [
    :title,
    :audience,
    :unlocks,
    :add_on,
    :validity_kind,
    :validity_months,
    :refresher_mode,
    :phases,
    :position
  ]
  @format_fields [:title, :description, :phases, :attendance_counts, :position]
  @source_fields [:title, :publisher, :url, :edition_date, :retrieved_on, :kind]
  @segment_fields [:label, :description, :default_path, :position]
  @glossary_fields [:label, :short_text]
  @block_fields [:kind, :body, :provenance, :collapsed_on, :placeholder_key]
  @option_fields [:key, :label, :correct, :feedback]
  @requirement_fields [:kind, :target_key]

  @typedoc "The added, changed and archived keys of one kind."
  @type entry :: %{
          required(:added) => [String.t()],
          required(:changed) => [String.t()],
          required(:archived) => [String.t()],
          optional(:changed_fields) => %{String.t() => [String.t()]}
        }

  @doc "The keyed kinds of the diff, in the order of the answer."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  @doc """
  Returns a map of every kind of `kinds/0` to its entry for `payload`, the
  normalized map of a content pack.
  """
  @spec compute(map()) :: %{atom() => entry()}
  def compute(%{"key" => slug} = payload) when is_binary(slug) do
    wanted = payload_values(payload)

    live =
      case Repo.get_by(Program, slug: slug) do
        %Program{id: program_id} -> live_values(program_id)
        nil -> Map.new(@kinds, &{&1, %{}})
      end

    Map.new(@kinds, fn kind -> {kind, entry(kind, wanted[kind], live[kind])} end)
  end

  defp entry(kind, wanted, live) do
    common = wanted |> Map.keys() |> Enum.filter(&Map.has_key?(live, &1))

    changed_fields =
      for key <- common,
          fields = differing(wanted[key], live[key]),
          fields != [],
          into: %{},
          do: {key, fields}

    entry = %{
      added: wanted |> Map.keys() |> Enum.reject(&Map.has_key?(live, &1)) |> Enum.sort(),
      changed: changed_fields |> Map.keys() |> Enum.sort(),
      archived: live |> Map.keys() |> Enum.reject(&Map.has_key?(wanted, &1)) |> Enum.sort()
    }

    if kind == :learning_objectives,
      do: Map.put(entry, :changed_fields, changed_fields),
      else: entry
  end

  defp differing(wanted, live) do
    wanted
    |> Map.keys()
    |> Enum.reject(&(Map.get(wanted, &1) == Map.get(live, &1)))
    |> Enum.map(&Atom.to_string/1)
    |> Enum.sort()
  end

  ## The payload

  defp payload_values(payload) do
    modules = list(payload, "modules")
    formats = list(payload, "formats")

    payload
    |> top_level_values()
    |> Map.merge(module_values(modules))
    |> Map.merge(%{
      learning_objectives: objective_values(modules, formats),
      items: item_values(modules),
      formats: format_values(formats)
    })
  end

  defp top_level_values(payload) do
    %{
      qualifications:
        for {qualification, position} <- Enum.with_index(list(payload, "qualifications"), 1),
            into: %{} do
          values =
            Qualification
            |> cast(Map.put(qualification, "position", position), @qualification_fields)
            |> Map.put(:requirements, payload_requirements(qualification))

          {qualification["code"], values}
        end,
      sources:
        Map.new(list(payload, "sources"), fn source ->
          {source["key"], cast(Source, source, @source_fields)}
        end),
      segments:
        for {segment, position} <- Enum.with_index(list(payload, "segments"), 1), into: %{} do
          {segment["key"], cast(Segment, Map.put(segment, "position", position), @segment_fields)}
        end,
      glossary_terms:
        Map.new(list(payload, "glossary"), fn term ->
          {term["slug"], cast(GlossaryTerm, term, @glossary_fields)}
        end)
    }
  end

  # A requirement of the payload names its target in `target`, the row in
  # `target_key`.
  defp payload_requirements(qualification) do
    qualification
    |> list("requirements")
    |> Enum.map(fn requirement ->
      attrs = %{"kind" => requirement["kind"], "target_key" => requirement["target"]}
      cast(Requirement, attrs, @requirement_fields)
    end)
    |> set()
  end

  defp module_values(modules) do
    %{
      modules:
        Map.new(modules, fn module ->
          {Integer.to_string(module["number"]), cast(CatalogModule, module, @module_fields)}
        end),
      lessons:
        for module <- modules, lesson <- list(module, "lessons"), into: %{} do
          values =
            Lesson
            |> cast(lesson, @lesson_fields)
            |> Map.put(:blocks, Enum.map(list(lesson, "blocks"), &payload_block/1))

          {"#{module["number"]}/#{lesson["key"]}", values}
        end,
      rules:
        for module <- modules, rule <- list(module, "rules"), into: %{} do
          values = Rule |> cast(rule, @rule_fields) |> Map.put(:cite, set(list(rule, "cite")))
          {"#{module["number"]}/#{rule["number"]}", values}
        end,
      assessments:
        for module <- modules, assessment <- list(module, "assessments"), into: %{} do
          values =
            Assessment
            |> cast(assessment, @assessment_fields)
            |> Map.merge(%{module: module["number"], items: list(assessment, "items")})

          {assessment["key"], values}
        end
    }
  end

  defp payload_block(block) do
    Block |> cast(block, @block_fields) |> Map.put(:cite, set(list(block, "cite")))
  end

  defp objective_values(modules, formats) do
    items_by_objective =
      for module <- modules, item <- list(module, "items"), key <- list(item, "objectives") do
        {key, item["key"]}
      end
      |> group()

    formats_by_objective =
      for format <- formats, key <- list(format, "objectives"), do: {key, format["key"]}

    formats_by_objective = group(formats_by_objective)

    for module <- modules,
        {objective, position} <- Enum.with_index(list(module, "objectives"), 1),
        into: %{} do
      key = objective["key"]

      values =
        LearningObjective
        |> cast(Map.put(objective, "position", position), @objective_fields)
        |> Map.merge(%{
          module: module["number"],
          taught_in: set(list(objective, "taught_in")),
          items: Map.get(items_by_objective, key, []),
          formats: Map.get(formats_by_objective, key, [])
        })

      {key, values}
    end
  end

  defp item_values(modules) do
    for module <- modules,
        {item, position} <- Enum.with_index(list(module, "items"), 1),
        into: %{} do
      values =
        Item
        |> cast(Map.put(item, "position", position), @item_fields)
        |> Map.merge(%{
          module: module["number"],
          lesson: item["lesson"],
          objectives: set(list(item, "objectives")),
          options: Enum.map(list(item, "options"), &cast(Option, &1, @option_fields)),
          rules: set(list(item, "rules")),
          reveals: set(list(item, "reveals")),
          cite: set(list(item, "cite"))
        })

      {item["key"], values}
    end
  end

  defp format_values(formats) do
    for {format, position} <- Enum.with_index(formats, 1), into: %{} do
      values =
        CompanionFormat
        |> cast(Map.put(format, "position", position), @format_fields)
        |> Map.put(:objectives, set(list(format, "objectives")))

      {format["key"], values}
    end
  end

  # The values of `fields` as the Ecto types of `schema` cast them, the cast
  # of the publisher.
  defp cast(schema, attrs, fields) do
    schema
    |> struct()
    |> Changeset.cast(attrs, fields, empty_values: [])
    |> Changeset.apply_changes()
    |> Map.take(fields)
  end

  ## The live tables

  defp live_values(program_id) do
    rows = live_rows(program_id)
    links = live_links(rows)

    rows
    |> live_module_values(links)
    |> Map.merge(live_objective_values(rows, links))
    |> Map.merge(live_item_values(rows, links))
    |> Map.merge(live_top_level_values(program_id, rows, links))
  end

  defp live_rows(program_id) do
    modules = live(from(m in CatalogModule, where: m.program_id == ^program_id))
    module_numbers = Map.new(modules, &{&1.id, &1.number})
    module_ids = Map.keys(module_numbers)
    lessons = live(from(l in Lesson, where: l.module_id in ^module_ids))
    rules = live(from(r in Rule, where: r.module_id in ^module_ids))
    objectives = live(from(o in LearningObjective, where: o.program_id == ^program_id))
    items = live(from(i in Item, where: i.program_id == ^program_id))
    formats = live(from(f in CompanionFormat, where: f.program_id == ^program_id))

    %{
      modules: modules,
      module_numbers: module_numbers,
      lessons: lessons,
      rules: rules,
      objectives: objectives,
      items: items,
      formats: formats,
      assessments: live(from(a in Assessment, where: a.program_id == ^program_id)),
      qualifications: live(from(q in Qualification, where: q.program_id == ^program_id)),
      lesson_keys: Map.new(lessons, &{&1.id, &1.key}),
      rule_numbers: Map.new(rules, &{&1.id, &1.number}),
      objective_keys: Map.new(objectives, &{&1.id, &1.key}),
      item_keys: Map.new(items, &{&1.id, &1.key}),
      format_keys: Map.new(formats, &{&1.id, &1.key})
    }
  end

  # The rows that the publisher writes per parent, grouped by the key or the
  # id of their parent. Join rows whose either side is archived (missing
  # from the maps of live_rows/1) count as absent.
  defp live_links(rows) do
    objective_lessons =
      join_pairs(
        "objective_lessons",
        :learning_objective_id,
        :lesson_id,
        rows.objective_keys,
        rows.lesson_keys
      )

    item_objectives =
      join_pairs(
        "item_objectives",
        :item_id,
        :learning_objective_id,
        rows.item_keys,
        rows.objective_keys
      )

    format_objectives =
      join_pairs(
        "format_objectives",
        :companion_format_id,
        :learning_objective_id,
        rows.format_keys,
        rows.objective_keys
      )

    item_rules = join_pairs("item_rules", :item_id, :rule_id, rows.item_keys, rows.rule_numbers)

    item_reveals =
      join_pairs("item_reveals", :item_id, :lesson_id, rows.item_keys, rows.lesson_keys)

    blocks = live_blocks(rows)

    %{
      lessons_by_objective: group(objective_lessons),
      items_by_objective: item_objectives |> swap() |> group(),
      formats_by_objective: format_objectives |> swap() |> group(),
      objectives_by_item: group(item_objectives),
      objectives_by_format: group(format_objectives),
      rules_by_item: group(item_rules),
      reveals_by_item: group(item_reveals),
      blocks: blocks,
      cites: live_citations(rows, blocks),
      options_by_item: live_options(rows),
      items_by_assessment: live_assessment_items(rows),
      requirements_by_qualification: live_requirements(rows)
    }
  end

  defp live_blocks(rows) do
    lesson_ids = Map.keys(rows.lesson_keys)

    Repo.all(
      from b in Block, where: b.lesson_id in ^lesson_ids, order_by: [b.lesson_id, b.position]
    )
  end

  # The citations of blocks, items and rules as `<source key>` or
  # `<source key>#<locator>`, the form of the payload, per parent id. A
  # citation row names exactly one parent.
  defp live_citations(rows, blocks) do
    block_ids = Enum.map(blocks, & &1.id)
    item_ids = Map.keys(rows.item_keys)
    rule_ids = Map.keys(rows.rule_numbers)

    Repo.all(
      from c in Citation,
        join: s in Source,
        on: s.id == c.source_id,
        where: c.block_id in ^block_ids or c.item_id in ^item_ids or c.rule_id in ^rule_ids,
        select: {c.block_id, c.item_id, c.rule_id, s.key, c.locator}
    )
    |> Enum.map(fn {block_id, item_id, rule_id, key, locator} ->
      {block_id || item_id || rule_id, if(locator, do: key <> "#" <> locator, else: key)}
    end)
    |> group()
  end

  defp live_options(rows) do
    item_ids = Map.keys(rows.item_keys)

    Repo.all(from o in Option, where: o.item_id in ^item_ids, order_by: [o.item_id, o.position])
    |> Enum.group_by(& &1.item_id, &Map.take(&1, @option_fields))
  end

  defp live_assessment_items(rows) do
    assessment_ids = Enum.map(rows.assessments, & &1.id)

    Repo.all(
      from ai in AssessmentItem,
        where: ai.assessment_id in ^assessment_ids,
        order_by: [ai.assessment_id, ai.position],
        select: {ai.assessment_id, ai.item_id}
    )
    |> Enum.flat_map(fn {assessment_id, item_id} ->
      case Map.get(rows.item_keys, item_id) do
        nil -> []
        key -> [{assessment_id, key}]
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp live_requirements(rows) do
    qualification_ids = Enum.map(rows.qualifications, & &1.id)

    Repo.all(from r in Requirement, where: r.qualification_id in ^qualification_ids)
    |> Enum.group_by(& &1.qualification_id, &Map.take(&1, @requirement_fields))
    |> Map.new(fn {id, requirements} -> {id, set(requirements)} end)
  end

  defp live_module_values(rows, links) do
    numbers = rows.module_numbers
    blocks_by_lesson = Enum.group_by(links.blocks, & &1.lesson_id)

    %{
      modules:
        Map.new(rows.modules, &{Integer.to_string(&1.number), Map.take(&1, @module_fields)}),
      lessons:
        Map.new(rows.lessons, fn lesson ->
          blocks =
            blocks_by_lesson
            |> Map.get(lesson.id, [])
            |> Enum.map(&live_block(&1, links.cites))

          values = lesson |> Map.take(@lesson_fields) |> Map.put(:blocks, blocks)
          {"#{numbers[lesson.module_id]}/#{lesson.key}", values}
        end),
      rules:
        Map.new(rows.rules, fn rule ->
          values =
            rule |> Map.take(@rule_fields) |> Map.put(:cite, Map.get(links.cites, rule.id, []))

          {"#{numbers[rule.module_id]}/#{rule.number}", values}
        end),
      assessments:
        Map.new(rows.assessments, fn assessment ->
          values =
            assessment
            |> Map.take(@assessment_fields)
            |> Map.merge(%{
              module: numbers[assessment.module_id],
              items: Map.get(links.items_by_assessment, assessment.id, [])
            })

          {assessment.key, values}
        end)
    }
  end

  defp live_block(block, cites) do
    block |> Map.take(@block_fields) |> Map.put(:cite, Map.get(cites, block.id, []))
  end

  defp live_objective_values(rows, links) do
    %{
      learning_objectives:
        Map.new(rows.objectives, fn objective ->
          key = objective.key

          values =
            objective
            |> Map.take(@objective_fields)
            |> Map.merge(%{
              module: rows.module_numbers[objective.module_id],
              taught_in: Map.get(links.lessons_by_objective, key, []),
              items: Map.get(links.items_by_objective, key, []),
              formats: Map.get(links.formats_by_objective, key, [])
            })

          {key, values}
        end)
    }
  end

  defp live_item_values(rows, links) do
    %{
      items:
        Map.new(rows.items, fn item ->
          values =
            item
            |> Map.take(@item_fields)
            |> Map.merge(%{
              module: rows.module_numbers[item.module_id],
              lesson: item.lesson_id && Map.get(rows.lesson_keys, item.lesson_id),
              objectives: Map.get(links.objectives_by_item, item.key, []),
              options: Map.get(links.options_by_item, item.id, []),
              rules: Map.get(links.rules_by_item, item.key, []),
              reveals: Map.get(links.reveals_by_item, item.key, []),
              cite: Map.get(links.cites, item.id, [])
            })

          {item.key, values}
        end)
    }
  end

  defp live_top_level_values(program_id, rows, links) do
    %{
      qualifications:
        Map.new(rows.qualifications, fn qualification ->
          requirements = Map.get(links.requirements_by_qualification, qualification.id, [])

          values =
            qualification
            |> Map.take(@qualification_fields)
            |> Map.put(:requirements, requirements)

          {qualification.code, values}
        end),
      formats:
        Map.new(rows.formats, fn format ->
          values =
            format
            |> Map.take(@format_fields)
            |> Map.put(:objectives, Map.get(links.objectives_by_format, format.key, []))

          {format.key, values}
        end),
      sources:
        Map.new(
          live(from(s in Source, where: s.program_id == ^program_id)),
          &{&1.key, Map.take(&1, @source_fields)}
        ),
      segments:
        Map.new(
          live(from(s in Segment, where: s.program_id == ^program_id)),
          &{&1.key, Map.take(&1, @segment_fields)}
        ),
      glossary_terms:
        Map.new(
          live(from(g in GlossaryTerm, where: g.program_id == ^program_id)),
          &{&1.slug, Map.take(&1, @glossary_fields)}
        )
    }
  end

  defp live(query), do: query |> where([r], is_nil(r.archived_at)) |> Repo.all()

  # The pairs of a join table as {left key, right key}, for the rows whose
  # both ids name a live row.
  defp join_pairs(table, left, right, left_keys, right_keys) do
    ids = Map.keys(left_keys)

    from(j in table,
      where: field(j, ^left) in type(^ids, {:array, Ecto.UUID}),
      select: {type(field(j, ^left), Ecto.UUID), type(field(j, ^right), Ecto.UUID)}
    )
    |> Repo.all()
    |> Enum.flat_map(fn {left_id, right_id} ->
      case {Map.get(left_keys, left_id), Map.get(right_keys, right_id)} do
        {nil, _right} -> []
        {_left, nil} -> []
        pair -> [pair]
      end
    end)
  end

  defp swap(pairs), do: Enum.map(pairs, fn {left, right} -> {right, left} end)

  # A map of each left key to the sorted set of its right keys.
  defp group(pairs) do
    pairs
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {key, values} -> {key, set(values)} end)
  end

  ## Helpers

  defp set(list), do: list |> Enum.uniq() |> Enum.sort()

  defp list(map, key) do
    case Map.get(map, key) do
      list when is_list(list) -> list
      _other -> []
    end
  end
end
