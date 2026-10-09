defmodule Espalier.Identity.OidcEndpointsTest do
  use ExUnit.Case, async: true

  alias Espalier.Identity.{Oidc, OidcProvider}
  alias Oidcc.ProviderConfiguration

  @provider %OidcProvider{
    key: "corp",
    type: "oidc",
    issuer: "https://id.example.org",
    client_auth: :client_secret_basic,
    allowed_hosts: ["id.example.org", "keys.example.org"]
  }

  @endpoints [
    :authorization_endpoint,
    :token_endpoint,
    :jwks_uri,
    :end_session_endpoint,
    :pushed_authorization_request_endpoint
  ]

  defp configuration(overrides \\ %{}) do
    struct!(
      ProviderConfiguration,
      Map.merge(
        %{
          issuer: "https://id.example.org",
          authorization_endpoint: "https://id.example.org/authorize",
          token_endpoint: "https://id.example.org/token",
          jwks_uri: "https://keys.example.org/jwks",
          end_session_endpoint: "https://id.example.org/logout",
          pushed_authorization_request_endpoint: "https://id.example.org/par"
        },
        overrides
      )
    )
  end

  describe "check_endpoints/2" do
    test "passes when every endpoint lies on an allowed host" do
      assert Oidc.check_endpoints(@provider, configuration()) == :ok
    end

    test "fails for each of the five endpoints on another host" do
      for field <- @endpoints do
        config = configuration(%{field => "https://evil.example.net/x"})

        assert Oidc.check_endpoints(@provider, config) == {:error, :endpoint_not_allowed},
               "#{field}"
      end
    end

    test "an endpoint must use https unless the development quirk applies" do
      for field <- @endpoints do
        config = configuration(%{field => "http://id.example.org/x"})

        assert Oidc.check_endpoints(@provider, config) == {:error, :endpoint_not_allowed},
               "#{field}"
      end

      # config/test.exs sets allow_unsafe_http, which applies to a local issuer only.
      local = %{@provider | issuer: "http://localhost:4011/oidc", allowed_hosts: ["localhost"]}
      config = configuration(%{token_endpoint: "http://localhost:4011/oidc/token"})
      config = %{config | authorization_endpoint: "http://localhost:4011/oidc/authorize"}

      config = %{
        config
        | jwks_uri: "http://localhost:4011/oidc/jwks",
          end_session_endpoint: :undefined,
          pushed_authorization_request_endpoint: :undefined
      }

      assert Oidc.check_endpoints(local, config) == :ok
    end

    test "an absent end-session or pushed authorization endpoint is fine" do
      config =
        configuration(%{
          end_session_endpoint: :undefined,
          pushed_authorization_request_endpoint: :undefined
        })

      assert Oidc.check_endpoints(@provider, config) == :ok
    end

    test "host names compare in lower case" do
      config = configuration(%{token_endpoint: "https://ID.Example.ORG/token"})
      assert Oidc.check_endpoints(@provider, config) == :ok

      provider = %{@provider | allowed_hosts: ["Id.Example.org", "KEYS.example.org"]}
      assert Oidc.check_endpoints(provider, configuration()) == :ok
    end
  end

  describe "quirks/1" do
    test "every type gets the algorithm allowlist and no request objects or DPoP" do
      for type <- ["entra", "google", "oidc"] do
        overrides = Oidc.quirks(%{@provider | type: type}).document_overrides
        assert overrides["id_token_signing_alg_values_supported"] == ["RS256", "PS256", "ES256"]
        assert overrides["request_parameter_supported"] == false
        assert overrides["dpop_signing_alg_values_supported"] == []
      end
    end

    test "entra gets S256, and every certificate client PS256 alone" do
      entra = Oidc.quirks(%{@provider | type: "entra"}).document_overrides
      assert entra["code_challenge_methods_supported"] == ["S256"]
      refute Map.has_key?(entra, "token_endpoint_auth_signing_alg_values_supported")

      refute Map.has_key?(
               Oidc.quirks(@provider).document_overrides,
               "code_challenge_methods_supported"
             )

      for type <- ["entra", "oidc"] do
        overrides =
          Oidc.quirks(%{@provider | type: type, client_auth: :private_key_jwt}).document_overrides

        assert overrides["token_endpoint_auth_signing_alg_values_supported"] == ["PS256"]
      end
    end
  end

  test "reason_tag/1 keeps only the first atom of an error term" do
    assert Oidc.reason_tag(:token_expired) == :token_expired
    assert Oidc.reason_tag({:missing_claim, {"aud", "client"}, %{"sub" => "x"}}) == :missing_claim
    assert Oidc.reason_tag({:http_error, 503, "body"}) == :http_error
    assert Oidc.reason_tag({"no atom"}) == :unknown
    assert Oidc.reason_tag("text") == :unknown
  end
end
