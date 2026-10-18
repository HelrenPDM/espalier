defmodule Espalier.Catalog.Pack.Schema.Block do
  @moduledoc """
  A block of a lesson body: one `:::` directive with its attributes and its Markdown text.

  Blocks sit in the body of a lesson file, below the front matter that
  `Espalier.Catalog.Pack.Schema.Lesson` describes. The body is not YAML.
  `Espalier.Catalog.Pack.Directives.split/2` reads the directive syntax and
  hands every block over as a map with atom keys, which the validator turns
  into a map with string keys and casts with `changeset/2`. The order of the
  blocks in the file is their position in the lesson.

  A block opens with `:::<kind>{<attributes>}`, holds Markdown text, and ends
  with a line `:::`. The attributes map to the fields below:

  | Attribute | Field | Notes |
  |---|---|---|
  | `provenance` | `provenance` | `provenance=invented` |
  | `collapsed_on` | `collapsed_on` | Values separated by commas: `collapsed_on=short` or `collapsed_on="short,full"` |
  | `cite` | `cite` | Entries separated by commas: `cite="assistant-manual#Chapter 2"` |
  | `key` | `placeholder_key` | `placeholder` blocks only |
  | `src`, `alt`, `decorative`, `size` | `media` | `figure` blocks only, as a map from the attribute name to its value (section "Media blocks") |
  | `src`, `embed`, `title`, `poster`, `captions` | `media` | `video` blocks only, in the same form (section "Media blocks") |

  An attribute value without spaces needs no quotes. A value with spaces is
  written in double quotes and holds no further double quote.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `kind` | one of `text`, `explanation`, `example`, `case_comparison`, `quote`, `callout`, `placeholder`, `figure`, `video` | yes | The name after `:::`. |
  | `body` | string | yes, except on `figure` and `video` blocks | The lines between the opening and the closing line, without leading and trailing blank lines. The body is Markdown, is not empty, and holds no NUL character. It may hold glossary references `[[term:slug]]`, with an optional label after a vertical bar, which the validator resolves against `glossary.yaml`. The body holds no Markdown image syntax `![text](address)`, because an image belongs in a `figure` block (ASVS 1.3.5). On a `figure` block the body is the caption, and on a `video` block it is the transcript. Both may be absent: the validator passes `nil` for an empty body of these two kinds, while `changeset/2` rejects an empty string. |
  | `provenance` | one of `invented`, `sourced`, `vendor_statement`, `assumption`, `placeholder` | yes | Required in the attribute on every kind except `placeholder`, where the splitter sets `placeholder` when the attribute is absent. A `placeholder` block takes the provenance `placeholder` only (the splitter checks this), and no other kind takes it. |
  | `collapsed_on` | list of `short` or `full` | no | The paths on which the block starts collapsed. A value appears at most once. |
  | `cite` | list of string | `quote` blocks: at least one entry | Each entry has the form `source-key#locator`: a source key in the key format, `#`, and a locator that starts and ends with a character other than whitespace, has no line feed and has at most 255 characters. An entry appears at most once. The source key must name an entry of `sources.yaml`, which the validator checks across files. A locator holds no comma, because the comma separates the entries. |
  | `placeholder_key` | key | `placeholder` blocks: yes, checked by the splitter | The key format `^[a-z0-9][a-z0-9-]*$` with at most 255 characters. It names the policy whose current version the block renders. The attribute `key` is valid on `placeholder` blocks only. The validator checks the format of the key and no other source for it. |
  | `media` | map | `figure` and `video` blocks: yes | The media attributes of the block as a map with string keys and string values, which `Espalier.Catalog.Pack.Schema.FigureMedia` or `Espalier.Catalog.Pack.Schema.VideoMedia` casts. After the cast, `media` holds that struct. Other kinds take no `media`. |
  | `line` | integer | yes | The line of the opening line in the lesson file. The splitter sets it, and errors of the block refer to it. |

  ## Kinds

  | Kind | Content |
  |---|---|
  | `text` | Running text |
  | `explanation` | An explanation that can start collapsed and that items open through `reveals` |
  | `example` | An example |
  | `case_comparison` | A comparison of cases. A lesson with such a block that an objective names in `taught_in` gives a `classification` item the evidence kind `classification_with_case_comparison`. |
  | `quote` | A quotation; it cites at least one source |
  | `callout` | A highlighted note |
  | `placeholder` | The place of a policy text. The player renders the current version of the policy that `key` names. Until a version exists, the block shows its own body. |
  | `figure` | An image or an SVG file of the pack with its text alternative; the body is the caption |
  | `video` | A video file of the pack, an external video file or the player of a streaming service; the body is the transcript |

  ## Provenance

  Every block shows where its content comes from.

  | Value | Use |
  |---|---|
  | `invented` | Content written for the pack, such as the cases of the demo pack |
  | `sourced` | Content that rests on a source; `cite` names the source |
  | `vendor_statement` | A statement that a vendor makes about its own product |
  | `assumption` | An assumption of the authors |
  | `placeholder` | Text that the organization replaces. Only `placeholder` blocks carry it. |

  The validator requires a citation on `quote` blocks only. A `sourced` block
  without `cite` raises no error.

  ## Example

  Authors write blocks as directives in the lesson file:

  ```markdown
  :::explanation{collapsed_on=short provenance=sourced cite="vendor-guide#Overview"}
  The next word follows from probabilities learned in training.
  :::

  :::quote{provenance=sourced cite="assistant-manual#Chapter 5"}
  Mark every shared document that the assistant helped to draft.
  :::

  :::placeholder{key=input-rules}
  Your organization adds its rules for inputs here.
  :::
  ```

  The validator passes the second block to `changeset/2` as the following map,
  shown as YAML with the string keys that the validator builds from the map of
  the splitter. The source key `assistant-manual` is checked across
  files against `sources.yaml`.

  ```yaml
  kind: quote
  body: Mark every shared document that the assistant helped to draft.
  provenance: sourced
  cite:
    - assistant-manual#Chapter 5
  line: 5
  ```

  The third block arrives with the provenance `placeholder` and the key as
  `placeholder_key`:

  ```yaml
  kind: placeholder
  body: Your organization adds its rules for inputs here.
  provenance: placeholder
  placeholder_key: input-rules
  line: 9
  ```

  ## Media blocks

  A `figure` and a `video` block take further attributes. The splitter
  collects them in `media`, a map from the attribute name to its raw value,
  and `changeset/2` casts that map with the schema of the kind. The two
  modules list the attributes and their rules:
  `Espalier.Catalog.Pack.Schema.FigureMedia` for `src`, `alt`, `decorative`
  and `size`, and `Espalier.Catalog.Pack.Schema.VideoMedia` for `src`,
  `embed`, `title`, `poster` and `captions`. The value of `decorative` is
  the string `true`.

  Two rules couple the media attributes to the body of a `video` block. A
  video file (`src`) needs `captions` or a transcript in the body, and an
  embed (`embed` without `src`) needs a transcript in the body. The
  validator also checks that the pack holds every file that `src`,
  `poster` and `captions` name below `media/`.

  ```markdown
  :::figure{src=media/next-word.svg alt="The words 'The meeting moves to' with three candidates for the next word" size=medium provenance=invented}
  The assistant continues the sentence with one of the likely words.
  :::

  :::video{src=media/release-checks.webm title="The release checks of a generated notice" captions=media/release-checks-en.vtt:en provenance=invented}
  A colleague reads a generated notice about a moved meeting and checks it before she shares it.
  :::
  ```

  The validator passes the two blocks to `changeset/2` as the following maps:

  ```yaml
  kind: figure
  body: The assistant continues the sentence with one of the likely words.
  provenance: invented
  media:
    src: media/next-word.svg
    alt: "The words 'The meeting moves to' with three candidates for the next word"
    size: medium
  line: 1
  ```

  ```yaml
  kind: video
  body: A colleague reads a generated notice about a moved meeting and checks it before she shares it.
  provenance: invented
  media:
    src: media/release-checks.webm
    title: The release checks of a generated notice
    captions: "media/release-checks-en.vtt:en"
  line: 5
  ```

  A figure that carries no information has no caption. The validator passes
  `nil` as its body, which the example leaves out:

  ```yaml
  kind: figure
  provenance: invented
  media:
    src: media/divider.svg
    decorative: "true"
  line: 9
  ```

  ## Checks

  The validator reports the errors of a block at the line of its opening line
  in the lesson file. The loader reports the syntax errors of the directive lines, which
  `Espalier.Catalog.Pack.Directives` finds, when it reads the file.

    * `` `kind` must be one of `text`, `explanation`, `example`, `case_comparison`, `quote`, `callout`, `placeholder`, `figure`, `video` ``
      and the corresponding message for `provenance`;
    * `` entries of `collapsed_on` must be one of `short`, `full` ``;
    * ``duplicate entry `:short` in `collapsed_on` `` (the entry in atom notation, because the field holds enum values) and ``duplicate entry `a#b` in `cite` `` (the plain string);
    * `` `cite` entry `<value>` does not have the form `source-key#locator` ``;
    * ``the locator of a `cite` entry must have at most 255 characters``;
    * ``unknown source `<key>` in `cite` ``: the source key is no entry of `sources.yaml`;
    * ``a `quote` block cites at least one source``;
    * ``the provenance `placeholder` belongs to `placeholder` blocks only``;
    * `` `placeholder_key` value `<value>` does not match the key format `^[a-z0-9][a-z0-9-]*$` ``;
    * `` `body` must not be empty ``;
    * ``unknown glossary term `<slug>` in `<reference>` `` for a `[[term:...]]` reference in the body;
    * ``use a figure block for images`` for a body that holds the Markdown image syntax `![text](address)`;
    * ``only `figure` and `video` blocks take media attributes`` for a `media` map on another kind;
    * ``an embedded video needs a transcript in the body`` and ``a video file needs `captions` or a transcript in the body``;
    * the messages of `Espalier.Catalog.Pack.Schema.FigureMedia` and `Espalier.Catalog.Pack.Schema.VideoMedia` for the rules of the media attributes, reported at `media`;
    * ``the pack holds no media file `<path>` `` for a path in `src`, `poster` or `captions` that names no file below `media/`.

  ## See also

    * [Content packs](content-packs.md), sections "Lesson directives" and "Provenance"
    * `Espalier.Catalog.Pack.Directives` for the syntax and its errors
    * `Espalier.Catalog.Pack.Schema.Lesson` for the front matter of the file
    * `Espalier.Catalog.Pack.Schema.Source` for the sources that `cite` names
    * `Espalier.Catalog.Pack.Schema.FigureMedia` for the attributes of a `figure` block
    * `Espalier.Catalog.Pack.Schema.VideoMedia` for the attributes of a `video` block
    * `Espalier.Catalog.Pack.Schema.Cast` for the shared value rules
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

  @typedoc "A block of a lesson body with its attributes."
  @type t :: %__MODULE__{}

  @doc """
  The block kinds that carry `media` and may have an empty body: `:figure`
  and `:video`.
  """
  @spec media_kinds() :: [atom()]
  def media_kinds, do: Map.keys(@media_schemas)

  @doc """
  Casts a block of a lesson body, a map with string keys, as the validator
  builds it from the map with atom keys that
  `Espalier.Catalog.Pack.Directives.split/2` returns.

  Returns an `Ecto.Changeset` that is valid when the block satisfies the rules
  of the moduledoc. The `body` of a `figure` or `video` block may be absent,
  and the `media` of these two kinds holds the cast media struct in the
  changeset.
  """
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
