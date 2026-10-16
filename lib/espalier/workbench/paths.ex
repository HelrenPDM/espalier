defmodule Espalier.Workbench.Paths do
  @moduledoc """
  The path rules of a draft (task 0016a, step 3, and task 0018, step 16;
  ASVS 5.2.2 and 5.3.2).

  `general?/1` holds the general rules: a path is valid UTF-8 of 1 to 527
  bytes, holds no U+0000 and no backslash, does not start with `/` or a
  drive letter, and holds no empty, `.` or `..` component and no component
  of more than 255 bytes when it is split at `/`. 255 bytes is the longest
  name of a file or a directory that common file systems hold, so every
  path that passes can be written below a directory, and a pack directory
  holds no longer name; the forms below with such components hold at most
  527 bytes (`modules/` and `/lessons/` around two components).
  `Espalier.Catalog.Pack.MediaPath.check/1` applies the same rules first.

  `check/1` applies the general rules and then admits exactly the four forms
  of the text files that the loader of task 0008 reads:

    * a name of `Espalier.Catalog.Pack.Loader.top_files/0`;
    * `modules/<dir>/<name>` with a name of
      `Espalier.Catalog.Pack.Loader.module_files/0`;
    * `modules/<dir>/lessons/<key>.md`;
    * a captions file, a path that `Espalier.Catalog.Pack.MediaPath.check/1`
      admits with the extension `vtt` (task 0018), stored as a text file of
      the draft.

  `<dir>` and `<key>` satisfy `Espalier.Catalog.Pack.Schema.Cast.key?/1`,
  the key format that the loader applies to module directories and lesson
  keys. In this layout no path names a directory of another path, so no
  file of a draft lies below another file of the same draft.

  `check_media/2` holds the rule for a media entry of a draft: a media path
  whose extension is the delivery extension of the kind of its asset.
  """

  alias Espalier.Catalog.Pack.{Loader, MediaPath}
  alias Espalier.Catalog.Pack.Schema.Cast

  @max_bytes 527
  @max_component_bytes 255

  @doc "The largest number of bytes of a path."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "The largest number of bytes of a component of a path."
  @spec max_component_bytes() :: pos_integer()
  def max_component_bytes, do: @max_component_bytes

  @doc "Returns `:ok` for a path of the pack layout and `{:error, :invalid_path}` otherwise."
  @spec check(term()) :: :ok | {:error, :invalid_path}
  def check(path) when is_binary(path) do
    if general?(path) and (layout?(String.split(path, "/")) or captions?(path)),
      do: :ok,
      else: {:error, :invalid_path}
  end

  def check(_path), do: {:error, :invalid_path}

  @doc """
  Returns `:ok` when `path` may hold a media entry of `asset` and
  `{:error, :invalid_path}` otherwise. The path passes
  `Espalier.Catalog.Pack.MediaPath.check/1`, and its extension is the
  delivery extension of the kind of the asset: `webp` for `:image`, `svg`
  for `:svg` and `webm` for `:video`. An asset of kind `:captions` is never
  a media entry; its content becomes a text file of the draft.
  """
  @spec check_media(term(), %{required(:kind) => atom(), optional(atom()) => term()}) ::
          :ok | {:error, :invalid_path}
  def check_media(path, %{kind: kind}) when kind in [:image, :svg, :video] and is_binary(path) do
    if MediaPath.check(path) == :ok and
         String.ends_with?(path, "." <> MediaPath.delivery_extension(kind)),
       do: :ok,
       else: {:error, :invalid_path}
  end

  def check_media(_path, _asset), do: {:error, :invalid_path}

  @doc """
  The language of the file at `path`: `:yaml` for `.yaml`, `:markdown` for
  `.md` and `:text` for a captions file (`.vtt`).
  """
  @spec language(String.t()) :: :yaml | :markdown | :text | nil
  def language(path) when is_binary(path) do
    cond do
      String.ends_with?(path, ".yaml") -> :yaml
      String.ends_with?(path, ".md") -> :markdown
      String.ends_with?(path, ".vtt") -> :text
      true -> nil
    end
  end

  @doc """
  The general rules of the moduledoc: true for valid UTF-8 of 1 to 527
  bytes without U+0000 and backslash, not absolute, whose components are
  neither empty nor `.` or `..` and hold at most 255 bytes.
  """
  @spec general?(term()) :: boolean()
  def general?(path) when is_binary(path) do
    byte_size(path) in 1..@max_bytes and String.valid?(path) and
      not String.contains?(path, [<<0>>, "\\"]) and not absolute?(path) and
      path |> String.split("/") |> Enum.all?(&component?/1)
  end

  def general?(_path), do: false

  defp component?(name),
    do: name not in ["", ".", ".."] and byte_size(name) <= @max_component_bytes

  defp absolute?("/" <> _rest), do: true

  defp absolute?(<<letter, ?:, _rest::binary>>) when letter in ?a..?z or letter in ?A..?Z,
    do: true

  defp absolute?(_path), do: false

  defp layout?([name]), do: name in Loader.top_files()
  defp layout?(["modules", dir, name]), do: Cast.key?(dir) and name in Loader.module_files()
  defp layout?(["modules", dir, "lessons", file]), do: Cast.key?(dir) and lesson_file?(file)
  defp layout?(_components), do: false

  defp lesson_file?(file) do
    String.ends_with?(file, ".md") and
      file |> binary_part(0, byte_size(file) - 3) |> Cast.key?()
  end

  defp captions?(path), do: MediaPath.check(path) == :ok and MediaPath.kind(path) == :captions
end
