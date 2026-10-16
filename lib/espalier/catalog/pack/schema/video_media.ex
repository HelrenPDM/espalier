defmodule Espalier.Catalog.Pack.Schema.VideoMedia do
  @moduledoc """
  The media attributes of a `video` block (task 0018, step 9; ASVS 1.2.2
  and 2.2.3), as `Espalier.Catalog.Pack.Directives.split/2` collects them:

  | Attribute | Value |
  |---|---|
  | `src` | a path below `media/` of a video file, or an external file: an absolute `https:` URL with a host, without user information, of at most 2,000 characters, whose path ends in `.webm` or `.mp4` |
  | `embed` | the player of a streaming service: an absolute `https:` URL with a host, without user information, of at most 2,000 characters |
  | `title` | required, 1 to 255 characters |
  | `poster` | a path below `media/` of an image; not with `embed` |
  | `captions` | 1 to 8 entries `<path>:<language>`, separated by commas: a path below `media/` with the extension `vtt` and a BCP 47 language tag; each language once, compared without regard to case; not with `embed` |

  A block has exactly one of `src` and `embed`. A path of an external `src`
  that ends in `.m3u8` or `.mpd` names a stream, which needs the player of
  an embed. The body of the block is the transcript; `Schema.Block` checks
  that a video file has captions or a transcript and that an embed has a
  transcript. The validator checks that the pack holds the files that the
  paths name, and `Espalier.Catalog.Pack.Hosts` checks the hosts of the
  URLs against the allowlists of the installation.
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
