defmodule EspalierWeb.CatalogJSON do
  @moduledoc """
  Catalog views for learners (README section 7, domain rule 4; ASVS
  15.3.1). Every view names its members explicitly. No view carries an
  answer key: no `correct`, `feedback` or `expected` member and no raw
  `config` of an item or a station. Correctness and feedback reach a
  learner only through `Espalier.Learning.Evaluator` in the answer to the
  learner's own submission.

  `Espalier.Catalog` returns only published programs and only rows without
  `archived_at`, so the views render what they receive.
  """

  alias Espalier.Catalog.{Block, Citation, CompanionFormat, Item, Lesson, Rule, Station}

  @doc "Renders the list of published programs."
  def index(%{programs: programs}) do
    %{programs: Enum.map(programs, &%{slug: &1.slug, title: &1.title, locale: &1.locale})}
  end

  @doc "Renders a program with its stations, segments, modules and formats."
  def show(%{program: program}) do
    %{
      id: program.id,
      slug: program.slug,
      title: program.title,
      locale: program.locale,
      pack_version: program.pack_version,
      stations: Enum.map(program.stations, &station/1),
      segments:
        Enum.map(program.segments, fn segment ->
          %{
            key: segment.key,
            label: segment.label,
            description: segment.description,
            default_path: segment.default_path
          }
        end),
      modules:
        Enum.map(program.modules, fn module ->
          %{
            id: module.id,
            number: module.number,
            title: module.title,
            summary: module.summary,
            phases: module.phases,
            single_path: module.single_path
          }
        end),
      companion_formats: Enum.map(program.companion_formats, &companion_format/1)
    }
  end

  defp station(%Station{config: config} = station) do
    config = config || %{}

    %{
      position: station.position,
      kind: station.kind,
      title: station.title,
      module_id: station.module_id,
      question: string_at(config, "question"),
      intro: string_at(config, "intro"),
      questions: config |> list_at("questions") |> Enum.map(&question/1)
    }
  end

  defp question(question) do
    %{
      key: question["key"],
      kind: question["kind"],
      label: question["label"],
      options: question |> list_at("options") |> Enum.map(&%{key: &1["key"], label: &1["label"]})
    }
  end

  @doc "Renders a companion format (schema `CompanionFormatView`)."
  def companion_format(%CompanionFormat{} = format) do
    %{
      id: format.id,
      key: format.key,
      title: format.title,
      description: format.description,
      phases: format.phases,
      attendance_counts: format.attendance_counts
    }
  end

  @doc """
  Renders a module with its lessons, rules, practice items, exams and
  objectives (the map of `Espalier.Catalog.module_view/1`).
  """
  def module(%{view: view}) do
    %{module: module, objective_keys: keys} = view

    %{
      id: module.id,
      program_slug: module.program.slug,
      number: module.number,
      title: module.title,
      summary: module.summary,
      phases: module.phases,
      single_path: module.single_path,
      lessons: Enum.map(view.lessons, &lesson/1),
      rules: Enum.map(view.rules, &rule/1),
      practice_items: Enum.map(view.practice_items, &item(&1, keys)),
      exams:
        Enum.map(view.exams, fn exam ->
          %{
            id: exam.id,
            key: exam.key,
            title: exam.title,
            max_wrong: exam.max_wrong,
            counts_for_credential: exam.counts_for_credential,
            items: Enum.map(exam.items, &item(&1, keys))
          }
        end),
      objectives: Enum.map(view.objectives, &objective/1)
    }
  end

  defp lesson(%Lesson{} = lesson) do
    %{
      id: lesson.id,
      key: lesson.key,
      position: lesson.position,
      title: lesson.title,
      blocks: Enum.map(lesson.blocks, &block/1)
    }
  end

  defp block(%Block{} = block) do
    %{
      kind: block.kind,
      body: block.body,
      provenance: block.provenance,
      collapsed_on: block.collapsed_on,
      placeholder_key: block.placeholder_key,
      citations: Enum.map(block.citations, &citation/1)
    }
  end

  defp rule(%Rule{} = rule) do
    %{
      id: rule.id,
      number: rule.number,
      statement: rule.statement,
      action: rule.action,
      citations: Enum.map(rule.citations, &citation/1)
    }
  end

  defp citation(%Citation{source: source} = citation) do
    %{
      locator: citation.locator,
      source: %{
        key: source.key,
        title: source.title,
        publisher: source.publisher,
        url: source.url,
        edition_date: source.edition_date,
        retrieved_on: source.retrieved_on,
        kind: source.kind
      }
    }
  end

  @doc """
  Renders an item without its answer key (schema `ItemView`). `keys` maps
  item ids to the sorted keys of their live objectives. The lists of the
  other kinds are empty.
  """
  def item(%Item{config: config} = item, keys) do
    config = config || %{}

    %{
      id: item.id,
      key: item.key,
      kind: item.kind,
      stem: item.stem,
      provenance: item.provenance,
      lesson_id: item.lesson_id,
      objective_keys: Map.get(keys, item.id, []),
      options: options(item),
      slots:
        if(item.kind == :slot_builder,
          do:
            config
            |> list_at("slots")
            |> Enum.map(fn slot ->
              %{key: slot["key"], label: slot["label"], options: choices(slot, "options")}
            end),
          else: []
        ),
      cases:
        if(item.kind == :classification,
          do: config |> list_at("cases") |> Enum.map(&%{key: &1["key"], text: &1["text"]}),
          else: []
        ),
      categories: if(item.kind == :classification, do: choices(config, "categories"), else: []),
      checks:
        if(item.kind == :checklist_drill,
          do:
            config
            |> list_at("checks")
            |> Enum.map(&%{key: &1["key"], label: &1["label"], required: &1["required"] == true}),
          else: []
        )
    }
  end

  defp options(%Item{kind: kind, options: options})
       when kind in [:single_choice, :multiple_choice, :poll],
       do: Enum.map(options, &%{key: &1.key, label: &1.label})

  defp options(_item), do: []

  defp choices(map, key),
    do: map |> list_at(key) |> Enum.map(&%{key: &1["key"], label: &1["label"]})

  @doc """
  Renders a learning objective of `Espalier.Catalog.objective_links/2`
  (schema `ObjectiveView`): the evidence items ordered by key, followed by
  the evidence formats ordered by key.
  """
  def objective(%{objective: objective} = link) do
    %{
      key: objective.key,
      statement: objective.statement,
      area: objective.area,
      depth: objective.depth,
      phase: objective.phase,
      domain: objective.domain,
      lesson_ids: link.lesson_ids,
      evidence:
        Enum.map(link.item_ids, &%{kind: "item", id: &1}) ++
          Enum.map(link.format_ids, &%{kind: "format", id: &1})
    }
  end

  @doc "Renders the glossary terms of a program."
  def glossary(%{terms: terms}) do
    %{terms: Enum.map(terms, &%{slug: &1.slug, label: &1.label, short_text: &1.short_text})}
  end

  @doc "Renders the handbook: every rule per module, and the placeholder keys."
  def handbook(%{handbook: handbook}) do
    %{
      modules:
        Enum.map(handbook.modules, fn module ->
          %{
            id: module.id,
            number: module.number,
            title: module.title,
            rules:
              Enum.map(
                module.rules,
                &%{number: &1.number, statement: &1.statement, action: &1.action}
              )
          }
        end),
      placeholders: handbook.placeholders
    }
  end

  defp string_at(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) -> value
      _other -> nil
    end
  end

  defp list_at(map, key) when is_map(map) do
    case Map.get(map, key) do
      entries when is_list(entries) -> Enum.filter(entries, &is_map/1)
      _other -> []
    end
  end
end
