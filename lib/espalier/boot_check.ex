defmodule Espalier.BootCheck do
  @moduledoc """
  Checks the environment before the configuration is built (task 0017,
  step 4). `config/runtime.exs` calls `errors/2` in every environment
  directly after `import Config` and raises once with all messages, so that
  one boot names every gap instead of stopping at the first.

  The list covers:

    * in every environment, a `PORT` that is no port number from 1 to
      65535;
    * in production, every missing required variable in one message:
      `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`,
      `DATABASE_CA_CERT_FILE` and the Cloak variables `CLOAK_KEY_V1` (when
      no `CLOAK_KEY_V<n>` is set) and `CLOAK_HMAC_SECRET` (task 0003); an
      empty or whitespace-only value counts as missing. `SMTP_HOST` is
      optional, and `MAIL_FROM` is required only together with it
      (`Espalier.RuntimeConfig`);
    * in production, a `SECRET_KEY_BASE` shorter than 64 bytes (task 0004),
      a `DATABASE_URL` without a host or a database name, with the query
      parameter `ssl` or with a `timeout`, `pool_size` or `idle_interval`
      that is no integer, a `POOL_SIZE` that is no positive integer, a
      `DATABASE_CA_CERT_FILE` that names no regular file, an `SMTP_PORT`
      that is no port number, and a `PUBLIC_URL` with another scheme than
      `https` (task 0005), with user info, a path, query or fragment, or
      with a host other than `PHX_HOST` (ASVS 3.5.4);
    * the message of the `Espalier.Identity.ConfigError` that
      `Espalier.Identity.Config.parse!/2` raises for the `AUTH_*`
      variables;
    * a missing sign-in pathway: `LOCAL_ACCOUNTS=false`, `AUTH_DEMO` not
      `true` and no provider in `AUTH_PROVIDERS` (README section 6.11);
    * in production, the messages of the tool check of the media processing
      (task 0018, `Espalier.Media.Ffmpeg.check/0`): a missing `ffmpeg`,
      `ffprobe` or `timeout`, an ffmpeg older than 7.1, and a missing
      encoder or demuxer;
    * the messages of `Espalier.RuntimeConfig.errors/2`, which validates
      every application setting outside `AUTH_*`, among them a missing
      `PUBLIC_URL`, `EXPORT_DIR` or `MEDIA_DIR` in production.

  Every value passes `Espalier.RuntimeConfig.value/2`, which trims it and
  removes one pair of surrounding double quotes. The production block of
  `config/runtime.exs` reads the variables of these checks the same way, so
  the check sees the values that the configuration uses. No message
  contains the value of a variable.
  """

  alias Espalier.Identity.{Config, ConfigError}
  alias Espalier.Media.Ffmpeg
  alias Espalier.RuntimeConfig

  @typep env :: %{optional(String.t()) => String.t()}

  @origin "PUBLIC_URL must be an origin without user info, path, query or fragment"

  @doc """
  Returns the message of every gap in `env` (the map of `System.get_env/0`)
  for the Mix environment `config_env`, or `[]`. In production it calls
  `tools`, the tool check of the media processing; the tests pass a stub,
  so that they start no process.
  """
  @spec errors(env(), atom(), (-> [String.t()])) :: [String.t()]
  def errors(env, config_env, tools \\ &Ffmpeg.check/0) when is_map(env) do
    port(env, "PORT") ++
      production(env, config_env) ++
      media_tools(config_env, tools) ++
      identity(env, config_env) ++ RuntimeConfig.errors(env, config_env)
  end

  # In development and tests the shell provides ffmpeg, and the check does
  # not run.
  defp media_tools(:prod, tools), do: tools.()
  defp media_tools(_config_env, _tools), do: []

  defp production(env, :prod) do
    missing =
      Enum.filter(
        ["DATABASE_URL", "SECRET_KEY_BASE", "PHX_HOST", "DATABASE_CA_CERT_FILE"],
        &(value(env, &1) == nil)
      ) ++
        missing_cloak(env)

    missing_message =
      if missing == [],
        do: [],
        else: ["Missing environment variables: #{Enum.join(missing, ", ")}"]

    missing_message ++
      secret_key_base(env) ++
      database_url(env) ++
      pool_size(env) ++ database_ca_cert_file(env) ++ port(env, "SMTP_PORT") ++ public_url(env)
  end

  defp production(_env, _config_env), do: []

  # Each CLOAK_KEY_V<n> defines the cipher tag AES.GCM.V<n> (task 0003); a
  # name with a leading zero or without a number does not count.
  defp missing_cloak(env) do
    keys? =
      Enum.any?(env, fn {name, _value} ->
        String.match?(name, ~r/\ACLOAK_KEY_V[1-9][0-9]*\z/) and value(env, name) != nil
      end)

    for {name, missing?} <- [
          {"CLOAK_KEY_V1", not keys?},
          {"CLOAK_HMAC_SECRET", value(env, "CLOAK_HMAC_SECRET") == nil}
        ],
        missing?,
        do: name
  end

  # The encrypted session cookies and the rate-limit key derive from the
  # secret key base, and the cookie store needs at least 64 bytes (task 0004).
  defp secret_key_base(env) do
    case value(env, "SECRET_KEY_BASE") do
      nil ->
        []

      secret when byte_size(secret) < 64 ->
        [
          "SECRET_KEY_BASE is shorter than 64 bytes; generate one with mix phx.gen.secret"
        ]

      _secret ->
        []
    end
  end

  # config/runtime.exs takes the host of DATABASE_URL as the server name of
  # the TLS connection. Ecto merges the query parameters of the URL over the
  # ssl options of the configuration, so ssl=false would turn TLS off.
  defp database_url(env) do
    case value(env, "DATABASE_URL") do
      nil ->
        []

      url ->
        uri = URI.parse(url)

        database_host(uri) ++ database_ssl(uri)
    end
  end

  # Without a database name, Ecto raises an error whose message holds the
  # whole URL with its password.
  # The rules of Ecto.Repo.Supervisor.parse_url/1 (ecto 3.14): one path
  # segment as the database name. Ecto raises for any other path, and its
  # error message holds the whole URL with its password.
  defp database_host(%URI{host: host, path: path}) do
    if host in [nil, ""] or not (is_binary(path) and path =~ ~r{\A/[^/]+\z}),
      do: ["DATABASE_URL must be an ecto:// URL with a host and a database name"],
      else: []
  end

  # Ecto merges the query parameters over the Repo options, so ssl would
  # replace the TLS options of config/runtime.exs, and it raises with the
  # URL for a timeout, pool_size or idle_interval that is no integer.
  defp database_ssl(%URI{query: nil}), do: []

  defp database_ssl(%URI{query: query}) do
    params = URI.query_decoder(query) |> Enum.to_list()

    ssl =
      if Enum.any?(params, &match?({"ssl", _value}, &1)),
        do: ["DATABASE_URL must not set ssl; TLS comes from DATABASE_CA_CERT_FILE"],
        else: []

    integers =
      if Enum.any?(params, fn {key, value} ->
           key in ["timeout", "pool_size", "idle_interval"] and
             not match?({_n, ""}, Integer.parse(value))
         end),
         do: ["DATABASE_URL must give timeout, pool_size and idle_interval as integers"],
         else: []

    ssl ++ integers
  end

  # config/runtime.exs passes PORT (every environment, 4000 by default) and
  # SMTP_PORT (production, 587 by default) on as integers.
  defp port(env, name) do
    case value(env, name) do
      nil ->
        []

      port ->
        case Integer.parse(port) do
          {number, ""} when number in 1..65_535 -> []
          _other -> ["#{name} must be a port number from 1 to 65535"]
        end
    end
  end

  # The size of the Repo pool, 10 by default.
  defp pool_size(env) do
    case value(env, "POOL_SIZE") do
      nil ->
        []

      size ->
        case Integer.parse(size) do
          {number, ""} when number > 0 -> []
          _other -> ["POOL_SIZE must be a positive integer"]
        end
    end
  end

  # The path comes from the operator's environment at boot; no request
  # reaches it.
  # sobelow_skip ["Traversal.FileModule"]
  defp database_ca_cert_file(env) do
    case value(env, "DATABASE_CA_CERT_FILE") do
      nil -> []
      path -> if File.regular?(path), do: [], else: ["DATABASE_CA_CERT_FILE names no file"]
    end
  end

  # RuntimeConfig reports a missing PUBLIC_URL and one that is no http or
  # https URL. Passkeys derive their origin from it (task 0005), so it must
  # use https, and Espalier runs on a hostname of its own (ASVS 3.5.4).
  defp public_url(env) do
    case value(env, "PUBLIC_URL") do
      nil ->
        []

      url ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host} = uri
          when scheme in ["http", "https"] and host not in [nil, ""] ->
            https(uri) ++ origin(uri, url) ++ phx_host(uri, value(env, "PHX_HOST"))

          _uri ->
            []
        end
    end
  end

  defp https(%URI{scheme: "https"}), do: []

  defp https(_uri),
    do: ["PUBLIC_URL must use https in production, because passkeys derive their origin from it"]

  # An origin has no user info. URI.parse/1 returns no user info for an
  # empty one ("https://@host"), so the check looks for "@" in the
  # authority of the URL itself.
  defp origin(%URI{path: path, query: nil, fragment: nil}, url) when path in [nil, "", "/"] do
    if Regex.match?(~r{\A[^:/?#]+://[^/?#]*@}, url), do: [@origin], else: []
  end

  defp origin(_uri, _url), do: [@origin]

  defp phx_host(_uri, nil), do: []

  defp phx_host(%URI{host: host}, phx_host) do
    if String.downcase(host) == String.downcase(phx_host),
      do: [],
      else: ["The host of PUBLIC_URL must equal PHX_HOST"]
  end

  defp identity(env, config_env) do
    case providers(env, config_env) do
      {:ok, providers} -> sign_in_pathway(env, providers)
      {:error, message} -> [message]
    end
  end

  defp providers(env, config_env) do
    {:ok, Config.parse!(env, config_env)}
  rescue
    error in ConfigError -> {:error, Exception.message(error)}
  end

  defp sign_in_pathway(env, []) do
    if value(env, "LOCAL_ACCOUNTS") == "false" and value(env, "AUTH_DEMO") != "true",
      do: [
        "No sign-in pathway: LOCAL_ACCOUNTS=false, AUTH_DEMO is not true " <>
          "and AUTH_PROVIDERS names no provider"
      ],
      else: []
  end

  defp sign_in_pathway(_env, _providers), do: []

  defp value(env, name), do: RuntimeConfig.value(env, name)
end
