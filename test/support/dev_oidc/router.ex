defmodule Espalier.DevOidc.Router do
  @moduledoc """
  The endpoints of the mock OIDC provider: discovery, JWKS, authorization
  with a plain HTML choice of fixture users, decision, token and logout
  (task 0006, step 15). `Espalier.DevOidc.put_switch/2` changes their
  answers per profile.
  """
  use Plug.Router

  alias Espalier.DevOidc
  alias Espalier.DevOidc.Fixtures

  @jwt_bearer "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @code_seconds 60
  @token_seconds 300

  plug :match
  plug Plug.Parsers, parsers: [:urlencoded, :json], json_decoder: JSON
  plug :dispatch

  match _ do
    case split(conn.path_info) do
      {profile, rest} -> route(conn, profile, conn.method, rest)
      :error -> send_resp(conn, 404, "")
    end
  end

  defp split(["entra", tenant, "v2.0" | rest]) do
    if tenant == DevOidc.config()[:tenant_id], do: {:entra, rest}, else: :error
  end

  defp split(["google" | rest]), do: {:google, rest}
  defp split(["oidc" | rest]), do: {:oidc, rest}
  defp split(_path), do: :error

  ## Routing

  defp route(conn, profile, "POST", ["token"]) do
    if DevOidc.switch?(profile, :token_redirect) do
      log(conn, profile, :token_redirect)
      redirect(conn, DevOidc.issuer(profile) <> "/token-moved", 307)
    else
      token(conn, profile)
    end
  end

  defp route(conn, profile, "POST", ["token-moved"]), do: token(conn, profile)

  defp route(conn, profile, method, rest) do
    log(conn, profile, endpoint(rest))
    serve(conn, profile, method, rest)
  end

  defp endpoint([".well-known", "openid-configuration"]), do: :discovery
  defp endpoint(["moved"]), do: :moved
  defp endpoint(["jwks"]), do: :jwks
  defp endpoint(["authorize"]), do: :authorize
  defp endpoint(["authorize", "decision"]), do: :decision
  defp endpoint(["logout"]), do: :logout
  defp endpoint(_rest), do: :unknown

  defp serve(conn, profile, "GET", [".well-known", "openid-configuration"]) do
    cond do
      DevOidc.switch?(profile, :discovery_down) ->
        send_resp(conn, 503, "")

      DevOidc.switch?(profile, :discovery_redirect) ->
        redirect(conn, DevOidc.issuer(profile) <> "/moved")

      true ->
        json(conn, 200, discovery(profile))
    end
  end

  defp serve(conn, profile, "GET", ["moved"]), do: json(conn, 200, discovery(profile))

  defp serve(conn, profile, "GET", ["jwks"]) do
    if DevOidc.switch?(profile, :discovery_down),
      do: send_resp(conn, 503, ""),
      else: json(conn, 200, jwks())
  end

  defp serve(conn, profile, "GET", ["authorize"]), do: authorize(conn, profile)
  defp serve(conn, profile, "POST", ["authorize", "decision"]), do: decision(conn, profile)

  defp serve(conn, profile, "GET", ["logout"]) when profile in [:entra, :oidc],
    do: logout(conn)

  defp serve(conn, _profile, _method, _rest), do: send_resp(conn, 404, "")

  ## Discovery and keys

  @doc false
  def discovery(profile) do
    issuer = DevOidc.issuer(profile)

    token_host =
      if DevOidc.switch?(profile, :foreign_token_endpoint),
        do: DevOidc.issuer(profile, "127.0.0.1"),
        else: issuer

    algs =
      if DevOidc.switch?(profile, :advertise_weak_algs),
        do: ["RS256", "HS256", "none"],
        else: ["RS256"]

    %{
      "issuer" => issuer,
      "authorization_endpoint" => issuer <> "/authorize",
      "token_endpoint" => token_host <> "/token",
      "jwks_uri" => issuer <> "/jwks",
      "response_types_supported" => ["code"],
      "response_modes_supported" => ["query"],
      "subject_types_supported" => ["public"],
      "id_token_signing_alg_values_supported" => algs,
      "grant_types_supported" => ["authorization_code"],
      "scopes_supported" => ["openid", "profile", "email"]
    }
    |> Map.merge(profile_document(profile, issuer))
    |> issuer_mismatch(profile)
    |> jar_dpop(profile)
  end

  defp profile_document(:entra, issuer) do
    %{
      "subject_types_supported" => ["pairwise"],
      "token_endpoint_auth_methods_supported" => ["client_secret_basic", "private_key_jwt"],
      "end_session_endpoint" => issuer <> "/logout",
      "frontchannel_logout_supported" => true
    }
  end

  defp profile_document(:google, _issuer) do
    %{
      "code_challenge_methods_supported" => ["plain", "S256"],
      "authorization_response_iss_parameter_supported" => true,
      "token_endpoint_auth_methods_supported" => ["client_secret_basic"]
    }
  end

  defp profile_document(:oidc, issuer) do
    %{
      "code_challenge_methods_supported" => ["S256"],
      "token_endpoint_auth_methods_supported" => ["client_secret_basic"],
      "end_session_endpoint" => issuer <> "/logout"
    }
  end

  defp issuer_mismatch(document, profile) do
    if DevOidc.switch?(profile, :discovery_issuer_mismatch),
      do: Map.put(document, "issuer", document["issuer"] <> "/other"),
      else: document
  end

  defp jar_dpop(document, profile) do
    if DevOidc.switch?(profile, :advertise_jar_dpop) do
      Map.merge(document, %{
        "request_parameter_supported" => true,
        "dpop_signing_alg_values_supported" => ["PS256", "ES256"]
      })
    else
      document
    end
  end

  defp jwks do
    %{jwk: jwk, kid: kid} = DevOidc.signing_key()
    {_meta, public} = JOSE.JWK.to_public_map(jwk)
    %{"keys" => [Map.merge(public, %{"kid" => kid, "alg" => "RS256", "use" => "sig"})]}
  end

  ## Authorization

  defp authorize(conn, profile) do
    params = conn.query_params

    case check_request(params) do
      :ok ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, page(profile, params))

      {:redirect, error} ->
        redirect(
          conn,
          with_query(params["redirect_uri"], %{error: error, state: params["state"]})
        )

      :bad_request ->
        send_resp(conn, 400, "invalid_request")
    end
  end

  # client_id and redirect_uri must be known before the mock redirects to
  # the redirect URI; every other check answers there.
  @doc false
  def check_request(params) do
    config = DevOidc.config()

    cond do
      params["client_id"] != config[:client_id] -> :bad_request
      params["redirect_uri"] not in config[:redirect_uris] -> :bad_request
      valid_request?(params) -> :ok
      true -> {:redirect, "invalid_request"}
    end
  end

  defp valid_request?(params) do
    params["response_type"] == "code" and
      "openid" in String.split(params["scope"] || "", " ") and
      params["state"] not in [nil, ""] and
      params["code_challenge"] not in [nil, ""] and
      params["code_challenge_method"] == "S256"
  end

  @request_fields ~w(client_id redirect_uri response_type scope state nonce code_challenge
                     code_challenge_method max_age)

  defp page(profile, params) do
    hidden =
      for field <- @request_fields, is_binary(params[field]) do
        ~s(<input type="hidden" name="#{field}" value="#{escape(params[field])}">)
      end

    action = escape(DevOidc.issuer(profile) <> "/authorize/decision")

    buttons =
      for id <- Fixtures.ids(profile) ++ ["deny"] do
        label = if id == "deny", do: "Deny", else: "Sign in as #{id}"

        ~s(<form method="post" action="#{action}">#{hidden}) <>
          ~s(<button name="fixture" value="#{escape(id)}">#{escape(label)}</button></form>)
      end

    """
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>Mock OIDC provider (#{profile})</title></head>
    <body><h1>Mock OIDC provider: #{profile}</h1>#{Enum.join(buttons)}</body>
    </html>
    """
  end

  defp escape(value), do: value |> Plug.HTML.html_escape() |> IO.iodata_to_binary()

  defp decision(conn, profile) do
    params = conn.body_params

    case check_request(params) do
      :ok -> decide(conn, profile, params)
      {:redirect, error} -> redirect(conn, with_query(params["redirect_uri"], %{error: error}))
      :bad_request -> send_resp(conn, 400, "invalid_request")
    end
  end

  defp decide(conn, _profile, %{"fixture" => "deny"} = params) do
    redirect(
      conn,
      with_query(params["redirect_uri"], %{error: "access_denied", state: params["state"]})
    )
  end

  defp decide(conn, profile, params) do
    if Fixtures.claims(profile, params["fixture"]) do
      code = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
      now = System.os_time(:second)

      DevOidc.put_code(code, %{
        profile: profile,
        client_id: params["client_id"],
        redirect_uri: params["redirect_uri"],
        challenge: params["code_challenge"],
        nonce: params["nonce"],
        fixture: params["fixture"],
        max_age: params["max_age"],
        auth_time: now,
        expires_at: now + @code_seconds
      })

      query = %{code: code, state: params["state"]}

      query =
        if profile == :google and not DevOidc.switch?(profile, :omit_iss),
          do: Map.put(query, :iss, DevOidc.issuer(profile)),
          else: query

      redirect(conn, with_query(params["redirect_uri"], query))
    else
      send_resp(conn, 400, "unknown fixture")
    end
  end

  ## Token

  defp token(conn, profile) do
    params = conn.body_params
    {method, header, client} = authenticate(conn, profile, params)

    log(conn, profile, :token, %{
      auth_method: method,
      assertion_header: header,
      dpop: get_req_header(conn, "dpop") != []
    })

    case client do
      {:ok, client_id} -> redeem(conn, profile, client_id, params)
      :error -> json(conn, 401, %{error: "invalid_client"})
    end
  end

  defp authenticate(conn, profile, params) do
    case {basic_credentials(conn), params["client_assertion_type"], params["client_assertion"]} do
      {{client_id, secret}, _type, _assertion} ->
        config = DevOidc.config()

        ok? =
          client_id == config[:client_id] and
            Plug.Crypto.secure_compare(secret, config[:client_secret])

        {"client_secret_basic", nil, if(ok?, do: {:ok, client_id}, else: :error)}

      {nil, @jwt_bearer, assertion} when is_binary(assertion) ->
        header = peek_header(assertion)
        result = if profile == :entra, do: verify_assertion(profile, assertion), else: :error
        {"private_key_jwt", header, result}

      _other ->
        {"none", nil, :error}
    end
  end

  defp basic_credentials(conn) do
    with ["Basic " <> encoded] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [client_id, secret] <- String.split(decoded, ":", parts: 2) do
      {URI.decode_www_form(client_id), URI.decode_www_form(secret)}
    else
      _ -> nil
    end
  end

  defp peek_header(assertion) do
    assertion |> JOSE.JWS.peek_protected() |> JSON.decode!()
  rescue
    _ -> nil
  end

  defp verify_assertion(profile, assertion) do
    client_id = DevOidc.config()[:client_id]
    now = System.os_time(:second)

    with %JOSE.JWK{} = key <- DevOidc.client_key(client_id),
         {true, %JOSE.JWT{fields: claims}, _jws} <-
           JOSE.JWT.verify_strict(key, ["RS256", "PS256"], assertion),
         true <- claims["iss"] == client_id and claims["sub"] == client_id,
         true <- claims["aud"] == assertion_audience(profile),
         true <- is_integer(claims["exp"]) and claims["exp"] > now,
         true <- is_binary(claims["jti"]) and DevOidc.use_jti(claims["jti"]) do
      {:ok, client_id}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp assertion_audience(profile) do
    if {:assertion_aud, :token_endpoint} in DevOidc.switches(profile),
      do: DevOidc.issuer(profile) <> "/token",
      else: DevOidc.issuer(profile)
  end

  defp redeem(conn, profile, client_id, params) do
    now = System.os_time(:second)

    with "authorization_code" <- params["grant_type"],
         %{} = code <- DevOidc.pop_code(params["code"]),
         true <- code.profile == profile and code.expires_at > now,
         true <- code.client_id == client_id and code.redirect_uri == params["redirect_uri"],
         true <- pkce?(params["code_verifier"], code.challenge) do
      json(conn, 200, %{
        access_token: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false),
        token_type: "Bearer",
        expires_in: @token_seconds,
        id_token: id_token(profile, code, client_id, now)
      })
    else
      _ -> json(conn, 400, %{error: "invalid_grant"})
    end
  end

  defp pkce?(verifier, challenge) when is_binary(verifier) and is_binary(challenge) do
    :sha256
    |> :crypto.hash(verifier)
    |> Base.url_encode64(padding: false)
    |> Plug.Crypto.secure_compare(challenge)
  end

  defp pkce?(_verifier, _challenge), do: false

  ## ID token

  @doc false
  def id_token(profile, code, client_id, now) do
    switches = DevOidc.switches(profile)

    %{
      "iss" => DevOidc.issuer(profile),
      "aud" => client_id,
      "iat" => now,
      "exp" => now + @token_seconds,
      "auth_time" => code.auth_time
    }
    |> Map.merge(Fixtures.claims(profile, code.fixture))
    |> put_nonce(code.nonce, :missing_nonce in switches)
    |> apply_switches(switches, now)
    |> sign(switches)
  end

  defp put_nonce(claims, nonce, false) when is_binary(nonce), do: Map.put(claims, "nonce", nonce)
  defp put_nonce(claims, _nonce, _missing?), do: claims

  defp apply_switches(claims, switches, now) do
    Enum.reduce(switches, claims, fn switch, claims -> apply_switch(switch, claims, now) end)
  end

  defp apply_switch(:wrong_aud, claims, _now), do: Map.put(claims, "aud", "another-client")

  defp apply_switch(:expired, claims, now),
    do: Map.merge(claims, %{"iat" => now - 3_900, "exp" => now - 3_600})

  defp apply_switch(:groups_overage, claims, _now) do
    Map.merge(claims, %{
      "_claim_names" => %{"groups" => "src1"},
      "_claim_sources" => %{
        "src1" => %{"endpoint" => "https://graph.example.org/v1.0/users/x/getMemberObjects"}
      }
    })
  end

  defp apply_switch(:hasgroups, claims, _now), do: Map.put(claims, "hasgroups", true)

  defp apply_switch(:wrong_tid, claims, _now),
    do: Map.put(claims, "tid", "9d8c7b6a-5f4e-4d3c-8b2a-1f0e9d8c7b6a")

  defp apply_switch(:no_auth_time, claims, _now), do: Map.delete(claims, "auth_time")
  defp apply_switch(:stale_auth_time, claims, now), do: Map.put(claims, "auth_time", now - 3_600)
  defp apply_switch(:amr_single_factor, claims, _now), do: Map.put(claims, "amr", ["pwd"])
  defp apply_switch(_switch, claims, _now), do: claims

  defp sign(claims, switches) do
    %{jwk: jwk, kid: kid} = DevOidc.signing_key()

    cond do
      :alg_none in switches ->
        encode = &Base.url_encode64(&1, padding: false)
        encode.(JSON.encode!(%{"alg" => "none"})) <> "." <> encode.(JSON.encode!(claims)) <> "."

      :alg_hs256 in switches ->
        DevOidc.config()[:client_secret]
        |> JOSE.JWK.from_oct()
        |> compact(%{"alg" => "HS256", "kid" => kid}, claims)

      :unknown_kid in switches ->
        %{jwk: other, kid: other_kid} = DevOidc.new_key()
        compact(other, %{"alg" => "RS256", "kid" => other_kid}, claims)

      :invalid_signature in switches ->
        compact(DevOidc.new_key().jwk, %{"alg" => "RS256", "kid" => kid}, claims)

      true ->
        compact(jwk, %{"alg" => "RS256", "kid" => kid}, claims)
    end
  end

  # The kid must be in the JWS map; a kid stored on the JWK does not reach
  # the compact token.
  defp compact(jwk, jws, claims) do
    {_meta, token} = jwk |> JOSE.JWT.sign(jws, claims) |> JOSE.JWS.compact()
    token
  end

  ## Logout

  defp logout(conn) do
    uri = conn.query_params["post_logout_redirect_uri"]

    if uri in DevOidc.config()[:post_logout_redirect_uris],
      do: redirect(conn, uri),
      else: send_resp(conn, 400, "invalid_request")
  end

  ## Helpers

  defp log(conn, profile, endpoint, extra \\ %{}) do
    DevOidc.log_request(
      profile,
      Map.merge(
        %{endpoint: endpoint, method: conn.method, path: conn.request_path, host: conn.host},
        extra
      )
    )
  end

  defp with_query(uri, query) do
    query = query |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> URI.encode_query()
    uri |> URI.parse() |> URI.append_query(query) |> URI.to_string()
  end

  defp redirect(conn, location, status \\ 302) do
    conn
    |> put_resp_header("location", location)
    |> send_resp(status, "")
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
