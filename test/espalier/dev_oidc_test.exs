defmodule Espalier.DevOidcTest do
  # The mock OIDC provider itself (task 0006, step 15).
  use Espalier.OidcCase

  @verifier "a-pkce-verifier-of-sufficient-length-0123456789abcdef"

  defp challenge(verifier \\ @verifier),
    do: Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

  defp request_params(overrides) do
    Map.merge(
      %{
        "client_id" => "espalier-dev",
        "redirect_uri" => public_url() <> "/auth/oidc/oidc/callback",
        "response_type" => "code",
        "scope" => "openid profile email",
        "state" => "state-1",
        "nonce" => "nonce-1",
        "code_challenge" => challenge(),
        "code_challenge_method" => "S256"
      },
      overrides
    )
  end

  defp code(overrides \\ %{}) do
    response =
      Req.post!(DevOidc.issuer(:oidc) <> "/authorize/decision",
        form: Map.put(request_params(overrides), "fixture", "olga"),
        redirect: false,
        retry: false
      )

    302 = response.status
    [location] = Req.Response.get_header(response, "location")
    URI.decode_query(URI.parse(location).query)["code"]
  end

  defp token(code, opts \\ []) do
    form = %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" =>
        Keyword.get(opts, :redirect_uri, public_url() <> "/auth/oidc/oidc/callback"),
      "code_verifier" => Keyword.get(opts, :verifier, @verifier)
    }

    Req.post!(DevOidc.issuer(:oidc) <> "/token",
      form: form,
      auth: {:basic, "espalier-dev:" <> Keyword.get(opts, :secret, fixture_secret())},
      retry: false
    )
  end

  test "a code works once with the right verifier and secret" do
    code = code()
    response = token(code)
    assert response.status == 200
    assert response.body["token_type"] == "Bearer"
    assert response.body["expires_in"] == 300

    # The kid stands in the protected header.
    header = response.body["id_token"] |> JOSE.JWS.peek_protected() |> JSON.decode!()
    assert %{"alg" => "RS256", "kid" => kid} = header
    assert kid == DevOidc.signing_key().kid

    claims = response.body["id_token"] |> JOSE.JWT.peek_payload() |> Map.fetch!(:fields)
    assert claims["nonce"] == "nonce-1"
    assert claims["aud"] == "espalier-dev"
    assert claims["exp"] == claims["iat"] + 300

    assert token(code).status == 400
  end

  test "a PKCE mismatch, a wrong secret and another redirect URI fail" do
    assert token(code(), verifier: "another-verifier-of-sufficient-length-0123456789").body ==
             %{"error" => "invalid_grant"}

    response = token(code(), secret: "wrong-secret")
    assert response.status == 401
    assert response.body == %{"error" => "invalid_client"}

    assert token(code(), redirect_uri: public_url() <> "/auth/oidc/google/callback").status == 400
  end

  test "an expired code fails" do
    code = code()

    :sys.replace_state(Espalier.DevOidc.State, fn state ->
      update_in(state, [:codes, code, :expires_at], &(&1 - 120))
    end)

    assert token(code).body == %{"error" => "invalid_grant"}
  end

  test "an unknown redirect URI is refused without a redirect" do
    url =
      DevOidc.issuer(:oidc) <>
        "/authorize?" <>
        URI.encode_query(request_params(%{"redirect_uri" => "https://evil.example.net/cb"}))

    response = Req.get!(url, redirect: false, retry: false)
    assert response.status == 400
    assert Req.Response.get_header(response, "location") == []
  end

  test "a request without PKCE S256 is answered with invalid_request" do
    url =
      DevOidc.issuer(:oidc) <>
        "/authorize?" <> URI.encode_query(request_params(%{"code_challenge_method" => "plain"}))

    response = Req.get!(url, redirect: false, retry: false)
    assert response.status == 302
    [location] = Req.Response.get_header(response, "location")
    assert URI.decode_query(URI.parse(location).query)["error"] == "invalid_request"
  end
end
