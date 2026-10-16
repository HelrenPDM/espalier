defmodule Espalier.Catalog.Pack.MediaPath do
  @moduledoc """
  The paths of the media files of a content pack (task 0018, step 9; ASVS
  5.3.2).

  `check/1` first applies the general path rules of
  `Espalier.Workbench.Paths.general?/1`: valid UTF-8 of 1 to 527 bytes,
  components of at most 255 bytes, no U+0000, no backslash, not absolute, and
  no empty, `.` or `..` component. It then admits `media/`, followed by zero
  to three directories and a file name: each directory satisfies
  `Espalier.Catalog.Pack.Schema.Cast.key?/1`, and the file name is
  `<key>.<extension>` with a key of that format and one of the lower-case
  extensions of `extensions/0`:

  | Kind | Extensions | Delivery extension |
  |---|---|---|
  | `image` | `png`, `jpg`, `jpeg`, `gif`, `webp` | `webp` |
  | `svg` | `svg` | `svg` |
  | `video` | `mp4`, `m4v`, `mov`, `webm`, `mkv` | `webm` |
  | `captions` | `vtt` | `vtt` |

  The loader, the validator, the importer and the workbench pass every
  media path through `check/1` before any file operation. `kind/1` names the
  kind of a path from its extension, and `delivery_path/1` gives the path of
  the file in its delivery format, which a pack export writes.
  """

  alias Espalier.Catalog.Pack.Schema.Cast
  alias Espalier.Workbench.Paths

  @extensions [
    image: ~w(png jpg jpeg gif webp),
    svg: ~w(svg),
    video: ~w(mp4 m4v mov webm mkv),
    captions: ~w(vtt)
  ]

  @delivery [image: "webp", svg: "svg", video: "webm", captions: "vtt"]

  @kinds Map.new(for {kind, exts} <- @extensions, ext <- exts, do: {ext, kind})

  @max_directories 3

  @typedoc "The kind of a media file, as `Espalier.Media` names it."
  @type kind :: :image | :svg | :video | :captions

  @doc """
  The accepted extensions per kind, in the order image, SVG, video and
  captions.
  """
  @spec extensions() :: [{kind(), [String.t()]}]
  def extensions, do: @extensions

  @doc "The accepted extensions of `kind`."
  @spec extensions(kind()) :: [String.t()]
  def extensions(kind), do: Keyword.fetch!(@extensions, kind)

  @doc "The delivery extension of `kind`: `webp`, `svg`, `webm` or `vtt`."
  @spec delivery_extension(kind()) :: String.t()
  def delivery_extension(kind), do: Keyword.fetch!(@delivery, kind)

  @doc "The largest number of directories between `media/` and the file name."
  @spec max_directories() :: pos_integer()
  def max_directories, do: @max_directories

  @doc """
  Returns `:ok` for a media path as the moduledoc describes it, and
  `{:error, message}` otherwise, with a message that names the broken rule.
  """
  @spec check(term()) :: :ok | {:error, String.t()}
  def check(path) when is_binary(path) do
    if Paths.general?(path) do
      path |> String.split("/") |> check_components()
    else
      {:error,
       "a media path is valid UTF-8 of at most #{Paths.max_bytes()} bytes with " <>
         "components of at most #{Paths.max_component_bytes()} bytes, and holds no " <>
         "backslash, no U+0000 and no empty, `.` or `..` component"}
    end
  end

  def check(_path), do: {:error, "a media path is a string"}

  @doc "Returns true when `check/1` admits `path`."
  @spec valid?(term()) :: boolean()
  def valid?(path), do: check(path) == :ok

  @doc """
  The kind of the media file at `path`, from its extension, or `nil` for an
  extension outside `extensions/0`.
  """
  @spec kind(String.t()) :: kind() | nil
  def kind(path) when is_binary(path), do: Map.get(@kinds, extension(path))

  @doc """
  The path of the file in its delivery format: the extension of `path`
  replaced by the delivery extension of its kind, for example
  `media/photo.webp` for `media/photo.jpg`. Raises `ArgumentError` for a
  path whose extension names no kind.
  """
  @spec delivery_path(String.t()) :: String.t()
  def delivery_path(path) when is_binary(path) do
    case kind(path) do
      nil ->
        raise ArgumentError, "no media kind for the path #{inspect(path)}"

      kind ->
        String.replace_suffix(path, "." <> extension(path), "." <> delivery_extension(kind))
    end
  end

  # The extension after the last dot of the last component, or "".
  defp extension(path) do
    name = path |> String.split("/") |> List.last()

    case String.split(name, ".") do
      [_name] -> ""
      parts -> List.last(parts)
    end
  end

  defp check_components(["media" | rest]) when rest != [] do
    {dirs, [file]} = Enum.split(rest, -1)

    cond do
      length(dirs) > @max_directories ->
        {:error, "a media path has at most #{@max_directories} directories below `media/`"}

      dir = Enum.find(dirs, &(not Cast.key?(&1))) ->
        {:error, "the media directory `#{dir}` does not match the key format"}

      true ->
        check_file_name(file)
    end
  end

  defp check_components(_components), do: {:error, "a media path starts with `media/`"}

  defp check_file_name(file) do
    with [key, ext] <- String.split(file, "."),
         true <- Cast.key?(key),
         true <- Map.has_key?(@kinds, ext) do
      :ok
    else
      _ ->
        {:error,
         "the media file name `#{file}` must have the form `<key>.<extension>` with a key " <>
           "in the key format and one of the extensions #{extension_list()}"}
    end
  end

  defp extension_list do
    @extensions |> Enum.flat_map(&elem(&1, 1)) |> Enum.map_join(", ", &"`#{&1}`")
  end
end
