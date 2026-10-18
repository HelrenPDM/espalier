defmodule Espalier.Media.WebVttTest do
  @moduledoc """
  The captions check of task 0018, step 6: size, encoding, U+0000, the
  header, the cue count, the cue timing lines and the block kinds.
  """
  use ExUnit.Case, async: true

  alias Espalier.Media
  alias Espalier.Media.WebVtt

  defp duration(text) do
    assert {:ok, %{duration_ms: duration_ms}} = WebVtt.check(text)
    duration_ms
  end

  defp rejects(text) do
    assert {:error, {:invalid_captions, tag}} = WebVtt.check(text)
    tag
  end

  defp cue(start, stop, text \\ "Caption"), do: "#{start} --> #{stop}\n#{text}\n\n"

  describe "valid files" do
    test "a file with cues answers the end of the cue that ends last" do
      text =
        "WEBVTT\n\n" <>
          cue("00:00.000", "00:02.500") <>
          "intro\n" <>
          cue("00:01.000", "00:04.250", "Second line one\nSecond line two") <>
          cue("00:03.000", "00:03.900")

      assert duration(text) == 4250
    end

    test "hours, identifiers and cue settings are accepted" do
      text =
        "WEBVTT - English captions\n\n" <>
          "1\n01:02:03.004 --> 01:02:05.000 align:start position:10% line:0\nText\n\n" <>
          "cue-2\n01:02:05.000-->01:02:06.000\tvertical:rl\nText\n"

      assert duration(text) == ((1 * 60 + 2) * 60 + 6) * 1000
    end

    test "a byte order mark, a tab after the signature and CR LF or CR line ends are accepted" do
      assert duration("\uFEFFWEBVTT\r\n\r\n00:01.000 --> 00:02.000\r\nHi\r\n") == 2000
      assert duration("WEBVTT\tcaptions\r\r00:01.000 --> 00:03.000\rHi\r") == 3000
    end

    test "a file without cues has a duration of 0" do
      assert duration("WEBVTT") == 0
      assert duration("WEBVTT\n") == 0
      assert duration("WEBVTT\nKind: captions\nLanguage: en\n\n") == 0
    end

    test "NOTE and REGION blocks are allowed, also with text on their first line" do
      text =
        "WEBVTT\n\n" <>
          "NOTE\nThis note spans\ntwo lines\n\n" <>
          "NOTE written by the example team\n\n" <>
          "REGION\nid:fred\nwidth:40%\n\n" <>
          cue("00:00.500", "00:01.000")

      assert duration(text) == 1000
    end

    test "a cue right after the header lines starts without an empty line" do
      assert duration("WEBVTT\nKind: captions\n00:00.000 --> 00:05.000\nHi\n") == 5000
    end

    test "a line with an arrow inside a cue payload starts the next cue" do
      text = "WEBVTT\n\n00:00.000 --> 00:01.000\nHi\n00:02.000 --> 00:07.000\nThere\n"
      assert duration(text) == 7000

      assert rejects("WEBVTT\n\n00:00.000 --> 00:01.000\nHi\n00:02.000 --> 00:01.000\n") ==
               :timing
    end

    test "the check changes no byte and returns no text" do
      text = "WEBVTT\n\n" <> cue("00:00.000", "00:01.000", "<b>Bold</b> &amp; <c.yellow>text</c>")
      assert WebVtt.check(text) == {:ok, %{duration_ms: 1000}}
    end
  end

  describe "rejections" do
    test "a file above captions_max_bytes answers too_large" do
      text = "WEBVTT\n\nNOTE " <> String.duplicate("x", Media.captions_max_bytes())
      assert rejects(text) == :too_large
    end

    test "invalid UTF-8 answers encoding and U+0000 answers nul" do
      assert rejects("WEBVTT\n\n" <> cue("00:00.000", "00:01.000", <<0xC3, 0x28>>)) == :encoding
      assert rejects("WEBVTT\n\n" <> cue("00:00.000", "00:01.000", "a\0b")) == :nul
    end

    test "a missing or malformed header answers header" do
      for text <- [
            "",
            "WEBVT",
            "WEBVTTX\n",
            "webvtt\n",
            " WEBVTT\n",
            "\n\nWEBVTT\n",
            "\uFEFF\uFEFFWEBVTT\n",
            "00:00.000 --> 00:01.000\nHi\n"
          ] do
        assert rejects(text) == :header, inspect(text)
      end
    end

    test "more than 10,000 cues answer too_many_cues" do
      cues = String.duplicate("00:00.000 --> 00:00.001\n\n", 10_000)
      assert duration("WEBVTT\n\n" <> cues) == 1
      assert rejects("WEBVTT\n\n" <> cues <> "00:00.000 --> 00:00.001\n") == :too_many_cues
    end

    test "a timing line that does not parse answers timing" do
      for timing <- [
            "00:01.000 --> 00:01.000",
            "00:02.000 --> 00:01.000",
            "0:01.000 --> 00:02.000",
            "00:01.00 --> 00:02.000",
            "00:01,000 --> 00:02.000",
            "00:60.000 --> 01:00.000",
            "60:00.000 --> 61:00.000",
            "100:00:00.000 --> 100:00:01.000",
            "00:01.000 --> 00:02.000align:start",
            "00:01.000 --> ",
            "--> 00:02.000",
            "00:01.000 -> 00:02.000 -->"
          ] do
        assert rejects("WEBVTT\n\n#{timing}\nText\n") == :timing, timing
      end
    end

    test "a block that is no cue, no NOTE and no REGION answers timing" do
      assert rejects("WEBVTT\n\n1\n00:01.000 - 00:02.000\nText\n") == :timing
      assert rejects("WEBVTT\n\nNOTES are not notes\n") == :timing
      assert rejects("WEBVTT\n\n" <> cue("00:00.000", "00:01.000") <> "stray text\n") == :timing
    end

    test "a STYLE block answers style" do
      assert rejects("WEBVTT\n\nSTYLE\n::cue { color: red }\n\n" <> cue("00:00.000", "00:01.000")) ==
               :style

      assert rejects("WEBVTT\n\n" <> cue("00:00.000", "00:01.000") <> "STYLE ::cue {}\n") ==
               :style
    end
  end
end
