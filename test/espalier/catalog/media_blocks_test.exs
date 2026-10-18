defmodule Espalier.Catalog.MediaBlocksTest do
  @moduledoc """
  Task 0018, steps 9 and 23 (ASVS 1.2.2, 1.3.5 and 2.2.3): the validator
  checks the `figure` and `video` blocks of a lesson with every rule of
  step 9, each finding an error at the file and the line of the block, and
  the normalizer writes their `media` maps.
  """
  use ExUnit.Case, async: true

  import Espalier.PackFixtures

  alias Espalier.Catalog.Pack.{Loader, Validator}

  @lesson "modules/01-basics/lessons/02-practice.md"

  @media ~w(media/diagram.svg media/photo.png media/m1/clip.webm media/m1/clip-poster.jpg
            media/m1/clip-en.vtt media/m1/clip-de.vtt)

  defp run!(pack) do
    assert {:ok, loaded} = Loader.load(pack)
    Validator.run(loaded)
  end

  defp errors(pack),
    do: pack |> run!() |> Map.fetch!(:errors) |> Enum.map(&{&1.file, &1.line, &1.message})

  # Appends `blocks`, each a list of lines, to the practice lesson and
  # returns the line of the opening line of each block.
  defp add_blocks!(pack, blocks) do
    content = read!(pack, @lesson)
    first = (content |> String.split("\n") |> length()) + 1

    {lines, openings} =
      Enum.reduce(blocks, {[], []}, fn block, {lines, openings} ->
        {lines ++ block ++ [""], openings ++ [first + length(lines)]}
      end)

    write!(pack, @lesson, content <> "\n" <> Enum.join(lines, "\n"))
    openings
  end

  # A media path of 600 bytes whose components each fit.
  defp long_path do
    dirs = Enum.map_join(~w(a b c), "/", &String.duplicate(&1, 150))
    path = "media/#{dirs}/" <> String.duplicate("k", 137) <> ".png"
    600 = byte_size(path)
    path
  end

  defp media_files!(pack, paths \\ @media), do: Enum.each(paths, &write!(pack, &1, ""))

  # The pack with the media files and `blocks`, and the expected errors as
  # `{index of the block, message}`.
  defp assert_errors(blocks_and_messages) do
    pack = copy_pack!("minimal")
    media_files!(pack)
    lines = add_blocks!(pack, Enum.map(blocks_and_messages, &elem(&1, 0)))

    expected =
      for {{_block, messages}, line} <- Enum.zip(blocks_and_messages, lines),
          message <- List.wrap(messages),
          do: {@lesson, line, message}

    assert errors(pack) == Enum.sort(expected)
  end

  defp practice_blocks(payload) do
    [basics | _] = payload["modules"]
    basics["lessons"] |> Enum.find(&(&1["key"] == "02-practice")) |> Map.fetch!("blocks")
  end

  describe "valid figure and video blocks" do
    test "pass without errors and warnings, and the payload holds their media maps" do
      pack = copy_pack!("minimal")
      media_files!(pack)

      add_blocks!(pack, [
        [
          ~s(:::figure{src=media/diagram.svg alt="#{String.duplicate("a", 1_000)}" size=small provenance=invented}),
          "The caption names the [[term:assistant|assistant]].",
          ":::"
        ],
        [":::figure{src=media/photo.png decorative=true provenance=invented}", ":::"],
        [":::figure{src=media/photo.png alt=Chart size=medium provenance=invented}", ":::"],
        [
          ~s(:::video{src=media/m1/clip.webm title="#{String.duplicate("t", 255)}" ) <>
            "poster=media/m1/clip-poster.jpg " <>
            ~s(captions="media/m1/clip-en.vtt:en, media/m1/clip-de.vtt:de-DE" provenance=invented}),
          ":::"
        ],
        [
          ":::video{src=media/m1/clip.webm title=Clip provenance=invented}",
          "The transcript.",
          ":::"
        ],
        [
          ~s(:::video{src="https://cdn.example.org/clips/demo.MP4?v=2" title=External provenance=invented}),
          "The transcript.",
          ":::"
        ],
        [
          ~s(:::video{embed="https://player.example.org/embed/42" title=Embedded provenance=sourced cite="fictional-guide#Section 1"}),
          "The transcript of the embedded video.",
          ":::"
        ]
      ])

      assert %{errors: [], warnings: [], payload: payload} = run!(pack)

      [_example, _callout, figure, decorative, medium, video, transcript, external, embed] =
        practice_blocks(payload)

      assert figure["kind"] == "figure"
      assert figure["body"] == "The caption names the [[term:assistant|assistant]]."

      assert figure["media"] == %{
               "src" => "media/diagram.svg",
               "alt" => String.duplicate("a", 1_000),
               "decorative" => nil,
               "size" => "small"
             }

      assert decorative["body"] == ""

      assert decorative["media"] == %{
               "src" => "media/photo.png",
               "alt" => nil,
               "decorative" => true,
               "size" => "full"
             }

      assert medium["media"]["size"] == "medium"

      assert video["body"] == ""

      assert video["media"] == %{
               "src" => "media/m1/clip.webm",
               "embed" => nil,
               "title" => String.duplicate("t", 255),
               "poster" => "media/m1/clip-poster.jpg",
               "captions" => [
                 %{"src" => "media/m1/clip-en.vtt", "lang" => "en"},
                 %{"src" => "media/m1/clip-de.vtt", "lang" => "de-DE"}
               ]
             }

      assert transcript["body"] == "The transcript."
      assert transcript["media"]["captions"] == []
      assert transcript["media"]["poster"] == nil

      assert external["media"]["src"] == "https://cdn.example.org/clips/demo.MP4?v=2"

      assert embed["media"] == %{
               "src" => nil,
               "embed" => "https://player.example.org/embed/42",
               "title" => "Embedded",
               "poster" => nil,
               "captions" => []
             }

      assert embed["cite"] == ["fictional-guide#Section 1"]
    end

    test "the other kinds hold media nil" do
      pack = copy_pack!("minimal")
      assert %{payload: payload} = run!(pack)
      assert Enum.all?(practice_blocks(payload), &(&1["media"] == nil))
    end
  end

  describe "figure rules" do
    test "src, alt, decorative and size" do
      assert_errors([
        {[":::figure{alt=A provenance=invented}", ":::"],
         "a `figure` block needs the attribute `src`"},
        {[":::figure{src=photo.png alt=A provenance=invented}", ":::"],
         "`src` must be a path below `media/`: a media path starts with `media/`"},
        {[":::figure{src=media/m1/clip.webm alt=A provenance=invented}", ":::"],
         "`src` of a `figure` block must name an image or an SVG file, with one of the " <>
           "extensions `png`, `jpg`, `jpeg`, `gif`, `webp`, `svg`"},
        {[":::figure{src=media/photo.png provenance=invented}", ":::"],
         "a `figure` block needs the attribute `alt`, or `decorative=true` for an image " <>
           "that carries no information"},
        {[":::figure{src=media/photo.png alt=A decorative=true provenance=invented}", ":::"],
         "a figure with `decorative=true` takes no `alt`"},
        {[":::figure{src=media/photo.png decorative=false provenance=invented}", ":::"],
         "`decorative` takes the value `true` only"},
        {[~s(:::figure{src=media/photo.png alt="" provenance=invented}), ":::"],
         "`alt` must not be empty"},
        {[
           ~s(:::figure{src=media/photo.png alt="#{String.duplicate("a", 1_001)}" provenance=invented}),
           ":::"
         ], "`alt` must have at most 1,000 characters"},
        {[":::figure{src=media/photo.png alt=A size=huge provenance=invented}", ":::"],
         "`size` must be one of `small`, `medium`, `full`"},
        {[":::figure{src=#{long_path()} alt=A provenance=invented}", ":::"],
         "`src` must be a path below `media/`: a media path is valid UTF-8 of at most 527 " <>
           "bytes with components of at most 255 bytes, and holds no backslash, no U+0000 and " <>
           "no empty, `.` or `..` component"}
      ])
    end
  end

  describe "video rules" do
    test "src and embed" do
      assert_errors([
        {[":::video{title=T provenance=invented}", "Transcript.", ":::"],
         "a `video` block needs `src` for a video file or `embed` for a player"},
        {[
           ":::video{src=media/m1/clip.webm embed=https://player.example.org/1 title=T provenance=invented}",
           "Transcript.",
           ":::"
         ], "a `video` block takes exactly one of `src` and `embed`"},
        {[":::video{src=media/photo.png title=T provenance=invented}", "Transcript.", ":::"],
         "`src` of a `video` block must name a video file, with one of the extensions " <>
           "`mp4`, `m4v`, `mov`, `webm`, `mkv`"},
        {[":::video{src=clip.webm title=T provenance=invented}", "Transcript.", ":::"],
         "`src` must be a path below `media/` or an `https:` URL: a media path starts with `media/`"},
        {[
           ":::video{src=http://cdn.example.org/a.mp4 title=T provenance=invented}",
           "Transcript.",
           ":::"
         ],
         "an external `src` must be an absolute `https:` URL with a host and without user information"},
        {[
           ":::video{src=https://user:secret@cdn.example.org/a.mp4 title=T provenance=invented}",
           "Transcript.",
           ":::"
         ],
         "an external `src` must be an absolute `https:` URL with a host and without user information"},
        {[":::video{src=https:/a.mp4 title=T provenance=invented}", "Transcript.", ":::"],
         "an external `src` must be an absolute `https:` URL with a host and without user information"},
        {[
           ":::video{src=https://cdn.example.org/live/index.m3u8 title=T provenance=invented}",
           "Transcript.",
           ":::"
         ], "streams need an embed player: use embed"},
        {[
           ":::video{src=https://cdn.example.org/live/manifest.mpd title=T provenance=invented}",
           "Transcript.",
           ":::"
         ], "streams need an embed player: use embed"},
        {[
           ":::video{src=https://cdn.example.org/clip.mov title=T provenance=invented}",
           "Transcript.",
           ":::"
         ], "an external `src` must name a file whose path ends in `.webm` or `.mp4`"},
        {[
           ":::video{src=https://cdn.example.org/#{String.duplicate("x", 1_973)}.mp4 title=T provenance=invented}",
           "Transcript.",
           ":::"
         ], "an external `src` must have at most 2,000 characters"},
        {[
           ":::video{embed=http://player.example.org/1 title=T provenance=invented}",
           "Transcript.",
           ":::"
         ], "`embed` must be an absolute `https:` URL with a host and without user information"},
        {[
           ":::video{embed=https://me@player.example.org/1 title=T provenance=invented}",
           "Transcript.",
           ":::"
         ], "`embed` must be an absolute `https:` URL with a host and without user information"},
        {[
           ":::video{embed=https://player.example.org/#{String.duplicate("x", 1_976)} title=T provenance=invented}",
           "Transcript.",
           ":::"
         ], "`embed` must have at most 2,000 characters"}
      ])
    end

    test "an external src of exactly 2,000 characters passes" do
      src = "https://cdn.example.org/" <> String.duplicate("x", 1_972) <> ".mp4"
      assert String.length(src) == 2_000

      assert_errors([
        {[":::video{src=#{src} title=T provenance=invented}", "Transcript.", ":::"], []}
      ])
    end

    test "title and poster" do
      assert_errors([
        {[":::video{src=media/m1/clip.webm provenance=invented}", "Transcript.", ":::"],
         "a `video` block needs the attribute `title`"},
        {[
           ~s(:::video{src=media/m1/clip.webm title="#{String.duplicate("t", 256)}" provenance=invented}),
           "Transcript.",
           ":::"
         ], "`title` must have at most 255 characters"},
        {[
           ":::video{embed=https://player.example.org/1 title=T poster=media/photo.png provenance=invented}",
           "Transcript.",
           ":::"
         ], "a poster needs a video file: use src"},
        {[
           ":::video{src=media/m1/clip.webm title=T poster=media/diagram.svg provenance=invented}",
           "Transcript.",
           ":::"
         ],
         "`poster` must be a path below `media/` of an image, with one of the extensions " <>
           "`png`, `jpg`, `jpeg`, `gif`, `webp`"}
      ])
    end

    test "captions" do
      nine = Enum.map_join(1..9, ",", &"media/c-#{&1}.vtt:a#{<<?a + &1>>}")

      assert_errors([
        {[
           ":::video{embed=https://player.example.org/1 title=T captions=media/m1/clip-en.vtt:en provenance=invented}",
           "Transcript.",
           ":::"
         ], "captions need a video file: use src"},
        {[
           ~s(:::video{src=media/m1/clip.webm title=T captions="#{nine}" provenance=invented}),
           ":::"
         ], "`captions` holds at most 8 entries"},
        {[
           ":::video{src=media/m1/clip.webm title=T captions=media/m1/clip-en.vtt provenance=invented}",
           ":::"
         ],
         "each entry of `captions` has the form `<path>:<language>`, such as `media/intro-en.vtt:en`"},
        {[
           ":::video{src=media/m1/clip.webm title=T captions=media/clip-en.srt:en provenance=invented}",
           ":::"
         ],
         "the captions file `media/clip-en.srt` must be a path below `media/` with the extension `vtt`"},
        {[
           ":::video{src=media/m1/clip.webm title=T captions=media/m1/clip-en.vtt:EN provenance=invented}",
           ":::"
         ], "the captions language `EN` must be a BCP 47 language tag such as `en` or `pt-BR`"},
        {[
           ":::video{src=media/m1/clip.webm title=T captions=media/m1/clip-en.vtt:en,media/m1/clip-de.vtt:en provenance=invented}",
           ":::"
         ], "the captions language `en` appears more than once"},
        {[
           ~s(:::video{src=media/m1/clip.webm title=T captions="media/m1/a.vtt:pt-BR, media/m1/b.vtt:pt-br" provenance=invented}),
           ":::"
         ], "the captions language `pt-br` appears more than once"}
      ])
    end

    test "eight captions with distinct languages pass" do
      eight = Enum.map_join(1..8, ",", &"media/c-#{&1}.vtt:a#{<<?a + &1>>}")
      pack = copy_pack!("minimal")
      media_files!(pack, ["media/m1/clip.webm" | Enum.map(1..8, &"media/c-#{&1}.vtt")])

      add_blocks!(pack, [
        [
          ~s(:::video{src=media/m1/clip.webm title=T captions="#{eight}" provenance=invented}),
          ":::"
        ]
      ])

      assert %{errors: [], payload: payload} = run!(pack)
      video = payload |> practice_blocks() |> List.last()
      assert length(video["media"]["captions"]) == 8
    end

    test "a video file needs captions or a transcript, and an embed a transcript" do
      assert_errors([
        {[":::video{src=media/m1/clip.webm title=T provenance=invented}", ":::"],
         "a video file needs `captions` or a transcript in the body"},
        {[
           ":::video{src=https://cdn.example.org/a.webm title=T provenance=invented}",
           "",
           ":::"
         ], "a video file needs `captions` or a transcript in the body"},
        {[":::video{embed=https://player.example.org/1 title=T provenance=invented}", ":::"],
         "an embedded video needs a transcript in the body"}
      ])
    end
  end

  describe "media references" do
    test "every media path of a block names a file of the pack" do
      pack = copy_pack!("minimal")
      media_files!(pack, ["media/photo.png", "media/m1/clip.webm"])

      [figure, video, file_poster, external] =
        add_blocks!(pack, [
          [":::figure{src=media/missing.png alt=A provenance=invented}", ":::"],
          [
            ":::video{src=media/m1/gone.webm title=T captions=media/m1/en.vtt:en provenance=invented}",
            ":::"
          ],
          [
            ":::video{src=media/m1/clip.webm title=T poster=media/m1/poster.png provenance=invented}",
            "Transcript.",
            ":::"
          ],
          [
            ":::video{src=https://cdn.example.org/a.mp4 title=T poster=media/photo.png provenance=invented}",
            "Transcript.",
            ":::"
          ]
        ])

      assert errors(pack) == [
               {@lesson, figure, "the pack holds no media file `media/missing.png`"},
               {@lesson, video, "the pack holds no media file `media/m1/en.vtt`"},
               {@lesson, video, "the pack holds no media file `media/m1/gone.webm`"},
               {@lesson, file_poster, "the pack holds no media file `media/m1/poster.png`"}
             ]

      refute external in Enum.map(errors(pack), &elem(&1, 1))
    end

    test "a file of the right kind in another directory does not count" do
      pack = copy_pack!("minimal")
      media_files!(pack, ["media/m1/photo.png"])

      [line] =
        add_blocks!(pack, [[":::figure{src=media/photo.png alt=A provenance=invented}", ":::"]])

      assert errors(pack) == [{@lesson, line, "the pack holds no media file `media/photo.png`"}]
    end
  end

  describe "the Markdown image syntax" do
    test "is an error in every block body, a figure caption included" do
      assert_errors([
        {[":::text{provenance=invented}", "See ![the chart](media/photo.png) here.", ":::"],
         "use a figure block for images"},
        {[":::callout{provenance=invented}", "![](https://cdn.example.org/a.png)", ":::"],
         "use a figure block for images"},
        {[
           ":::figure{src=media/photo.png alt=A provenance=invented}",
           "A caption with ![x](y).",
           ":::"
         ], "use a figure block for images"},
        {[
           ":::video{src=media/m1/clip.webm title=T provenance=invented}",
           "![poster](media/photo.png)",
           ":::"
         ], "use a figure block for images"},
        {[
           ":::text{provenance=invented}",
           "A [link](https://example.org) and a ! [space].",
           ":::"
         ], []}
      ])
    end
  end

  describe "the body" do
    test "a caption and a transcript resolve their glossary references" do
      assert_errors([
        {[
           ":::figure{src=media/photo.png alt=A provenance=invented}",
           "A [[term:no-such-term]].",
           ":::"
         ], "unknown glossary term `no-such-term` in `[[term:no-such-term]]`"}
      ])
    end

    test "an empty body stays an error for the other kinds" do
      assert_errors([
        {[":::text{provenance=invented}", "", ":::"], "`body` must not be empty"},
        {[":::figure{src=media/photo.png alt=A provenance=invented}", "", ":::"], []}
      ])
    end
  end

  describe "error kinds" do
    test "every media finding is an error in both alignment modes" do
      for mode <- [:strict, :warn] do
        pack = copy_pack!("minimal")

        if mode == :warn,
          do: replace!(pack, "pack.yaml", "version: 0.1.0", "version: 0.1.0\nalignment: warn")

        [line] =
          add_blocks!(pack, [[":::figure{src=media/a.png alt=A provenance=invented}", ":::"]])

        assert %{
                 errors: [%{file: @lesson, line: ^line, message: message}],
                 warnings: []
               } = run!(pack)

        assert message == "the pack holds no media file `media/a.png`"
      end
    end
  end
end
