defmodule Espalier.Catalog.Pack.Schema.FigureMedia do
  @moduledoc """
  The media attributes of a `figure` block (task 0018, step 9; ASVS 2.2.3),
  as `Espalier.Catalog.Pack.Directives.split/2` collects them:

  | Attribute | Value |
  |---|---|
  | `src` | required: a path below `media/` of an image or an SVG file (`Espalier.Catalog.Pack.MediaPath`) |
  | `alt` | the text alternative, 1 to 1,000 characters; required unless `decorative=true`, and absent with it |
  | `decorative` | `true` only: the image carries no information, and the player gives it an empty text alternative |
  | `size` | `small`, `medium` or `full` (the default) |

  The body of the block is the caption and may be empty. The validator
  checks that the pack holds the file that `src` names.
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
