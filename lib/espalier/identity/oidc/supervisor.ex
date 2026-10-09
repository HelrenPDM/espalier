defmodule Espalier.Identity.Oidc.Supervisor do
  @moduledoc """
  Starts one `Oidcc.ProviderConfiguration.Worker` per OIDC provider (task
  0006, step 5). The workers load discovery and keys and keep retrying with
  random exponential backoff while a provider is unreachable, so one
  provider's outage ends only its own sign-ins (ASVS 16.5.2).

  `init/1` loads the client keys of certificate clients into
  `:persistent_term` and logs a warning for every provider in `idp_trusted`
  mode (README section 6.2, rule 4).
  """
  use Supervisor

  require Logger

  alias Espalier.Identity
  alias Espalier.Identity.Oidc
  alias Espalier.Identity.Oidc.ClientKey

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    providers = Keyword.get(opts, :providers, Identity.oidc_providers())

    for provider <- providers do
      if Oidc.certificate_client?(provider) do
        Oidc.put_client_key(
          provider.key,
          ClientKey.load!(provider.cert_file, provider.key_file, provider.kid_format)
        )
      end

      if provider.mfa == :idp_trusted do
        Logger.warning(
          "AUTH_#{String.upcase(provider.key)}_MFA=idp_trusted: the provider's multi-factor " <>
            "sign-in counts as second factor (README section 6.2, rule 4)"
        )
      end
    end

    providers
    |> Enum.map(&child_spec_for/1)
    |> Supervisor.init(strategy: :one_for_one)
  end

  @doc "The child spec of the configuration worker of `provider`."
  def child_spec_for(provider) do
    Supervisor.child_spec(
      {Oidcc.ProviderConfiguration.Worker,
       %{
         issuer: provider.issuer,
         name: provider.worker,
         backoff_type: :random_exponential,
         backoff_min: Oidc.oidc_env(:backoff_min, 1_000),
         backoff_max: Oidc.oidc_env(:backoff_max, 30_000),
         provider_configuration_opts: %{
           quirks: Oidc.quirks(provider),
           request_opts: Oidc.request_opts()
         }
       }},
      id: provider.worker
    )
  end
end
