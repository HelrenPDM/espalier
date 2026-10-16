defmodule Espalier.Media.Ffmpeg do
  @moduledoc """
  The arguments of every ffmpeg and ffprobe call of the media processors
  (task 0018, step 5), and the check of the installed tools.

  Every call starts with `-nostdin -hide_banner -loglevel error -max_alloc
  536870912 -filter_threads <N>`, gives its input as `-threads <N>
  -protocol_whitelist file -f <format> -i <path>` with `-max_pixels` before
  `-i`, and repeats `-threads <N>` among the output options before an
  explicit output format and the output path (N = `MEDIA_FFMPEG_THREADS`).
  `-protocol_whitelist file` and the forced input format keep ffmpeg from
  following a playlist, a data reference or a concat list to the network or
  to another local file (ASVS 1.3.6), and `mov` inputs add `-enable_drefs
  0`.

  The arguments are lists. A filter expression such as
  `scale=-2:'min(ih,1080)'` is one element, and its quotes belong to the
  filtergraph syntax of ffmpeg; no shell reads the arguments. Every path
  comes from `Espalier.Media.Store`, built from a UUID or a SHA-256 hex
  digest, and every number from the configuration; no title, file name or
  other string from a request reaches these lists (ASVS 1.2.5).
  """

  alias Espalier.Media

  @max_alloc "536870912"

  @encoders ["libvpx-vp9", "libopus", "libwebp", "libwebp_anim"]
  @demuxers ["mov", "matroska", "png_pipe", "jpeg_pipe", "webp_pipe", "gif", "apng"]
  @oldest {7, 1}

  @typedoc "An input format that `Espalier.Media.Sniff` detects."
  @type format :: String.t()

  ## Arguments

  @doc """
  The arguments of the probe of `path` with the forced `format`, which
  writes its JSON to `json_path`. `max_pixels` is the pixel limit of the
  kind.
  """
  @spec probe_args(Path.t(), format(), pos_integer(), Path.t()) :: [String.t()]
  def probe_args(path, format, max_pixels, json_path) do
    ["-v", "error", "-max_alloc", @max_alloc, "-threads", threads()] ++
      ["-protocol_whitelist", "file", "-f", format, "-max_pixels", Integer.to_string(max_pixels)] ++
      mov_input(format) ++
      [
        "-count_packets",
        "-show_entries",
        "stream=index,codec_type,codec_name,width,height,pix_fmt,nb_read_packets,duration:" <>
          "stream_tags=alpha_mode:format=duration,nb_streams",
        "-of",
        "json",
        "-o",
        json_path,
        path
      ]
  end

  @doc """
  The arguments of the conversion of a still image to WebP. `lossless`
  selects `-lossless 1 -compression_level 6`, otherwise `-quality 82`.
  `filters` precede the scale filter, such as a `transpose` for the
  orientation of a JPEG.
  """
  @spec still_image_args(Path.t(), format(), Path.t(), keyword()) :: [String.t()]
  def still_image_args(input, format, output, opts \\ []) do
    codec =
      if Keyword.get(opts, :lossless, false),
        do: ["-c:v", "libwebp", "-lossless", "1", "-compression_level", "6"],
        else: ["-c:v", "libwebp", "-quality", Integer.to_string(Keyword.get(opts, :quality, 82))]

    common() ++
      image_input(input, format) ++
      ["-frames:v", "1", "-map_metadata", "-1", "-vf", image_filter(opts)] ++
      codec ++ output(output, "webp")
  end

  @doc "The arguments of the conversion of an animated GIF or APNG to an animated WebP."
  @spec animated_image_args(Path.t(), format(), Path.t()) :: [String.t()]
  def animated_image_args(input, format, output) do
    common() ++
      image_input(input, format) ++
      ["-map_metadata", "-1", "-vf", image_filter([])] ++
      ["-c:v", "libwebp_anim", "-loop", "0", "-quality", "80"] ++ output(output, "webp")
  end

  @doc "The arguments of the poster of an animated image: its first frame as a still WebP."
  @spec image_poster_args(Path.t(), format(), Path.t()) :: [String.t()]
  def image_poster_args(input, format, output) do
    common() ++
      image_input(input, format) ++
      ["-frames:v", "1", "-map_metadata", "-1", "-vf", image_filter([])] ++
      ["-c:v", "libwebp", "-quality", "80"] ++ output(output, "webp")
  end

  @doc """
  The arguments of the remux of a Matroska input with VP9 and Opus to WebM,
  without a new encoding.
  """
  @spec remux_args(Path.t(), Path.t()) :: [String.t()]
  def remux_args(input, output) do
    common() ++
      video_input(input, "matroska") ++
      ["-map", "0:v:0", "-map", "0:a:0?", "-c", "copy", "-map_metadata", "-1"] ++
      ["-map_chapters", "-1"] ++ output(output, "webm")
  end

  @doc """
  The arguments of the conversion of a video to WebM with VP9 and Opus,
  with progress lines on standard output.
  """
  @spec video_args(Path.t(), format(), Path.t()) :: [String.t()]
  def video_args(input, format, output) do
    height = Integer.to_string(Media.video_max_height())

    common() ++
      video_input(input, format) ++
      ["-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn", "-map_metadata", "-1"] ++
      ["-map_chapters", "-1"] ++
      ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-deadline", "good", "-cpu-used", "4"] ++
      ["-row-mt", "1", "-g", "240", "-pix_fmt", "yuv420p", "-vf", "scale=-2:'min(ih,#{height})'"] ++
      ["-c:a", "libopus", "-b:a", "96k", "-ac", "2"] ++
      ["-progress", "pipe:1", "-nostats"] ++ output(output, "webm")
  end

  @doc """
  The arguments of the poster of a video: the frame at `seconds` of the
  delivery file, without a scale filter, so it has the size of the video.
  """
  @spec video_poster_args(Path.t(), float(), Path.t()) :: [String.t()]
  def video_poster_args(input, seconds, output) do
    common() ++
      ["-ss", :erlang.float_to_binary(seconds / 1, decimals: 3)] ++
      video_input(input, "matroska") ++
      ["-frames:v", "1", "-map_metadata", "-1", "-c:v", "libwebp", "-quality", "80"] ++
      output(output, "webp")
  end

  defp common do
    ["-nostdin", "-hide_banner", "-loglevel", "error", "-max_alloc", @max_alloc] ++
      ["-filter_threads", threads()]
  end

  defp image_input(path, format) do
    ["-threads", threads(), "-protocol_whitelist", "file", "-f", format] ++
      ["-max_pixels", Integer.to_string(Media.max_input_pixels()), "-i", path]
  end

  defp video_input(path, format) do
    ["-threads", threads(), "-protocol_whitelist", "file", "-f", format] ++
      mov_input(format) ++
      ["-max_pixels", Integer.to_string(Media.max_video_pixels()), "-i", path]
  end

  defp mov_input("mov"), do: ["-enable_drefs", "0"]
  defp mov_input(_format), do: []

  defp output(path, format), do: ["-threads", threads(), "-f", format, "-y", path]

  defp image_filter(opts) do
    edge = Integer.to_string(Media.image_max_edge())

    scale =
      "scale='min(iw,#{edge})':'min(ih,#{edge})':force_original_aspect_ratio=decrease"

    Enum.join(Keyword.get(opts, :filters, []) ++ [scale], ",")
  end

  defp threads, do: Integer.to_string(Media.ffmpeg_threads())

  ## Tool check

  @doc """
  Checks the tools of the media processing for the boot check of task 0017
  (step 2): finds `ffmpeg`, `ffprobe` and `timeout`, runs `ffmpeg
  -hide_banner -version`, `-encoders` and `-demuxers` once in
  `System.tmp_dir!/0`, and returns one message per missing piece, or `[]`.
  ffmpeg 7.1, the release of Debian trixie, is the oldest one supported.
  """
  @spec check() :: [String.t()]
  def check do
    missing =
      for tool <- ["ffmpeg", "ffprobe", "timeout"], System.find_executable(tool) == nil do
        "#{tool} is not installed"
      end

    if System.find_executable("ffmpeg") do
      missing ++ ffmpeg_messages()
    else
      missing
    end
  end

  defp ffmpeg_messages do
    with {:ok, version} <- ffmpeg(["-version"]),
         {:ok, encoders} <- ffmpeg(["-encoders"]),
         {:ok, demuxers} <- ffmpeg(["-demuxers"]) do
      version_message(version) ++
        for(
          encoder <- @encoders,
          encoder not in listed(encoders),
          do: "ffmpeg lacks the encoder #{encoder}"
        ) ++
        for demuxer <- @demuxers, demuxer not in listed(demuxers) do
          "ffmpeg lacks the demuxer #{demuxer}"
        end
    else
      {:error, status} -> ["ffmpeg exits with status #{status}"]
    end
  end

  # The executable comes from System.find_executable/1 and the arguments are
  # fixed; no shell reads them.
  # sobelow_skip ["CI.System"]
  defp ffmpeg(args) do
    case System.cmd(System.find_executable("ffmpeg"), ["-hide_banner" | args],
           cd: System.tmp_dir!(),
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {_output, status} -> {:error, status}
    end
  end

  defp version_message(output) do
    case Regex.run(~r/ffmpeg version n?(\d+)\.(\d+)/, output) do
      [_match, major, minor] ->
        version = {String.to_integer(major), String.to_integer(minor)}

        if version < @oldest,
          do: ["ffmpeg #{major}.#{minor} is older than 7.1"],
          else: []

      nil ->
        ["ffmpeg reports no release version"]
    end
  end

  # The names of the codec and format lists: the second column of each
  # entry line, split at commas ("matroska,webm").
  defp listed(output) do
    output
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case String.split(String.trim(line), ~r/\s+/, parts: 3) do
        [flags, names | _rest] when byte_size(flags) in 1..6 -> String.split(names, ",")
        _other -> []
      end
    end)
  end
end
