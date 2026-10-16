defmodule Espalier.Catalog.Pack.Schema.Block do
  @moduledoc """
  A block of a lesson body, as `Espalier.Catalog.Pack.Directives.split/2`
  returns it: `kind`, `body`, `provenance`, `collapsed_on` (`short`, `full`),
  `cite` (`source-key#locator`), `placeholder_key` (key format), `media`
  and `line`, the line of its opening line in the lesson file.

  A `quote` block cites at least one source, and the provenance
  `placeholder` belongs to `placeholder` blocks only (README principle 4).

  A `figure` and a `video` block (task 0018, step 9) carry their media
  attributes in `media`, which `Espalier.Catalog.Pack.Schema.FigureMedia`
  and `Espalier.Catalog.Pack.Schema.VideoMedia` cast; after the cast,
  `media` holds the cast struct. Their body, the caption of a figure and
  the transcript of a video, may be absent: the validator passes `nil` for
  an empty body, and every other kind requires a body. A video file needs
  `captions` or a transcript, and an embed needs a transcript. No body
  holds the Markdown image syntax `![...](`, because an image belongs in a
  `figure` block (ASVS 1.3.5).
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_change: 2, get_field: 2, put_change: 3]

  alias Espalier.Catalog.Pack.Schema.{Cast, FigureMedia, VideoMedia}

  @media_schemas %{figure: FigureMedia, video: VideoMedia}
  @image_regex ~r/!\[[^\]]*\]\(/

  @primary_key false
  embedded_schema do
    field :kind, Ecto.Enum,
      values: [
        :text,
        :explanation,
        :example,
        :case_comparison,
        :quote,
        :callout,
        :placeholder,
        :figure,
        :video
      ]

    field :body, :string

    field :provenance, Ecto.Enum,
      values: [:invented, :sourced, :vendor_statement, :assumption, :placeholder]

    field :collapsed_on, {:array, Ecto.Enum}, values: [:short, :full]
    field :cite, {:array, :string}
    field :placeholder_key, :string
    field :media, :map
    field :line, :integer, virtual: true
  end

  @type t :: %__MODULE__{}

  @doc "The block kinds that carry `media` and may have an empty body."
  @spec media_kinds() :: [atom()]
  def media_kinds, do: Map.keys(@media_schemas)

  @doc "Casts a block of a lesson body."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(block, attrs) do
    block
    |> Cast.cast(attrs, required: required(attrs))
    |> Cast.validate_unique(:collapsed_on)
    |> Cast.validate_cite(:cite)
    |> Cast.validate_unique(:cite)
    |> Cast.validate_key(:placeholder_key)
    |> validate_quote()
    |> validate_provenance()
    |> validate_image_syntax()
    |> validate_media()
  end

  defp required(%{"kind" => kind}) when kind in ["figure", "video"],
    do: [:kind, :provenance, :line]

  defp required(_attrs), do: [:kind, :body, :provenance, :line]

  defp validate_quote(changeset) do
    if get_field(changeset, :kind) == :quote and List.wrap(get_field(changeset, :cite)) == [],
      do: Cast.add_entry_error(changeset, "a `quote` block cites at least one source"),
      else: changeset
  end

  defp validate_provenance(changeset) do
    kind = get_field(changeset, :kind)

    if get_field(changeset, :provenance) == :placeholder and not is_nil(kind) and
         kind != :placeholder,
       do:
         Cast.add(
           changeset,
           :provenance,
           "the provenance `placeholder` belongs to `placeholder` blocks only"
         ),
       else: changeset
  end

  defp validate_image_syntax(changeset) do
    case get_change(changeset, :body) do
      body when is_binary(body) ->
        if Regex.match?(@image_regex, body),
          do: Cast.add(changeset, :body, "use a figure block for images"),
          else: changeset

      _other ->
        changeset
    end
  end

  defp validate_media(changeset) do
    kind = get_field(changeset, :kind)
    raw = get_change(changeset, :media)

    cond do
      Cast.errored?(changeset, :media) ->
        changeset

      is_map_key(@media_schemas, kind) ->
        changeset
        |> put_change(:media, raw || %{})
        |> Cast.cast_nested(:media, Map.fetch!(@media_schemas, kind))
        |> validate_text(kind, raw || %{})

      is_nil(raw) ->
        changeset

      true ->
        Cast.add(changeset, :media, "only `figure` and `video` blocks take media attributes")
    end
  end

  # A video file needs captions or a transcript, and an embed a transcript
  # (WCAG 2.2 1.2.1 and 1.2.2 as far as the validator can check them).
  defp validate_text(changeset, :video, raw) do
    transcript? = not is_nil(get_field(changeset, :body))

    cond do
      transcript? ->
        changeset

      Map.has_key?(raw, "embed") and not Map.has_key?(raw, "src") ->
        Cast.add(changeset, :body, "an embedded video needs a transcript in the body")

      Map.has_key?(raw, "src") and not Map.has_key?(raw, "captions") ->
        Cast.add(changeset, :body, "a video file needs `captions` or a transcript in the body")

      true ->
        changeset
    end
  end

  defp validate_text(changeset, _kind, _raw), do: changeset
end
