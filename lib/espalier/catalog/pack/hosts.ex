defmodule Espalier.Catalog.Pack.Hosts do
  @moduledoc """
  The installation check of the external media of a content pack (task
  0018, step 10; ASVS 1.2.2).

  `check/2` runs over the directive blocks of the loaded lessons, which
  carry their file and their line, and returns an error entry for every
  `video` block whose external `src` names a host outside `external` or
  whose `embed` names a host outside `embed`, such as
  `host cdn.example.org is not in MEDIA_EXTERNAL_HOSTS`. The hosts are the
  lists `{host, port | nil}` of `MEDIA_EXTERNAL_HOSTS` and
  `MEDIA_EMBED_HOSTS` (`installation/0`). The comparison follows
  `Espalier.Credentials.Webhook`: the host of the URL is compared in lower
  case, an entry without a port admits the default port of `https`, 443,
  only, and an entry with a port admits that port.

  The function is pure. It checks only values that parse as `https:` URLs
  with a host; every other value of `src` and `embed` is an error of the
  validator (`Espalier.Catalog.Pack.Schema.VideoMedia`). `mix
  espalier.validate` stays independent of the installation and runs no such
  check.
  """

  alias Espalier.Catalog.Pack.{Entries, Loader}
  alias Espalier.Catalog.Pack.Schema.VideoMedia
  alias Espalier.Media

  @typedoc "The allowlists: `{host, port | nil}` with the host in lower case."
  @type hosts :: %{
          external: [{String.t(), pos_integer() | nil}],
          embed: [{String.t(), pos_integer() | nil}]
        }

  @typedoc "An error entry at the file and the line of a block."
  @type entry :: %{file: String.t(), line: pos_integer(), message: String.t()}

  @https_port 443

  @doc "The allowlists of the installation, from `Espalier.Media`."
  @spec installation() :: hosts()
  def installation, do: %{external: Media.external_hosts(), embed: Media.embed_hosts()}

  @doc """
  Returns the error entries of the external sources and embeds of `loaded`
  whose hosts `hosts` does not admit, sorted by file, line and message and
  bounded as the other entries of a report (`Espalier.Catalog.Pack.Entries`).
  """
  @spec check(Loader.loaded() | map(), hosts()) :: [entry()]
  def check(loaded, %{external: external, embed: embed}) do
    for module <- Map.get(loaded, :modules, []),
        lesson <- module.lessons,
        block <- lesson.blocks,
        message <- block_messages(block, external, embed) do
      %{file: lesson.file, line: block.line, message: message}
    end
    |> Entries.sort()
    |> Entries.limit(:error)
  end

  defp block_messages(%{kind: "video", media: %{} = media}, external, embed) do
    src =
      case Map.get(media, "src") do
        src when is_binary(src) -> url_messages(src, external, "MEDIA_EXTERNAL_HOSTS")
        _other -> []
      end

    src ++ url_messages(Map.get(media, "embed"), embed, "MEDIA_EMBED_HOSTS")
  end

  defp block_messages(_block, _external, _embed), do: []

  defp url_messages(value, hosts, variable) when is_binary(value) do
    with true <- VideoMedia.url?(value),
         {:ok, %URI{scheme: scheme, host: host, port: port}}
         when is_binary(scheme) and is_binary(host) and host != "" <- URI.new(value),
         "https" <- String.downcase(scheme) do
      host = String.downcase(host)

      if allowed?(hosts, host, port),
        do: [],
        else: ["host #{shown(host, port)} is not in #{variable}"]
    else
      _other -> []
    end
  end

  defp url_messages(_value, _hosts, _variable), do: []

  defp allowed?(hosts, host, port) do
    Enum.any?(hosts, fn {entry_host, entry_port} ->
      String.downcase(entry_host) == host and (entry_port || @https_port) == port
    end)
  end

  defp shown(host, @https_port), do: host
  defp shown(host, port), do: "#{host}:#{port}"
end
