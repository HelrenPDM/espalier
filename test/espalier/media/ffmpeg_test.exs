defmodule Espalier.Media.FfmpegTest do
  @moduledoc """
  Task 0018, steps 5 and 23 (ASVS 1.2.5 and 1.3.6): every argument list of
  `Espalier.Media.Ffmpeg` is a list of binaries with `-protocol_whitelist
  file`, a forced input format, `-max_pixels` with the limit of the kind and
  `-threads` before the input, `-threads` again before the output format,
  `-filter_threads`, `-max_alloc` and `-nostdin` in every ffmpeg call, and
  `-enable_drefs 0` for `mov` inputs. Built from paths of
  `Espalier.Media.Store`, no list holds a title, a file name or another
  string from a request: every element is a store path, a number, a filter
  of the configuration or a constant of the module.

  These tests read the default configuration; the tests that change it run
  in `Espalier.Media.FfmpegConfigTest` below, without `async`.
  """
  use ExUnit.Case, async: true

  alias Espalier.Media
  alias Espalier.Media.{Ffmpeg, Store}

  @max_alloc "536870912"
  @common ~w(-nostdin -hide_banner -loglevel error -max_alloc 536870912 -filter_threads 2)

  @show_entries "stream=index,codec_type,codec_name,width,height,pix_fmt,nb_read_packets," <>
                  "duration:stream_tags=alpha_mode:format=duration,nb_streams"

  # The constants that the builders may place in a list. Every other element
  # is a path of the store, a number or a filter of the configuration.
  @vocabulary MapSet.new(
                ~w(-nostdin -hide_banner -loglevel error -max_alloc -filter_threads -threads
                   -protocol_whitelist file -f -max_pixels -i -enable_drefs -frames:v -map_metadata
                   -vf -c:v libwebp -lossless -compression_level -quality -y webp webm libwebp_anim
                   -loop -map 0:v:0 0:a:0? -c copy -map_chapters -sn -dn libvpx-vp9 -b:v -crf
                   -deadline good -cpu-used -row-mt -g -pix_fmt yuv420p -c:a libopus -b:a 96k -ac
                   -progress pipe:1 -nostats -ss -v -count_packets -show_entries -of json -o
                   png_pipe apng jpeg_pipe gif webp_pipe mov matroska) ++ [@show_entries]
              )

  describe "every call" do
    test "every element is a binary" do
      for call <- calls(), element <- call.args do
        assert is_binary(element), "#{call.name}: #{inspect(element)}"
      end
    end

    test "-protocol_whitelist file appears once, before the input" do
      for call <- calls() do
        assert count_pair(call.args, "-protocol_whitelist", "file") == 1, call.name
        assert pair_index(call.args, "-protocol_whitelist", "file") < input_index(call), call.name
      end
    end

    test "the format of the detection is forced before the input" do
      for call <- calls() do
        index = pair_index(call.args, "-f", call.format)
        assert index, "#{call.name}: no -f #{call.format}"
        assert index < input_index(call), call.name
        assert count_before_input(call, "-f") == 1, call.name
      end
    end

    test "-max_pixels carries the limit of the kind before the input" do
      for call <- calls() do
        limit =
          case call.kind do
            :image -> Media.max_input_pixels()
            :video -> Media.max_video_pixels()
          end

        index = pair_index(call.args, "-max_pixels", Integer.to_string(limit))
        assert index, "#{call.name}: no -max_pixels #{limit}"
        assert index < input_index(call), call.name
      end
    end

    test "-threads before the input, and for ffmpeg again before the output format" do
      for call <- calls() do
        indexes = pair_indexes(call.args, "-threads", "2")
        input = input_index(call)

        case call.tool do
          :ffprobe ->
            assert [index] = indexes, call.name
            assert index < input

          :ffmpeg ->
            assert [before, output] = indexes, call.name
            assert before < input
            assert output > input

            assert Enum.slice(call.args, output..-1//1) == [
                     "-threads",
                     "2",
                     "-f",
                     call.output_format,
                     "-y",
                     call.output
                   ]
        end
      end
    end

    test "every ffmpeg call starts with the common options" do
      for call <- calls(), call.tool == :ffmpeg do
        assert Enum.take(call.args, length(@common)) == @common, call.name
        assert count_pair(call.args, "-filter_threads", "2") == 1, call.name
      end
    end

    test "-max_alloc in every call" do
      for call <- calls() do
        assert count_pair(call.args, "-max_alloc", @max_alloc) == 1, call.name
      end
    end

    test "-enable_drefs 0 only for mov inputs, before the input" do
      for call <- calls() do
        if call.format == "mov" do
          index = pair_index(call.args, "-enable_drefs", "0")
          assert index, call.name
          assert index < input_index(call), call.name
        else
          refute "-enable_drefs" in call.args, call.name
        end
      end
    end

    test "the input appears once, after -i for ffmpeg and last for ffprobe" do
      for call <- calls() do
        assert Enum.count(call.args, &(&1 == call.input)) == 1, call.name

        case call.tool do
          :ffmpeg -> assert pair_index(call.args, "-i", call.input), call.name
          :ffprobe -> assert List.last(call.args) == call.input, call.name
        end
      end
    end
  end

  describe "no request string (ASVS 1.2.5)" do
    test "store paths of an asset with a hostile title and file name reach no element" do
      asset = %{
        id: Ecto.UUID.generate(),
        title: "title; rm -rf / $(id)",
        source_name: "../../etc/passwd; `id`.png"
      }

      root = Store.root() <> "/"

      for call <- calls(asset.id), element <- call.args do
        refute element =~ "rm -rf", call.name
        refute element =~ "passwd", call.name
        refute element =~ "$(id)", call.name
        refute element =~ "`", call.name
        refute element =~ asset.title, call.name
        refute element =~ asset.source_name, call.name

        if String.starts_with?(element, "/") do
          assert String.starts_with?(element, root), "#{call.name}: #{element}"
          refute element =~ "..", "#{call.name}: #{element}"
        end
      end
    end

    test "every element is a store path, a number, a configured filter or a constant" do
      root = Store.root() <> "/"

      for call <- calls(), element <- call.args do
        assert String.starts_with?(element, root) or
                 Regex.match?(~r/\A-?\d+(\.\d+)?\z/, element) or
                 Regex.match?(
                   ~r/\A(transpose=\d,)?scale='min\(iw,\d+\)':'min\(ih,\d+\)':force_original_aspect_ratio=decrease\z/,
                   element
                 ) or
                 Regex.match?(~r/\Ascale=-2:'min\(ih,\d+\)'\z/, element) or
                 MapSet.member?(@vocabulary, element),
               "#{call.name}: #{inspect(element)}"
      end
    end

    test "the module exports only the builders that this test covers and check/0" do
      assert Enum.sort(Ffmpeg.__info__(:functions)) ==
               Enum.sort(
                 animated_image_args: 3,
                 check: 0,
                 image_poster_args: 3,
                 probe_args: 4,
                 remux_args: 2,
                 still_image_args: 3,
                 still_image_args: 4,
                 video_args: 3,
                 video_poster_args: 3
               )
    end
  end

  describe "the probe" do
    test "is the list of the spec" do
      input = Store.incoming_path(Ecto.UUID.generate())
      json = Path.join(Store.work_dir(Ecto.UUID.generate(), Ecto.UUID.generate()), "probe.json")

      assert Ffmpeg.probe_args(input, "matroska", 8_294_400, json) ==
               ~w(-v error -max_alloc 536870912 -threads 2 -protocol_whitelist file -f matroska
                  -max_pixels 8294400 -count_packets -show_entries) ++
                 [@show_entries, "-of", "json", "-o", json, input]
    end

    test "takes the pixel limit it is given" do
      input = Store.incoming_path(Ecto.UUID.generate())
      args = Ffmpeg.probe_args(input, "png_pipe", 1234, "/x/probe.json")
      assert pair_index(args, "-max_pixels", "1234")
    end
  end

  describe "images" do
    test "a lossless still image" do
      args = Ffmpeg.still_image_args(input(), "png_pipe", output("webp"), lossless: true)

      assert ["-frames:v", "1", "-map_metadata", "-1", "-vf", scale(2560)] ++
               ~w(-c:v libwebp -lossless 1 -compression_level 6) == after_input(args)
    end

    test "a lossy still image at quality 82, or the quality given" do
      args = Ffmpeg.still_image_args(input(), "jpeg_pipe", output("webp"))
      assert ~w(-c:v libwebp -quality 82) == Enum.slice(after_input(args), 6..-1//1)
      refute "-lossless" in args

      args = Ffmpeg.still_image_args(input(), "webp_pipe", output("webp"), quality: 90)
      assert pair_index(args, "-quality", "90")
    end

    test "filters precede the scale filter" do
      args =
        Ffmpeg.still_image_args(input(), "jpeg_pipe", output("webp"), filters: ["transpose=1"])

      assert pair_index(args, "-vf", "transpose=1," <> scale(2560))
    end

    test "an animated image converts with libwebp_anim and no frame limit" do
      args = Ffmpeg.animated_image_args(input(), "gif", output("webp"))

      assert ["-map_metadata", "-1", "-vf", scale(2560)] ++
               ~w(-c:v libwebp_anim -loop 0 -quality 80) == after_input(args)

      refute "-frames:v" in args
    end

    test "the poster of an animated image is its first frame at quality 80" do
      args = Ffmpeg.image_poster_args(input(), "apng", output("webp"))

      assert ["-frames:v", "1", "-map_metadata", "-1", "-vf", scale(2560)] ++
               ~w(-c:v libwebp -quality 80) == after_input(args)
    end
  end

  describe "videos" do
    test "the remux copies the streams of a Matroska input" do
      args = Ffmpeg.remux_args(input(), output("webm"))

      assert ~w(-map 0:v:0 -map 0:a:0? -c copy -map_metadata -1 -map_chapters -1) ==
               after_input(args)

      assert pair_index(args, "-f", "matroska") < pair_index(args, "-i", input())
      refute "-vf" in args
      refute "-c:v" in args
    end

    test "the conversion holds the options of the spec" do
      for format <- ["mov", "matroska"] do
        args = Ffmpeg.video_args(input(), format, output("webm"))

        assert ~w(-map 0:v:0 -map 0:a:0? -sn -dn -map_metadata -1 -map_chapters -1 -c:v libvpx-vp9
                  -b:v 0 -crf 32 -deadline good -cpu-used 4 -row-mt 1 -g 240 -pix_fmt yuv420p
                  -vf) ++
                 ["scale=-2:'min(ih,1080)'"] ++
                 ~w(-c:a libopus -b:a 96k -ac 2 -progress pipe:1 -nostats) == after_input(args)
      end
    end

    test "the poster seeks before the input, without a scale filter" do
      args = Ffmpeg.video_poster_args(input(), 1.0, output("webp"))

      assert pair_index(args, "-ss", "1.000") < pair_index(args, "-i", input())
      assert pair_index(args, "-f", "matroska")
      assert ~w(-frames:v 1 -map_metadata -1 -c:v libwebp -quality 80) == after_input(args)
      refute "-vf" in args

      assert pair_index(Ffmpeg.video_poster_args(input(), 0.25, output("webp")), "-ss", "0.250")
      assert pair_index(Ffmpeg.video_poster_args(input(), 1, output("webp")), "-ss", "1.000")
    end
  end

  ## Calls

  defp calls(id \\ Ecto.UUID.generate()) do
    input = Store.incoming_path(id)
    work = Store.work_dir(id, Ecto.UUID.generate())
    webp = Path.join(work, "out.webp")
    webm = Path.join(work, "out.webm")
    poster = Path.join(work, "poster.webp")
    json = Path.join(work, "probe.json")
    image_limit = Media.max_input_pixels()
    video_limit = Media.max_video_pixels()

    probes =
      for {format, kind, limit} <- [
            {"png_pipe", :image, image_limit},
            {"apng", :image, image_limit},
            {"jpeg_pipe", :image, image_limit},
            {"gif", :image, image_limit},
            {"webp_pipe", :image, image_limit},
            {"mov", :video, video_limit},
            {"matroska", :video, video_limit}
          ] do
        call(
          "probe #{format}",
          :ffprobe,
          Ffmpeg.probe_args(input, format, limit, json),
          format,
          kind,
          input,
          json,
          nil
        )
      end

    stills =
      for format <- ["png_pipe", "jpeg_pipe", "gif", "webp_pipe"], lossless <- [true, false] do
        args = Ffmpeg.still_image_args(input, format, webp, lossless: lossless)
        call("still #{format} #{lossless}", :ffmpeg, args, format, :image, input, webp, "webp")
      end

    animated =
      for format <- ["gif", "apng"] do
        [
          call(
            "animated #{format}",
            :ffmpeg,
            Ffmpeg.animated_image_args(input, format, webp),
            format,
            :image,
            input,
            webp,
            "webp"
          ),
          call(
            "image poster #{format}",
            :ffmpeg,
            Ffmpeg.image_poster_args(input, format, poster),
            format,
            :image,
            input,
            poster,
            "webp"
          )
        ]
      end

    videos =
      for format <- ["mov", "matroska"] do
        call(
          "video #{format}",
          :ffmpeg,
          Ffmpeg.video_args(input, format, webm),
          format,
          :video,
          input,
          webm,
          "webm"
        )
      end

    probes ++
      stills ++
      List.flatten(animated) ++
      videos ++
      [
        call(
          "remux",
          :ffmpeg,
          Ffmpeg.remux_args(input, webm),
          "matroska",
          :video,
          input,
          webm,
          "webm"
        ),
        call(
          "video poster",
          :ffmpeg,
          Ffmpeg.video_poster_args(webm, 0.5, poster),
          "matroska",
          :video,
          webm,
          poster,
          "webp"
        )
      ]
  end

  defp call(name, tool, args, format, kind, input, output, output_format) do
    %{
      name: name,
      tool: tool,
      args: args,
      format: format,
      kind: kind,
      input: input,
      output: output,
      output_format: output_format
    }
  end

  defp input, do: Store.incoming_path("0b5d3c1e-7f00-4a6b-9a1e-3c2d1f0e9b8a")

  defp output(ext) do
    work =
      Store.work_dir(
        "0b5d3c1e-7f00-4a6b-9a1e-3c2d1f0e9b8a",
        "5e8a1b2c-3d4f-4a5b-8c6d-7e8f9a0b1c2d"
      )

    Path.join(work, "out." <> ext)
  end

  defp scale(edge) do
    "scale='min(iw,#{edge})':'min(ih,#{edge})':force_original_aspect_ratio=decrease"
  end

  # The output options: the elements after the input, without the output
  # format and the output path.
  defp after_input(args) do
    index = pair_index(args, "-i", input()) + 2
    args |> Enum.slice(index..-1//1) |> Enum.drop(-6)
  end

  defp input_index(%{tool: :ffprobe, args: args}), do: length(args) - 1
  defp input_index(%{tool: :ffmpeg, args: args, input: input}), do: pair_index(args, "-i", input)

  defp count_before_input(call, flag) do
    call.args |> Enum.take(input_index(call)) |> Enum.count(&(&1 == flag))
  end

  defp pair_index(args, flag, value), do: List.first(pair_indexes(args, flag, value))

  defp pair_indexes(args, flag, value) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {[^flag, ^value], index} -> [index]
      _other -> []
    end)
  end

  defp count_pair(args, flag, value), do: length(pair_indexes(args, flag, value))
end

defmodule Espalier.Media.FfmpegConfigTest do
  @moduledoc """
  Task 0018, steps 2, 5 and 23: the arguments follow `MEDIA_IMAGE_MAX_EDGE`,
  `MEDIA_VIDEO_MAX_HEIGHT` and `MEDIA_FFMPEG_THREADS`, and
  `Espalier.Media.Ffmpeg.check/0` accepts the ffmpeg of the shell and names
  every missing tool, encoder and demuxer and an old or unknown release.
  The tests change the application environment and `PATH`, hence no
  `async`.
  """
  use ExUnit.Case, async: false

  alias Espalier.Media.{Ffmpeg, Store}

  @moduletag :tmp_dir

  describe "configuration" do
    setup do
      put_media(image_max_edge: 640, video_max_height: 240, ffmpeg_threads: 3)
    end

    test "the scale filters take the configured edge and height" do
      input = Store.incoming_path(Ecto.UUID.generate())
      out = Path.join(Store.work_dir(Ecto.UUID.generate(), Ecto.UUID.generate()), "out.webp")
      image_filter = "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease"

      for args <- [
            Ffmpeg.still_image_args(input, "png_pipe", out, lossless: true),
            Ffmpeg.animated_image_args(input, "gif", out),
            Ffmpeg.image_poster_args(input, "apng", out)
          ] do
        assert vf(args) == image_filter
      end

      assert vf(Ffmpeg.video_args(input, "mov", out)) == "scale=-2:'min(ih,240)'"
    end

    test "every call takes the configured number of threads" do
      input = Store.incoming_path(Ecto.UUID.generate())
      out = Path.join(Store.work_dir(Ecto.UUID.generate(), Ecto.UUID.generate()), "out.webm")

      ffmpeg_calls = [
        Ffmpeg.still_image_args(input, "jpeg_pipe", out),
        Ffmpeg.animated_image_args(input, "gif", out),
        Ffmpeg.image_poster_args(input, "gif", out),
        Ffmpeg.remux_args(input, out),
        Ffmpeg.video_args(input, "matroska", out),
        Ffmpeg.video_poster_args(input, 1.0, out)
      ]

      for args <- ffmpeg_calls do
        assert count(args, "-threads", "3") == 2
        assert count(args, "-filter_threads", "3") == 1
        refute count(args, "-threads", "2") > 0
      end

      assert count(Ffmpeg.probe_args(input, "mov", 1, out), "-threads", "3") == 1
    end
  end

  describe "check/0" do
    test "accepts the ffmpeg of the shell" do
      assert Ffmpeg.check() == []
    end

    test "names a missing ffprobe, an old release, a missing encoder and demuxer",
         %{tmp_dir: dir} do
      fake_path!(dir, ffprobe: false)

      fake_ffmpeg!(dir,
        version: "ffmpeg version 6.1.1 Copyright (c) 2000-2023 the FFmpeg developers",
        encoders: List.delete(encoders(), "libwebp_anim"),
        demuxers: List.delete(demuxers(), "apng")
      )

      assert Ffmpeg.check() == [
               "ffprobe is not installed",
               "ffmpeg 6.1 is older than 7.1",
               "ffmpeg lacks the encoder libwebp_anim",
               "ffmpeg lacks the demuxer apng"
             ]
    end

    test "accepts 7.1 with an n prefix and later releases, and joined demuxer names",
         %{tmp_dir: dir} do
      fake_path!(dir)

      for version <- ["ffmpeg version n7.1.2", "ffmpeg version 7.1", "ffmpeg version 10.0-static"] do
        fake_ffmpeg!(dir, version: version, encoders: encoders(), demuxers: demuxers())
        assert Ffmpeg.check() == [], version
      end
    end

    test "names 7.0 as too old and a build without a release version", %{tmp_dir: dir} do
      fake_path!(dir)

      fake_ffmpeg!(dir,
        version: "ffmpeg version 7.0.2",
        encoders: encoders(),
        demuxers: demuxers()
      )

      assert Ffmpeg.check() == ["ffmpeg 7.0 is older than 7.1"]

      fake_ffmpeg!(dir,
        version: "ffmpeg version N-118430-g1234abcd Copyright (c) 2000-2026",
        encoders: encoders(),
        demuxers: demuxers()
      )

      assert Ffmpeg.check() == ["ffmpeg reports no release version"]
    end

    test "names every missing encoder and demuxer", %{tmp_dir: dir} do
      fake_path!(dir)
      fake_ffmpeg!(dir, version: "ffmpeg version 8.1.2", encoders: [], demuxers: [])

      assert Ffmpeg.check() ==
               Enum.map(
                 ~w(libvpx-vp9 libopus libwebp libwebp_anim),
                 &"ffmpeg lacks the encoder #{&1}"
               ) ++
                 Enum.map(
                   ~w(mov matroska png_pipe jpeg_pipe webp_pipe gif apng),
                   &"ffmpeg lacks the demuxer #{&1}"
                 )
    end

    test "a name in the description column does not count", %{tmp_dir: dir} do
      fake_path!(dir)

      fake_ffmpeg!(dir,
        version: "ffmpeg version 8.1.2",
        encoders: List.delete(encoders(), "libopus"),
        demuxers: demuxers(),
        extra_encoder_line: " A....D opus                 libopus Opus wrapper libopus"
      )

      assert Ffmpeg.check() == ["ffmpeg lacks the encoder libopus"]
    end

    test "names an ffmpeg that fails", %{tmp_dir: dir} do
      fake_path!(dir)
      fake_ffmpeg!(dir, version: "ffmpeg version 8.1.2", exit: 3)
      assert Ffmpeg.check() == ["ffmpeg exits with status 3"]
    end

    test "names the missing tools without ffmpeg", %{tmp_dir: dir} do
      fake_path!(dir, ffprobe: false, timeout: false)

      assert Ffmpeg.check() == [
               "ffmpeg is not installed",
               "ffprobe is not installed",
               "timeout is not installed"
             ]
    end
  end

  defp put_media(changes) do
    previous = Application.fetch_env!(:espalier, :media)
    Application.put_env(:espalier, :media, Keyword.merge(previous, changes))
    on_exit(fn -> Application.put_env(:espalier, :media, previous) end)
    :ok
  end

  defp vf(args) do
    index = Enum.find_index(args, &(&1 == "-vf"))
    Enum.at(args, index + 1)
  end

  defp count(args, flag, value) do
    args |> Enum.chunk_every(2, 1, :discard) |> Enum.count(&(&1 == [flag, value]))
  end

  defp encoders, do: ~w(libvpx libvpx-vp9 libopus libvorbis libwebp libwebp_anim png)

  defp demuxers,
    do: [
      "mov,mp4,m4a,3gp,3g2,mj2",
      "matroska,webm",
      "png_pipe",
      "jpeg_pipe",
      "webp_pipe",
      "gif",
      "apng",
      "hls"
    ]

  # A PATH with only `dir/bin`: links to the real ffprobe and timeout unless
  # they are switched off. Restored after the test.
  defp fake_path!(dir, opts \\ []) do
    bin = Path.join(dir, "bin")
    File.mkdir_p!(bin)

    for tool <- [:ffprobe, :timeout], Keyword.get(opts, tool, true) do
      name = Atom.to_string(tool)
      File.ln_s!(System.find_executable(name), Path.join(bin, name))
    end

    previous = System.get_env("PATH")
    System.put_env("PATH", bin)
    on_exit(fn -> System.put_env("PATH", previous) end)
    bin
  end

  # A stand-in for ffmpeg that prints the given version, encoder and
  # demuxer lists in the layout of ffmpeg, using only builtins of sh.
  defp fake_ffmpeg!(dir, opts) do
    encoder_lines =
      Enum.map(Keyword.get(opts, :encoders, []), &" V....D #{&1}                libtest encoder") ++
        List.wrap(Keyword.get(opts, :extra_encoder_line))

    demuxer_lines =
      Enum.map(Keyword.get(opts, :demuxers, []), &" D   #{&1}          test demuxer")

    encoders =
      Enum.join(
        ["Encoders:", " V..... = Video", " A..... = Audio", " ------" | encoder_lines],
        "\n"
      )

    demuxers =
      Enum.join(["File formats:", " D. = Demuxing supported", " ---" | demuxer_lines], "\n")

    script = """
    #!/bin/sh
    exit_status=#{Keyword.get(opts, :exit, 0)}
    if [ "$exit_status" != 0 ]; then exit "$exit_status"; fi
    case "$2" in
      -version) printf '%s\\n' '#{Keyword.fetch!(opts, :version)}' ;;
      -encoders) printf '%s\\n' '#{encoders}' ;;
      -demuxers) printf '%s\\n' '#{demuxers}' ;;
      *) exit 1 ;;
    esac
    """

    path = Path.join([dir, "bin", "ffmpeg"])
    File.write!(path, script)
    File.chmod!(path, 0o755)
    path
  end
end
