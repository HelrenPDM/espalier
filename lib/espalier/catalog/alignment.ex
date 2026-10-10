defmodule Espalier.Catalog.Alignment do
  @moduledoc """
  Constructive alignment per topic (README section 7, domain rule 14). A
  topic is a module. Each learning objective of a module has one competence
  area (`subject`, `method`, `self` or `social`), a depth (`know`, `apply` or
  `judge`) and the lessons that teach it (`taught_in`). Items and companion
  formats name the objectives they serve.

  Evidence for an objective is every item that names the objective and is
  listed by an assessment, every other item that names the objective and
  whose kind has a correct answer (every kind except `poll`, so
  `checklist_drill` counts), and every companion format with
  `attendance_counts: true` that names the objective. A format with
  `attendance_counts: false` that names an objective anchors it and provides
  no evidence. An item may name an objective of another module, and its
  evidence then belongs to the objective's module.

  `check/1` applies four checks to a payload in the shape of the normalized
  map of a content pack:

  1. Every objective has at least one lesson in `taught_in` and at least one
     piece of evidence. Each missing part is one finding on the objective in
     `objectives.yaml`.
  2. Every item listed by an assessment with `counts_for_credential: true`
     names at least one objective. Each such item without an objective is one
     finding on the item in `items.yaml`.
  3. Each of the four areas has at least one objective of the module, or
     `areas_elsewhere` of the module names the area with a place that carries
     an objective of that area. A format carries an area when it names an
     objective with that area, and a module carries an area when it has an
     objective with that area. Each uncovered area is one finding on the area
     in `module.yaml`.
  4. The kind of the evidence fits the depth of the objective. An objective
     with evidence of which no piece has a kind that fits its depth is one
     finding on the objective in `objectives.yaml`. An objective without
     evidence gets no finding from this check, because check 1 reports it.

  The kinds that fit a depth come from the module attribute
  `@evidence_for_depth`:

  | Depth   | Evidence kinds that fit                                  |
  | ------- | -------------------------------------------------------- |
  | `know`  | `single_choice`, `multiple_choice`                       |
  | `apply` | `slot_builder`, `classification`, `checklist_drill`      |
  | `judge` | `classification_with_case_comparison`, `format`          |

  An item of the evidence has its item kind. A `classification` item also has
  the kind `classification_with_case_comparison` when a lesson in the
  objective's `taught_in` holds a `case_comparison` block. A companion format
  has the kind `format`.

  With `alignment: strict`, the default, findings of checks 1 to 3 are
  errors; with `alignment: warn`, they are warnings. Findings of check 4 are
  warnings in both modes.

  `matrix/1` returns the alignment matrix of a payload or of the live rows of
  a published program: one row per module, competence area and depth.
  """

  import Ecto.Query

  alias Espalier.Catalog.{
    Assessment,
    AssessmentItem,
    Block,
    CompanionFormat,
    Item,
    LearningObjective,
    Lesson,
    Program
  }

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Repo

  @evidence_for_depth %{
    know: [:single_choice, :multiple_choice],
    apply: [:slot_builder, :classification, :checklist_drill],
    judge: [:classification_with_case_comparison, :format]
  }

  # `@evidence_for_depth` with strings, as a payload holds depths and kinds.
  @fitting_kinds Map.new(@evidence_for_depth, fn {depth, kinds} ->
                   {Atom.to_string(depth), Enum.map(kinds, &Atom.to_string/1)}
                 end)

  # Item kinds with a correct answer: every kind except `poll`.
  @answer_kinds ~w(single_choice multiple_choice slot_builder classification checklist_drill)

  @areas ~w(subject method self social)
  @depths ~w(know apply judge)

  @typedoc """
  A map in the shape of the normalized payload of a content pack, with
  string keys. The members read here are `alignment`, `formats` (`key`,
  `attendance_counts`, `objectives`) and `modules` (`number`,
  `areas_elsewhere`, `lessons` with `key` and the `kind` of their `blocks`,
  `objectives` with `key`, `area`, `depth` and `taught_in`, `items` with
  `key`, `kind` and `objectives`, and `assessments` with `key`,
  `counts_for_credential` and `items`).
  """
  @type payload :: %{optional(String.t()) => term()}

  @typedoc """
  A finding of `check/1`. `module` is the module number, and `key` is the
  objective key (checks 1 and 4), the item key (check 2) or the area
  (check 3).
  """
  @type finding :: %{
          check: 1..4,
          module: integer(),
          file: String.t(),
          key: String.t(),
          message: String.t()
        }

  @typedoc """
  A row of the alignment matrix. `evidence` holds `item:<key>` and
  `format:<key>` entries, and `elsewhere` is the `where` of
  `areas_elsewhere` when the module has no objective in the area.
  """
  @type row :: %{
          module: integer(),
          area: String.t(),
          depth: String.t(),
          objectives: [String.t()],
          lessons: [String.t()],
          evidence: [String.t()],
          elsewhere: String.t() | nil
        }

  @doc """
  Checks the constructive alignment of `payload` and returns
  `{errors, warnings}`.

  Each finding is a map with `check` (1 to 4), `module` (the module number),
  `file` (`objectives.yaml`, `items.yaml` or `module.yaml`), `key` and
  `message`. Both lists are sorted by module number, check and key. Findings
  of checks 1 to 3 are errors unless the payload sets `alignment` to `warn`;
  findings of check 4 are always warnings.
  """
  @spec check(payload()) :: {[finding()], [finding()]}
  def check(payload) when is_map(payload) do
    index = index(payload)

    graded =
      check_lessons_and_evidence(index) ++ check_credential_items(index) ++ check_areas(index)

    advisory = check_depths(index)

    case Map.get(payload, "alignment") do
      "warn" -> {[], sort_findings(graded ++ advisory)}
      _strict -> {sort_findings(graded), sort_findings(advisory)}
    end
  end

  @doc """
  Returns the alignment matrix of a `%Espalier.Catalog.Program{}` or of a
  payload.

  The matrix holds one row per module, area and depth: modules in number
  order, areas in the order `subject`, `method`, `self`, `social`, and depths
  in the order `know`, `apply`, `judge`, so that every module has twelve rows.
  Every list of a row is sorted and free of duplicates.

  For a program, the function reads the live rows: it skips every row whose
  `archived_at` is set, every row of an archived module, and every join row
  that points to such a row. The program and the payload of the same pack
  give equal rows.
  """
  @spec matrix(struct() | payload()) :: [row()]
  def matrix(%Program{} = program), do: program |> program_payload() |> matrix()

  def matrix(payload) when is_map(payload) do
    index = index(payload)

    for module <- index.modules, area <- @areas, depth <- @depths do
      matrix_row(module, area, depth, index)
    end
  end

  ## Index of a payload

  defp index(payload) do
    modules = payload |> list_at("modules") |> Enum.sort_by(&Map.get(&1, "number"))
    formats = list_at(payload, "formats")

    objectives =
      for module <- modules, objective <- list_at(module, "objectives") do
        {module["number"], objective}
      end

    items = for module <- modules, item <- list_at(module, "items"), do: {module["number"], item}

    %{
      modules: modules,
      formats: formats,
      objectives: objectives,
      items: items,
      evidence: evidence(items, formats, assessed_items(modules)),
      objective_areas: Map.new(objectives, fn {_number, objective} -> area_of(objective) end),
      case_lessons: case_lessons(modules)
    }
  end

  defp area_of(objective), do: {objective["key"], objective["area"]}

  defp assessed_items(modules) do
    for module <- modules,
        assessment <- list_at(module, "assessments"),
        key <- list_at(assessment, "items"),
        into: MapSet.new(),
        do: key
  end

  # Maps each objective key to its evidence: `{:item, key, kind}` or
  # `{:format, key}`.
  defp evidence(items, formats, assessed) do
    item_pieces =
      for {_number, item} <- items,
          MapSet.member?(assessed, item["key"]) or item["kind"] in @answer_kinds,
          key <- list_at(item, "objectives"),
          do: {key, {:item, item["key"], item["kind"]}}

    format_pieces =
      for format <- formats,
          format["attendance_counts"] == true,
          key <- list_at(format, "objectives"),
          do: {key, {:format, format["key"]}}

    Enum.group_by(item_pieces ++ format_pieces, &elem(&1, 0), &elem(&1, 1))
  end

  # Maps each module number to the keys of its lessons that hold a
  # `case_comparison` block.
  defp case_lessons(modules) do
    Map.new(modules, fn module ->
      keys =
        for lesson <- list_at(module, "lessons"),
            Enum.any?(list_at(lesson, "blocks"), &(&1["kind"] == "case_comparison")),
            into: MapSet.new(),
            do: lesson["key"]

      {module["number"], keys}
    end)
  end

  defp evidence_of(index, objective), do: Map.get(index.evidence, objective["key"], [])

  defp has_area?(index, number, area) do
    Enum.any?(index.objectives, &match?({^number, %{"area" => ^area}}, &1))
  end

  defp place(module, area) do
    case module |> map_at("areas_elsewhere") |> Map.get(area) do
      %{"where" => where} when is_binary(where) -> where
      _absent -> nil
    end
  end

  ## Check 1: teaching lesson and evidence

  defp check_lessons_and_evidence(index) do
    for {number, objective} <- index.objectives,
        message <- objective_gaps(objective, evidence_of(index, objective)) do
      finding(1, number, "objectives.yaml", objective["key"], message)
    end
  end

  defp objective_gaps(objective, evidence) do
    key = objective["key"]

    lesson_gap =
      if list_at(objective, "taught_in") == [],
        do: ["objective `#{key}` names no teaching lesson in `taught_in`"],
        else: []

    evidence_gap =
      if evidence == [],
        do: [
          "objective `#{key}` has no evidence: no item of an assessment, no item with a " <>
            "correct answer and no format with `attendance_counts: true` names it"
        ],
        else: []

    lesson_gap ++ evidence_gap
  end

  ## Check 2: items of credential assessments

  defp check_credential_items(index) do
    items = Map.new(index.items, fn {number, item} -> {item["key"], {number, item}} end)

    listings =
      for module <- index.modules,
          assessment <- list_at(module, "assessments"),
          assessment["counts_for_credential"] == true,
          item_key <- list_at(assessment, "items"),
          do: {item_key, {module["number"], assessment["key"]}}

    listings
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {item_key, listed_by} ->
      credential_item_findings(item_key, listed_by, items)
    end)
  end

  # An item key that matches no item has no objective; its finding belongs
  # to the module of the first assessment that lists it.
  defp credential_item_findings(item_key, [{assessment_module, _key} | _rest] = listed_by, items) do
    {number, objectives} =
      case Map.fetch(items, item_key) do
        {:ok, {number, item}} -> {number, list_at(item, "objectives")}
        :error -> {assessment_module, []}
      end

    if objectives == [] do
      assessments = listed_by |> Enum.map(&elem(&1, 1)) |> sorted_set()

      message =
        "item `#{item_key}` names no objective in `objectives`, but #{listing(assessments)}"

      [finding(2, number, "items.yaml", item_key, message)]
    else
      []
    end
  end

  defp listing([assessment]) do
    "the assessment `#{assessment}` lists it and counts for a credential"
  end

  defp listing(assessments) do
    "the assessments #{join_keys(assessments, "and")} list it and count for a credential"
  end

  ## Check 3: the four areas of every module

  defp check_areas(index) do
    for module <- index.modules,
        area <- @areas,
        not covered?(module, area, index) do
      finding(3, module["number"], "module.yaml", area, area_message(module, area))
    end
  end

  defp covered?(module, area, index) do
    has_area?(index, module["number"], area) or carries?(place(module, area), area, index)
  end

  defp carries?("format:" <> key, area, index) do
    Enum.any?(index.formats, fn format ->
      format["key"] == key and
        Enum.any?(list_at(format, "objectives"), &(Map.get(index.objective_areas, &1) == area))
    end)
  end

  defp carries?("module:" <> number, area, index) do
    case Integer.parse(number) do
      {number, ""} -> has_area?(index, number, area)
      _other -> false
    end
  end

  defp carries?(_place, _area, _index), do: false

  defp area_message(module, area) do
    gap = "no objective of module #{module["number"]} has the area `#{area}`"

    case place(module, area) do
      nil -> "#{gap}, and `areas_elsewhere` does not name the area"
      where -> "#{gap}, and `#{where}` named in `areas_elsewhere` carries no `#{area}` objective"
    end
  end

  ## Check 4: kind of evidence and depth

  defp check_depths(index) do
    Enum.flat_map(index.objectives, fn {number, objective} ->
      depth_findings(number, objective, evidence_of(index, objective), index)
    end)
  end

  defp depth_findings(_number, _objective, [], _index), do: []

  defp depth_findings(number, objective, pieces, index) do
    kinds = pieces |> Enum.flat_map(&kinds(&1, number, objective, index)) |> sorted_set()
    depth = objective["depth"]
    fitting = Map.get(@fitting_kinds, depth, [])

    if Enum.any?(kinds, &(&1 in fitting)) do
      []
    else
      message =
        "evidence of objective `#{objective["key"]}` has the kinds #{join_keys(kinds, "and")}, " <>
          "none of which fits the depth `#{depth}` (#{join_keys(fitting, "or")})"

      [finding(4, number, "objectives.yaml", objective["key"], message)]
    end
  end

  defp kinds({:format, _key}, _number, _objective, _index), do: ["format"]

  defp kinds({:item, _key, "classification"}, number, objective, index) do
    if case_comparison_taught?(number, objective, index),
      do: ["classification", "classification_with_case_comparison"],
      else: ["classification"]
  end

  defp kinds({:item, _key, kind}, _number, _objective, _index), do: [to_string(kind)]

  defp case_comparison_taught?(number, objective, index) do
    lessons = Map.get(index.case_lessons, number, MapSet.new())
    Enum.any?(list_at(objective, "taught_in"), &MapSet.member?(lessons, &1))
  end

  ## Matrix

  defp matrix_row(module, area, depth, index) do
    number = module["number"]

    objectives =
      for {^number, %{"area" => ^area, "depth" => ^depth} = objective} <- index.objectives,
          do: objective

    %{
      module: number,
      area: area,
      depth: depth,
      objectives: objectives |> Enum.map(& &1["key"]) |> sorted_set(),
      lessons: objectives |> Enum.flat_map(&list_at(&1, "taught_in")) |> sorted_set(),
      evidence:
        objectives
        |> Enum.flat_map(&evidence_of(index, &1))
        |> Enum.map(&evidence_label/1)
        |> sorted_set(),
      elsewhere: if(has_area?(index, number, area), do: nil, else: place(module, area))
    }
  end

  defp evidence_label({:item, key, _kind}), do: "item:#{key}"
  defp evidence_label({:format, key}), do: "format:#{key}"

  ## Payload of the live rows of a program

  defp program_payload(%Program{id: program_id}) do
    rows = live_rows(program_id)
    links = links(program_id, rows)

    %{
      "formats" => Enum.map(rows.formats, &format_payload(&1, links)),
      "modules" => Enum.map(rows.modules, &module_payload(&1, rows, links))
    }
  end

  defp live_rows(program_id) do
    modules =
      Repo.all(
        from m in CatalogModule,
          where: m.program_id == ^program_id and is_nil(m.archived_at),
          order_by: m.number
      )

    module_ids = Enum.map(modules, & &1.id)

    %{
      modules: modules,
      lessons: live_children(Lesson, module_ids, [:position, :key]),
      objectives: live_children(LearningObjective, module_ids, [:position, :key]),
      items: live_children(Item, module_ids, [:position, :key]),
      assessments: live_children(Assessment, module_ids, [:key]),
      formats:
        Repo.all(
          from f in CompanionFormat,
            where: f.program_id == ^program_id and is_nil(f.archived_at),
            order_by: [f.position, f.key]
        )
    }
  end

  defp live_children(schema, module_ids, order) do
    Repo.all(
      from r in schema,
        where: r.module_id in ^module_ids and is_nil(r.archived_at),
        order_by: ^order
    )
  end

  # Join rows grouped by their owner: each owner id maps to the keys of the
  # rows it points to. A join row counts only when both of its rows are live.
  defp links(program_id, rows) do
    lessons = keys_by_id(rows.lessons)
    objectives = keys_by_id(rows.objectives)
    items = keys_by_id(rows.items)

    %{
      taught_in:
        LearningObjective |> linked_ids(:lessons, program_id) |> linked(objectives, lessons),
      item_objectives: Item |> linked_ids(:objectives, program_id) |> linked(items, objectives),
      format_objectives:
        CompanionFormat
        |> linked_ids(:objectives, program_id)
        |> linked(keys_by_id(rows.formats), objectives),
      assessment_items:
        program_id |> assessment_item_ids() |> linked(keys_by_id(rows.assessments), items),
      block_kinds: block_kinds(program_id)
    }
  end

  defp keys_by_id(rows), do: Map.new(rows, &{&1.id, &1.key})

  defp linked_ids(schema, assoc, program_id) do
    Repo.all(
      from owner in schema,
        join: target in assoc(owner, ^assoc),
        where: owner.program_id == ^program_id,
        select: {owner.id, target.id}
    )
  end

  defp assessment_item_ids(program_id) do
    Repo.all(
      from ai in AssessmentItem,
        join: a in assoc(ai, :assessment),
        where: a.program_id == ^program_id,
        order_by: [ai.position],
        select: {ai.assessment_id, ai.item_id}
    )
  end

  defp block_kinds(program_id) do
    Repo.all(
      from b in Block,
        join: l in assoc(b, :lesson),
        join: m in assoc(l, :module),
        where: m.program_id == ^program_id,
        order_by: [b.position],
        select: {b.lesson_id, b.kind}
    )
    |> Enum.group_by(&elem(&1, 0), &enum_string(elem(&1, 1)))
  end

  defp linked(pairs, owners, targets) do
    pairs
    |> Enum.filter(fn {owner, target} ->
      Map.has_key?(owners, owner) and Map.has_key?(targets, target)
    end)
    |> Enum.group_by(&elem(&1, 0), fn {_owner, target} -> Map.fetch!(targets, target) end)
  end

  defp module_payload(module, rows, links) do
    %{
      "number" => module.number,
      "areas_elsewhere" => module.areas_elsewhere || %{},
      "lessons" => for(l <- rows.lessons, l.module_id == module.id, do: lesson_payload(l, links)),
      "objectives" =>
        for(o <- rows.objectives, o.module_id == module.id, do: objective_payload(o, links)),
      "items" => for(i <- rows.items, i.module_id == module.id, do: item_payload(i, links)),
      "assessments" =>
        for(a <- rows.assessments, a.module_id == module.id, do: assessment_payload(a, links))
    }
  end

  defp lesson_payload(lesson, links) do
    blocks = links.block_kinds |> Map.get(lesson.id, []) |> Enum.map(&%{"kind" => &1})
    %{"key" => lesson.key, "position" => lesson.position, "blocks" => blocks}
  end

  defp objective_payload(objective, links) do
    %{
      "key" => objective.key,
      "area" => enum_string(objective.area),
      "depth" => enum_string(objective.depth),
      "taught_in" => links.taught_in |> Map.get(objective.id, []) |> Enum.sort()
    }
  end

  defp item_payload(item, links) do
    %{
      "key" => item.key,
      "kind" => enum_string(item.kind),
      "objectives" => links.item_objectives |> Map.get(item.id, []) |> Enum.sort()
    }
  end

  defp assessment_payload(assessment, links) do
    %{
      "key" => assessment.key,
      "counts_for_credential" => assessment.counts_for_credential,
      "items" => Map.get(links.assessment_items, assessment.id, [])
    }
  end

  defp format_payload(format, links) do
    %{
      "key" => format.key,
      "attendance_counts" => format.attendance_counts,
      "objectives" => links.format_objectives |> Map.get(format.id, []) |> Enum.sort()
    }
  end

  ## Helpers

  defp finding(check, module, file, key, message) do
    %{check: check, module: module, file: file, key: key, message: message}
  end

  defp sort_findings(findings), do: Enum.sort_by(findings, &{&1.module, &1.check, &1.key})

  defp sorted_set(list), do: list |> Enum.uniq() |> Enum.sort()

  defp join_keys(keys, conjunction) do
    quoted = Enum.map(keys, &"`#{&1}`")

    case Enum.split(quoted, -1) do
      {[], last} -> Enum.join(last)
      {init, [last]} -> "#{Enum.join(init, ", ")} #{conjunction} #{last}"
    end
  end

  defp list_at(map, key) do
    case Map.get(map, key) do
      list when is_list(list) -> list
      _absent -> []
    end
  end

  defp map_at(map, key) do
    case Map.get(map, key) do
      value when is_map(value) -> value
      _absent -> %{}
    end
  end

  defp enum_string(nil), do: nil
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
end
