defmodule EspalierWeb.CatalogJSONLeakTest do
  # Catalog views carry no answer key and no option feedback before a
  # submission (task 0009, step 12; ASVS 8.1.2 and 15.3.1).
  use Espalier.DataCase, async: true

  import Espalier.LearningFixtures
  import Espalier.PackFixtures

  alias Espalier.Catalog
  alias Espalier.Catalog.{Item, Option}
  alias EspalierWeb.CatalogJSON

  @forbidden ~w(config correct expected feedback)
  @kinds ~w(checklist_drill classification multiple_choice poll single_choice slot_builder)

  setup do
    program = publish_demo!()
    assert {:ok, program_view} = Catalog.program_view(demo_slug())
    program_json = round_trip(CatalogJSON.show(%{program: program_view}))

    modules =
      for %{"id" => id} <- program_json["modules"] do
        assert {:ok, view} = Catalog.module_view(id)
        round_trip(CatalogJSON.module(%{view: view}))
      end

    %{program: program, program_json: program_json, modules: modules}
  end

  test "the program view and every module view carry no answer key at any depth",
       %{program_json: program_json, modules: modules} do
    assert length(modules) == 2

    for json <- [program_json | modules] do
      keys = json |> keys() |> MapSet.new()

      assert MapSet.disjoint?(keys, MapSet.new(@forbidden)),
             "found #{inspect(MapSet.intersection(keys, MapSet.new(@forbidden)))}"
    end

    # The walk reaches the members that hold options, slots, cases and checks.
    module_keys = modules |> keys() |> MapSet.new()

    for key <- ~w(options slots cases categories checks objective_keys evidence),
        do: assert(key in module_keys)
  end

  test "the module views render every item of the demo program, practice and exam",
       %{program: program, modules: modules} do
    rendered = Enum.flat_map(modules, &items_of/1)
    keys = Enum.map(rendered, & &1["key"])

    assert keys == Enum.uniq(keys)

    assert MapSet.new(keys) ==
             MapSet.new(
               Repo.all(from i in Item, where: i.program_id == ^program.id, select: i.key)
             )

    assert MapSet.new(keys) == MapSet.new(yaml_items(), & &1["key"])
    assert rendered |> Enum.map(& &1["kind"]) |> Enum.uniq() |> Enum.sort() == @kinds

    [module_1, module_2] = modules
    exam = read_yaml!(demo_path(), "modules/01-basics/assessment.yaml") |> hd()

    assert [%{"key" => "module-1-exam", "items" => exam_items}] = module_1["exams"]
    assert Enum.map(exam_items, & &1["key"]) == exam["items"]

    assert module_1["practice_items"] |> Enum.map(& &1["key"]) |> Enum.sort() ==
             Enum.sort(yaml_item_keys("01-basics") -- exam["items"])

    assert module_2["exams"] == []

    assert module_2["practice_items"] |> Enum.map(& &1["key"]) |> Enum.sort() ==
             Enum.sort(yaml_item_keys("02-checking"))
  end

  test "options carry key and label only, the same for correct and wrong options",
       %{program: program, program_json: program_json, modules: modules} do
    for item <- Enum.flat_map(modules, &items_of/1) do
      stored = item!(program, item["key"])
      config = stored.config || %{}

      assert item["options"] == expected_options(stored), item["key"]

      assert item["slots"] ==
               for(
                 slot <- Map.get(config, "slots", []),
                 do: %{
                   "key" => slot["key"],
                   "label" => slot["label"],
                   "options" => key_and_label(slot["options"])
                 }
               ),
             item["key"]

      assert item["categories"] == key_and_label(Map.get(config, "categories", [])),
             item["key"]

      assert item["cases"] ==
               for(
                 c <- Map.get(config, "cases", []),
                 do: %{"key" => c["key"], "text" => c["text"]}
               ),
             item["key"]

      assert item["checks"] ==
               for(
                 check <- Map.get(config, "checks", []),
                 do: %{
                   "key" => check["key"],
                   "label" => check["label"],
                   "required" => check["required"] == true
                 }
               ),
             item["key"]
    end

    # The options of the station questions carry key and label as well.
    for station <- program_json["stations"],
        question <- station["questions"],
        option <- question["options"] do
      assert option |> Map.keys() |> Enum.sort() == ["key", "label"]
    end
  end

  test "no option or case feedback of the demo pack appears as a value in a view",
       %{program: program, program_json: program_json, modules: modules} do
    option_feedback =
      Repo.all(
        from o in Option,
          join: i in assoc(o, :item),
          where: i.program_id == ^program.id and not is_nil(o.feedback),
          select: o.feedback
      )

    config_feedback =
      for item <- yaml_items(),
          config = item["config"] || %{},
          entry <-
            Enum.flat_map(Map.get(config, "slots", []), & &1["options"]) ++
              Map.get(config, "cases", []),
          entry["feedback"],
          do: entry["feedback"]

    assert option_feedback != []
    assert config_feedback != []

    values = [program_json | modules] |> strings() |> MapSet.new()
    feedback = MapSet.new(option_feedback ++ config_feedback)

    assert MapSet.disjoint?(values, feedback),
           "found #{inspect(MapSet.intersection(values, feedback))}"
  end

  ## JSON

  defp round_trip(data), do: data |> JSON.encode!() |> JSON.decode!()

  defp items_of(view) do
    view["practice_items"] ++ Enum.flat_map(view["exams"], & &1["items"])
  end

  # Every map key at any depth.
  defp keys(map) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> [key | keys(value)] end)

  defp keys(list) when is_list(list), do: Enum.flat_map(list, &keys/1)
  defp keys(_value), do: []

  # Every string value at any depth.
  defp strings(map) when is_map(map), do: map |> Map.values() |> strings()
  defp strings(list) when is_list(list), do: Enum.flat_map(list, &strings/1)
  defp strings(value) when is_binary(value), do: [value]
  defp strings(_value), do: []

  defp expected_options(%Item{kind: kind, options: options})
       when kind in [:single_choice, :multiple_choice, :poll] do
    options
    |> Enum.sort_by(&{&1.position, &1.key})
    |> Enum.map(&%{"key" => &1.key, "label" => &1.label})
  end

  defp expected_options(%Item{}), do: []

  defp key_and_label(entries),
    do: Enum.map(entries, &%{"key" => &1["key"], "label" => &1["label"]})

  ## Demo pack

  defp yaml_items do
    for file <- Path.wildcard(Path.join(demo_path(), "modules/*/items.yaml")),
        item <- file |> File.read!() |> YamlElixir.read_from_string!(),
        do: item
  end

  defp yaml_item_keys(dir) do
    for item <- read_yaml!(demo_path(), "modules/#{dir}/items.yaml"), do: item["key"]
  end
end
