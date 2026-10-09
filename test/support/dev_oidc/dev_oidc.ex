defmodule Espalier.DevOidc do
  @moduledoc """
  A mock OIDC provider for development and tests (task 0006, step 15). It
  runs on Bandit at `127.0.0.1` and signs ID tokens with JOSE; it is never
  compiled in production.

  Three profiles share one key set: `entra`
  (`http://localhost:P/entra/<tenant>/v2.0`), `google`
  (`http://localhost:P/google`) and `oidc` (`http://localhost:P/oidc`).
  `Espalier.DevOidc.Fixtures` holds the invented users, and
  `put_switch/2` turns on a failure or a variant per profile.

  The configuration comes from `config :espalier, Espalier.DevOidc`
  (`client_id`, `client_secret`, `tenant_id`, `redirect_uris`,
  `post_logout_redirect_uris`); the fixture secret works only against the
  mock.
  """
  use Supervisor

  @agent Espalier.DevOidc.State
  @profiles [:entra, :google, :oidc]

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    port = Keyword.fetch!(opts, :port)

    children = [
      %{id: @agent, start: {Agent, :start_link, [fn -> initial_state(port) end, [name: @agent]]}},
      {Bandit, plug: Espalier.DevOidc.Router, ip: {127, 0, 0, 1}, port: port}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp initial_state(port) do
    %{
      port: port,
      key: new_key(),
      codes: %{},
      switches: Map.new(@profiles, &{&1, []}),
      client_keys: %{},
      jtis: MapSet.new(),
      requests: []
    }
  end

  @doc "Generates an RSA signing key whose `kid` is its thumbprint."
  def new_key do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    %{jwk: jwk, kid: JOSE.JWK.thumbprint(jwk)}
  end

  ## Configuration

  @doc "The configuration of `config :espalier, Espalier.DevOidc`."
  def config, do: Application.fetch_env!(:espalier, __MODULE__)

  @doc "The port of the running mock."
  def port, do: Agent.get(@agent, & &1.port)

  @doc "The issuer of `profile` on `host` (default `localhost`)."
  def issuer(profile, host \\ "localhost") do
    base = "http://#{host}:#{port()}"

    case profile do
      :entra -> "#{base}/entra/#{config()[:tenant_id]}/v2.0"
      :google -> "#{base}/google"
      :oidc -> "#{base}/oidc"
    end
  end

  ## Switches and keys

  @doc """
  Turns on a switch for `profile` until `reset!/0`. `{:assertion_aud, aud}`
  replaces an earlier audience switch.
  """
  def put_switch(profile, switch) when profile in @profiles do
    Agent.update(@agent, fn state ->
      update_in(state, [:switches, profile], fn switches ->
        switches = Enum.reject(switches, &same_switch?(&1, switch))
        [switch | switches]
      end)
    end)
  end

  defp same_switch?({name, _}, {name, _}), do: true
  defp same_switch?(switch, switch), do: true
  defp same_switch?(_switch, _other), do: false

  @doc "True when `switch` is on for `profile`."
  def switch?(profile, switch), do: switch in switches(profile)

  @doc "The switches of `profile`."
  def switches(profile), do: Agent.get(@agent, &Map.fetch!(&1.switches, profile))

  @doc "Registers the public key of a test certificate for `client_id` (`private_key_jwt`)."
  def put_client_key(client_id, %JOSE.JWK{} = jwk) do
    public = JOSE.JWK.to_public(jwk)
    Agent.update(@agent, &put_in(&1, [:client_keys, client_id], public))
  end

  @doc "The registered client key of `client_id`, or `nil`."
  def client_key(client_id), do: Agent.get(@agent, &Map.get(&1.client_keys, client_id))

  @doc "Clears switches, codes, client keys, used `jti` values and the request log."
  def reset! do
    Agent.update(@agent, fn state ->
      %{
        state
        | codes: %{},
          switches: Map.new(@profiles, &{&1, []}),
          client_keys: %{},
          jtis: MapSet.new(),
          requests: []
      }
    end)
  end

  @doc "Replaces the signing key with a new key under a new `kid`."
  def rotate_key! do
    key = new_key()
    Agent.update(@agent, &%{&1 | key: key})
  end

  @doc "The current signing key."
  def signing_key, do: Agent.get(@agent, & &1.key)

  ## Codes and assertions

  @doc false
  def put_code(code, data), do: Agent.update(@agent, &put_in(&1, [:codes, code], data))

  @doc false
  def pop_code(code) do
    Agent.get_and_update(@agent, fn state ->
      {data, codes} = Map.pop(state.codes, code)
      {data, %{state | codes: codes}}
    end)
  end

  @doc false
  # Returns true for a jti that has not been seen before and records it.
  def use_jti(jti) do
    Agent.get_and_update(@agent, fn state ->
      if MapSet.member?(state.jtis, jti),
        do: {false, state},
        else: {true, %{state | jtis: MapSet.put(state.jtis, jti)}}
    end)
  end

  ## Request log

  @doc false
  def log_request(profile, entry) do
    Agent.update(@agent, fn state ->
      %{state | requests: [Map.put(entry, :profile, profile) | state.requests]}
    end)
  end

  @doc "The logged requests of `profile`, oldest first."
  def requests(profile) do
    @agent
    |> Agent.get(& &1.requests)
    |> Enum.filter(&(&1.profile == profile))
    |> Enum.reverse()
  end
end
