defmodule Espalier.Interop.PayloadTest do
  use Espalier.DataCase, async: true

  alias Espalier.Catalog
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.{PackImport, Qualification}
  alias Espalier.Interop.Payload
  alias Espalier.{LearningFixtures, MediaFixtures, PackFixtures}
  alias Espalier.Media.Asset

  defp import_and_publish!(path) do
    {:ok, %PackImport{status: :validated} = pack_import} =
      Importer.import(path, nil, media: MediaFixtures.media_for(path))

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
      built = Payload.build(program)

      assert built == payload

      # The media list comes from program_media, and every block carries
      # its media attributes (task 0018, step 11).
      media = MediaFixtures.media_for(PackFixtures.demo_path())

      assert built["media"] == [
               %{
                 "path" => "media/assistant-demo-en.vtt",
                 "asset_id" => media["media/assistant-demo-en.vtt"],
                 "kind" => "captions"
               },
               %{
                 "path" => "media/assistant-demo.webm",
                 "asset_id" => media["media/assistant-demo.webm"],
                 "kind" => "video"
               },
               %{
                 "path" => "media/release-checks.svg",
                 "asset_id" => media["media/release-checks.svg"],
                 "kind" => "svg"
               }
             ]

      blocks =
        for module <- built["modules"], lesson <- module["lessons"], b <- lesson["blocks"], do: b

      assert Enum.all?(blocks, &Map.has_key?(&1, "media"))

      assert %{"src" => "media/release-checks.svg", "decorative" => nil, "size" => "full"} =
               Enum.find(blocks, &(&1["kind"] == "figure"))["media"]

      assert Enum.all?(blocks, &(&1["kind"] in ["figure", "video"] or &1["media"] == nil))
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

  describe "module/3" do
    setup do
      {payload, _program} = import_and_publish!(PackFixtures.demo_path())
      %{payload: payload, assets: assets(payload)}
    end

    test "cuts module 1 with its objectives, glossary, sources, formats and media", %{
      payload: payload,
      assets: assets
    } do
      content = Payload.module(payload, 1, assets)

      assert Map.keys(content) |> Enum.sort() ==
               ~w(formats glossary media module program sources)

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

    test "lists the media of module 1 by path with the facts of their delivery files", %{
      payload: payload,
      assets: assets
    } do
      content = Payload.module(payload, 1, assets)
      video = asset_at(payload, assets, "media/assistant-demo.webm")
      captions = asset_at(payload, assets, "media/assistant-demo-en.vtt")

      assert content["media"] == %{
               "media/assistant-demo.webm" => %{
                 "url" => "media/#{video.sha256}.webm",
                 "kind" => "video",
                 "mime" => "video/webm",
                 "width" => 640,
                 "height" => 360,
                 "duration_ms" => 8_008,
                 "has_audio" => true,
                 "has_alpha" => false,
                 "animated" => false,
                 "poster_url" => nil
               },
               "media/assistant-demo-en.vtt" => %{
                 "url" => "media/#{captions.sha256}.vtt",
                 "kind" => "captions",
                 "mime" => "text/vtt",
                 "width" => nil,
                 "height" => nil,
                 "duration_ms" => 8_000,
                 "has_audio" => false,
                 "has_alpha" => false,
                 "animated" => false,
                 "poster_url" => nil
               }
             }

      # The block keeps its media/ paths; the object resolves them.
      [video_block] =
        for lesson <- content["module"]["lessons"],
            %{"kind" => "video"} = block <- lesson["blocks"],
            do: block

      assert video_block["media"]["src"] == "media/assistant-demo.webm"

      assert video_block["media"]["captions"] == [
               %{"src" => "media/assistant-demo-en.vtt", "lang" => "en"}
             ]
    end

    test "cuts module 2 with its areas elsewhere, no format and its figure", %{
      payload: payload,
      assets: assets
    } do
      content = Payload.module(payload, 2, assets)

      assert length(content["module"]["objectives"]) == 3

      assert content["module"]["areas_elsewhere"] |> Map.keys() |> Enum.sort() == [
               "self",
               "social"
             ]

      assert content["formats"] == []

      svg = asset_at(payload, assets, "media/release-checks.svg")

      assert %{
               "media/release-checks.svg" => %{
                 "url" => url,
                 "kind" => "svg",
                 "mime" => "image/svg+xml",
                 "width" => 720,
                 "height" => 200,
                 "poster_url" => nil
               }
             } = content["media"]

      assert url == "media/#{svg.sha256}.svg"
      assert map_size(content["media"]) == 1
    end

    test "leaves out a path whose asset is not among the assets or not ready", %{
      payload: payload,
      assets: assets
    } do
      assert Payload.module(payload, 1, %{})["media"] == %{}

      video = asset_at(payload, assets, "media/assistant-demo.webm")
      queued = Map.put(assets, video.id, %{video | status: :queued})

      assert Map.keys(Payload.module(payload, 1, queued)["media"]) == [
               "media/assistant-demo-en.vtt"
             ]
    end

    test "gives a payload without the key media an empty media object", %{
      payload: payload,
      assets: assets
    } do
      content = Payload.module(Map.delete(payload, "media"), 1, assets)

      assert content["media"] == %{}
      assert content["module"] == Payload.module(payload, 1, assets)["module"]
    end

    test "raises for a module the payload lacks", %{payload: payload, assets: assets} do
      assert_raise ArgumentError, fn -> Payload.module(payload, 99, assets) end
    end
  end

  describe "media_paths/1 and media_asset_ids/2" do
    test "name the media/ paths of a module and their assets" do
      {payload, _program} = import_and_publish!(PackFixtures.demo_path())
      [module_1, module_2] = Enum.sort_by(payload["modules"], & &1["number"])
      by_path = Map.new(payload["media"], &{&1["path"], &1["asset_id"]})

      assert Enum.sort(Payload.media_paths(module_1)) ==
               ["media/assistant-demo-en.vtt", "media/assistant-demo.webm"]

      assert Payload.media_paths(module_2) == ["media/release-checks.svg"]

      assert Enum.sort(Payload.media_asset_ids(payload, module_1)) ==
               Enum.sort([
                 by_path["media/assistant-demo.webm"],
                 by_path["media/assistant-demo-en.vtt"]
               ])

      assert Payload.media_asset_ids(Map.delete(payload, "media"), module_1) == []
    end
  end

  # The asset rows of the media of `payload`, keyed by id.
  defp assets(payload) do
    ids = Enum.map(payload["media"], & &1["asset_id"])
    Map.new(Repo.all(from a in Asset, where: a.id in ^ids), &{&1.id, &1})
  end

  defp asset_at(payload, assets, path) do
    %{"asset_id" => id} = Enum.find(payload["media"], &(&1["path"] == path))
    Map.fetch!(assets, id)
  end

  defp rule_and_item_sources(module) do
    for entry <- module["rules"] ++ module["items"],
        cite <- entry["cite"],
        do: cite |> String.split("#") |> hd()
  end
end
