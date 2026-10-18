defmodule Espalier.Media.ProcessorTest do
  @moduledoc """
  Task 0018, steps 1, 6 and 23: `Espalier.Media.Processor.run/4` for images
  and videos, and its option `:proceed` for every kind, with fixtures that
  ffmpeg generates from `lavfi` sources at test start.

    * Images: a still image becomes a WebP (lossless for PNG, GIF and
      lossless WebP, lossy for JPEG and lossy WebP) within
      `MEDIA_IMAGE_MAX_EDGE`, with size and alpha from its WebP header; an
      animated GIF or APNG becomes an animated WebP with a poster, up to
      `max_frames` frames; metadata does not reach the output.
    * Videos: VP9 with Opus in Matroska is remuxed without a new encoding;
      every other input converts to VP9 and Opus within
      `MEDIA_VIDEO_MAX_HEIGHT`; the facts and the poster come from the
      delivery file; inputs without a video stream or longer than
      `MEDIA_VIDEO_MAX_MINUTES` fail.
    * The option `:proceed` is asked before each command and before the
      output of the SVG rebuild, the captions check or the check of an
      animated WebP is written; an answer `:halt` ends the processor with
      `{:error, :cancelled, nil}` before that command or output.
    * Isolation (step 1, ASVS 1.3.6): an HLS playlist, an ffconcat list and
      MP4 files with external data references, passed with a forced format,
      fail or read only the input, and a TCP listener records no connection;
      each fixture first proves that ffmpeg follows it when the protection
      is off.

  The processor writes only into the work directory of the test. Some tests
  change `config :espalier, :media`, hence no `async`.
  """
  use ExUnit.Case, async: false

  alias Espalier.Media.{Processor, Sniff}

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    work = Path.join(dir, "work")
    File.mkdir_p!(work)
    %{work: work}
  end

  describe "still images" do
    test "a PNG converts to a lossless WebP with the size of its header", %{
      tmp_dir: dir,
      work: work
    } do
      input =
        generate!(dir, "still.png", ["-f", "lavfi", "-i", "testsrc2=s=64x48", "-frames:v", "1"])

      assert {:ok, outputs} = run(:image, input, "still.png", work)

      assert outputs.ext == "webp"
      assert outputs.poster == nil
      assert Path.dirname(outputs.delivery) == work

      assert outputs.facts == %{
               width: 64,
               height: 48,
               duration_ms: nil,
               has_audio: false,
               animated: false,
               has_alpha: false
             }

      assert {:ok, %{lossless: true, animated: false, width: 64, height: 48}} =
               Sniff.webp_info(outputs.delivery)

      # The probe JSON is removed; the work directory holds the delivery only.
      assert File.ls!(work) == ["out.webp"]
    end

    test "a JPEG converts to a lossy WebP", %{tmp_dir: dir, work: work} do
      input =
        generate!(dir, "photo.jpg", ["-f", "lavfi", "-i", "testsrc2=s=80x60", "-frames:v", "1"])

      assert {:ok, %{facts: %{width: 80, height: 60, has_alpha: false}} = outputs} =
               run(:image, input, "photo.jpeg", work)

      assert {:ok, %{lossless: false}} = Sniff.webp_info(outputs.delivery)
    end

    test "a GIF with one frame converts losslessly and is no animation", %{
      tmp_dir: dir,
      work: work
    } do
      input =
        generate!(dir, "one.gif", ["-f", "lavfi", "-i", "color=c=green:s=40x30", "-frames:v", "1"])

      assert {:ok, %{poster: nil, facts: %{animated: false, width: 40, height: 30}} = outputs} =
               run(:image, input, "one.gif", work)

      assert {:ok, %{lossless: true}} = Sniff.webp_info(outputs.delivery)
    end

    test "a lossless WebP stays lossless, a lossy WebP stays lossy", %{tmp_dir: dir, work: work} do
      lossless =
        generate!(dir, "lossless.webp", [
          "-f",
          "lavfi",
          "-i",
          "testsrc2=s=64x48",
          "-frames:v",
          "1",
          "-c:v",
          "libwebp",
          "-lossless",
          "1"
        ])

      lossy =
        generate!(dir, "lossy.webp", [
          "-f",
          "lavfi",
          "-i",
          "testsrc2=s=64x48",
          "-frames:v",
          "1",
          "-c:v",
          "libwebp"
        ])

      assert {:ok, outputs} = run(:image, lossless, "a.webp", work)
      assert {:ok, %{lossless: true}} = Sniff.webp_info(outputs.delivery)

      assert {:ok, outputs} = run(:image, lossy, "b.webp", work)
      assert {:ok, %{lossless: false}} = Sniff.webp_info(outputs.delivery)
    end

    test "an APNG with a single frame converts as a still image", %{tmp_dir: dir, work: work} do
      still =
        generate!(dir, "still.png", ["-f", "lavfi", "-i", "testsrc2=s=48x32", "-frames:v", "1"])

      # acTL with one frame and the fcTL of the default image after IHDR.
      <<head::binary-size(33), rest::binary>> = File.read!(still)
      actl = png_chunk("acTL", <<1::32, 0::32>>)
      fctl = png_chunk("fcTL", <<0::32, 48::32, 32::32, 0::32, 0::32, 1::16, 10::16, 0, 0>>)
      input = write!(dir, "single.png", head <> actl <> fctl <> rest)

      assert {:ok, %{format: "apng"}} = Sniff.detect(input, "single.png")

      assert {:ok, %{poster: nil, facts: %{animated: false, width: 48, height: 32}} = outputs} =
               run(:image, input, "single.png", work)

      assert {:ok, %{animated: false, lossless: true}} = Sniff.webp_info(outputs.delivery)
    end

    test "a PNG with alpha keeps it", %{tmp_dir: dir, work: work} do
      input =
        generate!(dir, "alpha.png", [
          "-f",
          "lavfi",
          "-i",
          "color=c=red@0.5:s=32x24,format=rgba",
          "-frames:v",
          "1"
        ])

      assert {:ok, %{facts: %{has_alpha: true, width: 32, height: 24}} = outputs} =
               run(:image, input, "alpha.png", work)

      assert {:ok, %{has_alpha: true}} = Sniff.webp_info(outputs.delivery)
    end

    test "an image larger than MEDIA_IMAGE_MAX_EDGE is scaled down, a small one is not",
         %{tmp_dir: dir, work: work} do
      put_media(image_max_edge: 320)

      wide =
        generate!(dir, "wide.png", ["-f", "lavfi", "-i", "testsrc2=s=640x400", "-frames:v", "1"])

      tall =
        generate!(dir, "tall.jpg", ["-f", "lavfi", "-i", "testsrc2=s=300x900", "-frames:v", "1"])

      small =
        generate!(dir, "small.png", ["-f", "lavfi", "-i", "testsrc2=s=64x48", "-frames:v", "1"])

      assert {:ok, %{facts: %{width: 320, height: 200}}} = run(:image, wide, "wide.png", work)

      assert {:ok, %{facts: %{width: width, height: 320}}} = run(:image, tall, "tall.jpg", work)
      assert width in 106..107

      assert {:ok, %{facts: %{width: 64, height: 48}}} = run(:image, small, "small.png", work)
    end

    test "two JPEG files that differ only in EXIF data convert to the same bytes",
         %{tmp_dir: dir, work: work} do
      base =
        generate!(dir, "base.jpg", ["-f", "lavfi", "-i", "testsrc2=s=96x64", "-frames:v", "1"])

      <<0xFF, 0xD8, rest::binary>> = File.read!(base)

      first = write!(dir, "first.jpg", <<0xFF, 0xD8>> <> exif("Invented Camera A", nil) <> rest)

      second =
        write!(
          dir,
          "second.jpg",
          <<0xFF, 0xD8>> <>
            exif("Invented Camera B", "2026:01:02 03:04:05") <>
            segment(0xFE, "an invented comment") <> rest
        )

      refute File.read!(first) == File.read!(second)

      digests =
        for input <- [first, second] do
          assert {:ok, outputs} = run(:image, input, "photo.jpg", work)
          bytes = File.read!(outputs.delivery)
          refute bytes =~ "Invented Camera"
          refute bytes =~ "invented comment"
          :crypto.hash(:sha256, bytes)
        end

      assert [same, same] = digests
    end
  end

  describe "animated images" do
    test "an animated GIF with three frames becomes an animated WebP with a poster",
         %{tmp_dir: dir, work: work} do
      input = generate!(dir, "anim.gif", animation(48, 32))

      assert {:ok, outputs} = run(:image, input, "anim.gif", work)
      assert_animation(outputs, work, 48, 32)
    end

    test "an APNG with three frames becomes an animated WebP with a poster",
         %{tmp_dir: dir, work: work} do
      input = generate!(dir, "anim.png", animation(48, 32) ++ ["-plays", "0", "-f", "apng"])
      assert {:ok, %{format: "apng"}} = Sniff.detect(input, "anim.png")

      assert {:ok, outputs} = run(:image, input, "anim.png", work)
      assert_animation(outputs, work, 48, 32)
    end

    test "more frames than max_frames answer too_many_frames, as many pass",
         %{tmp_dir: dir, work: work} do
      gif = generate!(dir, "anim.gif", animation(48, 32))
      apng = generate!(dir, "anim.png", animation(48, 32) ++ ["-f", "apng"])

      put_media(max_frames: 2)
      assert run(:image, gif, "anim.gif", work) == {:error, :too_many_frames, nil}
      assert run(:image, apng, "anim.png", work) == {:error, :too_many_frames, nil}

      put_media(max_frames: 3)
      assert {:ok, %{facts: %{animated: true}}} = run(:image, gif, "anim.gif", work)
    end
  end

  describe "pixel limits" do
    test "a small PNG whose IHDR claims 10000 by 10000 answers too_many_pixels",
         %{tmp_dir: dir, work: work} do
      input = write!(dir, "huge.png", png_claiming(10_000, 10_000))
      assert byte_size(File.read!(input)) < 200

      assert Sniff.detect(input, "huge.png") == {:error, :too_many_pixels}

      # Past the detection, -max_pixels stops ffprobe before it decodes.
      detection = %{
        kind: :image,
        format: "png_pipe",
        width: 10_000,
        height: 10_000,
        animated: false
      }

      assert Processor.run(:image, input, detection, opts(work)) ==
               {:error, :too_many_pixels, nil}

      refute File.exists?(Path.join(work, "out.webp"))
    end

    test "a video above max_video_pixels answers too_many_pixels", %{tmp_dir: dir, work: work} do
      input =
        generate!(dir, "wide.webm", [
          "-f",
          "lavfi",
          "-i",
          "color=c=gray:s=320x240:r=5",
          "-t",
          "0.4",
          "-c:v",
          "libvpx-vp9",
          "-deadline",
          "realtime",
          "-cpu-used",
          "8"
        ])

      # 320 x 240 = 76,800 pixels.
      put_media(max_video_pixels: 76_799)

      assert run(:video, input, "wide.webm", work, video_opts()) ==
               {:error, :too_many_pixels, nil}
    end
  end

  describe "videos" do
    test "VP9 with Opus in WebM is remuxed: the packets pass unchanged",
         %{tmp_dir: dir, work: work} do
      input = generate!(dir, "clip.webm", vp9_opus(160, 90))

      assert {:ok, outputs} = run(:video, input, "clip.webm", work, video_opts())
      assert outputs.ext == "webm"
      assert streams(outputs.delivery) == [{"video", "vp9", "yuv420p"}, {"audio", "opus", nil}]

      assert packet_hashes(outputs.delivery, "v") == packet_hashes(input, "v")
      assert packet_hashes(outputs.delivery, "a") == packet_hashes(input, "a")

      assert %{width: 160, height: 90, has_audio: true, animated: false, has_alpha: false} =
               outputs.facts

      assert outputs.facts.duration_ms in 1_900..2_100
      assert_received {:duration, duration_ms} when duration_ms in 1_900..2_100
      assert_progress_within_range()
      assert_poster(outputs, 160, 90)
    end

    test "AV1 with Opus in Matroska converts to VP9 and Opus", %{tmp_dir: dir, work: work} do
      input =
        generate!(dir, "av1.mkv", [
          "-f",
          "lavfi",
          "-i",
          "testsrc2=s=160x90:r=10",
          "-f",
          "lavfi",
          "-i",
          "sine=f=440:r=48000",
          "-t",
          "2",
          "-c:v",
          "libaom-av1",
          "-cpu-used",
          "8",
          "-crf",
          "50",
          "-c:a",
          "libopus"
        ])

      assert streams(input) == [{"video", "av1", "yuv420p"}, {"audio", "opus", nil}]
      assert_converted(run(:video, input, "av1.mkv", work, video_opts()), 160, 90, true)
    end

    test "VP8 with Vorbis in Matroska converts to VP9 and Opus", %{tmp_dir: dir, work: work} do
      input =
        generate!(dir, "vp8.mkv", [
          "-f",
          "lavfi",
          "-i",
          "testsrc2=s=160x90:r=10",
          "-f",
          "lavfi",
          "-i",
          "sine=f=440:r=44100",
          "-t",
          "2",
          "-c:v",
          "libvpx",
          "-deadline",
          "realtime",
          "-c:a",
          "libvorbis"
        ])

      assert streams(input) == [{"video", "vp8", "yuv420p"}, {"audio", "vorbis", nil}]
      assert_converted(run(:video, input, "vp8.mkv", work, video_opts()), 160, 90, true)
    end

    test "H.264 with AAC in MP4 converts to VP9 and Opus", %{tmp_dir: dir, work: work} do
      input = generate!(dir, "h264.mp4", h264_aac(320, 180))

      assert streams(input) == [{"video", "h264", "yuv420p"}, {"audio", "aac", nil}]
      assert {:ok, %{format: "mov"}} = Sniff.detect(input, "h264.mp4")
      assert_converted(run(:video, input, "h264.mp4", work, video_opts()), 320, 180, true)
    end

    test "MPEG-4 Part 2 without audio converts, has_audio is false", %{tmp_dir: dir, work: work} do
      input =
        generate!(dir, "mpeg4.m4v", [
          "-f",
          "lavfi",
          "-i",
          "testsrc2=s=160x90:r=10",
          "-t",
          "2",
          "-c:v",
          "mpeg4",
          "-f",
          "mp4"
        ])

      assert streams(input) == [{"video", "mpeg4", "yuv420p"}]
      assert_converted(run(:video, input, "mpeg4.m4v", work, video_opts()), 160, 90, false)
    end

    test "VP9 without audio is remuxed and has no audio", %{tmp_dir: dir, work: work} do
      input = generate!(dir, "silent.webm", silent_vp9(160, 90))

      assert streams(input) == [{"video", "vp9", "yuv420p"}]
      assert {:ok, outputs} = run(:video, input, "silent.mkv", work, video_opts())
      assert outputs.facts.has_audio == false
      assert streams(outputs.delivery) == [{"video", "vp9", "yuv420p"}]
      assert packet_hashes(outputs.delivery, "v") == packet_hashes(input, "v")
    end

    test "VP9 in yuv444p or with Vorbis converts", %{tmp_dir: dir, work: work} do
      yuv444 =
        generate!(dir, "yuv444.webm", [
          "-f",
          "lavfi",
          "-i",
          "testsrc2=s=160x90:r=10",
          "-t",
          "1",
          "-c:v",
          "libvpx-vp9",
          "-pix_fmt",
          "yuv444p",
          "-deadline",
          "realtime",
          "-cpu-used",
          "8"
        ])

      vorbis =
        generate!(
          dir,
          "vorbis.webm",
          List.replace_at(vp9_opus(160, 90), -1, "libvorbis")
        )

      assert streams(yuv444) == [{"video", "vp9", "yuv444p"}]
      assert streams(vorbis) == [{"video", "vp9", "yuv420p"}, {"audio", "vorbis", nil}]

      assert {:ok, outputs} = run(:video, yuv444, "yuv444.webm", work, video_opts())
      assert streams(outputs.delivery) == [{"video", "vp9", "yuv420p"}]
      assert_received {:progress, _percent}

      File.rm_rf!(work)
      File.mkdir_p!(work)
      assert_converted(run(:video, vorbis, "vorbis.webm", work, video_opts()), 160, 90, true)
    end

    test "the height is capped at MEDIA_VIDEO_MAX_HEIGHT, also for VP9 with Opus",
         %{tmp_dir: dir, work: work} do
      put_media(video_max_height: 240)

      h264 = generate!(dir, "h264.mp4", h264_aac(640, 360))
      vp9 = generate!(dir, "vp9.webm", vp9_opus(480, 270))

      assert {:ok, outputs} = run(:video, h264, "h264.mp4", work, video_opts())
      assert %{height: 240, width: width} = outputs.facts
      assert width in 426..427
      assert rem(width, 2) == 0
      assert_poster(outputs, width, 240)

      File.rm_rf!(work)
      File.mkdir_p!(work)

      assert {:ok, outputs} = run(:video, vp9, "vp9.webm", work, video_opts())
      assert %{height: 240, width: 426} = outputs.facts
      refute packet_hashes(outputs.delivery, "v") == packet_hashes(vp9, "v")
      assert_received {:progress, _percent}
    end

    test "a file with only an audio stream answers no_video_stream", %{tmp_dir: dir, work: work} do
      webm =
        generate!(dir, "audio.webm", [
          "-f",
          "lavfi",
          "-i",
          "sine=f=440:r=48000",
          "-t",
          "1",
          "-c:a",
          "libopus"
        ])

      mp4 =
        generate!(dir, "audio.mp4", [
          "-f",
          "lavfi",
          "-i",
          "sine=f=440:r=44100",
          "-t",
          "1",
          "-c:a",
          "aac"
        ])

      assert run(:video, webm, "audio.webm", work, video_opts()) ==
               {:error, :no_video_stream, nil}

      assert run(:video, mp4, "audio.mp4", work, video_opts()) ==
               {:error, :no_video_stream, nil}

      assert File.ls!(work) == []
    end

    test "a video longer than MEDIA_VIDEO_MAX_MINUTES answers too_long",
         %{tmp_dir: dir, work: work} do
      put_media(video_max_minutes: 1)

      long = generate!(dir, "long.webm", tiny_vp9(61))
      short = generate!(dir, "short.webm", tiny_vp9(50))

      assert run(:video, long, "long.webm", work, video_opts()) == {:error, :too_long, nil}
      refute File.exists?(Path.join(work, "out.webm"))

      assert {:ok, %{facts: %{duration_ms: duration_ms}}} =
               run(:video, short, "short.webm", work, video_opts())

      assert duration_ms in 49_000..51_000
    end

    test "two videos with the same black first second give posters with the same digest",
         %{tmp_dir: dir, work: work} do
      first =
        generate!(dir, "first.mkv", [
          "-f",
          "lavfi",
          "-i",
          black_then("red"),
          "-c:v",
          "libvpx",
          "-deadline",
          "realtime"
        ])

      second =
        generate!(dir, "second.mp4", [
          "-f",
          "lavfi",
          "-i",
          black_then("blue"),
          "-f",
          "lavfi",
          "-i",
          "sine=f=220:r=44100",
          "-t",
          "2",
          "-c:v",
          "libx264",
          "-preset",
          "ultrafast",
          "-pix_fmt",
          "yuv420p",
          "-c:a",
          "aac"
        ])

      results =
        for {input, name} <- [{first, "first.mkv"}, {second, "second.mp4"}] do
          File.rm_rf!(work)
          File.mkdir_p!(work)
          assert {:ok, outputs} = run(:video, input, name, work, video_opts())
          assert_poster(outputs, 160, 90)
          {sha256(outputs.delivery), sha256(outputs.poster)}
        end

      [{first_delivery, first_poster}, {second_delivery, second_poster}] = results
      refute first_delivery == second_delivery
      assert first_poster == second_poster
    end

    test "a truncated WebM makes ffprobe log an error and exit 0, and processes without a crash",
         %{tmp_dir: dir, work: work} do
      complete = generate!(dir, "complete.webm", vp9_opus(160, 90))
      bytes = File.read!(complete)
      input = write!(dir, "truncated.webm", binary_part(bytes, 0, div(byte_size(bytes) * 2, 3)))

      {output, status} =
        System.cmd(
          tool("ffprobe"),
          ["-v", "error", "-count_packets", "-show_entries", "stream=index", input],
          stderr_to_stdout: true
        )

      assert status == 0
      assert output =~ "File ended prematurely"

      case run(:video, input, "truncated.webm", work, video_opts()) do
        {:ok, outputs} ->
          assert outputs.facts.duration_ms in 1..2_000
          assert {:ok, _info} = Sniff.webp_info(outputs.poster)

        {:error, :conversion_failed, nil} ->
          :ok
      end
    end

    test "a header that claims a shorter duration than the packets answers too_long",
         %{tmp_dir: dir, work: work} do
      put_media(video_max_minutes: 1)
      long = File.read!(generate!(dir, "long.webm", tiny_vp9(61)))

      # The Duration element of the segment info, an 8-byte float in ms.
      [{position, 3}] = :binary.matches(long, <<0x44, 0x89, 0x88>>)
      {head, <<61_000.0::float-64, rest::binary>>} = :erlang.split_binary(long, position + 3)
      input = write!(dir, "claims.webm", head <> <<10_000.0::float-64>> <> rest)

      assert run(:video, input, "claims.webm", work, video_opts()) == {:error, :too_long, nil}
      assert_received {:duration, 10_000}
    end

    test "VP9 with alpha converts, and the alpha is dropped", %{tmp_dir: dir, work: work} do
      input =
        generate!(dir, "alpha.webm", [
          "-f",
          "lavfi",
          "-i",
          "color=c=red@0.5:s=160x90:r=10,format=yuva420p",
          "-t",
          "1",
          "-c:v",
          "libvpx-vp9",
          "-deadline",
          "realtime",
          "-cpu-used",
          "8"
        ])

      assert alpha_mode(input) == "1"

      assert {:ok, outputs} = run(:video, input, "alpha.webm", work, video_opts())
      assert alpha_mode(outputs.delivery) == nil
      assert streams(outputs.delivery) == [{"video", "vp9", "yuv420p"}]
      refute packet_hashes(outputs.delivery, "v") == packet_hashes(input, "v")
      assert %{has_alpha: false, width: 160, height: 90} = outputs.facts
    end

    test "the title and the chapters of the input do not reach the delivery file",
         %{tmp_dir: dir, work: work} do
      metadata =
        write!(dir, "metadata.txt", """
        ;FFMETADATA1
        title=Invented secret title
        [CHAPTER]
        TIMEBASE=1/1000
        START=0
        END=1000
        title=Invented chapter name
        """)

      # Both fixtures start with two lavfi inputs of four elements each.
      inputs =
        for {name, args} <- [
              {"remux.webm", vp9_opus(160, 90)},
              {"convert.mp4", h264_aac(160, 90)}
            ] do
          {sources, codecs} = Enum.split(args, 8)
          maps = ["-map", "0", "-map", "1", "-map_metadata", "2", "-map_chapters", "2"]
          path = generate!(dir, name, sources ++ ["-i", metadata] ++ maps ++ codecs)

          assert File.read!(path) =~ "Invented chapter name"
          assert File.read!(path) =~ "Invented secret title"
          {path, name}
        end

      for {path, name} <- inputs do
        File.rm_rf!(work)
        File.mkdir_p!(work)
        assert {:ok, outputs} = run(:video, path, name, work, video_opts())
        delivery = File.read!(outputs.delivery)
        refute delivery =~ "Invented secret title", name
        refute delivery =~ "Invented chapter name", name
      end
    end

    test "trailing garbage and a bare EBML header", %{tmp_dir: dir, work: work} do
      complete = generate!(dir, "complete.webm", vp9_opus(160, 90))

      garbage =
        write!(dir, "garbage.webm", File.read!(complete) <> :crypto.strong_rand_bytes(4096))

      bare =
        write!(dir, "bare.webm", <<0x1A, 0x45, 0xDF, 0xA3>> <> :crypto.strong_rand_bytes(2048))

      assert {:ok, %{facts: %{width: 160, height: 90}}} =
               run(:video, garbage, "garbage.webm", work, video_opts())

      File.rm_rf!(work)
      File.mkdir_p!(work)

      assert run(:video, bare, "bare.webm", work, video_opts()) ==
               {:error, :conversion_failed, nil}
    end
  end

  describe "deadlines" do
    test "a deadline in the past answers timeout before a process starts",
         %{tmp_dir: dir, work: work} do
      image =
        generate!(dir, "still.png", ["-f", "lavfi", "-i", "testsrc2=s=64x48", "-frames:v", "1"])

      video = generate!(dir, "clip.webm", vp9_opus(160, 90))
      past = System.monotonic_time(:millisecond) - 1

      {:ok, detection} = Sniff.detect(image, "still.png")

      assert Processor.run(:image, image, detection, deadline: past, work_dir: work) ==
               {:error, :timeout, nil}

      {:ok, detection} = Sniff.detect(video, "clip.webm")

      assert Processor.run(:video, video, detection, deadline: past, work_dir: work) ==
               {:error, :timeout, nil}

      assert File.ls!(work) == []
    end

    test "the deadline that on_duration returns governs the conversion", %{
      tmp_dir: dir,
      work: work
    } do
      input = generate!(dir, "h264.mp4", h264_aac(160, 90))
      {:ok, detection} = Sniff.detect(input, "h264.mp4")
      test = self()

      opts = [
        deadline: System.monotonic_time(:millisecond) + 120_000,
        work_dir: work,
        on_duration: fn duration_ms ->
          send(test, {:duration, duration_ms})
          System.monotonic_time(:millisecond) - 1
        end
      ]

      assert Processor.run(:video, input, detection, opts) == {:error, :timeout, nil}
      assert_received {:duration, duration_ms} when duration_ms in 1_900..2_100
    end
  end

  describe "proceed" do
    test "an answer :halt before the first command ends the processor before a process starts",
         %{tmp_dir: dir, work: work} do
      image =
        generate!(dir, "still.png", ["-f", "lavfi", "-i", "testsrc2=s=64x48", "-frames:v", "1"])

      video = generate!(dir, "clip.webm", vp9_opus(160, 90))

      assert run(:image, image, "still.png", work, proceed: proceed_until(0)) ==
               {:error, :cancelled, nil}

      assert run(:video, video, "clip.webm", work, [proceed: proceed_until(0)] ++ video_opts()) ==
               {:error, :cancelled, nil}

      assert asked() == 2
      assert File.ls!(work) == []
    end

    test "the processor asks before each command, so an answer :halt stops the next one",
         %{tmp_dir: dir, work: work} do
      video = generate!(dir, "h264.mp4", h264_aac(160, 90))

      # The probe runs, and the conversion does not start.
      assert run(:video, video, "h264.mp4", work, [proceed: proceed_until(1)] ++ video_opts()) ==
               {:error, :cancelled, nil}

      assert asked() == 2
      refute File.exists?(Path.join(work, "out.webm"))

      # Without a halt, the probe, the conversion, the probe of the delivery
      # file and the poster each ask once.
      File.rm_rf!(work)
      File.mkdir_p!(work)

      assert {:ok, _outputs} =
               run(:video, video, "h264.mp4", work, [proceed: proceed_until(9)] ++ video_opts())

      assert asked() == 4
    end

    test "an answer :halt after the SVG rebuild, the captions check or the WebP check writes no output",
         %{tmp_dir: dir, work: work} do
      svg =
        write!(dir, "a.svg", ~s(<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"/>))

      vtt = write!(dir, "a.vtt", Espalier.MediaFixtures.vtt())

      webp =
        generate!(dir, "animated.webp", [
          "-f",
          "lavfi",
          "-i",
          "testsrc2=s=48x32:r=5",
          "-frames:v",
          "3",
          "-c:v",
          "libwebp_anim"
        ])

      inputs = [{:svg, svg, "a.svg"}, {:captions, vtt, "a.vtt"}, {:image, webp, "animated.webp"}]

      for {kind, input, name} <- inputs do
        assert run(kind, input, name, work, proceed: proceed_until(0)) ==
                 {:error, :cancelled, nil}

        assert asked() == 1
        assert File.ls!(work) == []

        # With an answer :ok, the same input gives its outputs.
        assert {:ok, outputs} = run(kind, input, name, work, proceed: proceed_until(1))
        assert asked() == 1
        assert File.exists?(outputs.delivery)
        File.rm_rf!(work)
        File.mkdir_p!(work)
      end
    end
  end

  describe "isolation (step 1)" do
    test "an HLS playlist naming a local file and a local port fails without a connection",
         %{tmp_dir: dir, work: work} do
      {listener, port} = listen!()

      playlist =
        write!(dir, "list.m3u8", """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXTINF:10.0,
        file:///etc/passwd
        #EXTINF:10.0,
        http://127.0.0.1:#{port}/segment.ts
        #EXT-X-ENDLIST
        """)

      assert Sniff.detect(playlist, "list.mp4") == {:error, :unsupported_type}

      for format <- ["mov", "matroska"] do
        detection = %{kind: :video, format: format, width: nil, height: nil, animated: false}

        assert Processor.run(:video, playlist, detection, opts(work)) ==
                 {:error, :conversion_failed, nil}
      end

      detection = %{kind: :image, format: "png_pipe", width: 1, height: 1, animated: false}

      assert Processor.run(:image, playlist, detection, opts(work)) ==
               {:error, :conversion_failed, nil}

      refute_connection(listener)

      # Control: with the hls demuxer and the network allowed, ffmpeg
      # connects to the port of a playlist.
      control =
        write!(dir, "control.m3u8", """
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXTINF:10.0,
        http://127.0.0.1:#{port}/segment.ts
        #EXT-X-ENDLIST
        """)

      assert_connection(listener, ["-protocol_whitelist", "file,http,tcp", "-f", "hls", control])
    end

    test "an ffconcat list fails without a connection", %{tmp_dir: dir, work: work} do
      {listener, port} = listen!()

      list =
        write!(dir, "list.ffconcat", """
        ffconcat version 1.0
        file 'http://127.0.0.1:#{port}/x.webm'
        file 'file:///etc/passwd'
        """)

      assert Sniff.detect(list, "list.webm") == {:error, :unsupported_type}

      for format <- ["mov", "matroska"] do
        detection = %{kind: :video, format: format, width: nil, height: nil, animated: false}

        assert Processor.run(:video, list, detection, opts(work)) ==
                 {:error, :conversion_failed, nil}
      end

      refute_connection(listener)

      assert_connection(listener, [
        "-safe",
        "0",
        "-protocol_whitelist",
        "file,http,tcp",
        "-f",
        "concat",
        list
      ])
    end

    test "an MP4 whose dref names a URL reads only the input, without a connection",
         %{tmp_dir: dir, work: work} do
      {listener, port} = listen!()
      plain = generate!(dir, "plain.mp4", mpeg4_without_audio())

      input =
        write!(
          dir,
          "url.mp4",
          replace_dref(File.read!(plain), url_entry("http://127.0.0.1:#{port}/x"))
        )

      assert dref_entries(File.read!(input)) =~ "url "
      assert {:ok, %{format: "mov"} = detection} = Sniff.detect(input, "url.mp4")

      # The mov demuxer reads the samples of a url entry from the input.
      assert {:ok, outputs} = Processor.run(:video, input, detection, opts(work, video_opts()))
      assert %{width: 64, height: 48, has_audio: false} = outputs.facts

      refute_connection(listener)
    end

    test "an MP4 whose dref is an alias of a file next to it reads no data from that file",
         %{tmp_dir: dir, work: work} do
      plain = generate!(dir, "plain.mp4", mpeg4_without_audio())

      # The target holds the same samples at the same offsets, so a reader
      # that follows the alias gets a decodable track.
      File.cp!(plain, Path.join(dir, "secret.bin"))
      input = write!(dir, "alias.mp4", replace_dref(File.read!(plain), alias_entry("secret.bin")))

      # Control: with drefs enabled, ffprobe reads the track from the target.
      assert probe_size(input, ["-enable_drefs", "1"]) == "64,48"
      assert probe_size(input, ["-enable_drefs", "0"]) == "0,0"

      {:ok, detection} = Sniff.detect(input, "alias.mp4")

      assert Processor.run(:video, input, detection, opts(work, video_opts())) ==
               {:error, :conversion_failed, nil}
    end
  end

  ## Assertions

  defp assert_animation(outputs, work, width, height) do
    assert outputs.ext == "webp"
    assert Path.dirname(outputs.poster) == work

    assert outputs.facts == %{
             width: width,
             height: height,
             duration_ms: nil,
             has_audio: false,
             animated: true,
             has_alpha: false
           }

    assert {:ok, %{animated: true, width: ^width, height: ^height}} =
             Sniff.webp_info(outputs.delivery)

    assert {:ok, %{animated: false, width: ^width, height: ^height, has_alpha: false}} =
             Sniff.webp_info(outputs.poster)

    assert Enum.sort(File.ls!(work)) == ["out.webp", "poster.webp"]
  end

  defp assert_converted(result, width, height, has_audio) do
    assert {:ok, outputs} = result
    assert outputs.ext == "webm"

    expected =
      if has_audio,
        do: [{"video", "vp9", "yuv420p"}, {"audio", "opus", nil}],
        else: [{"video", "vp9", "yuv420p"}]

    assert streams(outputs.delivery) == expected

    assert %{width: ^width, height: ^height, has_audio: ^has_audio, animated: false} =
             outputs.facts

    assert outputs.facts.duration_ms in 1_900..2_100
    assert_received {:duration, duration_ms} when duration_ms in 1_900..2_100
    assert_received {:progress, _percent}
    assert_progress_within_range()
    assert_poster(outputs, width, height)
  end

  defp assert_poster(outputs, width, height) do
    assert {:ok, %{width: ^width, height: ^height, animated: false}} =
             Sniff.webp_info(outputs.poster)

    assert outputs.facts.width == width
    assert outputs.facts.height == height
  end

  defp assert_progress_within_range do
    receive do
      {:progress, percent} ->
        assert percent in 0..99
        assert_progress_within_range()
    after
      0 -> :ok
    end
  end

  ## Running

  # An option :proceed that answers :ok to the first `oks` questions and
  # :halt to every further one, and tells the test of each question.
  defp proceed_until(oks) do
    test = self()
    counter = :counters.new(1, [])

    fn ->
      :counters.add(counter, 1, 1)
      send(test, :asked)
      if :counters.get(counter, 1) <= oks, do: :ok, else: :halt
    end
  end

  # The number of questions of an option :proceed since the last call.
  defp asked do
    receive do
      :asked -> 1 + asked()
    after
      0 -> 0
    end
  end

  defp run(kind, input, name, work, extra \\ []) do
    assert {:ok, %{kind: ^kind} = detection} = Sniff.detect(input, name)
    Processor.run(kind, input, detection, opts(work, extra))
  end

  defp opts(work, extra \\ []) do
    Keyword.merge(
      [deadline: System.monotonic_time(:millisecond) + 120_000, work_dir: work],
      extra
    )
  end

  defp video_opts do
    test = self()

    [
      on_duration: fn duration_ms ->
        send(test, {:duration, duration_ms})
        System.monotonic_time(:millisecond) + 120_000
      end,
      on_progress: fn percent -> send(test, {:progress, percent}) end
    ]
  end

  defp put_media(changes) do
    previous = Application.fetch_env!(:espalier, :media)
    Application.put_env(:espalier, :media, Keyword.merge(previous, changes))
    on_exit(fn -> Application.put_env(:espalier, :media, previous) end)
  end

  ## Fixtures

  defp animation(width, height) do
    ["-f", "lavfi", "-i", "testsrc2=s=#{width}x#{height}:r=5", "-frames:v", "3"]
  end

  defp vp9_opus(width, height) do
    [
      "-f",
      "lavfi",
      "-i",
      "testsrc2=s=#{width}x#{height}:r=10",
      "-f",
      "lavfi",
      "-i",
      "sine=f=440:r=48000",
      "-t",
      "2",
      "-c:v",
      "libvpx-vp9",
      "-pix_fmt",
      "yuv420p",
      "-deadline",
      "realtime",
      "-cpu-used",
      "8",
      "-c:a",
      "libopus"
    ]
  end

  defp silent_vp9(width, height) do
    [
      "-f",
      "lavfi",
      "-i",
      "testsrc2=s=#{width}x#{height}:r=10",
      "-t",
      "2",
      "-c:v",
      "libvpx-vp9",
      "-deadline",
      "realtime",
      "-cpu-used",
      "8"
    ]
  end

  defp h264_aac(width, height) do
    [
      "-f",
      "lavfi",
      "-i",
      "testsrc2=s=#{width}x#{height}:r=10",
      "-f",
      "lavfi",
      "-i",
      "sine=f=440:r=44100",
      "-t",
      "2",
      "-c:v",
      "libx264",
      "-preset",
      "ultrafast",
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "aac"
    ]
  end

  defp tiny_vp9(seconds) do
    [
      "-f",
      "lavfi",
      "-i",
      "testsrc2=s=16x16:r=1",
      "-t",
      Integer.to_string(seconds),
      "-c:v",
      "libvpx-vp9",
      "-deadline",
      "realtime",
      "-cpu-used",
      "8"
    ]
  end

  defp mpeg4_without_audio do
    ["-f", "lavfi", "-i", "testsrc2=s=64x48:r=10", "-t", "1", "-c:v", "mpeg4", "-an", "-f", "mp4"]
  end

  # One second of black, then one second of `color`, at 160x90.
  defp black_then(color) do
    "color=c=black:s=160x90:r=10:d=1[a];color=c=#{color}:s=160x90:r=10:d=1[b];" <>
      "[a][b]concat=n=2:v=1:a=0[out0]"
  end

  defp png_claiming(width, height) do
    <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <>
      png_chunk("IHDR", <<width::32, height::32, 8, 2, 0, 0, 0>>) <>
      png_chunk("IDAT", :zlib.compress(:binary.copy(<<0>>, 64))) <> png_chunk("IEND", "")
  end

  defp png_chunk(type, data),
    do: <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>

  defp segment(marker, payload), do: <<0xFF, marker, byte_size(payload) + 2::16, payload::binary>>

  # An APP1 EXIF segment with the tags Make and, optionally, DateTime.
  defp exif(make, date_time) do
    tags =
      [{0x010F, make <> <<0>>}] ++ if(date_time, do: [{0x0132, date_time <> <<0>>}], else: [])

    count = length(tags)
    data_start = 8 + 2 + 12 * count + 4

    {entries, data, _offset} =
      Enum.reduce(tags, {<<>>, <<>>, data_start}, fn {tag, value}, {entries, data, offset} ->
        entry = <<tag::little-16, 2::little-16, byte_size(value)::little-32, offset::little-32>>
        {entries <> entry, data <> value, offset + byte_size(value)}
      end)

    tiff = "II*\0" <> <<8::little-32, count::little-16>> <> entries <> <<0::little-32>> <> data
    segment(0xE1, "Exif\0\0" <> tiff)
  end

  ## ISO BMFF boxes

  @dref_path ["moov", "trak", "mdia", "minf", "dinf", "dref"]

  # Replaces the entries of the dref box with `entry`. ffmpeg writes moov
  # after mdat, so the new sizes move no sample offset.
  defp replace_dref(mp4, entry) do
    rewrite_box(mp4, @dref_path, fn <<version_flags::32, _count::32, _entries::binary>> ->
      <<version_flags::32, 1::32, entry::binary>>
    end)
  end

  defp dref_entries(mp4) do
    {:ok, body} = find_box(mp4, @dref_path)
    <<_version_flags::32, _count::32, entries::binary>> = body
    entries
  end

  defp rewrite_box(<<size::32, type::binary-size(4), rest::binary>>, [name | path] = all, fun) do
    {body, tail} = :erlang.split_binary(rest, size - 8)

    if type == name do
      body = if path == [], do: fun.(body), else: rewrite_box(body, path, fun)
      <<byte_size(body) + 8::32, type::binary, body::binary, tail::binary>>
    else
      <<size::32, type::binary, body::binary, rewrite_box(tail, all, fun)::binary>>
    end
  end

  defp find_box(<<size::32, type::binary-size(4), rest::binary>>, [name | path] = all) do
    {body, tail} = :erlang.split_binary(rest, size - 8)

    cond do
      type == name and path == [] -> {:ok, body}
      type == name -> find_box(body, path)
      true -> find_box(tail, all)
    end
  end

  # A `url ` entry without the self-contained flag.
  defp url_entry(url), do: <<byte_size(url) + 13::32, "url ", 0::32, url::binary, 0>>

  # A Macintosh alias record (`alis`) in the layout that the mov demuxer of
  # ffmpeg reads: volume, file name, one level up and down, and the absolute
  # path `/<name>`, whose last component names a file next to the input.
  defp alias_entry(name) do
    path = "/" <> name
    padding = if rem(byte_size(path), 2) == 1, do: <<0>>, else: <<>>

    payload =
      zeros(10) <>
        <<4>> <>
        pad("Disk", 27) <>
        zeros(12) <>
        <<byte_size(name)>> <>
        pad(name, 63) <>
        zeros(16) <>
        <<1::16, 1::16>> <>
        zeros(16) <>
        <<2::16, byte_size(path)::16, path::binary, padding::binary, 0xFFFF::16, 0::16>>

    <<byte_size(payload) + 12::32, "alis", 0::32, payload::binary>>
  end

  defp zeros(count), do: :binary.copy(<<0>>, count)
  defp pad(text, size), do: text <> zeros(size - byte_size(text))

  ## Network

  defp listen! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    {socket, port}
  end

  defp refute_connection(listener) do
    assert :gen_tcp.accept(listener, 0) == {:error, :timeout}
  end

  defp assert_connection(listener, probe_args) do
    task =
      Task.async(fn ->
        System.cmd(tool("ffprobe"), ["-v", "error", "-rw_timeout", "5000000" | probe_args],
          stderr_to_stdout: true
        )
      end)

    assert {:ok, socket} = :gen_tcp.accept(listener, 10_000)
    :gen_tcp.close(socket)
    Task.await(task, 30_000)
  end

  ## Probes

  defp streams(path) do
    {output, 0} =
      System.cmd(tool("ffprobe"), [
        "-v",
        "error",
        "-show_entries",
        "stream=codec_type,codec_name,pix_fmt",
        "-of",
        "json",
        path
      ])

    for stream <- Jason.decode!(output)["streams"] do
      {stream["codec_type"], stream["codec_name"], stream["pix_fmt"]}
    end
  end

  # The MD5 of every packet of the first stream of `type`, copied without a
  # decoder, so equal lists mean equal bitstreams.
  defp packet_hashes(path, type) do
    {output, 0} =
      System.cmd(tool("ffmpeg"), [
        "-nostdin",
        "-loglevel",
        "error",
        "-i",
        path,
        "-map",
        "0:#{type}:0",
        "-c",
        "copy",
        "-f",
        "framemd5",
        "-"
      ])

    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(&(&1 |> String.split(",") |> List.last() |> String.trim()))
  end

  defp alpha_mode(path) do
    {output, 0} =
      System.cmd(tool("ffprobe"), [
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream_tags=alpha_mode",
        "-of",
        "json",
        path
      ])

    get_in(Jason.decode!(output), ["streams", Access.at(0), "tags", "alpha_mode"])
  end

  defp probe_size(path, extra) do
    {output, 0} =
      System.cmd(
        tool("ffprobe"),
        ["-v", "quiet"] ++
          extra ++ ["-show_entries", "stream=width,height", "-of", "csv=p=0", path]
      )

    String.trim(output)
  end

  ## Files

  defp generate!(dir, name, args) do
    path = Path.join(dir, name)

    {output, status} =
      System.cmd(
        tool("ffmpeg"),
        ["-nostdin", "-hide_banner", "-loglevel", "error", "-y" | args] ++ [path],
        stderr_to_stdout: true
      )

    assert status == 0, output
    path
  end

  defp write!(dir, name, bytes) do
    path = Path.join(dir, name)
    File.write!(path, bytes)
    path
  end

  defp sha256(path), do: :crypto.hash(:sha256, File.read!(path))

  defp tool(name), do: System.find_executable(name) || flunk("#{name} is not on the PATH")
end
