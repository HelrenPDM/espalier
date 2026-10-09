defmodule Espalier.Identity.Oidc do
  @moduledoc """
  The OIDC client options of the platform (task 0006, step 5, README
  section 6.7).

  - `quirks/1` overrides parts of each discovery document: the ID token
    algorithm allowlist RS256, PS256 and ES256, no request objects and no
    DPoP proofs, `S256` for Entra ID, and PS256 alone for client
    assertions (README section 15, decision D13).
  - `request_opts/0` routes every request to a provider through
    `Espalier.Identity.Oidc.HttpAdapter`, which follows no redirect.
  - `check_endpoints/2` keeps every redirect and every token request on the
    hosts of `AUTH_<KEY>_ALLOWED_HOSTS`.
  - `reason_tag/1` reduces an oidcc error term, which can hold a token, to
    its first atom for the log.
  """

  alias Espalier.Identity.OidcProvider

  # oidcc 3.9.0 still needs a client secret next to client_jwks (oidcc issue
  # #442). The value is no secret and authenticates nothing.
  @unused_secret "unused-see-oidcc-issue-442"

  @id_token_algs ["RS256", "PS256", "ES256"]

  @endpoint_fields [
    :authorization_endpoint,
    :token_endpoint,
    :jwks_uri,
    :end_session_endpoint,
    :pushed_authorization_request_endpoint
  ]

  @doc "Reads a key of `config :espalier, Espalier.Identity.Oidc` with a default."
  @spec oidc_env(atom(), term()) :: term()
  def oidc_env(key, default) do
    :espalier |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)
  end

  @doc "The quirks of the provider configuration worker of `provider`."
  @spec quirks(OidcProvider.t()) :: map()
  def quirks(%OidcProvider{} = provider) do
    overrides =
      %{
        "id_token_signing_alg_values_supported" => @id_token_algs,
        "request_parameter_supported" => false,
        "dpop_signing_alg_values_supported" => []
      }
      |> put_if(provider.type == "entra", "code_challenge_methods_supported", ["S256"])
      |> put_if(
        certificate_client?(provider),
        "token_endpoint_auth_signing_alg_values_supported",
        ["PS256"]
      )

    quirks = %{document_overrides: overrides}

    if oidc_env(:allow_unsafe_http, false) and local_http?(provider.issuer),
      do: Map.put(quirks, :allow_unsafe_http, true),
      else: quirks
  end

  defp put_if(map, true, key, value), do: Map.put(map, key, value)
  defp put_if(map, false, _key, _value), do: map

  defp local_http?(issuer) do
    String.starts_with?(issuer, "http://localhost:") or
      String.starts_with?(issuer, "http://127.0.0.1:")
  end

  @doc """
  The `request_opts` of every request to a provider: discovery and JWKS
  (worker), pushed authorization (`Authorize`), token (`AuthorizationCallback`).
  No `ssl` key, so `:httpc` keeps its default TLS options.
  """
  @spec request_opts() :: map()
  def request_opts, do: %{http_adapter: {Espalier.Identity.Oidc.HttpAdapter, %{}}}

  @doc "True when the provider authenticates with `private_key_jwt`."
  @spec certificate_client?(OidcProvider.t()) :: boolean()
  def certificate_client?(%OidcProvider{client_auth: client_auth}),
    do: client_auth == :private_key_jwt

  @doc """
  The client secret that oidcc_plug receives: the configured secret, or a
  fixed value that is no secret for certificate clients.
  """
  @spec client_secret(OidcProvider.t()) :: String.t()
  def client_secret(%OidcProvider{} = provider) do
    if certificate_client?(provider), do: @unused_secret, else: provider.client_secret
  end

  @doc """
  The client context options: `%{client_jwks: jwk}` with the key that
  `Espalier.Identity.Oidc.Supervisor` loaded, or `%{}` for secret clients.
  """
  @spec client_context_opts(OidcProvider.t()) :: map()
  def client_context_opts(%OidcProvider{} = provider) do
    if certificate_client?(provider) do
      case :persistent_term.get(client_key_name(provider.key), nil) do
        %{jwk: jwk} -> %{client_jwks: jwk}
        nil -> %{}
      end
    else
      %{}
    end
  end

  @doc "Stores the loaded client key of a provider (`ClientKey.load!/3`)."
  @spec put_client_key(String.t(), map()) :: :ok
  def put_client_key(key, client_key), do: :persistent_term.put(client_key_name(key), client_key)

  defp client_key_name(key), do: {__MODULE__, :client_key, key}

  @doc """
  The one client authentication method of the token request, so oidcc does
  not move on to another method without a report.
  """
  @spec auth_methods(OidcProvider.t()) :: [atom()]
  def auth_methods(%OidcProvider{client_auth: client_auth}), do: [client_auth]

  @doc """
  Returns `{:ok, configuration}` with the loaded `Oidcc.ProviderConfiguration`
  of the provider's worker, or `{:error, :provider_not_ready}` while the worker
  has none or does not run.
  """
  @spec provider_configuration(OidcProvider.t()) ::
          {:ok, Oidcc.ProviderConfiguration.t()} | {:error, :provider_not_ready}
  def provider_configuration(%OidcProvider{worker: worker}) do
    with pid when is_pid(pid) <- Process.whereis(worker),
         record when is_tuple(record) <- worker_configuration(worker) do
      {:ok, Oidcc.ProviderConfiguration.record_to_struct(record)}
    else
      _ -> {:error, :provider_not_ready}
    end
  end

  # The worker answers :undefined while it has no configuration loaded. The
  # Elixir wrapper passes :undefined to record_to_struct/1, which raises, so
  # the Erlang function is called.
  defp worker_configuration(worker) do
    :oidcc_provider_configuration_worker.get_provider_configuration(worker)
  catch
    :exit, _reason -> :undefined
    :error, :badarg -> :undefined
  end

  @doc """
  Returns `:ok` when each endpoint that the configuration names uses `https`
  and a host of `provider.allowed_hosts`, and `{:error, :endpoint_not_allowed}`
  otherwise (ASVS 1.3.6, 12.3.2, 13.2.4, 13.2.5). oidcc 3.9.0 accepts `http`
  for the authorization, token and JWKS endpoints, so the scheme is checked
  here; `http` passes only under the development quirk of `quirks/1`, which
  applies to a local issuer only.
  """
  @spec check_endpoints(OidcProvider.t(), Oidcc.ProviderConfiguration.t()) ::
          :ok | {:error, :endpoint_not_allowed}
  def check_endpoints(%OidcProvider{allowed_hosts: allowed} = provider, configuration) do
    allowed = Enum.map(allowed, &String.downcase/1)

    schemes =
      if Map.has_key?(quirks(provider), :allow_unsafe_http),
        do: ["https", "http"],
        else: ["https"]

    ok? =
      @endpoint_fields
      |> Enum.map(&Map.get(configuration, &1))
      |> Enum.reject(&(&1 in [nil, :undefined]))
      |> Enum.all?(&(endpoint_host(&1, schemes) in allowed))

    if ok?, do: :ok, else: {:error, :endpoint_not_allowed}
  end

  defp endpoint_host(uri, schemes) do
    case URI.new(IO.chardata_to_string(uri)) do
      {:ok, %URI{scheme: scheme, host: host}} when is_binary(host) ->
        if scheme in schemes, do: String.downcase(host)

      _ ->
        nil
    end
  end

  @doc """
  Reduces an error term to its reason tag, the first atom of the term, so
  no token or claim reaches the log. Terms without an atom map to
  `:unknown`.
  """
  @spec reason_tag(term()) :: atom()
  def reason_tag(reason) when is_atom(reason) and not is_nil(reason), do: reason

  def reason_tag(reason) when is_tuple(reason) do
    reason |> Tuple.to_list() |> Enum.find(:unknown, &(is_atom(&1) and not is_nil(&1)))
  end

  def reason_tag(_reason), do: :unknown
end
