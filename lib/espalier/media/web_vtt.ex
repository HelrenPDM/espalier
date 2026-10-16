defmodule Espalier.Media.WebVtt do
  @moduledoc """
  The check of a WebVTT captions file (task 0018, step 6).

  `check/1` reads the bytes and changes nothing; the caller stores them
  unchanged. A file above `Espalier.Media.captions_max_bytes/0` answers
  `too_large`, a file that is no valid UTF-8 answers `encoding`, and a file
  that holds U+0000 answers `nul`. The file must start, after an optional
  byte order mark, with `WEBVTT` followed by a space, a tab, a line break or
  the end (`header`).

  The lines are split at CR LF, LF and CR. The blocks follow the parser of
  the WebVTT specification (W3C Candidate Recommendation): the header block
  ends at the first empty line or at the first line that holds `-->`, and
  every later block ends at an empty line. A block whose first line holds
  `-->`, or whose second line does while its first does not, is a cue, and
  a later line with `-->` starts the next block, as it does in a browser.
  The cue timing line must read `<start> --> <end>` with optional cue
  settings after white space, each time as `hh:mm:ss.ttt` or `mm:ss.ttt`
  with two digits for hours, minutes and seconds, minutes and seconds below
  60, and the start before the end (`timing`). Two digits for hours cover
  99 hours, far beyond the longest video.

  A block that starts with `STYLE` answers `style`, so no captions file
  brings CSS to the player. Blocks that start with `NOTE` or `REGION` are
  allowed. Any other block is no cue without a timing line and answers
  `timing`, because the browsers would drop it without notice. More than
  10,000 cues answer `too_many_cues`.

  `duration_ms` is the end of the cue that ends last, or 0 for a file
  without cues.
  """

  alias Espalier.Media

  @typedoc "The reason tags of a rejected captions file."
  @type tag :: :too_large | :encoding | :nul | :header | :too_many_cues | :timing | :style

  @max_cues 10_000

  @timestamp "(?:([0-9]{2}):)?([0-5][0-9]):([0-5][0-9])\\.([0-9]{3})"
  @timing Regex.compile!("\\A#{@timestamp}[ \\t]*-->[ \\t]*#{@timestamp}(?:[ \\t].*)?\\z")

  @doc """
  Checks a WebVTT file and returns its duration, or the reason tag of the
  rejection.
  """
  @spec check(binary()) ::
          {:ok, %{duration_ms: non_neg_integer()}} | {:error, {:invalid_captions, tag()}}
  def check(binary) when is_binary(binary) do
    with :ok <- check_bytes(binary),
         {:ok, lines} <- header(binary),
         {:ok, duration_ms} <- blocks(lines, 0, 0) do
      {:ok, %{duration_ms: duration_ms}}
    else
      {:error, tag} -> {:error, {:invalid_captions, tag}}
    end
  end

  defp check_bytes(binary) do
    cond do
      byte_size(binary) > Media.captions_max_bytes() -> {:error, :too_large}
      not String.valid?(binary) -> {:error, :encoding}
      String.contains?(binary, <<0>>) -> {:error, :nul}
      true -> :ok
    end
  end

  # The lines after the header block.
  defp header(binary) do
    text =
      case binary do
        "\uFEFF" <> rest -> rest
        text -> text
      end

    case String.split(text, ~r/\r\n|\r|\n/) do
      ["WEBVTT" | lines] -> {:ok, skip_header(lines)}
      ["WEBVTT" <> <<c, _rest::binary>> | lines] when c in [?\s, ?\t] -> {:ok, skip_header(lines)}
      _other -> {:error, :header}
    end
  end

  defp skip_header(lines), do: Enum.drop_while(lines, &(&1 != "" and not arrow?(&1)))

  defp blocks([], _cues, duration_ms), do: {:ok, duration_ms}
  defp blocks(["" | lines], cues, duration_ms), do: blocks(lines, cues, duration_ms)

  defp blocks([first | lines], cues, duration_ms) do
    case block(first, lines) do
      {:cue, timing, rest} ->
        with :ok <- check_cue_count(cues + 1),
             {:ok, end_ms} <- timing(timing) do
          blocks(rest, cues + 1, max(duration_ms, end_ms))
        end

      {:other, rest} ->
        with :ok <- other_block(first), do: blocks(rest, cues, duration_ms)
    end
  end

  # A block is a cue when its first line holds "-->", or when its second
  # line does while its first does not; otherwise it runs to the next empty
  # line or to the next line with "-->".
  defp block(first, lines) do
    if arrow?(first), do: {:cue, first, payload(lines)}, else: second_line(lines)
  end

  defp second_line([second | rest] = lines) do
    cond do
      arrow?(second) -> {:cue, second, payload(rest)}
      second == "" -> {:other, lines}
      true -> {:other, payload(rest)}
    end
  end

  defp second_line([]), do: {:other, []}

  defp payload(lines), do: Enum.drop_while(lines, &(&1 != "" and not arrow?(&1)))

  defp arrow?(line), do: String.contains?(line, "-->")

  defp check_cue_count(count) when count > @max_cues, do: {:error, :too_many_cues}
  defp check_cue_count(_count), do: :ok

  defp other_block(first) do
    cond do
      keyword?(first, "STYLE") -> {:error, :style}
      keyword?(first, "NOTE") or keyword?(first, "REGION") -> :ok
      true -> {:error, :timing}
    end
  end

  # The keyword alone on the line or followed by a space or a tab.
  defp keyword?(line, keyword) do
    line == keyword or String.starts_with?(line, [keyword <> " ", keyword <> "\t"])
  end

  defp timing(line) do
    case Regex.run(@timing, line, capture: :all_but_first) do
      [h1, m1, s1, ms1, h2, m2, s2, ms2 | _settings] ->
        start_ms = milliseconds(h1, m1, s1, ms1)
        end_ms = milliseconds(h2, m2, s2, ms2)
        if start_ms < end_ms, do: {:ok, end_ms}, else: {:error, :timing}

      _other ->
        {:error, :timing}
    end
  end

  defp milliseconds(hours, minutes, seconds, millis) do
    hours = if hours == "", do: 0, else: String.to_integer(hours)

    ((hours * 60 + String.to_integer(minutes)) * 60 + String.to_integer(seconds)) * 1000 +
      String.to_integer(millis)
  end
end
