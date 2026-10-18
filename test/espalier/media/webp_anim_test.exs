defmodule Espalier.Media.WebpAnimTest do
  @moduledoc """
  The structural path of animated WebP inputs (task 0018, step 6): files
  that libwebp_anim of the shell writes, every structural fault, a first
  frame smaller than the canvas, and the metadata chunks that the rewrite
  drops. ffprobe 8.1.2 cannot decode an animated WebP, so the tests count
  the ANMF chunks of the rewritten file and decode only the poster.
  """
  use ExUnit.Case, async: true

  import Bitwise

  alias Espalier.Media
  alias Espalier.Media.WebpAnim

  defp structure(binary),
    do: assert(WebpAnim.check(binary) == {:error, {:unsupported_animation, :structure}})

  ## Files from ffmpeg

  defp ffmpeg!(args) do
    {output, status} =
      System.cmd(
        System.find_executable("ffmpeg"),
        ["-nostdin", "-hide_banner", "-v", "error" | args],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  # An animated WebP from a lavfi source, written by libwebp_anim.
  defp animation!(tmp_dir, name, filter, codec_args) do
    path = Path.join(tmp_dir, name <> ".webp")

    ffmpeg!(
      ["-f", "lavfi", "-i", filter, "-c:v", "libwebp_anim"] ++
        codec_args ++ ["-loop", "0", "-f", "webp", "-y", path]
    )

    File.read!(path)
  end

  # Decodes a still WebP with the webp_pipe demuxer into RGBA bytes.
  defp decode_poster!(tmp_dir, poster) do
    input = Path.join(tmp_dir, "poster.webp")
    output = Path.join(tmp_dir, "poster.rgba")
    File.write!(input, poster)

    ffmpeg!(
      ["-f", "webp_pipe", "-i", input, "-frames:v", "1"] ++
        ["-f", "rawvideo", "-pix_fmt", "rgba", "-y", output]
    )

    File.read!(output)
  end

  defp alphas(rgba), do: for(<<_r, _g, _b, a <- rgba>>, uniq: true, do: a)

  ## Chunks

  defp chunks(<<"RIFF", _size::little-32, "WEBP", body::binary>>), do: split_chunks(body)

  defp split_chunks(<<>>), do: []

  defp split_chunks(<<fourcc::binary-4, size::little-32, rest::binary>>) do
    padded = size + rem(size, 2)
    <<payload::binary-size(^size), _pad::binary-size(^padded - ^size), more::binary>> = rest
    [{fourcc, payload} | split_chunks(more)]
  end

  defp chunk(fourcc, payload) do
    pad = if rem(byte_size(payload), 2) == 1, do: <<0>>, else: <<>>
    fourcc <> <<byte_size(payload)::little-32>> <> payload <> pad
  end

  defp riff(chunks) do
    body = "WEBP" <> IO.iodata_to_binary(chunks)
    "RIFF" <> <<byte_size(body)::little-32>> <> body
  end

  defp rebuild(chunks),
    do: riff(Enum.map(chunks, fn {fourcc, payload} -> chunk(fourcc, payload) end))

  defp fourccs(binary), do: Enum.map(chunks(binary), &elem(&1, 0))

  ## Synthetic files: the check reads the headers only, so a bitstream
  ## needs no more than its header.

  defp vp8x(flags, width, height),
    do: chunk("VP8X", <<flags, 0, 0, 0, width - 1::little-24, height - 1::little-24>>)

  defp anim, do: chunk("ANIM", <<255, 255, 255, 255, 0, 0>>)

  defp vp8l(width, height, alpha \\ 0, version \\ 0) do
    bits = width - 1 ||| (height - 1) <<< 14 ||| alpha <<< 28 ||| version <<< 29
    chunk("VP8L", <<0x2F, bits::little-32, 0, 0, 0>>)
  end

  defp vp8(width, height, tag \\ 0x9D012A, frame_tag \\ 0) do
    chunk("VP8 ", <<frame_tag::little-24, tag::24, width::little-16, height::little-16, 0, 0>>)
  end

  defp alph, do: chunk("ALPH", <<0, 1, 2>>)

  defp anmf(x, y, width, height, data) do
    header =
      <<div(x, 2)::little-24, div(y, 2)::little-24, width - 1::little-24, height - 1::little-24,
        100::little-24, 0>>

    chunk("ANMF", header <> IO.iodata_to_binary(data))
  end

  # A 4 by 4 canvas with a full first frame and a 2 by 2 frame at (2, 2).
  defp synthetic(opts \\ []) do
    riff(
      Keyword.get(opts, :head, [vp8x(0x02, 4, 4), anim()]) ++
        Keyword.get(opts, :frames, [
          anmf(0, 0, 4, 4, [vp8l(4, 4)]),
          anmf(2, 2, 2, 2, [vp8l(2, 2, 1)])
        ]) ++
        Keyword.get(opts, :tail, [])
    )
  end

  describe "files from libwebp_anim" do
    @describetag :tmp_dir

    test "a lossy opaque animation passes unchanged with its poster", %{tmp_dir: tmp_dir} do
      source = animation!(tmp_dir, "lossy", "testsrc2=size=64x48:rate=5:duration=1", [])

      assert {:ok, result} = WebpAnim.check(source)
      assert %{width: 64, height: 48, has_alpha: false, frames: 5} = result
      assert result.webp == source
      assert Enum.count(fourccs(result.webp), &(&1 == "ANMF")) == 5

      assert fourccs(result.poster) == ["VP8 "]
      assert byte_size(decode_poster!(tmp_dir, result.poster)) == 64 * 48 * 4
      assert WebpAnim.check(result.webp) == {:ok, result}
    end

    test "a lossy animation with alpha gets an extended poster with ALPH", %{tmp_dir: tmp_dir} do
      filter = "testsrc2=size=32x24:rate=4:duration=1,format=rgba,colorchannelmixer=aa=0.5"
      source = animation!(tmp_dir, "alpha", filter, ["-pix_fmt", "yuva420p"])

      assert {:ok, result} = WebpAnim.check(source)
      assert %{width: 32, height: 24, has_alpha: true, frames: 4} = result
      assert result.webp == source

      assert [{"VP8X", <<0x10, 0, 0, 0, 31::little-24, 23::little-24>>}, {"ALPH", _}, {"VP8 ", _}] =
               chunks(result.poster)

      rgba = decode_poster!(tmp_dir, result.poster)
      assert byte_size(rgba) == 32 * 24 * 4
      assert Enum.any?(alphas(rgba), &(&1 < 255))
    end

    test "lossless animations take has_alpha from the VP8L header of the first frame", %{
      tmp_dir: tmp_dir
    } do
      opaque =
        animation!(tmp_dir, "lossless", "testsrc2=size=40x30:rate=4:duration=1", [
          "-lossless",
          "1"
        ])

      assert {:ok, %{has_alpha: false, frames: 4, poster: poster} = result} =
               WebpAnim.check(opaque)

      assert result.webp == opaque
      assert fourccs(poster) == ["VP8L"]
      assert alphas(decode_poster!(tmp_dir, poster)) == [255]

      filter = "testsrc2=size=40x30:rate=4:duration=1,format=rgba,colorchannelmixer=aa=0.5"
      translucent = animation!(tmp_dir, "lossless_alpha", filter, ["-lossless", "1"])

      assert {:ok, %{has_alpha: true, poster: poster}} = WebpAnim.check(translucent)
      assert fourccs(poster) == ["VP8L"]
      assert Enum.any?(alphas(decode_poster!(tmp_dir, poster)), &(&1 < 255))
    end

    test "ICCP, EXIF and XMP are dropped and their flags cleared", %{tmp_dir: tmp_dir} do
      source = animation!(tmp_dir, "meta", "testsrc2=size=48x32:rate=4:duration=1", [])
      [{"VP8X", <<flags, rest::binary>>} | others] = chunks(source)
      {[anim], frames} = Enum.split(others, 1)

      # ICC, EXIF and XMP flags plus a reserved bit, and odd payload sizes
      # that need a padding byte.
      tagged =
        rebuild(
          [{"VP8X", <<flags ||| 0x20 ||| 0x08 ||| 0x04 ||| 0x01, rest::binary>>}] ++
            [{"ICCP", "icc profile of a sample camera"}, anim] ++
            frames ++
            [
              {"EXIF", "Exif\0\0GPS 51.0N 13.7E serial 0042"},
              {"XMP ", "<x:xmpmeta>sample</x:xmpmeta>"}
            ]
        )

      assert {:ok, result} = WebpAnim.check(tagged)
      assert result.webp == source
      assert result.frames == 4
      refute result.webp =~ "GPS"

      only_exif =
        rebuild(
          [{"VP8X", <<flags ||| 0x08, rest::binary>>}, anim] ++ frames ++ [{"EXIF", "Exif"}]
        )

      assert {:ok, %{webp: ^source}} = WebpAnim.check(only_exif)

      only_xmp =
        rebuild([{"VP8X", <<flags ||| 0x04, rest::binary>>}, anim] ++ frames ++ [{"XMP ", "x"}])

      assert {:ok, %{webp: ^source}} = WebpAnim.check(only_xmp)
    end

    test "binary edits of a real file answer structure", %{tmp_dir: tmp_dir} do
      source = animation!(tmp_dir, "edit", "testsrc2=size=48x32:rate=4:duration=1", [])
      <<"RIFF", riff_size::little-32, body::binary>> = source

      # RIFF size larger and smaller than the file.
      structure("RIFF" <> <<riff_size + 2::little-32>> <> body)
      structure("RIFF" <> <<riff_size - 2::little-32>> <> body)

      # A truncated file whose RIFF size matches its length.
      cut = binary_part(body, 0, byte_size(body) - 10)
      structure("RIFF" <> <<byte_size(cut)::little-32>> <> cut)

      # Bytes after the last chunk.
      structure("RIFF" <> <<riff_size + 2::little-32>> <> body <> <<0, 0>>)

      # An unknown chunk between the frames.
      [vp8x, anim | frames] = chunks(source)
      structure(rebuild([vp8x, anim, {"ABCD", "x"} | frames]))

      # The width of the first frame changed, so the VP8 header no longer
      # matches the frame size.
      [{"ANMF", <<head::binary-6, width::little-24, tail::binary>>} | others] = frames

      structure(
        rebuild([
          vp8x,
          anim,
          {"ANMF", <<head::binary, width - 1::little-24, tail::binary>>} | others
        ])
      )
    end
  end

  describe "structure" do
    test "the synthetic file passes" do
      assert {:ok, %{width: 4, height: 4, frames: 2, has_alpha: false} = result} =
               WebpAnim.check(synthetic())

      assert fourccs(result.webp) == ["VP8X", "ANIM", "ANMF", "ANMF"]
      assert fourccs(result.poster) == ["VP8L"]
    end

    test "the RIFF header and the chunk lengths must fit" do
      structure("")
      structure("RIFF")
      structure(<<"RIFX", 4::little-32, "WEBP">>)
      structure(<<"RIFF", 4::little-32, "WAVE">>)
      structure(<<"RIFF", 4::little-32, "WEBP">>)

      # An odd chunk length without its padding byte.
      <<"RIFF", _size::little-32, body::binary>> =
        synthetic(frames: [anmf(0, 0, 4, 4, [vp8l(4, 4)])])

      odd = body <> "EXIF" <> <<1::little-32>> <> "x"
      structure("RIFF" <> <<byte_size(odd)::little-32>> <> odd)

      # A chunk length beyond the end of the file.
      long = body <> "EXIF" <> <<100::little-32>> <> "xx"
      structure("RIFF" <> <<byte_size(long)::little-32>> <> long)
    end

    test "the chunks must follow VP8X, ICCP, ANIM, ANMF, EXIF, XMP" do
      frame = anmf(0, 0, 4, 4, [vp8l(4, 4)])
      iccp = chunk("ICCP", "icc")
      exif = chunk("EXIF", "exif")
      xmp = chunk("XMP ", "xmp")

      assert {:ok, _result} =
               WebpAnim.check(riff([vp8x(0x02, 4, 4), iccp, anim(), frame, exif, xmp]))

      for chunks <- [
            [anim(), vp8x(0x02, 4, 4), frame],
            [vp8x(0x02, 4, 4), vp8x(0x02, 4, 4), anim(), frame],
            [vp8x(0x02, 4, 4), anim(), iccp, frame],
            [vp8x(0x02, 4, 4), frame, anim()],
            [vp8x(0x02, 4, 4), anim(), anim(), frame],
            [vp8x(0x02, 4, 4), anim(), exif, frame],
            [vp8x(0x02, 4, 4), anim(), frame, xmp, exif],
            [vp8x(0x02, 4, 4), anim(), frame, exif, exif],
            [vp8x(0x02, 4, 4), anim(), frame, anim()],
            # EXIF and XMP before ANIM, which would end the walk without a
            # frame, and files that end before their first frame.
            [vp8x(0x02, 4, 4), exif],
            [vp8x(0x02, 4, 4), iccp, exif],
            [vp8x(0x02, 4, 4), exif, xmp],
            [vp8x(0x02, 4, 4), iccp, exif, anim(), frame],
            [vp8x(0x02, 4, 4), xmp],
            [vp8x(0x02, 4, 4), iccp, xmp],
            [vp8x(0x02, 4, 4), anim(), xmp],
            [vp8x(0x02, 4, 4)],
            [vp8x(0x02, 4, 4), iccp],
            [vp8x(0x02, 4, 4), iccp, anim()],
            [vp8x(0x02, 4, 4), anim()],
            [vp8x(0x02, 4, 4), anim(), frame, chunk("ABCD", "")],
            [vp8x(0x02, 4, 4), anim(), vp8l(4, 4)],
            [vp8l(4, 4)]
          ] do
        structure(riff(chunks))
      end
    end

    test "VP8X needs 10 bytes with the animation flag, and ANIM 6 bytes" do
      structure(synthetic(head: [vp8x(0x10, 4, 4), anim()]))

      structure(
        synthetic(
          head: [chunk("VP8X", <<0x02, 0, 0, 0, 3::little-24, 3::little-24, 0, 0>>), anim()]
        )
      )

      structure(synthetic(head: [vp8x(0x02, 4, 4), chunk("ANIM", <<0, 0, 0, 0, 0>>)]))
    end

    test "a canvas above max_input_pixels answers structure" do
      width = 10_000
      height = div(Media.max_input_pixels(), width) + 1
      structure(synthetic(head: [vp8x(0x02, width, height), anim()]))
    end

    test "every frame rectangle must lie within the canvas" do
      structure(
        synthetic(frames: [anmf(0, 0, 4, 4, [vp8l(4, 4)]), anmf(4, 0, 2, 2, [vp8l(2, 2)])])
      )

      structure(
        synthetic(frames: [anmf(0, 0, 4, 4, [vp8l(4, 4)]), anmf(0, 2, 2, 4, [vp8l(2, 4)])])
      )

      structure(synthetic(frames: [anmf(0, 0, 6, 4, [vp8l(6, 4)])]))
    end

    test "every ANMF holds one VP8 or VP8L chunk, optionally after ALPH before VP8" do
      assert {:ok, %{has_alpha: true, poster: poster}} =
               WebpAnim.check(synthetic(frames: [anmf(0, 0, 4, 4, [alph(), vp8(4, 4)])]))

      assert [{"VP8X", <<0x10, _::binary>>}, {"ALPH", _}, {"VP8 ", _}] = chunks(poster)

      for data <- [
            [],
            [alph()],
            [vp8(4, 4), alph()],
            [alph(), vp8l(4, 4)],
            [vp8l(4, 4), vp8l(4, 4)],
            [vp8(4, 4), vp8(4, 4)],
            [vp8l(4, 4), chunk("ABCD", "")],
            [chunk("ABCD", ""), vp8l(4, 4)]
          ] do
        structure(synthetic(frames: [anmf(0, 0, 4, 4, data)]))
      end

      structure(synthetic(frames: [chunk("ANMF", <<0::size(15)-unit(8)>>)]))
    end

    test "the bitstream header must name the frame size and a valid frame" do
      for data <- [
            [vp8l(4, 3)],
            [vp8l(3, 4)],
            [vp8(4, 3)],
            [vp8l(4, 4, 0, 1)],
            [vp8(4, 4, 0x9D012B)],
            [vp8(4, 4, 0x9D012A, 1)],
            [chunk("VP8L", <<0x2E, 0::32>>)],
            [chunk("VP8 ", <<0, 0, 0, 0x9D, 0x01>>)]
          ] do
        structure(synthetic(frames: [anmf(0, 0, 4, 4, data)]))
      end

      # The 2 scale bits of a VP8 size are no part of the size.
      assert {:ok, _result} =
               WebpAnim.check(
                 synthetic(frames: [anmf(0, 0, 4, 4, [vp8(4 ||| 0x4000, 4 ||| 0xC000)])])
               )
    end

    test "more than max_frames frames answer too_many_frames" do
      small = anmf(2, 2, 2, 2, [vp8l(2, 2)])
      first = anmf(0, 0, 4, 4, [vp8l(4, 4)])
      max = Media.max_frames()

      assert {:ok, %{frames: ^max}} =
               WebpAnim.check(synthetic(frames: [first | List.duplicate(small, max - 1)]))

      assert WebpAnim.check(synthetic(frames: [first | List.duplicate(small, max)])) ==
               {:error, {:unsupported_animation, :too_many_frames}}
    end

    # libwebp crops even the first frame against a transparent canvas (step 1
    # of task 0018), so such a file passes, and its poster is an animated
    # WebP with that single frame, which needs no decoder.
    test "a first frame that does not cover the canvas gives a one-frame animated poster" do
      for first <- [
            anmf(0, 0, 2, 2, [vp8l(2, 2)]),
            anmf(2, 0, 2, 4, [vp8l(2, 4)]),
            anmf(0, 0, 4, 2, [vp8(4, 2)])
          ] do
        assert {:ok, result} =
                 WebpAnim.check(synthetic(frames: [first, anmf(0, 0, 4, 4, [vp8l(4, 4)])]))

        assert %{width: 4, height: 4, has_alpha: true, frames: 2} = result

        assert <<"RIFF", _size::little-32, "WEBP", "VP8X", 10::little-32, flags, _rest::binary>> =
                 result.poster

        assert Bitwise.band(flags, 0x12) == 0x12
        assert :binary.matches(result.poster, "ANMF") |> length() == 1
        assert {:ok, %{frames: 1}} = WebpAnim.check(result.poster)
      end
    end
  end
end
