defmodule Espalier.Identity do
  @moduledoc """
  Access to the configured external identity providers (README section
  6.11). `config/runtime.exs` stores the structs of
  `Espalier.Identity.Config.parse!/2` under `:identity_providers`.
  """

  alias Espalier.Identity.OidcProvider

  @doc "Returns the configured OIDC providers in the order of `AUTH_PROVIDERS`."
  @spec oidc_providers() :: [OidcProvider.t()]
  def oidc_providers do
    for %OidcProvider{} = provider <- Application.get_env(:espalier, :identity_providers, []),
        do: provider
  end

  @doc "Returns `{:ok, provider}` for a configured OIDC key, and `:error` otherwise."
  @spec fetch_oidc_provider(term()) :: {:ok, OidcProvider.t()} | :error
  def fetch_oidc_provider(key) when is_binary(key) do
    case Enum.find(oidc_providers(), &(&1.key == key)) do
      nil -> :error
      provider -> {:ok, provider}
    end
  end

  def fetch_oidc_provider(_key), do: :error

  @doc """
  Returns the label of the configured provider `key` of any type, or the
  key when no provider of that key is configured.
  """
  @spec provider_label(String.t()) :: String.t()
  def provider_label(key) when is_binary(key) do
    case Enum.find(Application.get_env(:espalier, :identity_providers, []), &(&1.key == key)) do
      %{label: label} when is_binary(label) -> label
      _ -> key
    end
  end
end
