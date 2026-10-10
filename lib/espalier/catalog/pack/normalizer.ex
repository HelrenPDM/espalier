defmodule Espalier.Catalog.Pack.Normalizer do
  @moduledoc """
  Builds the normalized map of a content pack (task 0008, step 9) from the
  cast pack of `Espalier.Catalog.Pack.Validator`. The importer stores it as
  the `payload` of a `PackImport`, the publisher applies it, and
  `Espalier.Catalog.Alignment.check/1` reads it.

  The map has string keys everywhere, holds JSON values only and no line
  numbers, so that a payload read back from a `:map` column equals the map
  before the insert:

    * every field of an entry is present: an absent scalar is `nil`, an
      absent list `[]`, an absent map `%{}`, and `alignment` defaults to
      `strict`;
    * enum values are strings, dates ISO 8601 strings of the form
      `YYYY-MM-DD` (`Date.to_iso8601/1` of the date), and a requirement
      target is a string (`"1"` for module 1);
    * numbers are integers: the free `config` of a station holds no float,
      because `jsonb` would give a float such as `1.0e3` back as an integer;
    * positioned lists keep their order: modules follow `number`, lessons
      `position` (lessons keep `"position"`), rules `number`; segments,
      stations, objectives, items, options, blocks, companion formats and the
      items of an assessment follow their file; `phases`, `domains`,
      `unlocks` and `collapsed_on` keep the file order;
    * every other list is sorted ascending: sources and assessments by key,
      glossary terms by slug, qualifications by code, requirements by kind
      and then target, the `rules` of an item by number, and the `reveals`,
      `objectives`, `taught_in` and `cite` lists by value.

  Two packs that differ only in the order of the sorted lists give equal
  maps.
  """

  alias Espalier.Catalog.Pack.Schema.{
    AreasElsewhere,
    Assessment,
    Block,
    ChecklistDrillConfig,
    ClassificationConfig,
    Feedback,
    Format,
    GlossaryTerm,
    Item,
    Objective,
    Option,
    Qualification,
    Rule,
    Segment,
    SlotBuilderConfig,
    Source,
    Station
  }

  @typedoc "The cast pack of the validator."
  @type cast_pack :: map()

  @doc "Builds the normalized map of `cast_pack`."
  @spec build(cast_pack()) :: map()
  def build(%{pack: pack} = cast) do
    %{
      "schema" => pack.schema,
      "key" => pack.key,
      "title" => pack.title,
      "locale" => pack.locale,
      "license" => pack.license,
      "version" => pack.version,
      "alignment" => enum(pack.alignment || :strict),
      "sources" => cast.sources |> Enum.map(&source/1) |> Enum.sort_by(& &1["key"]),
      "glossary" => cast.glossary |> Enum.map(&term/1) |> Enum.sort_by(& &1["slug"]),
      "segments" => Enum.map(cast.segments, &segment/1),
      "stations" => Enum.map(cast.stations, &station(&1, cast.feedback)),
      "qualifications" =>
        cast.qualifications |> Enum.map(&qualification/1) |> Enum.sort_by(& &1["code"]),
      "formats" => Enum.map(cast.formats, &format/1),
      "modules" => cast.modules |> Enum.map(&module/1) |> Enum.sort_by(& &1["number"])
    }
  end

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

  # The validator accepts `YYYY-MM-DD` only; the payload holds the date as
  # `Date.to_iso8601/1` writes it, the form the live `date` column gives back.
  defp iso_date(nil), do: nil
  defp iso_date(value), do: value |> Date.from_iso8601!() |> Date.to_iso8601()

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

  defp station(%Station{} = station, feedback) do
    %{
      "kind" => enum(station.kind),
      "title" => station.title,
      "module" => if(station.kind == :module, do: station.module),
      "config" => station_config(station, feedback)
    }
  end

  defp station_config(%Station{kind: :feedback, config: config}, %Feedback{} = feedback) do
    Map.merge(config || %{}, %{
      "intro" => feedback.intro,
      "questions" => Enum.map(feedback.questions, &question/1)
    })
  end

  defp station_config(%Station{config: config}, _feedback), do: config || %{}

  defp question(question) do
    %{
      "key" => question.key,
      "kind" => enum(question.kind),
      "label" => question.label,
      "options" => Enum.map(question.options || [], &%{"key" => &1.key, "label" => &1.label})
    }
  end

  defp qualification(%Qualification{} = qualification) do
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
        qualification.requirements
        |> Enum.map(&%{"kind" => enum(&1.kind), "target" => target(&1.target)})
        |> Enum.sort_by(&{&1["kind"], &1["target"]})
    }
  end

  defp target(number) when is_integer(number), do: Integer.to_string(number)
  defp target(key) when is_binary(key), do: key

  defp format(%Format{} = format) do
    %{
      "key" => format.key,
      "title" => format.title,
      "description" => format.description,
      "phases" => enums(format.phases),
      "attendance_counts" => format.attendance_counts,
      "objectives" => sorted(format.objectives)
    }
  end

  defp module(%{module: module} = cast_module) do
    %{
      "number" => module.number,
      "title" => module.title,
      "summary" => module.summary,
      "phases" => enums(module.phases),
      "domains" => module.domains || [],
      "single_path" => module.single_path,
      "refresher_unit" => module.refresher_unit,
      "areas_elsewhere" => areas_elsewhere(module.areas_elsewhere),
      "lessons" => cast_module.lessons |> Enum.map(&lesson/1) |> Enum.sort_by(& &1["position"]),
      "objectives" => Enum.map(cast_module.objectives, &objective/1),
      "rules" => cast_module.rules |> Enum.map(&rule/1) |> Enum.sort_by(& &1["number"]),
      "items" => Enum.map(cast_module.items, &item/1),
      "assessments" =>
        cast_module.assessments |> Enum.map(&assessment/1) |> Enum.sort_by(& &1["key"])
    }
  end

  defp areas_elsewhere(nil), do: %{}

  defp areas_elsewhere(%AreasElsewhere{} = areas) do
    areas
    |> Map.take(AreasElsewhere.areas())
    |> Enum.reject(fn {_area, elsewhere} -> is_nil(elsewhere) end)
    |> Map.new(fn {area, elsewhere} ->
      {Atom.to_string(area), %{"where" => elsewhere.where, "reason" => elsewhere.reason}}
    end)
  end

  defp lesson(%{key: key, front: front, blocks: blocks}) do
    %{
      "key" => key,
      "title" => front.title,
      "position" => front.position,
      "blocks" => Enum.map(blocks, &block/1)
    }
  end

  defp block(%Block{} = block) do
    %{
      "kind" => enum(block.kind),
      "body" => block.body,
      "provenance" => enum(block.provenance),
      "collapsed_on" => enums(block.collapsed_on),
      "placeholder_key" => block.placeholder_key,
      "cite" => sorted(block.cite)
    }
  end

  defp objective(%Objective{} = objective) do
    %{
      "key" => objective.key,
      "statement" => objective.statement,
      "area" => enum(objective.area),
      "depth" => enum(objective.depth),
      "phase" => enum(objective.phase),
      "domain" => objective.domain,
      "taught_in" => sorted(objective.taught_in)
    }
  end

  defp rule(%Rule{} = rule) do
    %{
      "number" => rule.number,
      "statement" => rule.statement,
      "action" => rule.action,
      "cite" => sorted(rule.cite)
    }
  end

  defp item(%Item{} = item) do
    %{
      "key" => item.key,
      "kind" => enum(item.kind),
      "lesson" => item.lesson,
      "stem" => item.stem,
      "core" => item.core,
      "phase" => enum(item.phase),
      "provenance" => enum(item.provenance),
      "objectives" => sorted(item.objectives),
      "rules" => sorted(item.rules),
      "reveals" => sorted(item.reveals),
      "cite" => sorted(item.cite),
      "options" => Enum.map(item.options || [], &option/1),
      "config" => config(item.config)
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

  defp config(nil), do: %{}

  defp config(%SlotBuilderConfig{slots: slots}) do
    %{
      "slots" =>
        Enum.map(slots, fn slot ->
          %{
            "key" => slot.key,
            "label" => slot.label,
            "options" => Enum.map(slot.options, &option/1)
          }
        end)
    }
  end

  defp config(%ClassificationConfig{} = config) do
    %{
      "categories" => Enum.map(config.categories, &%{"key" => &1.key, "label" => &1.label}),
      "cases" =>
        Enum.map(config.cases, &%{"key" => &1.key, "text" => &1.text, "feedback" => &1.feedback}),
      "expected" => config.expected
    }
  end

  defp config(%ChecklistDrillConfig{checks: checks}) do
    %{
      "checks" =>
        Enum.map(checks, &%{"key" => &1.key, "label" => &1.label, "required" => &1.required})
    }
  end

  defp assessment(%Assessment{} = assessment) do
    %{
      "key" => assessment.key,
      "title" => assessment.title,
      "kind" => enum(assessment.kind),
      "counts_for_credential" => assessment.counts_for_credential,
      "max_wrong" => assessment.max_wrong,
      "core_required" => assessment.core_required,
      "items" => assessment.items || []
    }
  end

  defp enum(nil), do: nil
  defp enum(value) when is_atom(value), do: Atom.to_string(value)

  defp enums(values), do: Enum.map(values || [], &enum/1)

  defp sorted(values), do: Enum.sort(values || [])
end
