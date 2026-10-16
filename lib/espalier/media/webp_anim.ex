defmodule Espalier.Media.WebpAnim do
  @moduledoc """
  The structural path of an animated WebP input (task 0018, step 6).

  Neither ffmpeg build of the platform decodes an animated WebP, and an
  animated WebP is the delivery format of every animation, so a pack
  exported by the platform holds such files. `check/1` checks the container
  in the BEAM, decodes nothing, and writes the file anew from the checked
  chunks, as the remux of a WebM passes its streams unchanged.

  ## Checks

  The RIFF size plus eight equals the file size, every chunk length fits
  the file and is followed by a padding byte when it is odd, and the chunks
  follow the order `VP8X`, `ICCP` (optional), `ANIM`, one or more `ANMF`,
  `EXIF` (optional) and `XMP ` (optional); every other chunk, also an
  unknown one, answers `structure`. `VP8X` holds 10 bytes with the
  animation flag set, `ANIM` holds 6 bytes, and the canvas stays within
  `Espalier.Media.max_input_pixels/0`. More than
  `Espalier.Media.max_frames/0` frames answer `too_many_frames`.

  Every frame rectangle lies within the canvas. The payload of every `ANMF`
  holds, after its 16-byte header, either one `VP8 ` or `VP8L` chunk or an
  `ALPH` chunk followed by one `VP8 ` chunk, and nothing else. An `ALPH`
  chunk before a `VP8L` chunk answers `structure`: RFC 9649 says that a
  frame with `VP8L` should not hold one, and its alpha would contradict the
  alpha of the lossless bitstream. A `VP8 ` chunk must start with the frame
  tag of a key frame and the start code `9D 01 2A`, a `VP8L` chunk with the
  signature `2F` and version 0, and the width and height in that header
  must equal the frame size.

  The first frame may cover only a part of the canvas: the animation
  encoder of libwebp crops even the first frame against a transparent
  canvas, so an animation whose source starts with a transparent margin
  gives such a file (step 1 of task 0018). The reason tag `first_frame`
  of the closed list is therefore no longer produced.

  ## Output

  `webp` is the file without `ICCP`, `EXIF` and `XMP `. Its `VP8X` keeps
  the canvas and of its flags only the animation flag and the alpha flag;
  the ICC, EXIF and XMP flags and the reserved bits are cleared, and the
  reserved bytes are zero. `ANIM` and the frame headers stay as they were,
  and every frame bitstream passes unchanged.

  `poster` shows the first frame without a decoder. A first frame that
  covers the canvas becomes a still WebP: a frame with `ALPH` the extended
  format (`VP8X` with the alpha flag and the canvas size, `ALPH`, `VP8 `),
  every other frame the simple format with its `VP8 ` or `VP8L` chunk
  alone, whose lossless bitstream carries its own alpha. A first frame
  that covers only a part of the canvas becomes an animated WebP with that
  single frame (`VP8X` with the animation and the alpha flag, the `ANIM`
  of the input and the first `ANMF`), which browsers show as a still
  picture on the transparent canvas. `width` and `height` are the canvas,
  `has_alpha` comes from the `ALPH` chunk or the alpha bit of the `VP8L`
  header of the first frame, because libwebp sets the alpha flag of `VP8X`
  also for opaque sources, and is true for a first frame with a margin;
  `frames` counts the `ANMF` chunks.
  """

  import Bitwise

  alias Espalier.Media

  @typedoc "The reason tags of a rejected animated WebP."
  @type tag :: :structure | :too_many_frames

  @typedoc "The rewritten file, its poster and its facts."
  @type result :: %{
          webp: binary(),
          poster: binary(),
          width: pos_integer(),
          height: pos_integer(),
          has_alpha: boolean(),
          frames: pos_integer()
        }

  @flag_alpha 0x10
  @flag_animation 0x02

  @doc """
  Checks an animated WebP and returns the rewritten file, the poster and
  the facts, or the reason tag of the rejection.
  """
  @spec check(binary()) :: {:ok, result()} | {:error, {:unsupported_animation, tag()}}
  def check(binary) when is_binary(binary) do
    with {:ok, body} <- riff(binary),
         {:ok, image} <- walk(body, :vp8x, %{frames: [], count: 0}),
         {:ok, result} <- output(image) do
      {:ok, result}
    else
      {:error, tag} -> {:error, {:unsupported_animation, tag}}
    end
  end

  ## Container

  defp riff(<<"RIFF", size::little-32, "WEBP", body::binary>> = binary)
       when size + 8 == byte_size(binary),
       do: {:ok, body}

  defp riff(_binary), do: {:error, :structure}

  # Splits the next chunk off, with its padding byte when its length is odd.
  defp next_chunk(<<fourcc::binary-4, length::little-32, rest::binary>>) do
    padded = length + rem(length, 2)

    if byte_size(rest) >= padded do
      {:ok, fourcc, binary_part(rest, 0, length),
       binary_part(rest, padded, byte_size(rest) - padded)}
    else
      {:error, :structure}
    end
  end

  defp next_chunk(_rest), do: {:error, :structure}

  # Walks the chunks in the order VP8X, ICCP?, ANIM, ANMF+, EXIF?, XMP .
  # The state names the chunks that may come next.
  defp walk(<<>>, state, image) when state in [:frames, :xmp, :done] do
    {:ok, %{image | frames: Enum.reverse(image.frames)}}
  end

  defp walk(<<>>, _state, _image), do: {:error, :structure}

  defp walk(body, state, image) do
    with {:ok, fourcc, payload, rest} <- next_chunk(body),
         {:ok, next, image} <- chunk(state, fourcc, payload, image) do
      walk(rest, next, image)
    end
  end

  defp chunk(:vp8x, "VP8X", payload, image) do
    case payload do
      <<flags, _reserved::binary-3, width::little-24, height::little-24>>
      when (flags &&& @flag_animation) != 0 ->
        canvas(image, flags, width + 1, height + 1)

      _other ->
        {:error, :structure}
    end
  end

  defp chunk(:iccp, "ICCP", _payload, image), do: {:ok, :anim, image}

  defp chunk(state, "ANIM", <<_::binary-6>> = payload, image) when state in [:iccp, :anim],
    do: {:ok, :first_frame, Map.put(image, :anim, payload)}

  defp chunk(state, "ANMF", payload, image) when state in [:first_frame, :frames] do
    if image.count >= Media.max_frames() do
      {:error, :too_many_frames}
    else
      with {:ok, frame} <- frame(payload, image) do
        {:ok, :frames, %{image | frames: [frame | image.frames], count: image.count + 1}}
      end
    end
  end

  defp chunk(:frames, "EXIF", _payload, image), do: {:ok, :xmp, image}

  defp chunk(state, "XMP ", _payload, image) when state in [:frames, :xmp],
    do: {:ok, :done, image}

  defp chunk(_state, _fourcc, _payload, _image), do: {:error, :structure}

  defp canvas(image, flags, width, height) do
    if width * height <= Media.max_input_pixels() do
      {:ok, :iccp, Map.merge(image, %{flags: flags, width: width, height: height})}
    else
      {:error, :structure}
    end
  end

  ## Frames

  defp frame(payload, image) do
    with <<header::binary-16, data::binary>> <- payload,
         <<x::little-24, y::little-24, width::little-24, height::little-24, _rest::binary>> <-
           header,
         frame = %{x: 2 * x, y: 2 * y, width: width + 1, height: height + 1, header: header},
         true <- frame.x + frame.width <= image.width and frame.y + frame.height <= image.height,
         {:ok, frame} <- frame_data(data, frame) do
      {:ok, frame}
    else
      _other -> {:error, :structure}
    end
  end

  # The frame data: one VP8 or VP8L chunk, or ALPH followed by VP8 .
  defp frame_data(data, frame) do
    case subchunks(data, []) do
      {:ok, [{"ALPH", alpha}, {"VP8 ", bitstream}]} ->
        bitstream(frame, alpha, "VP8 ", bitstream)

      {:ok, [{fourcc, bitstream}]} when fourcc in ["VP8 ", "VP8L"] ->
        bitstream(frame, nil, fourcc, bitstream)

      _other ->
        {:error, :structure}
    end
  end

  # A frame holds at most two chunks, so the walk stops at a third one.
  defp subchunks(_data, [_, _, _ | _chunks]), do: {:error, :structure}
  defp subchunks(<<>>, chunks), do: {:ok, Enum.reverse(chunks)}

  defp subchunks(data, chunks) do
    with {:ok, fourcc, payload, rest} <- next_chunk(data) do
      subchunks(rest, [{fourcc, payload} | chunks])
    end
  end

  defp bitstream(frame, alpha, fourcc, payload) do
    case bitstream_header(fourcc, payload) do
      {width, height, lossless_alpha} when width == frame.width and height == frame.height ->
        {:ok,
         Map.merge(frame, %{
           alpha: alpha,
           fourcc: fourcc,
           bitstream: payload,
           has_alpha: alpha != nil or lossless_alpha
         })}

      _other ->
        {:error, :structure}
    end
  end

  # The frame size of a VP8 key frame: a 3-byte frame tag whose lowest bit
  # is 0, the start code 9D 01 2A, and two 14-bit sizes with 2 scale bits.
  defp bitstream_header(
         "VP8 ",
         <<tag::little-24, 0x9D, 0x01, 0x2A, width::little-16, height::little-16, _rest::binary>>
       )
       when (tag &&& 0x01) == 0 do
    {width &&& 0x3FFF, height &&& 0x3FFF, false}
  end

  # The VP8L header: the signature 2F, then 14 bits width minus one, 14 bits
  # height minus one, the alpha_is_used bit and a 3-bit version of 0.
  defp bitstream_header("VP8L", <<0x2F, bits::little-32, _rest::binary>>) when bits >>> 29 == 0 do
    {(bits &&& 0x3FFF) + 1, (bits >>> 14 &&& 0x3FFF) + 1, (bits >>> 28 &&& 1) == 1}
  end

  defp bitstream_header(_fourcc, _payload), do: :invalid

  defp covers_canvas?(first, image) do
    first.x == 0 and first.y == 0 and first.width == image.width and
      first.height == image.height
  end

  ## Output

  # The walk accepts no file without a frame; a file without one would have
  # no poster, so the output answers `structure` for it on its own as well.
  defp output(%{frames: []}), do: {:error, :structure}

  defp output(%{frames: [first | _rest]} = image) do
    {:ok,
     %{
       webp: webp(image),
       poster: poster(first, image),
       width: image.width,
       height: image.height,
       has_alpha: first.has_alpha or not covers_canvas?(first, image),
       frames: image.count
     }}
  end

  defp webp(image) do
    flags = @flag_animation ||| (image.flags &&& @flag_alpha)

    riff_file([
      vp8x(flags, image.width, image.height),
      chunk_data("ANIM", image.anim),
      Enum.map(image.frames, &chunk_data("ANMF", [&1.header, frame_chunks(&1)]))
    ])
  end

  defp poster(first, image) do
    cond do
      not covers_canvas?(first, image) ->
        riff_file([
          vp8x(@flag_animation ||| @flag_alpha, image.width, image.height),
          chunk_data("ANIM", image.anim),
          chunk_data("ANMF", [first.header, frame_chunks(first)])
        ])

      first.alpha == nil ->
        riff_file([chunk_data(first.fourcc, first.bitstream)])

      true ->
        riff_file([vp8x(@flag_alpha, image.width, image.height), frame_chunks(first)])
    end
  end

  defp frame_chunks(%{alpha: nil} = frame), do: [chunk_data(frame.fourcc, frame.bitstream)]

  defp frame_chunks(frame),
    do: [chunk_data("ALPH", frame.alpha), chunk_data(frame.fourcc, frame.bitstream)]

  defp vp8x(flags, width, height) do
    chunk_data("VP8X", <<flags, 0, 0, 0, width - 1::little-24, height - 1::little-24>>)
  end

  defp chunk_data(fourcc, payload) do
    size = IO.iodata_length(payload)
    [fourcc, <<size::little-32>>, payload, if(rem(size, 2) == 1, do: <<0>>, else: <<>>)]
  end

  defp riff_file(chunks) do
    body = IO.iodata_to_binary(["WEBP", chunks])
    <<"RIFF", byte_size(body)::little-32, body::binary>>
  end
end
