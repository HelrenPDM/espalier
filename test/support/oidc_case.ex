defmodule Espalier.OidcCase do
  @moduledoc """
  Test case for the OIDC flows against the mock provider of
  `test/support/dev_oidc/`, which the application starts on port 4011 in
  tests (task 0006, step 17). It builds on `EspalierWeb.ConnCase` with
  `async: false`, because the mock and the provider configuration are
  global, and resets the mock before each test.

  `setup_providers/1` parses a provider env map with
  `Espalier.Identity.Config.parse!/2`, puts the structs and their public
  entries into the application env, starts
  `Espalier.Identity.Oidc.Supervisor` and waits until every worker has
  loaded its configuration and keys. The flow helpers run authorize, the
  mock decision for a fixture, the callback with recycled cookies and the
  finish step.
  """
  use ExUnit.CaseTemplate

  import Phoenix.ConnTest, only: [dispatch: 5, json_response: 2, redirected_to: 1]

  alias Espalier.DevOidc
  alias Espalier.Identity.Config
  alias EspalierWeb.ConnCase

  @tenant "3f0c2a9e-7b1d-4e5a-8c6f-2d9b0e4a1c7d"
  @secret "dev-oidc-fixture-secret"

  using do
    quote do
      use EspalierWeb.ConnCase, async: false

      import Espalier.OidcCase
      import ExUnit.CaptureLog

      alias Espalier.DevOidc

      @moduletag :capture_log
    end
  end

  setup do
    DevOidc.reset!()
    :ok
  end

  @doc "The invented tenant id of the mock's `entra` profile."
  def tenant_id, do: @tenant

  @doc "The fixture secret of the mock."
  def fixture_secret, do: @secret

  @doc """
  The environment of one provider `key` of type `type` against the mock
  profile `profile` (default: the type), merged with `overrides` (variable
  suffixes such as `"MFA"` or full names).
  """
  def provider_env(key, type, overrides \\ %{}, profile \\ nil) do
    profile = profile || String.to_existing_atom(type)
    prefix = "AUTH_#{String.upcase(key)}_"

    base =
      %{
        "TYPE" => type,
        "LABEL" => "#{key} (mock)",
        "CLIENT_ID" => "espalier-dev",
        "CLIENT_SECRET" => @secret,
        "ISSUER" => DevOidc.issuer(profile)
      }
      |> Map.merge(type_env(type))
      |> Map.merge(overrides)

    for {name, value} <- base, not is_nil(value), into: %{} do
      if String.starts_with?(name, "AUTH_"), do: {name, value}, else: {prefix <> name, value}
    end
  end

  defp type_env("entra"), do: %{"TENANT_ID" => @tenant}
  defp type_env("google"), do: %{"HOSTED_DOMAIN" => "example.org"}
  defp type_env("oidc"), do: %{}

  @doc """
  Parses `envs` (maps of `provider_env/4`, in the order of `AUTH_PROVIDERS`),
  configures the providers, starts the supervisor and, unless `wait: false`,
  waits until every worker is ready. Returns the providers.
  """
  def setup_providers(envs, opts \\ []) do
    keys =
      for env <- envs do
        [name | _] = env |> Map.keys() |> Enum.filter(&String.ends_with?(&1, "_TYPE"))
        name |> String.trim_leading("AUTH_") |> String.trim_trailing("_TYPE") |> String.downcase()
      end

    base = %{"AUTH_PROVIDERS" => Enum.join(keys, ","), "PUBLIC_URL" => public_url()}
    env = Enum.reduce(envs, base, &Map.merge(&2, &1))

    providers = Config.parse!(env, :test)
    put_providers(providers)
    ExUnit.Callbacks.start_supervised!({Espalier.Identity.Oidc.Supervisor, providers: providers})

    if Keyword.get(opts, :wait, true), do: Enum.each(providers, &wait_ready/1)
    providers
  end

  @doc "Puts the providers and their public entries into the application env for one test."
  def put_providers(providers) do
    ConnCase.put_setting(:identity_providers, providers)
    ConnCase.put_setting(:auth_providers, Enum.map(providers, &Config.public_entry/1))
  end

  @doc "The provider of `key` in the application env."
  def provider(key) do
    {:ok, provider} = Espalier.Identity.fetch_oidc_provider(key)
    provider
  end

  @doc "Waits up to `timeout` milliseconds until the worker has loaded configuration and keys."
  def wait_ready(provider, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_ready(provider, deadline)
  end

  defp do_wait_ready(provider, deadline) do
    case :oidcc_client_context.from_configuration_worker(provider.worker, "probe", "probe") do
      {:ok, _context} ->
        :ok

      {:error, _reason} ->
        if System.monotonic_time(:millisecond) > deadline do
          raise "provider #{provider.key} did not load its configuration"
        end

        Process.sleep(20)
        do_wait_ready(provider, deadline)
    end
  end

  @doc "`PUBLIC_URL` of the test configuration."
  def public_url, do: Application.fetch_env!(:espalier, :public_url)

  @doc """
  Writes a self-signed test certificate and its RSA key to `dir`, registers
  the public key with the mock for the client `espalier-dev`, and returns
  `%{cert_file: ..., key_file: ..., der: ..., jwk: ...}`.
  """
  def client_certificate(dir) do
    key = X509.PrivateKey.new_rsa(2048)
    cert = X509.Certificate.self_signed(key, "/CN=espalier-test")
    cert_file = Path.join(dir, "client.crt")
    key_file = Path.join(dir, "client.key")
    File.write!(cert_file, X509.Certificate.to_pem(cert))
    File.write!(key_file, X509.PrivateKey.to_pem(key))

    jwk = key |> X509.PublicKey.derive() |> JOSE.JWK.from_key()
    DevOidc.put_client_key("espalier-dev", jwk)

    %{cert_file: cert_file, key_file: key_file, der: X509.Certificate.to_der(cert), jwk: jwk}
  end

  ## Flow helpers

  @doc """
  A browser conn for a top-level navigation of the same client: recycles a
  sent conn and keeps its cookies.
  """
  def browser(conn) do
    if conn.state == :unset, do: conn, else: ConnCase.next_request(conn)
  end

  @doc """
  `GET /auth/oidc/<key>` with `query`. Returns `{conn, location}`.
  """
  def authorize(conn, key, query \\ %{}) do
    conn = navigate(browser(conn), with_query("/auth/oidc/#{key}", query))
    {conn, redirected_to(conn)}
  end

  @doc "A GET navigation to `path`, which may carry a query string."
  def navigate(conn, path), do: dispatch(conn, EspalierWeb.Endpoint, :get, path, nil)

  defp with_query(path, query) when query == %{}, do: path
  defp with_query(path, query), do: path <> "?" <> URI.encode_query(query)

  @doc """
  Opens the mock's authorization page of `location` and posts the decision
  for `fixture`. Returns the callback URL that the mock redirects to.
  """
  def decide(location, fixture) do
    uri = URI.parse(location)
    params = URI.decode_query(uri.query || "")
    page = Req.get!(location, redirect: false, retry: false)
    200 = page.status

    decision =
      Req.post!(URI.to_string(%{uri | query: nil}) <> "/decision",
        form: Map.put(params, "fixture", fixture),
        redirect: false,
        retry: false
      )

    302 = decision.status
    [callback] = Req.Response.get_header(decision, "location")
    callback
  end

  @doc "Sends the browser to the callback URL. Returns `{conn, location}`."
  def callback(conn, callback_url) do
    uri = URI.parse(callback_url)
    conn = navigate(browser(conn), uri.path <> "?" <> (uri.query || ""))
    {conn, redirected_to(conn)}
  end

  @doc "The ticket of a `/auth/finish#ticket=` location, or `nil`."
  def ticket(location) do
    case Regex.run(~r{\A/auth/finish#ticket=([A-Za-z0-9_-]+)\z}, location) do
      [_, ticket] -> ticket
      nil -> nil
    end
  end

  @doc "The error code of a `/auth/finish?error=` location, or `nil`."
  def finish_error(location) do
    case Regex.run(~r{\A/auth/finish\?error=([a-z_]+)\z}, location) do
      [_, code] -> code
      nil -> nil
    end
  end

  @doc "`POST /api/auth/finish` with `ticket` and a CSRF token."
  def finish(conn, ticket) do
    ConnCase.api_request(conn, :post, "/api/auth/finish", %{ticket: ticket})
  end

  @doc """
  Runs authorize, the decision for `fixture` and the callback. Returns
  `{conn, location}` of the callback.
  """
  def to_callback(conn, key, fixture, query \\ %{}) do
    {conn, location} = authorize(conn, key, query)
    callback(conn, decide(location, fixture))
  end

  @doc """
  Runs a complete flow up to the answer of `POST /api/auth/finish`. Returns
  `{conn, body, status}`.
  """
  def sign_in(conn, key, fixture, query \\ %{}) do
    {conn, location} = to_callback(conn, key, fixture, query)
    ticket = ticket(location) || raise "the callback redirected to #{location}"
    conn = finish(conn, ticket)
    {conn, Jason.decode!(conn.resp_body), conn.status}
  end

  @doc "Asserts a full sign-in and returns the conn after it."
  def sign_in!(conn, key, fixture, query \\ %{}) do
    {conn, body, status} = sign_in(conn, key, fixture, query)
    200 = status
    true = is_map(body["session"])
    conn
  end

  @doc """
  `GET /auth/oidc/<key>/front-channel-logout` as an iframe of the provider:
  cross-site, without platform cookies.
  """
  def front_channel_logout(key, query) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("sec-fetch-site", "cross-site")
    |> Plug.Conn.put_req_header("sec-fetch-mode", "navigate")
    |> Plug.Conn.put_req_header("sec-fetch-dest", "iframe")
    |> navigate(with_query("/auth/oidc/#{key}/front-channel-logout", query))
  end

  @doc "The JSON body of a conn."
  def body(conn, status), do: json_response(conn, status)

  @doc """
  A browser conn whose `__Host-espalier` cookie holds a session of `user`
  (`ConnCase.log_in_user/3`), as a top-level navigation carries it.
  """
  def signed_in_browser(user, attrs \\ %{}) do
    ConnCase.api_conn() |> ConnCase.log_in_user(user, attrs) |> ConnCase.with_csrf_token()
  end

  @doc "The token requests that the mock logged for `profile`."
  def token_requests(profile),
    do: Enum.filter(DevOidc.requests(profile), &(&1.endpoint == :token))
end
