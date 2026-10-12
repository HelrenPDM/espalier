defmodule Espalier.Interop.SchemaFiles do
  @moduledoc """
  The XML schema files that a SCORM package carries at its root (task 0016,
  step 8). The repository does not hold them: the IMS files among them and
  `adlcp_rootv1p2.xsd`, the ADL file of SCORM 1.2, carry no license grant
  that clearly covers redistribution in an open-source repository
  (`priv/scorm/xsd/SOURCE.md`). `install/2` fetches them at build time into
  `priv/scorm/xsd/12/` and `priv/scorm/xsd/2004/`, which git ignores, and
  `Espalier.Interop.ExportWorker` copies the files of a version into each
  package of that version.

  `sources/0` pins one archive per version by URL and SHA-256, and every
  file taken from it by its path and SHA-256. `install/2` checks both and
  writes nothing that does not match, so a changed download fails the
  build instead of reaching a package. `mix espalier.scorm_xsd` runs it.
  """

  @typedoc "One pinned archive: the files of one version."
  @type source :: %{
          version: String.t(),
          label: String.t(),
          url: String.t(),
          sha256: String.t(),
          files: %{String.t() => String.t()}
        }

  @typedoc "Fetches a URL and returns the body."
  @type fetch :: (String.t() -> {:ok, binary()} | {:error, term()})

  @base "https://scorm.com/wp-content/assets/SchemaDefinitionFiles/zips/"

  @sources [
    %{
      version: "12",
      label: "SCORM 1.2",
      url: @base <> "scorm12schemadefinition.zip",
      sha256: "728d26a798de0e4c48cf2dd8e08b1037eb9e70d4f8c9d63221f5c4edc7f5338a",
      files: %{
        "adlcp_rootv1p2.xsd" =>
          "173decaf9cd31ea847e6ff6853c702137974aca6b56567151aa4a885e0aa4883",
        "imscp_rootv1p1p2.xsd" =>
          "d9ee699094e0db4518cf0143c81873d196b2683cf1c5ed770f108239ee079dda",
        "imsmd_rootv1p2p1.xsd" =>
          "51310a1097f373e619e54ef2ba9c050117de4822e6119a1cc2a3d07cfe450db9",
        "ims_xml.xsd" => "5209ff1d1e89cac16e797a2cdb0d5f345343ad97c1b125483a4bc6fc29319bd5"
      }
    },
    %{
      version: "2004",
      label: "SCORM 2004 4th edition",
      url: @base <> "scorm20044theditionschemadefinition%28nometadata%29.zip",
      sha256: "81ddd45740a7915e9927bc525cc2b6cd3f92e3119f7133c45fa1f2d8ec072ee6",
      files: %{
        "adlcp_v1p3.xsd" => "51a0515f707ca9a951ac945b7d13b201ffacc3800480e54a4e8bc6d88f13eaf1",
        "adlnav_v1p3.xsd" => "8a8559c6ab2bc6aa34689c5bc6be8dff269820c36ba8cb6f85b667c8094a2d3a",
        "adlseq_v1p3.xsd" => "4f2a55c07628d3a8ed133543e72dc7c4a3c0ebc2676268029fd40f339d56ecce",
        "datatypes.dtd" => "c8bd6bdf36184efe6e9ca0a11396254f1def5c6c3b28bce9f72216d685b02921",
        "imscp_v1p1.xsd" => "cf91ad47eeafa08193547d37ce950a837d7d49755ce90b7872c1ca7656b74369",
        "imsss_v1p0.xsd" => "daef999eb61a3755a483e86be07226d877dbdcf6062fb978a7e4069921f8ef7b",
        "imsss_v1p0auxresource.xsd" =>
          "c5985ad0f64a7fc780fe3e8b5ee85c983de54a1aba8df4a32dd4e6febcf43baa",
        "imsss_v1p0control.xsd" =>
          "5c74cfa648b2cf98b71a15e77a5e92ff75f111d72ac84766ccafff3d29ab8e43",
        "imsss_v1p0delivery.xsd" =>
          "ea44db41eeae1f8802117362236b68d3943bf3eafa8d41fa5ab5d7354a2b61f0",
        "imsss_v1p0limit.xsd" =>
          "5c1b1e5add19942ff205b423ea750959ffb79f080983b51ba5a62f185eff13ec",
        "imsss_v1p0objective.xsd" =>
          "6b196b71ac408141811899cd77b7cbeac5e3cbc239abf223de1777efedfaf4e8",
        "imsss_v1p0random.xsd" =>
          "195472fbb65a3daeda13edb9cb5a62adcc41287c61d7433a65b5b3ed32460e85",
        "imsss_v1p0rollup.xsd" =>
          "e0e95bafa5693eb7649946379ec735ad6a4f6389c6b385ae2296efc38b8a412f",
        "imsss_v1p0seqrule.xsd" =>
          "a391f0b7c7faee99207865df735dde2bb682ac07e4804b1140a7e2d9b8ec77d8",
        "imsss_v1p0util.xsd" =>
          "3afc09fead11951b1aa5db10f80d09874d516eded489b382aa3ee380f1eae814",
        "xml.xsd" => "987f7ddbb71278c7a5bbb2d46cfc3913a9c752670d8d3c0c4f88e827c25f5f94",
        "XMLSchema.dtd" => "68b500f142a9d1f69686f95184b23f6003515dfff3c8775d24521438507b6799"
      }
    }
  ]

  @doc "The pinned archives, one per SCORM version."
  @spec sources() :: [source()]
  def sources, do: @sources

  @doc """
  Checks the schema files of `source` below `dir`: the version directory
  holds exactly the pinned files with their checksums. Returns `:ok` or
  `{:error, problems}` with one text per missing, changed or extra file.
  """
  @spec verify(Path.t(), source()) :: :ok | {:error, [String.t()]}
  def verify(dir, %{version: version, files: files}) do
    version_dir = Path.join(dir, version)

    problems =
      Enum.flat_map(Enum.sort(files), &file_problem(version_dir, &1)) ++
        for rel <- files_below(version_dir),
            not Map.has_key?(files, rel),
            do: "#{rel} is not pinned"

    if problems == [], do: :ok, else: {:error, problems}
  end

  # The path joins the version directory and a key of the pinned file list.
  # sobelow_skip ["Traversal.FileModule"]
  defp file_problem(version_dir, {rel, sha256}) do
    case File.read(Path.join(version_dir, rel)) do
      {:ok, data} -> if sha256(data) == sha256, do: [], else: ["#{rel} differs"]
      {:error, _reason} -> ["#{rel} is missing"]
    end
  end

  @doc """
  Installs the schema files of every source below `dir`. A version whose
  files already verify is left as it is. Otherwise the archive is fetched
  with `fetch`, checked against its SHA-256, and the pinned files are taken
  from it, checked one by one and written to a new directory that then
  replaces the version directory.

  Returns `{:ok, results}` with `{source, :present | :installed}` per
  source, or `{:error, source, reason}` for the first source that fails.
  """
  @spec install(Path.t(), fetch(), [source()]) ::
          {:ok, [{source(), :present | :installed}]} | {:error, source(), String.t()}
  def install(dir, fetch \\ &fetch_https/1, sources \\ @sources) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, done} ->
      case install_source(dir, fetch, source) do
        {:ok, outcome} -> {:cont, {:ok, done ++ [{source, outcome}]}}
        {:error, reason} -> {:halt, {:error, source, reason}}
      end
    end)
  end

  defp install_source(dir, fetch, source) do
    if verify(dir, source) == :ok do
      {:ok, :present}
    else
      with {:ok, archive} <- fetch_archive(fetch, source),
           {:ok, entries} <- unpack(archive, source),
           :ok <- write_version(dir, source, entries) do
        {:ok, :installed}
      end
    end
  end

  defp fetch_archive(fetch, %{url: url, sha256: sha256}) do
    case fetch.(url) do
      {:ok, archive} when is_binary(archive) ->
        if sha256(archive) == sha256,
          do: {:ok, archive},
          else: {:error, "the archive from #{url} does not match its SHA-256"}

      {:error, reason} ->
        {:error, "the archive from #{url} could not be fetched: #{inspect(reason)}"}
    end
  end

  # The archive matched its pinned SHA-256, so its size is known; the
  # entries are taken in memory and only the pinned ones.
  defp unpack(archive, %{files: files}) do
    names = Enum.map(Map.keys(files), &String.to_charlist/1)

    case :zip.unzip(archive, [:memory, file_list: names]) do
      {:ok, entries} ->
        entries = Map.new(entries, fn {name, data} -> {List.to_string(name), data} end)
        check_entries(entries, files)

      {:error, reason} ->
        {:error, "the archive could not be read: #{inspect(reason)}"}
    end
  end

  defp check_entries(entries, files) do
    problems =
      for {rel, sha256} <- Enum.sort(files),
          problem = entry_problem(Map.get(entries, rel), sha256),
          do: "#{rel} #{problem}"

    if problems == [],
      do: {:ok, entries},
      else: {:error, "the archive does not hold the pinned files: " <> Enum.join(problems, ", ")}
  end

  defp entry_problem(nil, _sha256), do: "is missing"
  defp entry_problem(data, sha256), do: if(sha256(data) != sha256, do: "differs")

  # The paths are the keys of the pinned file list and the version, never
  # names read from the archive.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_version(dir, %{version: version}, entries) do
    target = Path.join(dir, version)
    part = target <> ".part"
    File.rm_rf!(part)

    Enum.each(entries, fn {rel, data} ->
      path = Path.join(part, rel)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, data)
    end)

    File.rm_rf!(target)
    File.rename!(part, target)
    :ok
  end

  @doc """
  Fetches `url` over HTTPS with `:httpc`, checking the server certificate
  against the CA certificates of the operating system.
  """
  @spec fetch_https(String.t()) :: {:ok, binary()} | {:error, term()}
  def fetch_https(url) do
    {:ok, _apps} = Application.ensure_all_started([:inets, :ssl])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    request = {String.to_charlist(url), [{~c"user-agent", ~c"espalier"}]}

    case :httpc.request(:get, request, [ssl: ssl, timeout: 60_000], body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> {:ok, body}
      {:ok, {{_version, status, _reason}, _headers, _body}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # The regular files below `dir` as paths relative to it, sorted.
  defp files_below(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.sort()
  end

  defp sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)
end
