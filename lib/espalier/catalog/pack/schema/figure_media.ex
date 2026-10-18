defmodule Espalier.Catalog.Pack.Schema.FigureMedia do
  @moduledoc """
  The media attributes of a `figure` block: the image or SVG file, its text alternative and its size.

  The attributes stand on the opening line of a `figure` block in a lesson file,
  in the braces after `:::figure`. `Espalier.Catalog.Pack.Directives.split/2`
  collects `src`, `alt`, `decorative` and `size` in the map `media` of the
  block, with the raw values as strings, and `Espalier.Catalog.Pack.Schema.Block`
  casts that map with this module. The body of the block is the caption. It may
  be empty, and `Espalier.Catalog.Pack.Schema.Block` describes its rules.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `src` | string | yes | A media path: `media/`, then zero to three directories, then a file name `<key>.<extension>`, where every directory and the key follow the key format `^[a-z0-9][a-z0-9-]*$`. The extension is `png`, `jpg`, `jpeg`, `gif`, `webp` or `svg`, in lower case (`Espalier.Catalog.Pack.MediaPath`). A URL is no media path. The validator checks across files that the pack holds the file. |
  | `alt` | string | yes, unless `decorative` is `true` | The text alternative that a screen reader reads in place of the image, 1 to 1,000 characters (code points). A value of whitespace only is empty. Not allowed together with `decorative`. |
  | `decorative` | string | no | The string `true` and no other value. It marks an image that carries no information, and the player gives it an empty text alternative. In YAML the value is quoted (`"true"`), because an unquoted `true` is a boolean. In a lesson file `decorative=true` yields the string. |
  | `size` | one of `small`, `medium`, `full` | no | The width of the figure in the lesson. An absent `size` counts as `full`. |

  A field that the table does not list is an error. A `null` value counts as
  absent. Every string is not empty after trimming whitespace and holds no NUL
  character (`Espalier.Catalog.Pack.Schema.Cast`).

  `max_alt/0` returns the limit of `alt`, and `decorative?/1` tells whether a
  cast struct marks the figure as decorative.

  ## Example

  The first example is an informative figure with a text alternative and a
  size. The second marks an ornament as decorative and has no `alt`. The third
  sets only `src` and `alt`, so that the size is `full`. The examples show the
  map that the validator passes to `changeset/2`, written as YAML.

  ```yaml
  src: media/next-word.svg
  alt: "The words 'The meeting moves to' with three candidates for the next word"
  size: medium
  ```

  ```yaml
  src: media/ornaments/divider.svg
  decorative: "true"
  ```

  ```yaml
  src: media/release-checks.png
  alt: "Four steps from left to right: generated draft, mark the statements, check each source, initials and release"
  ```

  An author writes the attributes on the opening line of the block in the
  lesson file. The block closes with a line `:::`, and its body is the caption:

  ```markdown
  :::figure{src=media/next-word.svg alt="The words 'The meeting moves to' with three candidates for the next word" size=medium provenance=invented}
  The assistant continues the sentence with one of the likely words.
  :::

  :::figure{src=media/ornaments/divider.svg decorative=true provenance=invented}
  :::
  ```

  A value with spaces stands in double quotes and holds no further double
  quote, so a quotation in `alt` uses single quotes. `provenance`, `collapsed_on`
  and `cite` belong to the block and not to `media`.

  ## Checks

  The messages below are errors at `media` in the line of the block. A value
  of the wrong type gives the cast message of its type, such as
  "`src` must be a string".

    * "a `figure` block needs the attribute `src`" when `src` is absent.
    * "`src` must be a path below `media/`: ..." followed by the broken rule of
      the media path, such as "a media path starts with `media/`" (for the value
      `images/a.png`) or "the media file name
      `Photo.PNG` must have the form `<key>.<extension>` with a key in the key
      format and one of the extensions ...".
    * "`src` of a `figure` block must name an image or an SVG file, with one of
      the extensions `png`, `jpg`, `jpeg`, `gif`, `webp`, `svg`" for a valid
      media path of another kind, such as a video or a captions file.
    * "`decorative` takes the value `true` only".
    * "a figure with `decorative=true` takes no `alt`" when both are present.
    * "a `figure` block needs the attribute `alt`, or `decorative=true` for an
      image that carries no information" when neither is present.
    * "`alt` must have at most 1,000 characters".
    * "`alt` must not be empty" for an `alt` of whitespace only.
    * "`size` must be one of `small`, `medium`, `full`".
    * "unknown field `caption`" for an attribute that the table does not list.

  The check across files, "the pack holds no media file `media/next-word.svg`",
  belongs to `Espalier.Catalog.Pack.Validator`: it reports a `src` that names no
  file below `media/` of the pack. The import also refuses a file that the media
  library does not accept, as [Media](media.md) describes.

  ## See also

    * [Media](media.md) for the media library, the conversion of files and the accepted formats
    * [Content packs](content-packs.md), section "The block `figure`"
    * `Espalier.Catalog.Pack.Schema.VideoMedia` for the attributes of a `video` block
    * `Espalier.Catalog.Pack.Schema.Block` for the block, its body and its other attributes
    * `Espalier.Catalog.Pack.MediaPath` for the rules of a media path
    * `Espalier.Catalog.Pack.Directives` for the syntax of the opening line
    * `Espalier.Catalog.Pack.Schema.Cast` for the shared value rules
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.MediaPath
  alias Espalier.Catalog.Pack.Schema.Cast

  @max_alt 1_000

  @primary_key false
  embedded_schema do
    field :src, :string
    field :alt, :string
    field :decorative, :string
    field :size, Ecto.Enum, values: [:small, :medium, :full]
  end

  @typedoc "The cast media attributes of a `figure` block."
  @type t :: %__MODULE__{}

  @doc "The largest number of characters of `alt`."
  @spec max_alt() :: pos_integer()
  def max_alt, do: @max_alt

  @doc "Casts the media attributes of a `figure` block."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(media, attrs) do
    media
    |> Cast.cast(attrs)
    |> validate_src()
    |> validate_decorative()
    |> validate_alt()
  end

  @doc "True when the cast attributes mark the figure as decorative."
  @spec decorative?(t()) :: boolean()
  def decorative?(%__MODULE__{decorative: "true"}), do: true
  def decorative?(%__MODULE__{}), do: false

  defp validate_src(changeset) do
    src = get_field(changeset, :src)

    cond do
      Cast.errored?(changeset, :src) ->
        changeset

      is_nil(src) ->
        Cast.add_entry_error(changeset, "a `figure` block needs the attribute `src`")

      true ->
        case src_error(src) do
          nil -> changeset
          message -> Cast.add(changeset, :src, message)
        end
    end
  end

  defp src_error(src) do
    case MediaPath.check(src) do
      :ok -> if MediaPath.kind(src) in [:image, :svg], do: nil, else: src_message()
      {:error, message} -> "`src` must be a path below `media/`: #{message}"
    end
  end

  defp src_message do
    extensions = MediaPath.extensions(:image) ++ MediaPath.extensions(:svg)

    "`src` of a `figure` block must name an image or an SVG file, with one of the " <>
      "extensions #{Enum.map_join(extensions, ", ", &"`#{&1}`")}"
  end

  defp validate_decorative(changeset) do
    case get_field(changeset, :decorative) do
      value when value in [nil, "true"] -> changeset
      _other -> Cast.add(changeset, :decorative, "`decorative` takes the value `true` only")
    end
  end

  defp validate_alt(changeset) do
    alt = get_field(changeset, :alt)
    decorative = get_field(changeset, :decorative)

    cond do
      Cast.errored?(changeset, :alt) or Cast.errored?(changeset, :decorative) ->
        changeset

      decorative == "true" and not is_nil(alt) ->
        Cast.add(changeset, :alt, "a figure with `decorative=true` takes no `alt`")

      decorative == "true" ->
        changeset

      is_nil(alt) ->
        Cast.add_entry_error(
          changeset,
          "a `figure` block needs the attribute `alt`, or `decorative=true` for an image " <>
            "that carries no information"
        )

      length(String.codepoints(alt)) > @max_alt ->
        Cast.add(changeset, :alt, "`alt` must have at most 1,000 characters")

      true ->
        changeset
    end
  end
end
