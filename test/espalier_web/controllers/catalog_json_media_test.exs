defmodule EspalierWeb.CatalogJSONMediaTest do
  @moduledoc """
  The media of `figure` and `video` blocks in the learner API (task 0018,
  step 12): `GET /api/modules/:id` of the published demo resolves the
  figure of module 2 and the video of module 1 into URLs below `/media/`,
  every other block kind carries `media: null`, and an external file and an
  embed are `available` only while their hosts stand in the current
  allowlists. `CatalogJSON.block_media/2` renders the poster of a video, of
  an animated image and of a `poster` attribute, which gives the still first
  frame of an animated image.
  """
  # The tests change the allowlists in the application environment :media.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.LearningFixtures, only: [demo_slug: 0, module!: 2, publish_demo!: 0]
  import Espalier.PackFixtures, only: [copy_pack!: 1, demo_path: 0, replace!: 4]

  alias Espalier.{Catalog, Media, MediaFixtures, Repo}
  alias Espalier.Catalog.Block
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.PackImport
  alias Espalier.Media.Asset
  alias EspalierWeb.CatalogJSON

  @media_keys ~w(alt available captions decorative embed image poster size title video)

  @svg "media/release-checks.svg"
  @webm "media/assistant-demo.webm"
  @vtt "media/assistant-demo-en.vtt"

  @lesson "modules/01-basics/lessons/01-first-lesson.md"

  # Three external videos, an embed and a decorative figure after the video
  # of the demo lesson.
  @extra_blocks """

  :::video{src="https://cdn.example.org/videos/clip.webm" title="An external clip" provenance=invented}
  The clip shows the test pattern from a file host.
  :::

  :::video{src="https://cdn.example.org:8443/videos/clip.mp4" title="An external MP4" provenance=invented}
  The clip shows the test pattern from a second port.
  :::

  :::video{embed="https://Player.Example.net/embed/4711" title="An embedded player" provenance=invented}
  The player shows the test pattern on a streaming service.
  :::

  :::figure{src=media/release-checks.svg decorative=true size=small provenance=invented}
  :::
  """

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  describe "the published demo" do
    setup do
      program = publish_demo!()
      mapping = MediaFixtures.media_for(demo_path())

      %{
        program: program,
        svg: Repo.get!(Asset, mapping[@svg]),
        webm: Repo.get!(Asset, mapping[@webm]),
        vtt: Repo.get!(Asset, mapping[@vtt])
      }
    end

    test "the figure of module 2 resolves to its SVG", %{conn: conn, program: program, svg: svg} do
      blocks = blocks(conn, module!(program, 2))
      assert [figure] = Enum.filter(blocks, &(&1["kind"] == "figure"))

      assert figure["body"] ==
               "The release checks run from the generated draft to the initials of the person who releases it."

      assert figure["media"] |> Map.keys() |> Enum.sort() == @media_keys

      assert figure["media"] == %{
               "image" => %{
                 "url" => "/media/#{svg.sha256}.svg",
                 "mime" => "image/svg+xml",
                 "width" => 720,
                 "height" => 200,
                 "has_alpha" => false,
                 "animated" => false
               },
               "video" => nil,
               "poster" => nil,
               "embed" => nil,
               "captions" => [],
               "alt" =>
                 "A diagram of four steps from left to right: generated draft, mark the " <>
                   "statements, check each source, initials and release.",
               "decorative" => false,
               "size" => "full",
               "title" => nil,
               "available" => true
             }
    end

    test "the video of module 1 resolves to its WebM and its captions", %{
      conn: conn,
      program: program,
      webm: webm,
      vtt: vtt
    } do
      blocks = blocks(conn, module!(program, 1))
      assert [video] = Enum.filter(blocks, &(&1["kind"] == "video"))

      assert video["body"] =~ "The video shows a moving test pattern"
      assert video["media"] |> Map.keys() |> Enum.sort() == @media_keys

      assert video["media"] == %{
               "image" => nil,
               "video" => %{
                 "url" => "/media/#{webm.sha256}.webm",
                 "mime" => "video/webm",
                 "width" => 640,
                 "height" => 360,
                 "duration_ms" => 8_008,
                 "has_audio" => true,
                 "external" => false
               },
               "poster" => nil,
               "embed" => nil,
               "captions" => [%{"url" => "/media/#{vtt.sha256}.vtt", "lang" => "en"}],
               "alt" => nil,
               "decorative" => false,
               "size" => nil,
               "title" => "A test pattern with a tone",
               "available" => true
             }
    end

    test "a video with a stored poster carries it with the size of the video", %{
      conn: conn,
      program: program,
      webm: webm
    } do
      poster = MediaFixtures.random_sha256()

      webm
      |> Ecto.Changeset.change(poster_sha256: poster, poster_bytes: 1000)
      |> Repo.update!()

      [video] = conn |> blocks(module!(program, 1)) |> Enum.filter(&(&1["kind"] == "video"))

      assert video["media"]["poster"] == %{
               "url" => "/media/#{poster}.webp",
               "width" => 640,
               "height" => 360
             }
    end

    test "every other block kind carries media null", %{conn: conn, program: program} do
      blocks = Enum.flat_map([1, 2], &blocks(conn, module!(program, &1)))
      others = Enum.reject(blocks, &(&1["kind"] in ["figure", "video"]))

      assert others != []
      assert others |> Enum.map(& &1["kind"]) |> Enum.uniq() |> length() > 1

      for block <- others do
        assert Map.has_key?(block, "media")
        assert block["media"] == nil, block["kind"]
      end
    end

    test "a media file that is not ready leaves the block unavailable", %{
      conn: conn,
      program: program,
      svg: svg,
      vtt: vtt
    } do
      Repo.update_all(
        from(a in Asset, where: a.id in ^[svg.id, vtt.id]),
        set: [status: :failed, failure: :conversion_failed]
      )

      [figure] = conn |> blocks(module!(program, 2)) |> Enum.filter(&(&1["kind"] == "figure"))
      assert figure["media"]["image"] == nil
      assert figure["media"]["available"] == false

      [video] = conn |> blocks(module!(program, 1)) |> Enum.filter(&(&1["kind"] == "video"))
      assert video["media"]["available"] == true
      assert video["media"]["captions"] == []
    end
  end

  describe "external files and embeds" do
    setup do
      pack = copy_pack!(demo_path())

      replace!(
        pack,
        @lesson,
        "It holds no speech.\n:::\n",
        "It holds no speech.\n:::\n" <> @extra_blocks
      )

      program = publish_with_hosts!(pack)
      %{program: program}
    end

    test "available follows the current allowlists", %{conn: conn, program: program} do
      module = module!(program, 1)

      # The test configuration holds empty lists.
      assert Media.external_hosts() == []
      assert Media.embed_hosts() == []

      %{webm: webm, mp4: mp4, embed: embed} = external_blocks(conn, module)

      assert webm == %{
               "image" => nil,
               "video" => %{
                 "url" => "https://cdn.example.org/videos/clip.webm",
                 "mime" => "video/webm",
                 "width" => nil,
                 "height" => nil,
                 "duration_ms" => nil,
                 "has_audio" => nil,
                 "external" => true
               },
               "poster" => nil,
               "embed" => nil,
               "captions" => [],
               "alt" => nil,
               "decorative" => false,
               "size" => nil,
               "title" => "An external clip",
               "available" => false
             }

      assert mp4["video"]["mime"] == "video/mp4"
      assert mp4["video"]["url"] == "https://cdn.example.org:8443/videos/clip.mp4"
      assert mp4["available"] == false

      assert embed == %{
               "image" => nil,
               "video" => nil,
               "poster" => nil,
               "embed" => %{
                 "url" => "https://Player.Example.net/embed/4711",
                 "host" => "player.example.net"
               },
               "captions" => [],
               "alt" => nil,
               "decorative" => false,
               "size" => nil,
               "title" => "An embedded player",
               "available" => false
             }

      put_media(external_hosts: [{"cdn.example.org", nil}])
      blocks = external_blocks(conn, module)
      assert blocks.webm["available"] == true
      assert blocks.mp4["available"] == false
      assert blocks.embed["available"] == false

      put_media(
        external_hosts: [{"cdn.example.org", 8443}],
        embed_hosts: [{"player.example.net", nil}]
      )

      blocks = external_blocks(conn, module)
      assert blocks.webm["available"] == false
      assert blocks.mp4["available"] == true
      assert blocks.embed["available"] == true

      put_media(embed_hosts: [{"player.example.net", 8443}])
      assert external_blocks(conn, module).embed["available"] == false

      put_media(external_hosts: [], embed_hosts: [])
      blocks = external_blocks(conn, module)

      assert Enum.map([blocks.webm, blocks.mp4, blocks.embed], & &1["available"]) == [
               false,
               false,
               false
             ]
    end

    test "a decorative figure carries no alternative text and its size", %{
      conn: conn,
      program: program
    } do
      figures =
        conn |> blocks(module!(program, 1)) |> Enum.filter(&(&1["kind"] == "figure"))

      assert [figure] = figures
      assert figure["body"] == ""
      assert figure["media"]["decorative"] == true
      assert figure["media"]["alt"] == nil
      assert figure["media"]["size"] == "small"
      assert figure["media"]["available"] == true
      assert figure["media"]["image"]["mime"] == "image/svg+xml"
    end
  end

  describe "CatalogJSON.block_media/2" do
    test "an animated figure carries the still poster of its asset" do
      animated = %Asset{
        status: :ready,
        kind: :image,
        sha256: MediaFixtures.random_sha256(),
        ext: "webp",
        width: 320,
        height: 180,
        animated: true,
        has_alpha: true,
        poster_sha256: MediaFixtures.random_sha256()
      }

      block = %Block{
        kind: :figure,
        media: %{"src" => "media/loop.gif", "alt" => "A loop", "decorative" => nil, "size" => nil}
      }

      media = CatalogJSON.block_media(block, %{"media/loop.gif" => animated})

      assert media.image == %{
               url: "/media/#{animated.sha256}.webp",
               mime: "image/webp",
               width: 320,
               height: 180,
               has_alpha: true,
               animated: true
             }

      assert media.size == "full"
      assert media.alt == "A loop"
      assert media.available == true
      assert %{width: 320, height: 180} = media.poster
    end

    test "the poster of an animated figure is its still first frame" do
      animated = %Asset{
        status: :ready,
        kind: :image,
        sha256: MediaFixtures.random_sha256(),
        ext: "webp",
        width: 320,
        height: 180,
        animated: true,
        poster_sha256: MediaFixtures.random_sha256()
      }

      block = %Block{kind: :figure, media: %{"src" => "media/loop.gif", "alt" => "A loop"}}
      media = CatalogJSON.block_media(block, %{"media/loop.gif" => animated})

      assert media.poster == %{
               url: "/media/#{animated.poster_sha256}.webp",
               width: 320,
               height: 180
             }
    end

    test "a still figure carries no poster" do
      image = %Asset{
        status: :ready,
        kind: :image,
        sha256: MediaFixtures.random_sha256(),
        ext: "webp",
        width: 10,
        height: 10,
        animated: false
      }

      block = %Block{kind: :figure, media: %{"src" => "media/photo.jpg", "alt" => "A photo"}}
      assert CatalogJSON.block_media(block, %{"media/photo.jpg" => image}).poster == nil
    end

    test "a poster attribute names an image asset that replaces the poster of the video" do
      video = %Asset{
        status: :ready,
        kind: :video,
        sha256: MediaFixtures.random_sha256(),
        ext: "webm",
        width: 1280,
        height: 720,
        duration_ms: 1000,
        has_audio: false,
        poster_sha256: MediaFixtures.random_sha256()
      }

      image = %Asset{
        status: :ready,
        kind: :image,
        sha256: MediaFixtures.random_sha256(),
        ext: "webp",
        width: 640,
        height: 360
      }

      block = %Block{
        kind: :video,
        media: %{
          "src" => "media/clip.mp4",
          "embed" => nil,
          "title" => "A clip",
          "poster" => "media/cover.png",
          "captions" => []
        }
      }

      media =
        CatalogJSON.block_media(block, %{"media/clip.mp4" => video, "media/cover.png" => image})

      assert media.poster == %{url: "/media/#{image.sha256}.webp", width: 640, height: 360}
      assert media.video.url == "/media/#{video.sha256}.webm"
      assert media.available == true

      # Without the attribute the video shows its own poster.
      media =
        CatalogJSON.block_media(%{block | media: Map.put(block.media, "poster", nil)}, %{
          "media/clip.mp4" => video
        })

      assert media.poster == %{
               url: "/media/#{video.poster_sha256}.webp",
               width: 1280,
               height: 720
             }
    end

    test "a poster attribute that names an animated image gives its still first frame" do
      # WCAG 2.2 2.2.2: the delivery file of the image loops, so the video
      # area shows the still poster of that image until the learner starts
      # the video.
      video = %Asset{
        status: :ready,
        kind: :video,
        sha256: MediaFixtures.random_sha256(),
        ext: "webm",
        width: 1280,
        height: 720,
        duration_ms: 1000,
        has_audio: false,
        poster_sha256: MediaFixtures.random_sha256()
      }

      teaser = %Asset{
        status: :ready,
        kind: :image,
        sha256: MediaFixtures.random_sha256(),
        ext: "webp",
        width: 480,
        height: 270,
        animated: true,
        poster_sha256: MediaFixtures.random_sha256()
      }

      block = %Block{
        kind: :video,
        media: %{
          "src" => "media/clip.mp4",
          "embed" => nil,
          "title" => "A clip",
          "poster" => "media/teaser.gif",
          "captions" => []
        }
      }

      media =
        CatalogJSON.block_media(block, %{"media/clip.mp4" => video, "media/teaser.gif" => teaser})

      assert media.poster == %{
               url: "/media/#{teaser.poster_sha256}.webp",
               width: 480,
               height: 270
             }

      # An animated image without a still poster never moves in its place:
      # the video shows its own poster.
      media =
        CatalogJSON.block_media(block, %{
          "media/clip.mp4" => video,
          "media/teaser.gif" => %{teaser | poster_sha256: nil}
        })

      assert media.poster == %{
               url: "/media/#{video.poster_sha256}.webp",
               width: 1280,
               height: 720
             }
    end

    test "a pack video file that is not ready is unavailable" do
      video = %Asset{status: :processing, kind: :video}

      block = %Block{
        kind: :video,
        media: %{"src" => "media/clip.mp4", "title" => "A clip", "captions" => []}
      }

      media = CatalogJSON.block_media(block, %{"media/clip.mp4" => video})
      assert media.video == nil
      assert media.available == false
    end

    test "other kinds carry nil" do
      for kind <- [:text, :explanation, :placeholder] do
        assert CatalogJSON.block_media(%Block{kind: kind, media: nil}, %{}) == nil
      end
    end
  end

  ## Helpers

  defp blocks(conn, module) do
    conn = json_request(conn, :get, "/api/modules/#{module.id}")
    conn |> json_response(200) |> Map.fetch!("lessons") |> Enum.flat_map(& &1["blocks"])
  end

  defp external_blocks(conn, module) do
    videos =
      conn |> blocks(module) |> Enum.filter(&(&1["kind"] == "video")) |> Enum.map(& &1["media"])

    %{
      webm: Enum.find(videos, &(&1["title"] == "An external clip")),
      mp4: Enum.find(videos, &(&1["title"] == "An external MP4")),
      embed: Enum.find(videos, &(&1["title"] == "An embedded player"))
    }
  end

  # Imports and publishes the pack copy with the hosts of its external
  # sources and embeds allowed for the import only.
  defp publish_with_hosts!(pack) do
    hosts = %{
      external: [{"cdn.example.org", nil}, {"cdn.example.org", 8443}],
      embed: [{"player.example.net", nil}]
    }

    {:ok, %PackImport{status: :validated} = pack_import} =
      Importer.import(pack, nil, media: MediaFixtures.media_for(pack), hosts: hosts)

    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    Catalog.get_program_by_slug(demo_slug())
  end

  defp put_media(changes) do
    previous = Application.fetch_env!(:espalier, :media)
    Application.put_env(:espalier, :media, Keyword.merge(previous, changes))
    on_exit(fn -> Application.put_env(:espalier, :media, previous) end)
  end
end
