defmodule Espalier.Catalog do
  @moduledoc """
  The Catalog context: programs and their content. Content arrives only
  through content packs: `Espalier.Catalog.Pack.Importer` validates a pack
  and stores it as a draft, and `Espalier.Catalog.Pack.Publisher` applies the
  draft to the catalog tables (README section 11). This module reads them.

  The learner read paths (task 0009) return only programs with status
  `published`, and only modules, lessons, learning objectives, items, rules,
  assessments, segments, glossary terms and companion formats without
  `archived_at`. A row of an archived module counts as archived.
  """

  import Ecto.Query, warn: false
  alias Espalier.Repo

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
    Rule,
    Segment,
    Station
  }

  alias Espalier.Catalog.Module, as: CatalogModule

  @doc """
  Returns the list of programs.
  """
  def list_programs do
    Repo.all(from p in Program, order_by: p.slug)
  end

  @doc """
  Gets a single program.

  Raises `Ecto.NoResultsError` if the Program does not exist.
  """
  def get_program!(id), do: Repo.get!(Program, id)

  @doc """
  Gets the program whose slug is the key of its content pack, or `nil`.
  """
  def get_program_by_slug(slug) when is_binary(slug), do: Repo.get_by(Program, slug: slug)

  ## Learner read paths (task 0009)

  @doc "Returns the published programs, ordered by slug."
  def list_published_programs do
    Repo.all(from p in Program, where: p.status == :published, order_by: p.slug)
  end

  @doc "Returns the published program with `slug`, or `nil`."
  def get_published_program(slug) when is_binary(slug) do
    Repo.get_by(Program, slug: slug, status: :published)
  end

  @doc """
  Returns the published program with `slug` together with its stations,
  live segments, live modules and live companion formats, or
  `{:error, :not_found}`.
  """
  def program_view(slug) when is_binary(slug) do
    case get_published_program(slug) do
      nil ->
        {:error, :not_found}

      program ->
        {:ok,
         Repo.preload(program,
           stations: from(s in Station, order_by: s.position),
           segments:
             from(s in Segment, where: is_nil(s.archived_at), order_by: [s.position, s.key]),
           modules: from(m in CatalogModule, where: is_nil(m.archived_at), order_by: m.number),
           companion_formats:
             from(f in CompanionFormat,
               where: is_nil(f.archived_at),
               order_by: [f.position, f.key]
             )
         )}
    end
  end

  @doc """
  Returns the content of a live module of a published program, or
  `{:error, :not_found}`.

  The map holds `module` (with `program`), `lessons` (with their blocks and
  the citations of each block with its source), `rules` (with citations),
  `practice_items` (the live items of the module that no live exam lists),
  `exams` (the live exams of the module with their live items in position
  order), `objectives` (the result of `objective_links/2` for the module)
  and `objective_keys` (item id to the sorted keys of its live objectives).
  Items carry their options in position order.
  """
  def module_view(id) do
    case live_module(id) do
      nil -> {:error, :not_found}
      module -> {:ok, build_module_view(module)}
    end
  end

  defp build_module_view(module) do
    items = live_items(module.id)
    exams = live_exams(module.id)
    listed = exams |> Enum.map(& &1.id) |> exam_items()

    listed =
      Enum.zip(
        Enum.map(listed, &elem(&1, 0)),
        listed |> Enum.map(&elem(&1, 1)) |> preload_options()
      )

    exam_item_ids = exam_item_ids(Enum.map(items, & &1.id))
    practice_items = Enum.reject(items, &MapSet.member?(exam_item_ids, &1.id))

    exams =
      Enum.map(exams, fn exam ->
        %{exam | items: for({assessment_id, item} <- listed, assessment_id == exam.id, do: item)}
      end)

    item_ids = Enum.map(practice_items, & &1.id) ++ Enum.map(listed, &elem(&1, 1).id)

    %{
      module: module,
      lessons: lessons_with_blocks(module.id),
      rules: rules_with_citations(module.id),
      practice_items: practice_items,
      exams: exams,
      objectives: objective_links(module.program_id, module_id: module.id),
      objective_keys: objective_keys(item_ids)
    }
  end

  defp live_module(id) do
    Repo.one(
      from m in CatalogModule,
        join: p in assoc(m, :program),
        where: m.id == ^id and is_nil(m.archived_at) and p.status == :published,
        preload: [program: p]
    )
  end

  defp live_items(module_id) do
    Repo.all(
      from i in Item,
        where: i.module_id == ^module_id and is_nil(i.archived_at),
        order_by: [i.position, i.key],
        preload: [options: ^from(o in Option, order_by: [o.position, o.key])]
    )
  end

  defp live_exams(module_id) do
    Repo.all(
      from a in Assessment,
        where: a.module_id == ^module_id and a.kind == :exam and is_nil(a.archived_at),
        order_by: a.key
    )
  end

  # {assessment_id, item} of the live items of the given assessments, in
  # position order.
  defp exam_items([]), do: []

  defp exam_items(assessment_ids) do
    Repo.all(
      from ai in AssessmentItem,
        join: i in assoc(ai, :item),
        where: ai.assessment_id in ^assessment_ids and is_nil(i.archived_at),
        order_by: [ai.assessment_id, ai.position],
        select: {ai.assessment_id, i}
    )
  end

  # The ids among `item_ids` that a live exam lists.
  defp exam_item_ids([]), do: MapSet.new()

  defp exam_item_ids(item_ids) do
    Repo.all(
      from ai in AssessmentItem,
        join: a in assoc(ai, :assessment),
        where: ai.item_id in ^item_ids and a.kind == :exam and is_nil(a.archived_at),
        distinct: true,
        select: ai.item_id
    )
    |> MapSet.new()
  end

  defp preload_options(items) do
    Repo.preload(items, options: from(o in Option, order_by: [o.position, o.key]))
  end

  defp lessons_with_blocks(module_id) do
    citations = from(c in Citation, order_by: [c.locator, c.id], preload: :source)

    Repo.all(
      from l in Lesson,
        where: l.module_id == ^module_id and is_nil(l.archived_at),
        order_by: [l.position, l.key],
        preload: [
          blocks: ^from(b in Block, order_by: b.position, preload: [citations: ^citations])
        ]
    )
  end

  defp rules_with_citations(module_id) do
    Repo.all(
      from r in Rule,
        where: r.module_id == ^module_id and is_nil(r.archived_at),
        order_by: r.number,
        preload: [citations: ^from(c in Citation, order_by: [c.locator, c.id], preload: :source)]
    )
  end

  @doc """
  Returns item id to the sorted keys of the live learning objectives that
  each item names (`item_objectives`).
  """
  def objective_keys([]), do: %{}

  def objective_keys(item_ids) do
    Repo.all(
      from io in "item_objectives",
        join: o in LearningObjective,
        on: o.id == io.learning_objective_id,
        join: m in CatalogModule,
        on: m.id == o.module_id,
        where:
          io.item_id in type(^item_ids, {:array, :binary_id}) and is_nil(o.archived_at) and
            is_nil(m.archived_at),
        select: {type(io.item_id, :binary_id), o.key}
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {item_id, keys} -> {item_id, Enum.sort(keys)} end)
  end

  @doc """
  Returns the live glossary terms of a published program by slug, or
  `{:error, :not_found}`.
  """
  def glossary(slug) when is_binary(slug) do
    case get_published_program(slug) do
      nil ->
        {:error, :not_found}

      program ->
        {:ok,
         Repo.all(
           from t in GlossaryTerm,
             where: t.program_id == ^program.id and is_nil(t.archived_at),
             order_by: t.slug
         )}
    end
  end

  @doc """
  Returns the handbook of a published program by slug (README section 7,
  domain rule 10): the live modules with their live rules, and the sorted
  keys of the `placeholder` blocks of the program's live lessons. Returns
  `{:error, :not_found}` for a program that is not published.
  """
  def handbook(slug) when is_binary(slug) do
    case get_published_program(slug) do
      nil ->
        {:error, :not_found}

      program ->
        modules =
          Repo.all(
            from m in CatalogModule,
              where: m.program_id == ^program.id and is_nil(m.archived_at),
              order_by: m.number,
              preload: [
                rules: ^from(r in Rule, where: is_nil(r.archived_at), order_by: r.number)
              ]
          )

        placeholders =
          Repo.all(
            from b in Block,
              join: l in assoc(b, :lesson),
              join: m in assoc(l, :module),
              where:
                m.program_id == ^program.id and is_nil(m.archived_at) and is_nil(l.archived_at) and
                  b.kind == :placeholder and not is_nil(b.placeholder_key),
              distinct: true,
              order_by: b.placeholder_key,
              select: b.placeholder_key
          )

        {:ok, %{program: program, modules: modules, placeholders: placeholders}}
    end
  end

  @doc """
  Returns a live item of a published program, prepared for
  `Espalier.Learning.Evaluator`, together with `exam?` (a live exam lists
  it), or `{:error, :not_found}`.
  """
  def learner_item(id) do
    item =
      Repo.one(
        from i in Item,
          join: m in assoc(i, :module),
          join: p in assoc(i, :program),
          where:
            i.id == ^id and is_nil(i.archived_at) and is_nil(m.archived_at) and
              p.status == :published,
          preload: [program: p]
      )

    case item do
      nil -> {:error, :not_found}
      item -> {:ok, for_evaluation(item), MapSet.member?(exam_item_ids([item.id]), item.id)}
    end
  end

  @doc """
  Returns a live exam of a live module of a published program with its live
  items in position order, prepared for `Espalier.Learning.Evaluator`, or
  `{:error, :not_found}`. Practice assessments answer `{:error, :not_found}`.
  """
  def learner_exam(id) do
    exam =
      Repo.one(
        from a in Assessment,
          join: m in assoc(a, :module),
          join: p in assoc(a, :program),
          where:
            a.id == ^id and a.kind == :exam and is_nil(a.archived_at) and is_nil(m.archived_at) and
              p.status == :published,
          preload: [program: p]
      )

    case exam do
      nil ->
        {:error, :not_found}

      exam ->
        items = [exam.id] |> exam_items() |> Enum.map(&elem(&1, 1)) |> for_evaluation()
        {:ok, exam, items}
    end
  end

  @doc """
  Returns a live module of a published program, or `{:error, :not_found}`.
  """
  def learner_module(id) do
    case live_module(id) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  @doc """
  Returns the live exams of a module that count for a credential, ordered by
  key.
  """
  def credential_exams(module_id) do
    Repo.all(
      from a in Assessment,
        where:
          a.module_id == ^module_id and a.kind == :exam and a.counts_for_credential and
            is_nil(a.archived_at),
        order_by: a.key
    )
  end

  # Options in position order, the live rules and the live lessons of
  # `item_reveals`: the data that the evaluator reads.
  defp for_evaluation(item_or_items) do
    Repo.preload(item_or_items,
      options: from(o in Option, order_by: [o.position, o.key]),
      rules: from(r in Rule, where: is_nil(r.archived_at), order_by: r.number),
      reveals: from(l in Lesson, where: is_nil(l.archived_at), order_by: [l.position, l.key])
    )
  end

  @doc """
  Reads the live learning objectives of a program, or of one module with the
  option `module_id:`, with their teaching lessons and their evidence.

  Evidence follows `Espalier.Catalog.Alignment`: an item that names the
  objective counts when a live assessment lists it or when its kind has a
  correct answer (every kind except `poll`), and a companion format that
  names the objective counts when its attendance counts. A row with
  `archived_at` set, or of an archived module, counts for nothing.

  The function runs a fixed number of queries over `learning_objectives`,
  `objective_lessons`, `item_objectives`, `format_objectives`,
  `assessment_items` and the parent rows, whatever the number of objectives.
  It returns one map per objective, ordered by module number and
  `position`, with:

    * `objective`: the `%LearningObjective{}`;
    * `lesson_ids`: the teaching lessons, in lesson `position` order;
    * `item_ids`: the evidence items, ordered by item key;
    * `format_ids`: the evidence formats, ordered by format key;
    * `assessment_ids`: the live assessments that list an evidence item.
  """
  def objective_links(program_id, opts \\ []) do
    objectives = live_objectives(program_id, Keyword.get(opts, :module_id))
    ids = Enum.map(objectives, & &1.id)
    lessons = teaching_lessons(ids)
    candidates = named_items(ids)
    listed = listing_assessments(candidates |> Enum.map(& &1.item_id) |> Enum.uniq())
    formats = evidence_formats(ids)

    for objective <- objectives do
      items =
        for %{objective_id: objective_id} = candidate <- candidates,
            objective_id == objective.id,
            candidate.kind != :poll or Map.has_key?(listed, candidate.item_id),
            do: candidate

      %{
        objective: objective,
        lesson_ids: Map.get(lessons, objective.id, []),
        item_ids: Enum.map(items, & &1.item_id),
        format_ids: Map.get(formats, objective.id, []),
        assessment_ids:
          items |> Enum.flat_map(&Map.get(listed, &1.item_id, [])) |> Enum.uniq() |> Enum.sort()
      }
    end
  end

  defp live_objectives(program_id, module_id) do
    query =
      from o in LearningObjective,
        join: m in assoc(o, :module),
        where: o.program_id == ^program_id and is_nil(o.archived_at) and is_nil(m.archived_at),
        order_by: [m.number, o.position, o.key]

    query = if module_id, do: where(query, [o], o.module_id == ^module_id), else: query
    Repo.all(query)
  end

  # Objective id to the ids of its live teaching lessons in position order.
  defp teaching_lessons([]), do: %{}

  defp teaching_lessons(objective_ids) do
    Repo.all(
      from ol in "objective_lessons",
        join: l in Lesson,
        on: l.id == ol.lesson_id,
        join: m in CatalogModule,
        on: m.id == l.module_id,
        where:
          ol.learning_objective_id in type(^objective_ids, {:array, :binary_id}) and
            is_nil(l.archived_at) and is_nil(m.archived_at),
        order_by: [l.position, l.key],
        select: {type(ol.learning_objective_id, :binary_id), l.id}
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # The live items that name one of the objectives, ordered by item key.
  defp named_items([]), do: []

  defp named_items(objective_ids) do
    Repo.all(
      from io in "item_objectives",
        join: i in Item,
        on: i.id == io.item_id,
        join: m in CatalogModule,
        on: m.id == i.module_id,
        where:
          io.learning_objective_id in type(^objective_ids, {:array, :binary_id}) and
            is_nil(i.archived_at) and is_nil(m.archived_at),
        order_by: [i.key, i.id],
        select: %{
          objective_id: type(io.learning_objective_id, :binary_id),
          item_id: i.id,
          kind: i.kind
        }
    )
  end

  # Item id to the ids of the live assessments of live modules that list it.
  defp listing_assessments([]), do: %{}

  defp listing_assessments(item_ids) do
    Repo.all(
      from ai in AssessmentItem,
        join: a in assoc(ai, :assessment),
        join: m in assoc(a, :module),
        where: ai.item_id in ^item_ids and is_nil(a.archived_at) and is_nil(m.archived_at),
        select: {ai.item_id, a.id}
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # Objective id to the ids of the live formats with `attendance_counts: true`
  # that name it, ordered by format key.
  defp evidence_formats([]), do: %{}

  defp evidence_formats(objective_ids) do
    Repo.all(
      from fo in "format_objectives",
        join: f in CompanionFormat,
        on: f.id == fo.companion_format_id,
        where:
          fo.learning_objective_id in type(^objective_ids, {:array, :binary_id}) and
            is_nil(f.archived_at) and f.attendance_counts,
        order_by: [f.key, f.id],
        select: {type(fo.learning_objective_id, :binary_id), f.id}
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
