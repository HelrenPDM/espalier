defmodule Espalier.Media.Sniff do
  @moduledoc """
  Detects the kind and the format of a media file from its leading bytes
  (task 0018, step 5), before any process reads it (ASVS 5.2.2). It reads
  at most the first 1 MiB in the BEAM.

  | Kind | Extensions | Signature | Format passed to ffmpeg |
  |---|---|---|---|
  | `image` | `.png` | `89 50 4E 47 0D 0A 1A 0A` | `apng` with `acTL` before the first `IDAT`, `png_pipe` otherwise |
  | `image` | `.jpg`, `.jpeg` | `FF D8 FF` | `jpeg_pipe` |
  | `image` | `.gif` | `GIF87a` or `GIF89a` | `gif` |
  | `image` | `.webp` | `RIFF`, four bytes, `WEBP` | `webp_pipe` |
  | `svg` | `.svg` | `<?xml`, `<svg` or `<!--` after an optional BOM and white space | none |
  | `video` | `.mp4`, `.m4v`, `.mov` | `ftyp` at offset 4 without a HEIF brand | `mov` |
  | `video` | `.webm`, `.mkv` | `1A 45 DF A3` | `matroska` |
  | `captions` | `.vtt` | `WEBVTT` after an optional BOM, then a space, a tab, a line break or the end | none |

  The extension is compared in lower case. A signature outside the table
  answers `unsupported_type`, and an extension of another kind
  `extension_mismatch`. An `ftyp` box whose major brand or a compatible
  brand within the first 64 bytes names HEIF or AVIF answers
  `unsupported_type`, because ffmpeg would read such a file as a still
  image sequence.

  For images, the width and the height come from the header: the PNG
  `IHDR`, the GIF logical screen, the WebP `VP8 `, `VP8L` or `VP8X` header,
  and the first JPEG `SOFn` segment within the first 1 MiB. Width times
  height above `max_input_pixels` answers `too_many_pixels`, before any
  decoder runs. A WebP with the animation flag in `VP8X` is `animated`.

  `webp_info/1` reads the facts of a WebP delivery file: its size, its
  alpha and whether it is lossless or animated.
  """

  alias Espalier.Media

  @head 64
  @window 1_048_576
  @max_png_chunks 64

  @extensions %{
    image: ~w(png jpg jpeg gif webp),
    svg: ~w(svg),
    video: ~w(mp4 m4v mov webm mkv),
    captions: ~w(vtt)
  }

  @heif_brands ~w(mif1 mif2 msf1 heic heix heim heis hevc hevx hevm hevs avif avis avio)

  @sof_markers [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]

  @typedoc "The result of a detection."
  @type detection :: %{
          kind: Media.kind(),
          format: String.t() | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          animated: boolean()
        }

  @doc "The accepted extensions per kind."
  @spec extensions() :: %{Media.kind() => [String.t()]}
  def extensions, do: @extensions

  @doc """
  Detects the file at `path`, named `file_name` by its uploader or its
  pack. Only the extension of `file_name` is read.
  """
  @spec detect(Path.t(), String.t()) ::
          {:ok, detection()}
          | {:error, :unsupported_type | :extension_mismatch | :too_many_pixels}
  # The caller passes an upload of Plug.Upload, a file of a loaded pack below
  # its root, or an incoming file of the store; the name only gives the
  # extension.
  # sobelow_skip ["Traversal.FileModule"]
  def detect(path, file_name) do
    ext = file_name |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    case File.open(path, [:read, :binary, :raw]) do
      {:ok, file} ->
        try do
          detect_open(file, ext)
        after
          File.close(file)
        end

      {:error, _reason} ->
        {:error, :unsupported_type}
    end
  end

  defp detect_open(file, ext) do
    head = read_at(file, 0, @head)

    with {:ok, kind, format} <- signature(head),
         :ok <- extension(kind, ext),
         {:ok, detection} <- header(kind, format, file, head) do
      pixels(detection)
    end
  end

  ## Signatures

  defp signature(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>),
    do: {:ok, :image, "png"}

  defp signature(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, :image, "jpeg_pipe"}
  defp signature(<<"GIF87a", _rest::binary>>), do: {:ok, :image, "gif"}
  defp signature(<<"GIF89a", _rest::binary>>), do: {:ok, :image, "gif"}

  defp signature(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: {:ok, :image, "webp_pipe"}

  defp signature(<<0x1A, 0x45, 0xDF, 0xA3, _rest::binary>>), do: {:ok, :video, "matroska"}

  defp signature(<<_size::binary-size(4), "ftyp", _rest::binary>> = head) do
    if heif?(head), do: {:error, :unsupported_type}, else: {:ok, :video, "mov"}
  end

  defp signature(head) do
    text = strip_bom(head)

    cond do
      webvtt?(text) -> {:ok, :captions, nil}
      svg?(skip_space(text)) -> {:ok, :svg, nil}
      true -> {:error, :unsupported_type}
    end
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(text), do: text

  # The head may end inside a multi-byte character, so only ASCII white
  # space is skipped.
  defp skip_space(<<char, rest::binary>>) when char in [?\s, ?\t, ?\r, ?\n], do: skip_space(rest)
  defp skip_space(text), do: text

  defp webvtt?(<<"WEBVTT">>), do: true
  defp webvtt?(<<"WEBVTT", next, _rest::binary>>) when next in [?\s, ?\t, ?\n, ?\r], do: true
  defp webvtt?(_text), do: false

  # Leading white space may fill the 64 bytes of the head; a file that
  # holds only white space there is no SVG.
  defp svg?(<<"<?xml", _rest::binary>>), do: true
  defp svg?(<<"<svg", _rest::binary>>), do: true
  defp svg?(<<"<!--", _rest::binary>>), do: true
  defp svg?(_text), do: false

  # The major brand and the compatible brands to the end of the box, within
  # the first 64 bytes. A box size of 1 announces a 64-bit size after the
  # type, which moves the brands by eight bytes, and a box size of 0 runs to
  # the end of the file.
  defp heif?(
         <<1::32, "ftyp", _large::64, major::binary-size(4), _minor::binary-size(4),
           rest::binary>>
       ),
       do: heif_brand?(major, rest)

  defp heif?(<<0::32, "ftyp", major::binary-size(4), _minor::binary-size(4), rest::binary>>),
    do: heif_brand?(major, rest)

  defp heif?(<<size::32, "ftyp", major::binary-size(4), _minor::binary-size(4), rest::binary>>) do
    heif_brand?(major, binary_part(rest, 0, min(max(size - 16, 0), byte_size(rest))))
  end

  defp heif?(_head), do: true

  defp heif_brand?(major, compatible) do
    brands = [major | for(<<brand::binary-size(4) <- compatible>>, do: brand)]
    Enum.any?(brands, &(&1 in @heif_brands))
  end

  defp extension(kind, ext) do
    if ext in Map.fetch!(@extensions, kind), do: :ok, else: {:error, :extension_mismatch}
  end

  ## Headers

  defp header(:image, "png", file, head), do: png(file, head)

  defp header(:image, "jpeg_pipe", file, _head) do
    case jpeg_size(read_at(file, 0, @window), 2) do
      {:ok, width, height} -> image("jpeg_pipe", width, height, false)
      :error -> {:error, :unsupported_type}
    end
  end

  defp header(
         :image,
         "gif",
         _file,
         <<_sig::binary-size(6), width::little-16, height::little-16, _rest::binary>>
       ),
       do: image("gif", width, height, false)

  defp header(:image, "webp_pipe", file, _head) do
    case webp_header(read_at(file, 0, @window)) do
      {:ok, %{width: width, height: height, animated: animated}} ->
        image("webp_pipe", width, height, animated)

      :error ->
        {:error, :unsupported_type}
    end
  end

  defp header(:image, _format, _file, _head), do: {:error, :unsupported_type}

  defp header(kind, format, _file, _head),
    do: {:ok, %{kind: kind, format: format, width: nil, height: nil, animated: false}}

  defp image(_format, width, height, _animated) when width < 1 or height < 1,
    do: {:error, :unsupported_type}

  defp image(format, width, height, animated),
    do: {:ok, %{kind: :image, format: format, width: width, height: height, animated: animated}}

  defp pixels(%{kind: :image, width: width, height: height} = detection) do
    if width * height > Media.max_input_pixels(),
      do: {:error, :too_many_pixels},
      else: {:ok, detection}
  end

  defp pixels(detection), do: {:ok, detection}

  # The PNG IHDR holds the size at bytes 16 to 23. The chunk walk reads the
  # length and the type of each chunk from offset 8 and skips its data,
  # until acTL (an APNG) or IDAT, at most 64 chunks or 1 MiB.
  defp png(file, <<_sig::binary-size(8), _len::32, "IHDR", width::32, height::32, _rest::binary>>) do
    case png_walk(file, 8, 0) do
      {:ok, format} -> image(format, width, height, false)
      :error -> {:error, :unsupported_type}
    end
  end

  defp png(_file, _head), do: {:error, :unsupported_type}

  defp png_walk(_file, offset, count) when count >= @max_png_chunks or offset >= @window,
    do: {:ok, "png_pipe"}

  defp png_walk(file, offset, count) do
    case read_at(file, offset, 8) do
      <<length::32, _type::binary-size(4)>> when length > 0x7FFFFFFF -> :error
      <<_length::32, "acTL">> -> {:ok, "apng"}
      <<_length::32, "IDAT">> -> {:ok, "png_pipe"}
      <<length::32, _type::binary-size(4)>> -> png_walk(file, offset + 12 + length, count + 1)
      _short -> {:ok, "png_pipe"}
    end
  end

  # A walk over the JPEG segment markers from offset 2 to the first SOFn,
  # within the first 1 MiB, which is read once.
  defp jpeg_size(data, offset) when offset >= byte_size(data), do: :error

  defp jpeg_size(data, offset) do
    case binary_part(data, offset, min(9, byte_size(data) - offset)) do
      <<0xFF, 0xFF, _rest::binary>> ->
        jpeg_size(data, offset + 1)

      <<0xFF, marker, _rest::binary>> when marker in 0xD0..0xD7 or marker == 0x01 ->
        jpeg_size(data, offset + 2)

      <<0xFF, marker, _length::16, _precision, height::16, width::16>>
      when marker in @sof_markers ->
        {:ok, width, height}

      <<0xFF, marker, _rest::binary>> when marker in [0xD9, 0xDA] ->
        :error

      <<0xFF, _marker, length::16, _rest::binary>> when length >= 2 ->
        jpeg_size(data, offset + 2 + length)

      _other ->
        :error
    end
  end

  ## WebP

  @doc """
  Reads the facts of a WebP file: `width`, `height` (the frame size of a
  `VP8 ` chunk, the size of a `VP8L` chunk, or the canvas of `VP8X`),
  `has_alpha` (the `alpha_is_used` bit of `VP8L`, or an `ALPH` chunk next
  to a `VP8X`), `lossless` (a `VP8L` image) and `animated` (the animation
  flag of `VP8X`). ffprobe 8.1.2 reports `argb` for every lossless WebP and
  no size for an animated one, so the processors read these facts here.
  """
  @spec webp_info(Path.t()) ::
          {:ok,
           %{
             width: pos_integer(),
             height: pos_integer(),
             has_alpha: boolean(),
             lossless: boolean(),
             animated: boolean()
           }}
          | :error
  # The caller passes a file of the media store or of its work directory.
  # sobelow_skip ["Traversal.FileModule"]
  def webp_info(path) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, file} ->
        try do
          webp_header(read_at(file, 0, @window))
        after
          File.close(file)
        end

      {:error, _reason} ->
        :error
    end
  end

  defp webp_header(<<"RIFF", _size::binary-size(4), "WEBP", chunks::binary>>),
    do: webp_chunk(chunks)

  defp webp_header(_binary), do: :error

  defp webp_chunk(
         <<"VP8 ", _length::little-32, _tag::binary-size(3), 0x9D, 0x01, 0x2A, width::little-16,
           height::little-16, _rest::binary>>
       ) do
    {:ok,
     %{
       width: Bitwise.band(width, 0x3FFF),
       height: Bitwise.band(height, 0x3FFF),
       has_alpha: false,
       lossless: false,
       animated: false
     }}
  end

  defp webp_chunk(<<"VP8L", _length::little-32, 0x2F, bits::little-32, _rest::binary>>) do
    {:ok,
     %{
       width: Bitwise.band(bits, 0x3FFF) + 1,
       height: Bitwise.band(Bitwise.bsr(bits, 14), 0x3FFF) + 1,
       has_alpha: Bitwise.band(Bitwise.bsr(bits, 28), 1) == 1,
       lossless: true,
       animated: false
     }}
  end

  defp webp_chunk(
         <<"VP8X", length::little-32, flags, _reserved::binary-size(3), width::little-24,
           height::little-24, rest::binary>>
       )
       when length >= 10 do
    inner = vp8x_inner(rest, length - 10)
    animated = Bitwise.band(flags, 0x02) != 0

    {:ok,
     %{
       width: width + 1,
       height: height + 1,
       has_alpha: Map.has_key?(inner, "ALPH"),
       lossless: Map.has_key?(inner, "VP8L"),
       animated: animated
     }}
  end

  defp webp_chunk(_chunks), do: :error

  # The chunks after VP8X, without their data, as a map of type to true.
  defp vp8x_inner(rest, padding) when byte_size(rest) >= padding do
    rest |> binary_part(padding, byte_size(rest) - padding) |> chunk_types(%{}, 0)
  end

  defp vp8x_inner(_rest, _padding), do: %{}

  defp chunk_types(<<type::binary-size(4), length::little-32, rest::binary>>, types, count)
       when count < 64 do
    skip = length + rem(length, 2)
    types = Map.put(types, type, true)

    if byte_size(rest) >= skip,
      do: chunk_types(binary_part(rest, skip, byte_size(rest) - skip), types, count + 1),
      else: types
  end

  defp chunk_types(_rest, types, _count), do: types

  defp read_at(file, offset, length) do
    case :file.pread(file, offset, length) do
      {:ok, data} -> data
      _eof_or_error -> <<>>
    end
  end
end
