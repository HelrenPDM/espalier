defmodule Espalier.Media.Processor do
  @moduledoc """
  The processors of the media kinds (task 0018, step 6). Each takes the
  incoming file and its detection, writes its outputs into the work
  directory of the job, and returns the delivery file, an optional poster
  and the facts of the asset, or a failure code with a reason tag.

    * Images become WebP. A still image converts with ffmpeg, losslessly
      for PNG, GIF and lossless WebP inputs and at quality 82 for JPEG and
      lossy WebP inputs, at most `MEDIA_IMAGE_MAX_EDGE` pixels per edge and
      without metadata. An animated GIF or APNG with at most `max_frames`
      frames converts to an animated WebP, and its first frame becomes the
      poster. An animated WebP takes the structural path of
      `Espalier.Media.WebpAnim`, because no supported ffmpeg build decodes
      one. Width, height and alpha come from the WebP header of the delivery
      file (`Espalier.Media.Sniff.webp_info/1`).
    * SVG files are rebuilt from an allowlist by `Espalier.Media.Svg`. A
      rebuilt file above `svg_max_bytes` fails with `invalid_svg` and the
      reason `too_large`, as an input above that limit does.
    * Captions pass `Espalier.Media.WebVtt` and are stored unchanged.
    * Videos become WebM with VP9 and Opus at most `MEDIA_VIDEO_MAX_HEIGHT`
      high, or are remuxed without a new encoding when they are VP9 and
      Opus in Matroska already. The poster is the frame at `min(1 s,
      duration / 10)` of the delivery file, and the facts come from a probe
      of the delivery file.

  Every command receives the time that remains until the deadline of the
  job (`deadline`, in `System.monotonic_time(:millisecond)`). Before each
  command, and before it writes the output of the SVG rebuild, the captions
  check or the structural check of an animated WebP, a processor asks the
  option `:proceed`, so that a job whose asset was deleted meanwhile stops
  between two steps.
  """

  alias Espalier.Media
  alias Espalier.Media.{Command, Ffmpeg, Sniff, Svg, WebpAnim, WebVtt}

  @typedoc "The outputs of a processor."
  @type outputs :: %{
          delivery: Path.t(),
          ext: String.t(),
          poster: Path.t() | nil,
          facts: %{
            width: pos_integer() | nil,
            height: pos_integer() | nil,
            duration_ms: non_neg_integer() | nil,
            has_audio: boolean(),
            animated: boolean(),
            has_alpha: boolean()
          }
        }

  @typedoc """
  A failure: the code of step 8 and an optional reason tag, or
  `{:error, :cancelled, nil}` when a command was cancelled
  (`Espalier.Media.Command.cancel/1`).
  """
  @type failure :: {:error, atom(), atom() | nil}

  @max_pixels_message ~r/exceeds specified max pixel count/

  @doc """
  Runs the processor of `kind` on `incoming` with the `detection` of
  `Espalier.Media.Sniff.detect/2`. `opts` take `:deadline`, the monotonic
  deadline in milliseconds, `:work_dir`, and for videos `:on_progress`,
  called with the percentage of the conversion, and `:on_duration`, called
  with the duration once the probe knows it so that the caller can extend
  the deadline, and `:proceed`, a function without arguments that answers
  `:ok` or `:halt`. An answer `:halt` of `:on_progress` stops the
  conversion, and a cancelled command or an answer `:halt` of `:proceed`
  ends the processor with `{:error, :cancelled, nil}`.
  """
  @spec run(Media.kind(), Path.t(), Sniff.detection(), keyword()) :: {:ok, outputs()} | failure()
  def run(:image, incoming, detection, opts), do: image(incoming, detection, opts)
  def run(:svg, incoming, _detection, opts), do: svg(incoming, opts)
  def run(:captions, incoming, _detection, opts), do: captions(incoming, opts)
  def run(:video, incoming, detection, opts), do: video(incoming, detection, opts)

  ## Images

  # The incoming file comes from Espalier.Media.Store.
  # sobelow_skip ["Traversal.FileModule"]
  defp image(incoming, %{format: "webp_pipe", animated: true}, opts) do
    case WebpAnim.check(File.read!(incoming)) do
      {:ok, animation} ->
        with :ok <- proceed(opts), do: animation_outputs(animation, opts)

      {:error, {:unsupported_animation, tag}} ->
        {:error, :unsupported_animation, tag}
    end
  end

  defp image(incoming, %{format: format}, opts) do
    with {:ok, probe} <- probe(incoming, format, Media.max_input_pixels(), opts) do
      frames = frame_count(probe)

      # Only a GIF or an APNG is an animation; a JPEG or PNG stream with
      # further images converts its first image.
      animation? = frames > 1 and format in ["gif", "apng"]

      cond do
        animation? and frames > Media.max_frames() -> {:error, :too_many_frames, nil}
        animation? -> animated_image(incoming, format, opts)
        true -> still_image(incoming, format, opts)
      end
    end
  end

  # The work directory comes from Espalier.Media.Store.
  # sobelow_skip ["Traversal.FileModule"]
  defp animation_outputs(animation, opts) do
    %{webp: webp, poster: poster, width: width, height: height, has_alpha: alpha} = animation
    work_dir = Keyword.fetch!(opts, :work_dir)
    delivery = Path.join(work_dir, "out.webp")
    poster_path = Path.join(work_dir, "poster.webp")
    File.write!(delivery, webp)
    File.write!(poster_path, poster)
    {:ok, outputs(delivery, "webp", poster_path, image_facts(width, height, alpha, true))}
  end

  defp still_image(incoming, format, opts) do
    delivery = Path.join(Keyword.fetch!(opts, :work_dir), "out.webp")

    args =
      Ffmpeg.still_image_args(incoming, format, delivery, lossless: lossless?(incoming, format))

    with :ok <- ffmpeg(args, opts),
         {:ok, info} <- webp(delivery) do
      {:ok,
       outputs(delivery, "webp", nil, image_facts(info.width, info.height, info.has_alpha, false))}
    end
  end

  defp animated_image(incoming, format, opts) do
    work_dir = Keyword.fetch!(opts, :work_dir)
    delivery = Path.join(work_dir, "out.webp")
    poster = Path.join(work_dir, "poster.webp")

    with :ok <- ffmpeg(Ffmpeg.animated_image_args(incoming, format, delivery), opts),
         :ok <- ffmpeg(Ffmpeg.image_poster_args(incoming, format, poster), opts),
         {:ok, canvas} <- webp(delivery),
         {:ok, first} <- webp(poster) do
      # libwebp_anim sets the alpha flag of VP8X also for an opaque source,
      # so the alpha comes from the poster.
      {:ok,
       outputs(
         delivery,
         "webp",
         poster,
         image_facts(canvas.width, canvas.height, first.has_alpha, true)
       )}
    end
  end

  defp lossless?(_incoming, format) when format in ["png_pipe", "apng", "gif"], do: true

  defp lossless?(incoming, "webp_pipe") do
    match?({:ok, %{lossless: true}}, Sniff.webp_info(incoming))
  end

  defp lossless?(_incoming, _format), do: false

  defp webp(path) do
    case Sniff.webp_info(path) do
      {:ok, info} -> {:ok, info}
      :error -> {:error, :conversion_failed, nil}
    end
  end

  defp image_facts(width, height, has_alpha, animated) do
    %{
      width: width,
      height: height,
      duration_ms: nil,
      has_audio: false,
      animated: animated,
      has_alpha: has_alpha
    }
  end

  # The frame count of the first video stream; absent counts as one.
  defp frame_count(probe) do
    with [stream | _rest] <- streams(probe, "video"),
         count when is_binary(count) <- stream["nb_read_packets"],
         {frames, ""} <- Integer.parse(count) do
      frames
    else
      _absent -> 1
    end
  end

  ## SVG and captions

  # The rebuild runs in the BEAM under the remaining time of the job. The
  # incoming file and the work directory come from Espalier.Media.Store.
  # sobelow_skip ["Traversal.FileModule"]
  defp svg(incoming, opts) do
    binary = File.read!(incoming)
    remaining = max(Keyword.fetch!(opts, :deadline) - System.monotonic_time(:millisecond), 0)
    task = Task.async(fn -> Svg.sanitize(binary) end)

    case Task.yield(task, remaining) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> svg_result(result, opts)
      nil -> {:error, :timeout, nil}
    end
  end

  # The rebuild writes some characters as references such as `&amp;`, so
  # its file can be larger than the input. A file above svg_max_bytes would
  # fail the size check of the pack loader in an export or a draft
  # download, so it fails here with the reason of an input above that limit.
  # sobelow_skip ["Traversal.FileModule"]
  defp svg_result({:ok, svg, %{width: width, height: height}}, opts) do
    if byte_size(svg) > Media.svg_max_bytes() do
      {:error, :invalid_svg, :too_large}
    else
      with :ok <- proceed(opts) do
        delivery = Path.join(Keyword.fetch!(opts, :work_dir), "out.svg")
        File.write!(delivery, svg)
        {:ok, outputs(delivery, "svg", nil, image_facts(width, height, false, false))}
      end
    end
  end

  defp svg_result({:error, {:invalid_svg, tag}}, _opts), do: {:error, :invalid_svg, tag}

  # The incoming file and the work directory come from Espalier.Media.Store.
  # sobelow_skip ["Traversal.FileModule"]
  defp captions(incoming, opts) do
    case WebVtt.check(File.read!(incoming)) do
      {:ok, %{duration_ms: duration_ms}} ->
        with :ok <- proceed(opts) do
          delivery = Path.join(Keyword.fetch!(opts, :work_dir), "out.vtt")
          File.cp!(incoming, delivery)

          facts = %{
            width: nil,
            height: nil,
            duration_ms: duration_ms,
            has_audio: false,
            animated: false,
            has_alpha: false
          }

          {:ok, outputs(delivery, "vtt", nil, facts)}
        end

      {:error, {:invalid_captions, tag}} ->
        {:error, :invalid_captions, tag}
    end
  end

  ## Videos

  defp video(incoming, %{format: format}, opts) do
    work_dir = Keyword.fetch!(opts, :work_dir)
    delivery = Path.join(work_dir, "out.webm")

    with {:ok, probe} <- probe(incoming, format, Media.max_video_pixels(), opts),
         {:ok, input} <- video_input(probe) do
      # An input without a duration in its container gets the deadline of the
      # longest admitted video; the probe of the delivery file checks its
      # duration against MEDIA_VIDEO_MAX_MINUTES.
      opts =
        extend_deadline(
          opts,
          if(input.duration_ms > 0, do: input.duration_ms, else: Media.video_max_ms())
        )

      args =
        if remux?(format, input),
          do: Ffmpeg.remux_args(incoming, delivery),
          else: Ffmpeg.video_args(incoming, format, delivery)

      convert_video(args, delivery, Path.join(work_dir, "poster.webp"), input, opts)
    end
  end

  # The conversion or remux, a probe of the delivery file for the facts, and
  # the poster at min(1 s, duration / 10).
  defp convert_video(args, delivery, poster, input, opts) do
    with :ok <- ffmpeg(args, progress_opts(opts, input.duration_ms)),
         {:ok, output_probe} <- probe(delivery, "matroska", Media.max_video_pixels(), opts),
         {:ok, output} <- video_input(output_probe),
         {:ok, poster} <- video_poster(delivery, poster, output.duration_ms, opts) do
      facts = %{
        width: output.width,
        height: output.height,
        duration_ms: output.duration_ms,
        has_audio: output.audio != nil,
        animated: false,
        has_alpha: false
      }

      {:ok, outputs(delivery, "webm", poster, facts)}
    end
  end

  # The frame at min(1 s, duration / 10), or else the first frame; ffmpeg
  # exits 0 without a file when the seek finds no frame. A video without a
  # decodable frame there keeps no poster.
  # sobelow_skip ["Traversal.FileModule"]
  defp video_poster(delivery, poster, duration_ms, opts) do
    Enum.reduce_while([min(1.0, duration_ms / 10_000), 0.0], {:ok, nil}, fn seconds, acc ->
      with :ok <- ffmpeg(Ffmpeg.video_poster_args(delivery, seconds, poster), opts),
           {:ok, %File.Stat{size: size}} when size > 0 <- File.stat(poster) do
        {:halt, {:ok, poster}}
      else
        {:error, _failure, _detail} = error -> {:halt, error}
        _empty -> {:cont, acc}
      end
    end)
  end

  # The first video and audio streams of a probe and the duration, checked
  # against the limits of the kind.
  defp video_input(probe) do
    case streams(probe, "video") do
      [] ->
        {:error, :no_video_stream, nil}

      [video | _rest] ->
        input = %{
          codec: video["codec_name"],
          pix_fmt: video["pix_fmt"],
          alpha_mode: get_in(video, ["tags", "alpha_mode"]),
          width: video["width"],
          height: video["height"],
          audio: List.first(streams(probe, "audio")),
          duration_ms: duration_ms(probe, video)
        }

        cond do
          not is_integer(input.width) or not is_integer(input.height) ->
            {:error, :conversion_failed, nil}

          input.width * input.height > Media.max_video_pixels() ->
            {:error, :too_many_pixels, nil}

          input.duration_ms > Media.video_max_ms() ->
            {:error, :too_long, nil}

          true ->
            {:ok, input}
        end
    end
  end

  # A Matroska input with VP9 in yuv420p without alpha, no audio or Opus,
  # and at most the configured height passes unchanged.
  defp remux?("matroska", input) do
    input.codec == "vp9" and input.pix_fmt == "yuv420p" and input.alpha_mode == nil and
      (input.audio == nil or input.audio["codec_name"] == "opus") and
      input.height <= Media.video_max_height()
  end

  defp remux?(_format, _input), do: false

  defp duration_ms(probe, video) do
    [get_in(probe, ["format", "duration"]), video["duration"]]
    |> Enum.find_value(0, fn
      value when is_binary(value) ->
        case Float.parse(value) do
          {seconds, _rest} when seconds >= 0 -> round(seconds * 1000)
          _invalid -> nil
        end

      _absent ->
        nil
    end)
  end

  # The conversion and the poster of a video share one deadline from the
  # duration that the probe found.
  defp extend_deadline(opts, duration_ms) do
    case Keyword.get(opts, :on_duration) do
      nil -> opts
      on_duration -> Keyword.put(opts, :deadline, on_duration.(duration_ms))
    end
  end

  defp progress_opts(opts, duration_ms) do
    case Keyword.get(opts, :on_progress) do
      nil ->
        opts

      _on_progress when duration_ms <= 0 ->
        opts

      on_progress ->
        Keyword.put(opts, :command_progress, fn us ->
          on_progress.(min(99, div(us, 10 * duration_ms)))
        end)
    end
  end

  ## Commands

  # Asks the caller whether the job goes on: an answer `:halt` of the
  # option `:proceed` ends the processor as a cancelled command does.
  defp proceed(opts) do
    case Keyword.get(opts, :proceed) do
      nil -> :ok
      proceed -> if proceed.() == :halt, do: {:error, :cancelled, nil}, else: :ok
    end
  end

  defp probe(path, format, max_pixels, opts) do
    with :ok <- proceed(opts), do: run_probe(path, format, max_pixels, opts)
  end

  # The probe file lies in the work directory of the job, named by a unique
  # integer.
  # sobelow_skip ["Traversal.FileModule"]
  defp run_probe(path, format, max_pixels, opts) do
    work_dir = Keyword.fetch!(opts, :work_dir)
    json = Path.join(work_dir, "probe-#{System.unique_integer([:positive])}.json")
    args = Ffmpeg.probe_args(path, format, max_pixels, json)

    result = Command.run(Command.executable!("ffprobe"), args, command_opts(opts))

    decoded = with {:ok, text} <- File.read(json), do: Jason.decode(text)

    _ignored = File.rm(json)

    case {result, decoded} do
      {{:error, :timeout}, _decoded} ->
        {:error, :timeout, nil}

      {{:error, :cancelled}, _decoded} ->
        {:error, :cancelled, nil}

      {{:ok, output}, {:ok, probe}} ->
        pixels(output, {:ok, probe})

      {{:ok, output}, _error} ->
        pixels(output, {:error, :conversion_failed, nil})

      {{:error, {:exit, _status, tail}}, _decoded} ->
        pixels(Enum.join(tail, "\n"), {:error, :conversion_failed, nil})
    end
  end

  defp ffmpeg(args, opts) do
    with :ok <- proceed(opts), do: run_ffmpeg(args, opts)
  end

  defp run_ffmpeg(args, opts) do
    case Command.run(Command.executable!("ffmpeg"), args, command_opts(opts)) do
      {:ok, _output} ->
        :ok

      {:error, :timeout} ->
        {:error, :timeout, nil}

      {:error, :cancelled} ->
        {:error, :cancelled, nil}

      {:error, {:exit, _status, tail}} ->
        pixels(Enum.join(tail, "\n"), {:error, :conversion_failed, nil})
    end
  end

  # The max-pixel message of ffmpeg answers too_many_pixels.
  defp pixels(output, result) do
    if Regex.match?(@max_pixels_message, output),
      do: {:error, :too_many_pixels, nil},
      else: result
  end

  defp command_opts(opts) do
    remaining = Keyword.fetch!(opts, :deadline) - System.monotonic_time(:millisecond)

    [
      timeout: max(div(remaining, 1000), 0),
      cd: Keyword.fetch!(opts, :work_dir),
      on_progress: Keyword.get(opts, :command_progress)
    ]
  end

  defp streams(probe, type) do
    probe
    |> Map.get("streams", [])
    |> Enum.filter(&(is_map(&1) and &1["codec_type"] == type))
  end

  defp outputs(delivery, ext, poster, facts),
    do: %{delivery: delivery, ext: ext, poster: poster, facts: facts}
end
