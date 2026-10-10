defmodule Espalier.Catalog.Pack.Publisher do
  @moduledoc """
  Applies the payload of a validated `PackImport` to the catalog tables
  (task 0008, step 10; README section 11).

  `publish/1` runs in one `Repo.transact/2`. It first takes
  `pg_advisory_xact_lock(hashtext(<pack key>))`, so that two publishes of one
  pack run one after the other, and then re-reads the import with
  `FOR UPDATE`. An import whose status is not `validated` at that point
  gives `{:error, :not_validated}`. The `:timeout` of the transaction is
  `transaction_timeout/0`. DBConnection applies that timeout to the whole
  transaction, and its own default of 15 seconds is shorter than the
  publish of a pack near the archive limits of task 0015.

  Keyed rows are upserted by the unique index of their key with
  `on_conflict: {:replace_all_except, [:id, :inserted_at]}` and
  `returning: [:id]`, so a row keeps its id across publishes, and
  `archived_at` is cleared on every row present in the payload. The order
  is: program (`slug`), sources (`program_id, key`), glossary terms
  (`program_id, slug`), segments, companion formats, modules
  (`program_id, number`), lessons (`module_id, key`), rules
  (`module_id, number`), learning objectives (`program_id, key`, with the
  module whose `objectives.yaml` holds them), items (`program_id, key`),
  assessments (`program_id, key`) and qualifications (`program_id, code`).

  Rows without a key of their own are replaced per parent (delete, then
  insert): the blocks of each lesson with their citations, the options and
  the citations of each item, the citations of each rule, the join rows
  `item_rules`, `item_reveals` and `item_objectives` of each item, the
  `assessment_items` of each assessment, the requirements and the
  `qualification_prerequisites` (from the `qualification_held`
  requirements) of each qualification, the stations of the program, the
  `objective_lessons` of each objective and the `format_objectives` of each
  companion format. Positions are the place in the list of the payload,
  starting at 1; lessons keep the `position` of their front matter. These
  rows are written with `Repo.insert_all/3` in chunks that stay below the
  65,535 parameters of one PostgreSQL statement. The fields of blocks,
  options, requirements and stations are cast by their schema with
  `empty_values: []`, and an invalid value raises
  `Ecto.InvalidChangesetError`. Every block, option, citation, requirement
  and station gets its id from `Ecto.UUID.generate/0` before the insert, so
  that the citations of a block can name it. Its `inserted_at` and
  `updated_at` are the time of the publish, which is also the
  `published_at` of the import, and each statement sends that time once as
  an `insert_all` placeholder.

  Every keyed row of the program whose key the payload no longer holds
  receives `archived_at`, so records that reference it keep their target. A
  row that is already archived keeps its first `archived_at`. Finally the
  program becomes `published` with the `title`, `locale` and `version` of the
  pack, and the import becomes `published` with `published_at`.
  """

  import Ecto.Query, warn: false

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

  @program_fields [:slug, :title, :locale, :pack_version]
  @source_fields [:key, :title, :publisher, :url, :edition_date, :retrieved_on, :kind]
  @glossary_fields [:slug, :label, :short_text]
  @segment_fields [:key, :label, :description, :default_path, :position]
  @format_fields [:key, :title, :description, :phases, :attendance_counts, :position]
  @module_fields [
    :number,
    :title,
    :summary,
    :phases,
    :domains,
    :single_path,
    :refresher_unit,
    :areas_elsewhere
  ]
  @lesson_fields [:key, :position, :title]
  @rule_fields [:number, :statement, :action]
  @objective_fields [:key, :statement, :area, :depth, :phase, :domain, :position]
  @item_fields [:key, :kind, :stem, :core, :phase, :provenance, :config, :position]
  @assessment_fields [:key, :title, :kind, :counts_for_credential, :max_wrong, :core_required]
  @qualification_fields [
    :code,
    :title,
    :audience,
    :unlocks,
    :add_on,
    :validity_kind,
    :validity_months,
    :refresher_mode,
    :phases
  ]
  @block_fields [:position, :kind, :body, :provenance, :collapsed_on, :placeholder_key]
  @option_fields [:key, :label, :correct, :feedback, :position]
  @station_fields [:position, :kind, :title, :config]
  @requirement_fields [:kind, :target_key]

  # PostgreSQL takes at most 65,535 parameters per statement.
  @max_parameters 65_535

  @transaction_timeout :timer.minutes(10)

  # Keyed tables with a program_id, and the key of their ids in the map that
  # apply_payload/1 builds.
  @program_keyed [
    {LearningObjective, :objectives},
    {Item, :items},
    {Assessment, :assessments},
    {Qualification, :qualifications},
    {CompanionFormat, :formats},
    {Source, :sources},
    {GlossaryTerm, :glossary},
    {Segment, :segments}
  ]

  @typedoc "A `%Espalier.Catalog.PackImport{}`."
  @type pack_import :: Ecto.Schema.schema()

  @doc """
  Publishes a `validated` import and returns `{:ok, pack_import}` with the
  import in status `published`. Answers `{:error, :not_validated}` for an
  import in any other status, also when the import was published or changed
  after the caller read it.
  """
  @spec publish(pack_import()) :: {:ok, pack_import()} | {:error, :not_validated}
  def publish(%PackImport{status: :validated, pack_key: pack_key, id: id})
      when is_binary(pack_key) do
    Repo.transact(
      fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [pack_key])

        case Repo.one(from i in PackImport, where: i.id == ^id, lock: "FOR UPDATE") do
          %PackImport{status: :validated, payload: %{} = payload} = locked ->
            {:ok, apply_payload(locked, payload)}

          _other ->
            {:error, :not_validated}
        end
      end,
      timeout: transaction_timeout()
    )
  end

  def publish(%PackImport{}), do: {:error, :not_validated}

  @doc """
  The `:timeout` of the publish transaction in milliseconds: 600,000 (ten
  minutes) by default. `config :espalier, Espalier.Catalog.Pack.Publisher,
  transaction_timeout: ...` overrides it.
  """
  @spec transaction_timeout() :: timeout()
  def transaction_timeout do
    :espalier
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:transaction_timeout, @transaction_timeout)
  end

  defp apply_payload(pack_import, payload) do
    now = DateTime.utc_now(:second)
    program = upsert_program(payload)
    ids = upsert_rows(program.id, payload)

    replace_children(ids, payload, now)
    archive_missing(ids, now)

    program
    |> Changeset.change(
      status: :published,
      title: payload["title"],
      locale: payload["locale"],
      pack_version: payload["version"]
    )
    |> Repo.update!()

    pack_import
    |> Changeset.change(status: :published, published_at: now)
    |> Repo.update!()
  end

  ## Keyed rows

  defp upsert_program(payload) do
    attrs = %{
      "slug" => payload["key"],
      "title" => payload["title"],
      "locale" => payload["locale"],
      "pack_version" => payload["version"]
    }

    upsert!(%Program{}, attrs, @program_fields, [:slug])
  end

  defp upsert_rows(program_id, payload) do
    modules = payload["modules"]

    ids = %{
      program: program_id,
      sources: upsert_sources(program_id, payload["sources"]),
      glossary: upsert_glossary(program_id, payload["glossary"]),
      segments: upsert_segments(program_id, payload["segments"]),
      formats: upsert_formats(program_id, payload["formats"]),
      modules: upsert_modules(program_id, modules)
    }

    ids = Map.put(ids, :lessons, upsert_lessons(ids, modules))
    ids = Map.put(ids, :rules, upsert_rules(ids, modules))
    ids = Map.put(ids, :objectives, upsert_objectives(ids, modules))
    ids = Map.put(ids, :items, upsert_items(ids, modules))
    ids = Map.put(ids, :assessments, upsert_assessments(ids, modules))
    Map.put(ids, :qualifications, upsert_qualifications(program_id, payload["qualifications"]))
  end

  defp upsert_sources(program_id, sources) do
    Map.new(sources, fn source ->
      row = upsert!(%Source{program_id: program_id}, source, @source_fields, [:program_id, :key])
      {source["key"], row.id}
    end)
  end

  defp upsert_glossary(program_id, terms) do
    Map.new(terms, fn term ->
      struct = %GlossaryTerm{program_id: program_id}
      {term["slug"], upsert!(struct, term, @glossary_fields, [:program_id, :slug]).id}
    end)
  end

  defp upsert_segments(program_id, segments) do
    for {segment, position} <- Enum.with_index(segments, 1), into: %{} do
      attrs = positioned(segment, position)
      row = upsert!(%Segment{program_id: program_id}, attrs, @segment_fields, [:program_id, :key])
      {segment["key"], row.id}
    end
  end

  defp upsert_formats(program_id, formats) do
    for {format, position} <- Enum.with_index(formats, 1), into: %{} do
      struct = %CompanionFormat{program_id: program_id}
      attrs = positioned(format, position)
      {format["key"], upsert!(struct, attrs, @format_fields, [:program_id, :key]).id}
    end
  end

  defp upsert_modules(program_id, modules) do
    Map.new(modules, fn module ->
      struct = %CatalogModule{program_id: program_id}
      {module["number"], upsert!(struct, module, @module_fields, [:program_id, :number]).id}
    end)
  end

  defp upsert_lessons(ids, modules) do
    for module <- modules, lesson <- module["lessons"], into: %{} do
      struct = %Lesson{module_id: module_id(ids, module)}
      row = upsert!(struct, lesson, @lesson_fields, [:module_id, :key])
      {{module["number"], lesson["key"]}, row.id}
    end
  end

  defp upsert_rules(ids, modules) do
    for module <- modules, rule <- module["rules"], into: %{} do
      row =
        upsert!(%Rule{module_id: module_id(ids, module)}, rule, @rule_fields, [
          :module_id,
          :number
        ])

      {{module["number"], rule["number"]}, row.id}
    end
  end

  defp upsert_objectives(ids, modules) do
    for module <- modules,
        {objective, position} <- Enum.with_index(module["objectives"], 1),
        into: %{} do
      struct = %LearningObjective{program_id: ids.program, module_id: module_id(ids, module)}
      attrs = positioned(objective, position)
      {objective["key"], upsert!(struct, attrs, @objective_fields, [:program_id, :key]).id}
    end
  end

  defp upsert_items(ids, modules) do
    for module <- modules, {item, position} <- Enum.with_index(module["items"], 1), into: %{} do
      struct = %Item{
        program_id: ids.program,
        module_id: module_id(ids, module),
        lesson_id: lesson_id(ids, module, item["lesson"])
      }

      attrs = positioned(item, position)
      {item["key"], upsert!(struct, attrs, @item_fields, [:program_id, :key]).id}
    end
  end

  defp upsert_assessments(ids, modules) do
    for module <- modules, assessment <- module["assessments"], into: %{} do
      struct = %Assessment{program_id: ids.program, module_id: module_id(ids, module)}
      row = upsert!(struct, assessment, @assessment_fields, [:program_id, :key])
      {assessment["key"], row.id}
    end
  end

  defp upsert_qualifications(program_id, qualifications) do
    Map.new(qualifications, fn qualification ->
      struct = %Qualification{program_id: program_id}
      row = upsert!(struct, qualification, @qualification_fields, [:program_id, :code])
      {qualification["code"], row.id}
    end)
  end

  ## Rows replaced per parent

  defp replace_children(ids, payload, now) do
    modules = payload["modules"]

    replace_blocks(ids, modules, now)
    replace_options(ids, modules, now)
    replace_item_citations(ids, modules, now)
    replace_rule_citations(ids, modules, now)
    replace_item_rules(ids, modules)
    replace_item_reveals(ids, modules)
    replace_assessment_items(ids, modules)
    replace_requirements(ids, payload["qualifications"], now)
    replace_prerequisites(ids, payload["qualifications"])
    replace_stations(ids, payload["stations"], now)
    replace_objective_lessons(ids, modules)
    replace_item_objectives(ids, modules)
    replace_format_objectives(ids, payload["formats"])
  end

  # Deleting a block deletes its citations (on_delete: :delete_all). The
  # citations of the blocks name the ids that the block rows carry.
  defp replace_blocks(ids, modules, now) do
    delete_children(Block, :lesson_id, Map.values(ids.lessons))

    blocks =
      for module <- modules,
          lesson <- module["lessons"],
          {block, position} <- Enum.with_index(lesson["blocks"], 1) do
        lesson_id = Map.fetch!(ids.lessons, {module["number"], lesson["key"]})
        attrs = positioned(block, position)
        {row!(Block, attrs, @block_fields, %{lesson_id: lesson_id}), block["cite"]}
      end

    insert_rows(Block, Enum.map(blocks, &elem(&1, 0)), now)

    citations =
      Stream.flat_map(blocks, fn {row, cites} -> citation_rows(ids, cites, :block_id, row.id) end)

    insert_rows(Citation, citations, now)
  end

  defp replace_options(ids, modules, now) do
    delete_children(Option, :item_id, Map.values(ids.items))

    rows =
      for module <- modules,
          item <- module["items"],
          {option, position} <- Enum.with_index(item["options"], 1) do
        parent = %{item_id: Map.fetch!(ids.items, item["key"])}
        row!(Option, positioned(option, position), @option_fields, parent)
      end

    insert_rows(Option, rows, now)
  end

  defp replace_item_citations(ids, modules, now) do
    delete_children(Citation, :item_id, Map.values(ids.items))

    rows =
      Stream.flat_map(modules, fn module ->
        Stream.flat_map(module["items"], fn item ->
          item_id = Map.fetch!(ids.items, item["key"])
          citation_rows(ids, item["cite"], :item_id, item_id)
        end)
      end)

    insert_rows(Citation, rows, now)
  end

  defp replace_rule_citations(ids, modules, now) do
    delete_children(Citation, :rule_id, Map.values(ids.rules))

    rows =
      Stream.flat_map(modules, fn module ->
        Stream.flat_map(module["rules"], fn rule ->
          rule_id = Map.fetch!(ids.rules, {module["number"], rule["number"]})
          citation_rows(ids, rule["cite"], :rule_id, rule_id)
        end)
      end)

    insert_rows(Citation, rows, now)
  end

  # A citation row names its one parent in parent_field. The other two
  # parent columns stay NULL, as the check constraint citations_one_parent
  # requires.
  defp citation_rows(ids, cites, parent_field, parent_id) do
    for cite <- cites do
      {source_key, locator} = split_cite(cite)

      %{
        id: Ecto.UUID.generate(),
        source_id: Map.fetch!(ids.sources, source_key),
        locator: locator,
        inserted_at: {:placeholder, :now},
        updated_at: {:placeholder, :now}
      }
      |> Map.put(parent_field, parent_id)
    end
  end

  defp split_cite(cite) do
    case String.split(cite, "#", parts: 2) do
      [source_key, locator] -> {source_key, locator}
      [source_key] -> {source_key, nil}
    end
  end

  defp replace_item_rules(ids, modules) do
    rows =
      for module <- modules, item <- module["items"], number <- item["rules"] do
        %{
          item_id: Map.fetch!(ids.items, item["key"]),
          rule_id: Map.fetch!(ids.rules, {module["number"], number})
        }
      end

    replace_join("item_rules", :item_id, Map.values(ids.items), rows)
  end

  defp replace_item_reveals(ids, modules) do
    rows =
      for module <- modules, item <- module["items"], key <- item["reveals"] do
        %{
          item_id: Map.fetch!(ids.items, item["key"]),
          lesson_id: Map.fetch!(ids.lessons, {module["number"], key})
        }
      end

    replace_join("item_reveals", :item_id, Map.values(ids.items), rows)
  end

  defp replace_assessment_items(ids, modules) do
    delete_children(AssessmentItem, :assessment_id, Map.values(ids.assessments))

    rows =
      for module <- modules,
          assessment <- module["assessments"],
          {key, position} <- Enum.with_index(assessment["items"], 1) do
        %{
          assessment_id: Map.fetch!(ids.assessments, assessment["key"]),
          item_id: Map.fetch!(ids.items, key),
          position: position
        }
      end

    insert_all(AssessmentItem, rows)
  end

  defp replace_requirements(ids, qualifications, now) do
    delete_children(Requirement, :qualification_id, Map.values(ids.qualifications))

    rows =
      for qualification <- qualifications, requirement <- qualification["requirements"] do
        parent = %{qualification_id: Map.fetch!(ids.qualifications, qualification["code"])}
        attrs = %{"kind" => requirement["kind"], "target_key" => requirement["target"]}
        row!(Requirement, attrs, @requirement_fields, parent)
      end

    insert_rows(Requirement, rows, now)
  end

  defp replace_prerequisites(ids, qualifications) do
    rows =
      for qualification <- qualifications,
          %{"kind" => "qualification_held", "target" => code} <- qualification["requirements"] do
        %{
          qualification_id: Map.fetch!(ids.qualifications, qualification["code"]),
          prerequisite_id: Map.fetch!(ids.qualifications, code)
        }
      end

    replace_join(
      "qualification_prerequisites",
      :qualification_id,
      Map.values(ids.qualifications),
      rows
    )
  end

  defp replace_stations(ids, stations, now) do
    delete_children(Station, :program_id, [ids.program])

    rows =
      for {station, position} <- Enum.with_index(stations, 1) do
        module_id = if station["module"], do: Map.fetch!(ids.modules, station["module"])
        parents = %{program_id: ids.program, module_id: module_id}
        row!(Station, positioned(station, position), @station_fields, parents)
      end

    insert_rows(Station, rows, now)
  end

  defp replace_objective_lessons(ids, modules) do
    rows =
      for module <- modules, objective <- module["objectives"], key <- objective["taught_in"] do
        %{
          learning_objective_id: Map.fetch!(ids.objectives, objective["key"]),
          lesson_id: Map.fetch!(ids.lessons, {module["number"], key})
        }
      end

    replace_join("objective_lessons", :learning_objective_id, Map.values(ids.objectives), rows)
  end

  defp replace_item_objectives(ids, modules) do
    rows =
      for module <- modules, item <- module["items"], key <- item["objectives"] do
        %{
          item_id: Map.fetch!(ids.items, item["key"]),
          learning_objective_id: Map.fetch!(ids.objectives, key)
        }
      end

    replace_join("item_objectives", :item_id, Map.values(ids.items), rows)
  end

  defp replace_format_objectives(ids, formats) do
    rows =
      for format <- formats, key <- format["objectives"] do
        %{
          companion_format_id: Map.fetch!(ids.formats, format["key"]),
          learning_objective_id: Map.fetch!(ids.objectives, key)
        }
      end

    replace_join("format_objectives", :companion_format_id, Map.values(ids.formats), rows)
  end

  # A join table without a schema: the ids are dumped to their binary form,
  # and a pair that the payload names twice is written once.
  defp replace_join(table, parent_column, parent_ids, rows) do
    delete_children(table, parent_column, parent_ids)

    rows
    |> Enum.uniq()
    |> Enum.map(fn row -> Map.new(row, fn {column, id} -> {column, Ecto.UUID.dump!(id)} end) end)
    |> then(&insert_all(table, &1))
  end

  defp delete_children(_source, _parent_column, []), do: :ok

  defp delete_children(source, parent_column, parent_ids) do
    Repo.delete_all(
      from r in source,
        where: field(r, ^parent_column) in type(^parent_ids, {:array, Ecto.UUID})
    )

    :ok
  end

  # The rows of row!/4 and citation_rows/4 hold the time of the publish as
  # the placeholder :now, which a statement sends once.
  defp insert_rows(schema, rows, now), do: insert_all(schema, rows, placeholders: %{now: now})

  # A row takes at most one parameter per column, so a chunk holds as many
  # rows as fit into @max_parameters: by the number of fields of a schema,
  # which no row of it exceeds, or by the columns of the first row of a
  # join table.
  defp insert_all(source, rows, opts \\ [])

  defp insert_all(schema, rows, opts) when is_atom(schema) do
    insert_chunks(schema, length(schema.__schema__(:fields)), rows, opts)
  end

  defp insert_all(_table, [], _opts), do: :ok

  defp insert_all(table, [first | _] = rows, opts) when is_binary(table) do
    insert_chunks(table, map_size(first), rows, opts)
  end

  defp insert_chunks(source, columns, rows, opts) do
    rows
    |> Stream.chunk_every(div(@max_parameters, columns))
    |> Enum.each(&Repo.insert_all(source, &1, opts))
  end

  ## Archive

  defp archive_missing(ids, now) do
    program_id = ids.program
    module_ids = from m in CatalogModule, where: m.program_id == ^program_id, select: m.id

    archive(from(m in CatalogModule, where: m.program_id == ^program_id), ids.modules, now)
    archive(from(l in Lesson, where: l.module_id in subquery(module_ids)), ids.lessons, now)
    archive(from(r in Rule, where: r.module_id in subquery(module_ids)), ids.rules, now)

    for {schema, key} <- @program_keyed do
      archive(from(r in schema, where: r.program_id == ^program_id), Map.fetch!(ids, key), now)
    end

    :ok
  end

  defp archive(query, present, now) do
    present_ids = Map.values(present)

    query
    |> where([r], r.id not in ^present_ids and is_nil(r.archived_at))
    |> Repo.update_all(set: [archived_at: now, updated_at: now])
  end

  ## Helpers

  defp upsert!(struct, attrs, fields, conflict_target) do
    struct
    |> Changeset.cast(attrs, fields, empty_values: [])
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: conflict_target,
      returning: [:id]
    )
  end

  # A row for insert_rows/3: the fields cast by the schema, with its
  # defaults for the fields the attrs lack, the parent ids, a new id and the
  # placeholder of the time of the publish.
  defp row!(schema, attrs, fields, parents) do
    schema
    |> struct()
    |> Changeset.cast(attrs, fields, empty_values: [])
    |> Changeset.apply_action!(:insert)
    |> Map.take(fields)
    |> Map.merge(parents)
    |> Map.merge(%{
      id: Ecto.UUID.generate(),
      inserted_at: {:placeholder, :now},
      updated_at: {:placeholder, :now}
    })
  end

  defp positioned(entry, position), do: Map.put(entry, "position", position)

  defp module_id(ids, module), do: Map.fetch!(ids.modules, module["number"])

  defp lesson_id(_ids, _module, nil), do: nil
  defp lesson_id(ids, module, key), do: Map.fetch!(ids.lessons, {module["number"], key})
end
