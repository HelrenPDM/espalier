defmodule Espalier.Interop.PayloadTest do
  use Espalier.DataCase, async: true

  alias Espalier.Catalog
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.PackImport
  alias Espalier.Interop.Payload
  alias Espalier.{LearningFixtures, PackFixtures}

  defp import_and_publish!(path) do
    {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(path, nil)
    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    {pack_import.payload, Catalog.get_program_by_slug(pack_import.pack_key)}
  end

  describe "build/1" do
    test "equals the payload of the published import of the demo pack" do
      {payload, program} = import_and_publish!(PackFixtures.demo_path())

      assert Payload.build(program) == payload
    end

    test "skips archived rows and the join rows that point to them" do
      {_payload, _program} = import_and_publish!(PackFixtures.demo_path())
      pack = PackFixtures.copy_pack!(PackFixtures.demo_path())

      # Drop the poll of module 1 and the format workshop, which names two
      # objectives of module 1.
      PackFixtures.update_yaml!(pack, "modules/01-basics/items.yaml", fn items ->
        Enum.reject(items, &(&1["kind"] == "poll"))
      end)

      PackFixtures.update_yaml!(pack, "formats.yaml", fn formats ->
        Enum.reject(formats, &(&1["key"] == "workshop"))
      end)

      PackFixtures.update_yaml!(pack, "qualifications.yaml", fn qualifications ->
        Enum.map(qualifications, fn qualification ->
          Map.update!(qualification, "requirements", fn requirements ->
            Enum.reject(requirements, &(&1["target"] == "workshop"))
          end)
        end)
      end)

      PackFixtures.update_yaml!(pack, "modules/02-checking/module.yaml", fn module ->
        Map.delete(module, "areas_elsewhere")
      end)

      PackFixtures.update_yaml!(pack, "pack.yaml", &Map.put(&1, "alignment", "warn"))

      {payload, program} = import_and_publish!(pack)
      built = Payload.build(program)

      assert built == payload
      refute Enum.any?(built["formats"], &(&1["key"] == "workshop"))
      assert built["alignment"] == "warn"

      module_1 = Enum.find(built["modules"], &(&1["number"] == 1))
      refute Enum.any?(module_1["items"], &(&1["kind"] == "poll"))
    end
  end

  describe "module/2" do
    setup do
      {payload, _program} = import_and_publish!(PackFixtures.demo_path())
      %{payload: payload}
    end

    test "cuts module 1 with its objectives, glossary, sources and formats", %{payload: payload} do
      content = Payload.module(payload, 1)

      assert Map.keys(content) |> Enum.sort() ==
               ~w(formats glossary module program sources)

      assert content["program"] == %{
               "slug" => LearningFixtures.demo_slug(),
               "title" => payload["title"],
               "locale" => "en"
             }

      assert Enum.map(content["module"]["objectives"], & &1["key"]) == [
               "m1-subject-next-word",
               "m1-subject-varying-answers",
               "m1-method-check-claims",
               "m1-self-own-responsibility",
               "m1-social-team-transparency"
             ]

      assert [%{"key" => "workshop", "objectives" => objectives}] = content["formats"]

      assert objectives == ["m1-self-own-responsibility", "m1-social-team-transparency"]

      slugs = Enum.map(content["glossary"], & &1["slug"])
      assert "hallucination" in slugs
      assert slugs == Enum.sort(slugs)

      blocks =
        for lesson <- content["module"]["lessons"],
            block <- lesson["blocks"],
            do: block["body"]

      for slug <- slugs do
        assert Enum.any?(blocks, &String.contains?(&1, "[[term:#{slug}"))
      end

      cited =
        for lesson <- content["module"]["lessons"],
            block <- lesson["blocks"],
            cite <- block["cite"],
            do: cite |> String.split("#") |> hd()

      assert Enum.map(content["sources"], & &1["key"]) |> Enum.sort() ==
               Enum.sort(Enum.uniq(cited ++ rule_and_item_sources(content["module"])))
    end

    test "cuts module 2 with its areas elsewhere and no format", %{payload: payload} do
      content = Payload.module(payload, 2)

      assert length(content["module"]["objectives"]) == 3

      assert content["module"]["areas_elsewhere"] |> Map.keys() |> Enum.sort() == [
               "self",
               "social"
             ]

      assert content["formats"] == []
    end

    test "raises for a module the payload lacks", %{payload: payload} do
      assert_raise ArgumentError, fn -> Payload.module(payload, 99) end
    end
  end

  defp rule_and_item_sources(module) do
    for entry <- module["rules"] ++ module["items"],
        cite <- entry["cite"],
        do: cite |> String.split("#") |> hd()
  end
end
