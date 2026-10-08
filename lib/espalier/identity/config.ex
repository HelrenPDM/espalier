defmodule Espalier.Identity.Config do
  @moduledoc """
  Parses the external identity providers from the environment
  (README section 6.11).

  `AUTH_PROVIDERS` lists the provider keys in the order of the sign-in page.
  For each key, `<KEY>` is its upper-case form, and `AUTH_<KEY>_TYPE` names
  the provider type. This task knows no type; task 0006 adds `entra`,
  `google` and `oidc`, and task 0007 adds `ldap`. Every provider struct
  carries at least `key`, `type`, `kind`, `label` and `start_url`; `kind` is
  `redirect` (0006) or `credentials` (0007), and `start_url` is the path
  where the sign-in starts.

  `config/runtime.exs` stores the structs under `:identity_providers` and
  their `public_entry/1` under `:auth_providers`.
  """

  alias Espalier.Identity.ConfigError

  @key_format ~r/\A[a-z][a-z0-9_]{0,31}\z/

  @doc """
  Returns the providers of `AUTH_PROVIDERS` in `env` (the map of
  `System.get_env/0`) in configured order, or raises `ConfigError`.
  """
  @spec parse!(%{optional(String.t()) => String.t()}, atom()) :: [map()]
  def parse!(env, config_env) when is_map(env) do
    case String.trim(Map.get(env, "AUTH_PROVIDERS", "")) do
      "" ->
        []

      value ->
        keys = value |> String.split(",") |> Enum.map(&String.trim/1)
        Enum.each(keys, &check_key!/1)

        if Enum.uniq(keys) != keys do
          raise ConfigError, "AUTH_PROVIDERS lists a provider key twice"
        end

        Enum.map(keys, &provider!(&1, env, config_env))
    end
  end

  defp check_key!(key) do
    if not Regex.match?(@key_format, key) do
      raise ConfigError,
            "AUTH_PROVIDERS holds a key that does not match ^[a-z][a-z0-9_]{0,31}$"
    end
  end

  defp provider!(key, env, _config_env) do
    variable = "AUTH_#{String.upcase(key)}_TYPE"

    case env |> Map.get(variable, "") |> String.trim() do
      "" -> raise ConfigError, "#{variable} is required"
      type -> raise ConfigError, "#{variable}=#{type} is not supported"
    end
  end

  @doc """
  Returns the public fields of a provider, which the session payload and
  `GET /auth/providers` render. It holds no secret and no other
  configuration value.
  """
  @spec public_entry(map()) :: %{
          key: String.t(),
          type: String.t(),
          kind: String.t(),
          label: String.t(),
          start_url: String.t()
        }
  def public_entry(%{key: key, type: type, kind: kind, label: label, start_url: start_url}) do
    %{key: key, type: type, kind: kind, label: label, start_url: start_url}
  end
end
