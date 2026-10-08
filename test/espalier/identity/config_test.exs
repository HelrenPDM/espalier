defmodule Espalier.Identity.ConfigTest do
  use ExUnit.Case, async: true

  alias Espalier.Identity.{Config, ConfigError}

  test "no AUTH_PROVIDERS, or a blank one, means no external provider" do
    assert Config.parse!(%{}, :prod) == []
    assert Config.parse!(%{"AUTH_PROVIDERS" => "  "}, :prod) == []
  end

  test "an invalid key names AUTH_PROVIDERS" do
    assert_raise ConfigError, ~r/AUTH_PROVIDERS/, fn ->
      Config.parse!(%{"AUTH_PROVIDERS" => "Bad"}, :prod)
    end
  end

  test "a repeated key names AUTH_PROVIDERS" do
    assert_raise ConfigError, ~r/AUTH_PROVIDERS/, fn ->
      Config.parse!(%{"AUTH_PROVIDERS" => "entra, entra"}, :prod)
    end
  end

  test "a key without AUTH_<KEY>_TYPE names that variable" do
    assert_raise ConfigError, "AUTH_ENTRA_TYPE is required", fn ->
      Config.parse!(%{"AUTH_PROVIDERS" => "entra"}, :prod)
    end
  end

  test "an unknown type names the variable" do
    assert_raise ConfigError, "AUTH_CORP_TYPE=saml is not supported", fn ->
      Config.parse!(%{"AUTH_PROVIDERS" => "corp", "AUTH_CORP_TYPE" => "saml"}, :prod)
    end
  end

  test "public_entry/1 returns exactly the five public fields" do
    provider = %{
      key: "corp",
      type: "oidc",
      kind: "redirect",
      label: "Company",
      start_url: "/auth/oidc/corp",
      client_secret: "do-not-render"
    }

    entry = Config.public_entry(provider)
    assert Map.keys(entry) |> Enum.sort() == [:key, :kind, :label, :start_url, :type]
    refute inspect(entry) =~ "do-not-render"
  end
end
