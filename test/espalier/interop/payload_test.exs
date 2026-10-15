defmodule Espalier.Interop.PayloadTest do
  use Espalier.DataCase, async: true

  alias Espalier.Catalog
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.{PackImport, Qualification}
  alias Espalier.Interop.Payload
  alias Espalier.{LearningFixtures, PackFixtures}

  defp import_and_publish!(path) do
    {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(path, nil)
    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    {pack_import.payload, Catalog.get_program_by_slug(pack_import.pack_key)}
  end

  # A copy of the demo pack whose qualifications.yaml lists `workshop`
  # before `basics`, against the code order.
  defp reversed_pack! do
    pack = PackFixtures.copy_pack!(PackFixtures.demo_path())
    PackFixtures.update_yaml!(pack, "qualifications.yaml", &Enum.reverse/1)
    pack
  end

  # A copy of the demo pack that keeps `basics` before `workshop` in
  # qualifications.yaml and sets `position` on every entry against that
  # order.
  defp positioned_pack! do
    pack = PackFixtures.copy_pack!(PackFixtures.demo_path())

    PackFixtures.update_yaml!(pack, "qualifications.yaml", fn qualifications ->
      count = length(qualifications)

      qualifications
      |> Enum.with_index()
      |> Enum.map(fn {qualification, index} ->
        Map.put(qualification, "position", count - index)
      end)
    end)

    pack
  end

  defp codes(qualifications), do: Enum.map(qualifications, & &1["code"])

  # Code and position of every qualification row of `program`, archived
  # rows included, by position.
  defp stored_positions(program) do
    Repo.all(
      from q in Qualification,
        where: q.program_id == ^program.id,
        order_by: q.position,
        select: {q.code, q.position}
    )
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

    test "lists the qualifications in the order of the file, against the code order" do
      {payload, program} = import_and_publish!(reversed_pack!())
      built = Payload.build(program)

      assert built == payload
      assert codes(built["qualifications"]) == ["workshop", "basics"]
      assert stored_positions(program) == [{"workshop", 1}, {"basics", 2}]
    end

    test "lists the qualifications by position, against the order of the file" do
      pack = positioned_pack!()

      assert [%{"code" => "basics", "position" => 2}, %{"code" => "workshop", "position" => 1}] =
               PackFixtures.read_yaml!(pack, "qualifications.yaml")

      {payload, program} = import_and_publish!(pack)
      built = Payload.build(program)

      assert built == payload
      assert codes(built["qualifications"]) == ["workshop", "basics"]
      refute Enum.any?(built["qualifications"], &Map.has_key?(&1, "position"))
      assert stored_positions(program) == [{"workshop", 1}, {"basics", 2}]
    end

    test "lists the qualifications in the order of the import published last" do
      {_payload, program} = import_and_publish!(PackFixtures.demo_path())
      assert codes(Payload.build(program)["qualifications"]) == ["basics", "workshop"]

      {payload, republished} = import_and_publish!(reversed_pack!())
      assert republished.id == program.id

      assert Payload.build(republished) == payload
      assert codes(payload["qualifications"]) == ["workshop", "basics"]
      assert stored_positions(republished) == [{"workshop", 1}, {"basics", 2}]
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
