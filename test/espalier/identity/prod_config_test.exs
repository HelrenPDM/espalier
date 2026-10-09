defmodule Espalier.Identity.ProdConfigTest do
  # Changes the application env of Espalier.Identity.Oidc in one test.
  use ExUnit.Case, async: false

  alias Config.Reader, as: ConfigReader
  alias Espalier.Identity.{Config, ConfigError, Oidc, OidcProvider}

  defp keys(value) when is_list(value) do
    Enum.flat_map(value, fn
      {key, inner} when is_atom(key) -> [key | keys(inner)]
      inner -> keys(inner)
    end)
  end

  defp keys(_value), do: []

  test "no production configuration sets allow_unsafe_http" do
    prod = ConfigReader.read!("config/config.exs", env: :prod, target: :host)
    refute :allow_unsafe_http in keys(prod)

    for file <- ["config/prod.exs", "config/runtime.exs"] do
      refute File.read!(file) =~ "allow_unsafe_http"
    end
  end

  test "quirks/1 never returns allow_unsafe_http while the key is unset" do
    previous = Application.get_env(:espalier, Oidc, [])
    Application.put_env(:espalier, Oidc, Keyword.delete(previous, :allow_unsafe_http))
    on_exit(fn -> Application.put_env(:espalier, Oidc, previous) end)

    provider = %OidcProvider{
      type: "oidc",
      issuer: "http://localhost:4011/oidc",
      client_auth: :client_secret_basic
    }

    refute Map.has_key?(Oidc.quirks(provider), :allow_unsafe_http)
  end

  test "parse!/2 refuses an http issuer in production" do
    env = %{
      "AUTH_PROVIDERS" => "corp",
      "AUTH_CORP_TYPE" => "oidc",
      "AUTH_CORP_LABEL" => "Company",
      "AUTH_CORP_ISSUER" => "http://localhost:4011/oidc",
      "AUTH_CORP_CLIENT_ID" => "client",
      "AUTH_CORP_CLIENT_SECRET" => "secret"
    }

    assert_raise ConfigError, ~r/AUTH_CORP_ISSUER must start with https/, fn ->
      Config.parse!(env, :prod)
    end
  end

  test ".env.example holds no client secret, certificate or key value" do
    for line <- ".env.example" |> File.read!() |> String.split("\n"),
        not String.starts_with?(String.trim_leading(line), "#") do
      refute line =~ ~r/^AUTH_[A-Z0-9_]+_(CLIENT_SECRET|CLIENT_CERT_FILE|CLIENT_KEY_FILE)=.+/
    end
  end
end
