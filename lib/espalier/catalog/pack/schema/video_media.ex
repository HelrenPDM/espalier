defmodule Espalier.Catalog.Pack.Schema.VideoMedia do
  @moduledoc """
  The media attributes of a `video` block: the video file or player, its title, its poster and its captions.

  The attributes stand on the opening line of a `video` block in a lesson file,
  in the braces after `:::video`. `Espalier.Catalog.Pack.Directives.split/2`
  collects `src`, `embed`, `title`, `poster` and `captions` in the map `media`
  of the block, with the raw values as strings, and
  `Espalier.Catalog.Pack.Schema.Block` casts that map with this module. The
  body of the block is the transcript.

  A block has exactly one of `src` and `embed`. `src` names a video file of the
  pack or an external video file, which the browser of the learner loads from
  its host. `embed` names the player of a streaming service, which the lesson
  shows in an `iframe`. The server fetches neither external kind.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `src` | string | exactly one of `src` and `embed` | Either a media path of a video file of the pack or an external file. A media path is `media/`, then zero to three directories, then `<key>.<extension>`, with the extension `mp4`, `m4v`, `mov`, `webm` or `mkv` in lower case (`Espalier.Catalog.Pack.MediaPath`). A value that starts with a scheme such as `https:` is an external file: an absolute `https:` URL with a host, without user information, of at most 2,000 characters, whose path (without query and fragment) ends in `.webm` or `.mp4`, compared in lower case. A path that ends in `.m3u8` or `.mpd` names a stream and needs `embed`. |
  | `embed` | string | exactly one of `src` and `embed` | The player of a streaming service: an absolute `https:` URL with a host, without user information, of at most 2,000 characters. No rule applies to the path of the URL. |
  | `title` | string | yes | 1 to 255 characters. The player shows it as the label of the block. |
  | `poster` | string | no | A media path of an image with the extension `png`, `jpg`, `jpeg`, `gif` or `webp`. An SVG file is no poster. Not allowed together with `embed`. |
  | `captions` | string | no | 1 to 8 entries `<path>:<language>`, separated by commas, with optional whitespace around an entry. The path is a media path with the extension `vtt`. The language is a BCP 47 language tag: 2 or 3 lower-case letters, then any number of groups of a hyphen and 2 to 8 letters or digits, such as `en` or `pt-BR`. A language appears once, compared without regard to case, so `pt-BR` and `pt-br` count as one. The first entry is the default track of the player. Not allowed together with `embed`. |

  A field that the table does not list is an error. A `null` value counts as
  absent. Every string is not empty after trimming whitespace and holds no NUL
  character (`Espalier.Catalog.Pack.Schema.Cast`).

  ## Text for the video

  The body of the block is the transcript, in Markdown, and the player shows it
  under the video in a closed disclosure "Transcript". Two rules couple the
  body to the attributes. `Espalier.Catalog.Pack.Schema.Block` checks them:

  | Video | Needs |
  |---|---|
  | A video file (`src`, in the pack or external) | `captions` or a transcript in the body |
  | An embed (`embed`) | a transcript in the body, because the validator cannot look into the player of another service |

  The criteria of WCAG 2.2 for audio description and for captions of every
  video with sound go further than these checks, as [Media](media.md), section
  "Captions and transcripts", lists.

  ## Example

  The first example is a video file of the pack with a poster and captions in
  two languages. The second is an external file, and the third the player of a
  streaming service. The examples show the map that the validator passes to
  `changeset/2`, written as YAML.

  ```yaml
  src: media/release-checks.webm
  title: The release checks of a generated notice
  poster: media/release-checks-start.png
  captions: "media/release-checks-en.vtt:en,media/release-checks-de.vtt:de"
  ```

  ```yaml
  src: "https://cdn.example.org/clips/release-checks.mp4"
  title: The release checks of a generated notice
  ```

  ```yaml
  embed: "https://player.example.org/embed/release-checks"
  title: The release checks of a generated notice
  ```

  An author writes the attributes on the opening line of the block in the
  lesson file. The body between the opening and the closing line is the
  transcript:

  ```markdown
  :::video{src=media/release-checks.webm title="The release checks of a generated notice" poster=media/release-checks-start.png captions="media/release-checks-en.vtt:en,media/release-checks-de.vtt:de" provenance=invented}
  A colleague reads a generated notice about a moved meeting and checks it before she shares it.
  :::

  :::video{embed="https://player.example.org/embed/release-checks" title="The release checks of a generated notice" provenance=invented}
  A colleague reads a generated notice about a moved meeting and checks it before she shares it.
  :::
  ```

  A value with spaces stands in double quotes, which the value does not
  contain. The quotes around a `captions` value are needed only when the value
  contains whitespace, for example after a comma. `provenance`, `collapsed_on` and `cite` belong to the
  block and not to `media`.

  ## Checks

  The messages below are errors at `media` in the line of the block. A value
  of the wrong type gives the cast message of its type, such as
  "`title` must be a string".

    * "a `video` block needs `src` for a video file or `embed` for a player"
      when both are absent, and "a `video` block takes exactly one of `src` and
      `embed`" when both are present.
    * "`src` must be a path below `media/` or an `https:` URL: ..." followed by
      the broken rule of the media path, for a value that starts with no scheme.
    * "`src` of a `video` block must name a video file, with one of the
      extensions `mp4`, `m4v`, `mov`, `webm`, `mkv`" for a valid media path of
      another kind.
    * "an external `src` must have at most 2,000 characters" and "an external
      `src` must be an absolute `https:` URL with a host and without user
      information", for a value that starts with a scheme.
    * "streams need an embed player: use embed" for an external `src` whose path
      ends in `.m3u8` or `.mpd`, and "an external `src` must name a file whose
      path ends in `.webm` or `.mp4`" for any other path.
    * "`embed` must have at most 2,000 characters" and "`embed` must be an
      absolute `https:` URL with a host and without user information".
    * "a `video` block needs the attribute `title`" and "`title` must have at
      most 255 characters".
    * "a poster needs a video file: use src" for a `poster` together with
      `embed`, and "`poster` must be a path below `media/` of an image, with one
      of the extensions `png`, `jpg`, `jpeg`, `gif`, `webp`" for any other
      value that is no media path of an image.
    * "captions need a video file: use src" for `captions` together with
      `embed`.
    * "`captions` holds at most 8 entries".
    * "each entry of `captions` has the form `<path>:<language>`, such as
      `media/intro-en.vtt:en`", which also covers an empty entry such as a
      trailing comma.
    * "the captions file `<path>` must be a path below `media/` with the
      extension `vtt`".
    * "the captions language `<tag>` must be a BCP 47 language tag such as `en`
      or `pt-BR`" and "the captions language `<tag>` appears more than once".
    * "unknown field `<name>`" for an attribute that the table does not list.

  Further checks belong to other modules:

    * `Espalier.Catalog.Pack.Schema.Block` reports "an embedded video needs a
      transcript in the body" and "a video file needs `captions` or a transcript
      in the body" at `body`.
    * `Espalier.Catalog.Pack.Validator` reports "the pack holds no media file
      `<path>`" for a media path in `src`, `poster` or `captions` that names no
      file below `media/` of the pack. An external `src` has no such check.
    * `Espalier.Catalog.Pack.Hosts` reports a host outside the allowlists of the
      installation, such as "host cdn.example.org is not in
      MEDIA_EXTERNAL_HOSTS", for an external `src` (list `MEDIA_EXTERNAL_HOSTS`)
      and an `embed` (list `MEDIA_EMBED_HOSTS`).

  ## See also

    * [Media](media.md) for external files and embeds, the allowlists, captions and transcripts
    * [Content packs](content-packs.md), section "The block `video`"
    * `Espalier.Catalog.Pack.Schema.FigureMedia` for the attributes of a `figure` block
    * `Espalier.Catalog.Pack.Schema.Block` for the block, its body and its other attributes
    * `Espalier.Catalog.Pack.MediaPath` for the rules of a media path
    * `Espalier.Catalog.Pack.Hosts` for the check of the hosts
    * `Espalier.Catalog.Pack.Directives` for the syntax of the opening line
    * `Espalier.Catalog.Pack.Schema.Cast` for the shared value rules
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.MediaPath
  alias Espalier.Catalog.Pack.Schema.Cast

  @max_url 2_000
  @max_captions 8
  @language_regex ~r/\A[a-z]{2,3}(-[A-Za-z0-9]{2,8})*\z/
  @scheme_regex ~r/\A[A-Za-z][A-Za-z0-9+.-]*:/

  @primary_key false
  embedded_schema do
    field :src, :string
    field :embed, :string
    field :title, :string
    field :poster, :string
    field :captions, :string
  end

  @typedoc "The cast media attributes of a `video` block."
  @type t :: %__MODULE__{}

  @typedoc "A captions track: the path of its file and its language."
  @type track :: %{src: String.t(), lang: String.t()}

  @doc "The largest number of characters of an external `src` or of `embed`."
  @spec max_url() :: pos_integer()
  def max_url, do: @max_url

  @doc "The largest number of captions entries."
  @spec max_captions() :: pos_integer()
  def max_captions, do: @max_captions

  @doc "The format of a captions language, a BCP 47 language tag."
  @spec language_regex() :: Regex.t()
  def language_regex, do: @language_regex

  @doc """
  True when the value of `src` is a URL, that is, starts with a scheme such
  as `https:`, and no path below `media/`.
  """
  @spec url?(String.t()) :: boolean()
  def url?(value) when is_binary(value), do: Regex.match?(@scheme_regex, value)

  @doc """
  Parses the value of `captions` into its tracks in the order of the value,
  or answers the message of the first broken rule.
  """
  @spec tracks(String.t()) :: {:ok, [track()]} | {:error, String.t()}
  def tracks(value) when is_binary(value) do
    entries = value |> String.split(",") |> Enum.map(&String.trim/1)

    if length(entries) > @max_captions,
      do: {:error, "`captions` holds at most #{@max_captions} entries"},
      else: collect_tracks(entries, [])
  end

  defp collect_tracks([], tracks), do: {:ok, Enum.reverse(tracks)}

  defp collect_tracks([entry | rest], tracks) do
    with {:ok, track} <- track(entry, tracks), do: collect_tracks(rest, [track | tracks])
  end

  @doc "Casts the media attributes of a `video` block."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(media, attrs) do
    media
    |> Cast.cast(attrs)
    |> validate_source()
    |> validate_title()
    |> validate_poster()
    |> validate_captions()
  end

  defp track(entry, tracks) do
    with [_entry, path, lang] <- Regex.run(~r/\A(.*):([^:]*)\z/s, entry),
         :ok <- captions_path(path),
         :ok <- language(lang),
         :ok <- distinct(lang, tracks) do
      {:ok, %{src: path, lang: lang}}
    else
      {:error, message} ->
        {:error, message}

      nil ->
        {:error,
         "each entry of `captions` has the form `<path>:<language>`, such as " <>
           "`media/intro-en.vtt:en`"}
    end
  end

  defp captions_path(path) do
    if MediaPath.check(path) == :ok and MediaPath.kind(path) == :captions,
      do: :ok,
      else:
        {:error,
         "the captions file `#{path}` must be a path below `media/` with the extension `vtt`"}
  end

  defp language(lang) do
    if Regex.match?(@language_regex, lang),
      do: :ok,
      else:
        {:error,
         "the captions language `#{lang}` must be a BCP 47 language tag such as `en` or `pt-BR`"}
  end

  # BCP 47 tags are case-insensitive (RFC 5646, section 2.1.1), so `pt-BR`
  # and `pt-br` name one language.
  defp distinct(lang, tracks) do
    lang_key = String.downcase(lang)

    if Enum.any?(tracks, &(String.downcase(&1.lang) == lang_key)),
      do: {:error, "the captions language `#{lang}` appears more than once"},
      else: :ok
  end

  defp validate_source(changeset) do
    src = get_field(changeset, :src)
    embed = get_field(changeset, :embed)

    cond do
      Cast.errored?(changeset, :src) or Cast.errored?(changeset, :embed) ->
        changeset

      is_nil(src) and is_nil(embed) ->
        Cast.add_entry_error(
          changeset,
          "a `video` block needs `src` for a video file or `embed` for a player"
        )

      not is_nil(src) and not is_nil(embed) ->
        Cast.add_entry_error(changeset, "a `video` block takes exactly one of `src` and `embed`")

      not is_nil(src) ->
        add_message(changeset, :src, src_error(src))

      true ->
        add_message(changeset, :embed, url_error(embed, "`embed`"))
    end
  end

  defp add_message(changeset, _field, nil), do: changeset
  defp add_message(changeset, field, message), do: Cast.add(changeset, field, message)

  defp src_error(src) do
    if url?(src),
      do: url_error(src, "an external `src`") || file_error(src),
      else: media_src_error(src)
  end

  defp media_src_error(src) do
    case MediaPath.check(src) do
      :ok -> if MediaPath.kind(src) == :video, do: nil, else: video_path_message()
      {:error, message} -> "`src` must be a path below `media/` or an `https:` URL: #{message}"
    end
  end

  defp video_path_message do
    "`src` of a `video` block must name a video file, with one of the extensions " <>
      Enum.map_join(MediaPath.extensions(:video), ", ", &"`#{&1}`")
  end

  # The rules of an external `src` and of `embed` (ASVS 1.2.2).
  defp url_error(value, name) do
    cond do
      length(String.codepoints(value)) > @max_url ->
        "#{name} must have at most 2,000 characters"

      https_url?(value) ->
        nil

      true ->
        "#{name} must be an absolute `https:` URL with a host and without user information"
    end
  end

  defp https_url?(value) do
    case URI.new(value) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil}}
      when is_binary(scheme) and is_binary(host) and host != "" ->
        String.downcase(scheme) == "https"

      _other ->
        false
    end
  end

  defp file_error(src) do
    path = src |> URI.new!() |> Map.get(:path) |> Kernel.||("") |> String.downcase()

    cond do
      String.ends_with?(path, [".webm", ".mp4"]) -> nil
      String.ends_with?(path, [".m3u8", ".mpd"]) -> "streams need an embed player: use embed"
      true -> "an external `src` must name a file whose path ends in `.webm` or `.mp4`"
    end
  end

  defp validate_title(changeset) do
    cond do
      Cast.errored?(changeset, :title) ->
        changeset

      is_nil(get_field(changeset, :title)) ->
        Cast.add_entry_error(changeset, "a `video` block needs the attribute `title`")

      true ->
        Cast.validate_max_length(changeset, :title)
    end
  end

  defp validate_poster(changeset) do
    poster = get_field(changeset, :poster)

    cond do
      is_nil(poster) or Cast.errored?(changeset, :poster) ->
        changeset

      not is_nil(get_field(changeset, :embed)) ->
        Cast.add(changeset, :poster, "a poster needs a video file: use src")

      MediaPath.check(poster) == :ok and MediaPath.kind(poster) == :image ->
        changeset

      true ->
        Cast.add(
          changeset,
          :poster,
          "`poster` must be a path below `media/` of an image, with one of the extensions " <>
            Enum.map_join(MediaPath.extensions(:image), ", ", &"`#{&1}`")
        )
    end
  end

  defp validate_captions(changeset) do
    captions = get_field(changeset, :captions)

    cond do
      is_nil(captions) or Cast.errored?(changeset, :captions) ->
        changeset

      not is_nil(get_field(changeset, :embed)) ->
        Cast.add(changeset, :captions, "captions need a video file: use src")

      true ->
        case tracks(captions) do
          {:ok, _tracks} -> changeset
          {:error, message} -> Cast.add(changeset, :captions, message)
        end
    end
  end
end
