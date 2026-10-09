defmodule EspalierWeb.OidcFlowTest do
  use Espalier.OidcCase

  import Ecto.Query

  alias Espalier.Accounts
  alias Espalier.Accounts.{ExternalIdentity, MailWorker, Scope, UserToken}
  alias Espalier.DevOidc.Fixtures
  alias Espalier.Hashed.HMAC
  alias Espalier.Identity.Config
  alias Espalier.Identity.Oidc
  alias Espalier.Identity.Oidc.ClientKey
  alias Espalier.Repo

  defp entra(overrides \\ %{}), do: provider_env("entra", "entra", overrides)
  defp google(overrides \\ %{}), do: provider_env("google", "google", overrides)
  defp oidc(overrides \\ %{}), do: provider_env("oidc", "oidc", overrides)

  defp certificate_entra(dir, overrides \\ %{}) do
    cert = client_certificate(dir)

    entra(
      Map.merge(
        %{
          "CLIENT_SECRET" => nil,
          "CLIENT_CERT_FILE" => cert.cert_file,
          "CLIENT_KEY_FILE" => cert.key_file
        },
        overrides
      )
    )
    |> Map.put(:cert, cert)
  end

  defp setup_with_cert(envs) do
    {certs, envs} =
      Enum.map_reduce(envs, [], fn env, acc ->
        {Map.get(env, :cert), [Map.delete(env, :cert) | acc]}
      end)

    {Enum.reject(certs, &is_nil/1), setup_providers(Enum.reverse(envs))}
  end

  defp ticket_rows do
    Repo.aggregate(from(t in UserToken, where: t.context == :login_ticket), :count)
  end

  defp session_rows(user_id \\ nil) do
    query = from t in UserToken, where: t.context == :session

    query =
      if user_id, do: from(t in query, where: t.user_id == ^user_id), else: query

    Repo.all(query)
  end

  defp current_session(conn) do
    token = conn |> Phoenix.ConnTest.recycle() |> fetch_main_token()
    {:ok, _user, session} = Accounts.get_session_by_token(token)
    session
  end

  defp fetch_main_token(conn) do
    conn = Phoenix.ConnTest.dispatch(next_request(conn), @endpoint, :get, "/api/session", nil)
    conn |> Plug.Conn.fetch_session() |> Plug.Conn.get_session(:user_token)
  end

  # A local user that already holds the identity of `fixture` at `key`.
  defp identity_user(key, profile, fixture, attrs \\ %{}) do
    claims = Fixtures.claims(profile, fixture)
    provider = provider(key)

    {subject, tenant_id} =
      if provider.type == "entra", do: {claims["oid"], claims["tid"]}, else: {claims["sub"], nil}

    user = user_fixture(Map.merge(%{password: nil}, attrs))

    %ExternalIdentity{}
    |> ExternalIdentity.changeset(
      %{provider_key: key, issuer: provider.issuer, tenant_id: tenant_id, subject: subject},
      Scope.for_user(user)
    )
    |> Repo.insert!()

    user
  end

  defp error_of({_conn, location}), do: finish_error(location)

  defp assert_fail_event(ref, reason) do
    reason = to_string(reason)
    assert_received {^ref, %{name: :authn_login_fail, reason: ^reason} = meta}
    assert is_binary(meta.provider)
    meta
  end

  describe "provider list" do
    test "GET /auth/providers and GET /api/session list the providers in configured order",
         %{conn: conn} do
      setup_providers([entra(), google(), oidc()])

      expected = [
        %{"key" => "entra", "kind" => "redirect", "start_url" => "/auth/oidc/entra"},
        %{"key" => "google", "kind" => "redirect", "start_url" => "/auth/oidc/google"},
        %{"key" => "oidc", "kind" => "redirect", "start_url" => "/auth/oidc/oidc"}
      ]

      providers = conn |> get("/auth/providers") |> json_response(200) |> Map.fetch!("providers")
      assert Enum.map(providers, &Map.take(&1, ["key", "kind", "start_url"])) == expected

      session = build_conn() |> get("/api/session") |> json_response(200)

      assert Enum.map(session["providers"], &Map.take(&1, ["key", "kind", "start_url"])) ==
               expected
    end

    test "an unknown provider answers 404", %{conn: conn} do
      setup_providers([entra()])
      conn = navigate(conn, "/auth/oidc/nope")
      assert json_response(conn, 404) == %{"error" => "unknown_provider"}
    end
  end

  describe "entra with a client certificate" do
    @tag :tmp_dir
    test "uses private_key_jwt with PS256 and the configured kid format", %{
      conn: conn,
      tmp_dir: dir
    } do
      for format <- ["x5t_s256", "x5t", "sha1_hex"] do
        DevOidc.reset!()
        stop_supervised(Espalier.Identity.Oidc.Supervisor)

        {[cert], _providers} =
          setup_with_cert([certificate_entra(dir, %{"CLIENT_KID_FORMAT" => format})])

        {conn, location} = authorize(build_api_conn(conn), "entra")
        assert URI.decode_query(URI.parse(location).query)["code_challenge_method"] == "S256"

        {conn, location} = callback(conn, decide(location, "ada"))
        assert ticket(location), "#{format}: #{location}"

        [token_request] = token_requests(:entra)
        assert token_request.auth_method == "private_key_jwt"
        assert token_request.assertion_header["alg"] == "PS256"

        assert token_request.assertion_header["kid"] ==
                 ClientKey.kid(cert.der, String.to_existing_atom(format))

        conn = finish(conn, ticket(location))
        assert json_response(conn, 200)["next"] in ["enroll_second_factor", "second_factor"]
      end

      [session | _] = session_rows()
      assert session.provider_key == "entra"
      assert session.idp_sid_hash == HMAC.hash("sid-ada")
    end

    @tag :tmp_dir
    test "a discovery document that offers JAR and DPoP changes nothing", %{
      conn: conn,
      tmp_dir: dir
    } do
      DevOidc.put_switch(:entra, :advertise_jar_dpop)
      setup_with_cert([certificate_entra(dir)])

      {conn, location} = authorize(conn, "entra")
      query = URI.decode_query(URI.parse(location).query)
      refute Map.has_key?(query, "request")
      refute Map.has_key?(query, "dpop_jkt")

      {conn, location} = callback(conn, decide(location, "ada"))
      assert json_response(finish(conn, ticket(location)), 200)

      [token_request] = token_requests(:entra)
      assert token_request.auth_method == "private_key_jwt"
      refute token_request.dpop
    end

    @tag :tmp_dir
    test "without the signing-algorithm override the token request never starts", %{
      conn: conn,
      tmp_dir: dir
    } do
      cert = client_certificate(dir)

      env =
        entra(%{
          "CLIENT_SECRET" => nil,
          "CLIENT_CERT_FILE" => cert.cert_file,
          "CLIENT_KEY_FILE" => cert.key_file
        })
        |> Map.put("AUTH_PROVIDERS", "entra")
        |> Map.put("PUBLIC_URL", public_url())

      [provider] = Config.parse!(env, :test)
      worker = Module.concat(__MODULE__, NoSigningAlgs)

      start_supervised!(
        {Oidcc.ProviderConfiguration.Worker,
         %{
           issuer: provider.issuer,
           name: worker,
           provider_configuration_opts: %{
             quirks: %{
               allow_unsafe_http: true,
               document_overrides: %{
                 "id_token_signing_alg_values_supported" => ["RS256", "PS256", "ES256"],
                 "code_challenge_methods_supported" => ["S256"]
               }
             },
             request_opts: Oidc.request_opts()
           }
         }}
      )

      provider = %{provider | worker: worker}
      put_providers([provider])
      Oidc.put_client_key("entra", ClientKey.load!(cert.cert_file, cert.key_file, :x5t_s256))
      wait_ready(provider)
      ref = attach_security_events()

      assert error_of(to_callback(conn, "entra", "ada")) == "oidc_failed"
      assert_fail_event(ref, :no_supported_auth_method)
      assert token_requests(:entra) == []
    end
  end

  describe "local mode" do
    test "ada with TOTP gets the second factor and keeps provider and sid", %{conn: conn} do
      setup_providers([entra()])
      user = identity_user("entra", :entra, "ada")
      {_factor, secret} = totp_fixture(user)

      {conn, body, 200} = sign_in(conn, "entra", "ada")
      assert body == %{"next" => "second_factor"}

      conn = api_request(conn, :post, "/api/auth/second-factor", %{totp: totp_code(secret)})
      assert json_response(conn, 200)["session"]["auth_methods"] == ["oidc", "totp"]

      [session] = session_rows(user.id)
      assert session.auth_methods == [:oidc, :totp]
      assert session.strength == :mfa
      assert session.provider_key == "entra"
      assert session.idp_sid_hash == HMAC.hash("sid-ada")

      assert response(front_channel_logout("entra", %{sid: "sid-ada"}), 200) == ""
      assert session_rows(user.id) == []
    end

    test "a new user enrolls TOTP and the mfa session keeps provider and sid", %{conn: conn} do
      setup_providers([entra()])

      {conn, location} = authorize(conn, "entra")
      {conn, location} = callback(conn, decide(location, "ada"))
      assert ticket = ticket(location)
      assert session_rows() == []

      conn = finish(conn, ticket)
      assert json_response(conn, 200) == %{"next" => "enroll_second_factor"}

      [session] = session_rows()
      assert {session.auth_methods, session.strength} == {[:oidc], :enrollment}
      assert session.provider_key == "entra"
      assert session.idp_sid_hash == HMAC.hash("sid-ada")

      conn = api_request(conn, :post, "/api/me/totp")
      secret = Base.decode32!(json_response(conn, 200)["secret_base32"], padding: false)
      conn = api_request(conn, :post, "/api/me/totp/confirm", %{code: totp_code(secret)})
      assert json_response(conn, 200)["session"]["session"]["strength"] == "mfa"

      [session] = session_rows()
      assert {session.auth_methods, session.strength} == {[:oidc, :totp], :mfa}
      assert session.provider_key == "entra"
      assert session.idp_sid_hash == HMAC.hash("sid-ada")

      front_channel_logout("entra", %{sid: "sid-ada"})
      assert session_rows() == []
    end
  end

  describe "idp_trusted mode" do
    test "ben gets a full session with the provider's amr", %{conn: conn} do
      setup_providers([entra(%{"MFA" => "idp_trusted"})])

      {_conn, body, 200} = sign_in(conn, "entra", "ben")
      refute Map.has_key?(body, "next")
      assert body["session"]["auth_methods"] == ["oidc", "idp_mfa"]
      assert body["session"]["strength"] == "mfa"

      [session] = session_rows()
      assert session.idp_amr == ["pwd", "mfa"]
      assert session.mfa_at
    end

    test "a single-factor amr leads to the local second factor", %{conn: conn} do
      setup_providers([entra(%{"MFA" => "idp_trusted"})])
      DevOidc.put_switch(:entra, :amr_single_factor)

      {_conn, body, 200} = sign_in(conn, "entra", "ben")
      assert body == %{"next" => "enroll_second_factor"}

      user = identity_user("entra", :entra, "ada")
      totp_fixture(user)
      {_conn, body, 200} = sign_in(build_api_conn(conn), "entra", "ada")
      assert body == %{"next" => "second_factor"}
    end

    test "a provider without amr keeps the operator's statement", %{conn: conn} do
      setup_providers([google(%{"MFA" => "idp_trusted"})])

      {_conn, body, 200} = sign_in(conn, "google", "gina")
      assert body["session"]["auth_methods"] == ["oidc", "idp_mfa"]
    end
  end

  describe "provider rules" do
    test "the entra issuer as type oidc fails closed without PKCE", %{conn: conn} do
      setup_providers([
        provider_env("entra", "oidc", %{"PROVISION" => "true"}, :entra)
      ])

      ref = attach_security_events()
      {_conn, location} = authorize(conn, "entra")
      assert finish_error(location) == "oidc_unavailable"
      assert_fail_event(ref, :no_supported_code_challenge)
    end

    test "Google: hosted domain, unverified address and the iss parameter", %{conn: conn} do
      setup_providers([google()])

      assert {_conn, _body, 200} = sign_in(conn, "google", "gina")
      assert Accounts.get_user_by_email("gina@example.org")

      ref = attach_security_events()
      assert error_of(to_callback(build_api_conn(conn), "google", "gus")) == "oidc_failed"
      assert_fail_event(ref, :domain_mismatch)

      {_conn, _body, 200} = sign_in(build_api_conn(conn), "google", "uma")
      refute Accounts.get_user_by_email("uma@example.org")

      [identity] =
        Repo.all(
          from i in ExternalIdentity,
            where:
              i.subject_hash ==
                ^ExternalIdentity.hash_input(
                  DevOidc.issuer(:google),
                  nil,
                  Fixtures.claims(:google, "uma")["sub"]
                )
        )

      assert Accounts.get_user!(identity.user_id).email == nil

      DevOidc.put_switch(:google, :omit_iss)
      assert error_of(to_callback(build_api_conn(conn), "google", "gina")) == "oidc_failed"
      assert_fail_event(ref, :issuer_mismatch)
    end

    test "every token failure ends without a ticket", %{conn: conn} do
      setup_providers([entra()])

      # The reason tags of oidcc 3.9.0 and of Rules.check/4.
      for {switch, reason} <- [
            invalid_signature: :no_matching_key,
            wrong_aud: :missing_claim,
            expired: :token_expired,
            missing_nonce: :missing_claim,
            unknown_kid: :no_matching_key_with_kid,
            groups_overage: :groups_overage,
            hasgroups: :groups_overage,
            wrong_tid: :tenant_mismatch,
            alg_none: :no_matching_key,
            alg_hs256: :no_matching_key
          ] do
        DevOidc.reset!()
        DevOidc.put_switch(:entra, switch)
        ref = attach_security_events()

        assert error_of(to_callback(build_api_conn(conn), "entra", "ada")) == "oidc_failed",
               "#{switch}"

        assert_fail_event(ref, reason)
        assert ticket_rows() == 0
      end
    end

    test "a discovery document of another issuer leaves the provider unavailable", %{
      conn: conn
    } do
      DevOidc.put_switch(:entra, :discovery_issuer_mismatch)
      setup_providers([entra()], wait: false)
      # The worker has fetched the document once and rejected it.
      assert eventually(fn ->
               Enum.any?(DevOidc.requests(:entra), &(&1.endpoint == :discovery))
             end)

      ref = attach_security_events()

      assert error_of(authorize(conn, "entra")) == "oidc_unavailable"
      assert_fail_event(ref, :provider_not_ready)
      assert ticket_rows() == 0
    end

    test "weak algorithms in the discovery document are never accepted", %{conn: conn} do
      DevOidc.put_switch(:entra, :advertise_weak_algs)
      setup_providers([entra()])

      for switch <- [:alg_none, :alg_hs256] do
        DevOidc.reset!()
        DevOidc.put_switch(:entra, switch)
        ref = attach_security_events()
        assert error_of(to_callback(build_api_conn(conn), "entra", "ada")) == "oidc_failed"
        assert_fail_event(ref, :no_matching_key)
        assert ticket_rows() == 0
      end
    end

    test "a token endpoint on another host fails closed until it is allowed", %{conn: conn} do
      DevOidc.put_switch(:oidc, :foreign_token_endpoint)
      setup_providers([oidc(%{"PROVISION" => "true"})])
      ref = attach_security_events()

      assert error_of(authorize(conn, "oidc")) == "oidc_unavailable"
      assert_fail_event(ref, :endpoint_not_allowed)

      conn = navigate(build_api_conn(conn), "/auth/oidc/oidc/callback?code=x&state=y")
      assert finish_error(redirected_to(conn)) == "oidc_unavailable"
      assert token_requests(:oidc) == []

      stop_supervised(Espalier.Identity.Oidc.Supervisor)

      setup_providers([
        oidc(%{"PROVISION" => "true", "ALLOWED_HOSTS" => "localhost,127.0.0.1"})
      ])

      assert {_conn, _body, 200} = sign_in(build_api_conn(conn), "oidc", "olga")
      assert [%{host: "127.0.0.1"}] = token_requests(:oidc)
    end

    test "a rotated key is fetched for its new kid", %{conn: conn} do
      setup_providers([entra()])
      assert {_conn, _body, 200} = sign_in(conn, "entra", "ada")

      DevOidc.rotate_key!()
      assert {_conn, _body, 200} = sign_in(build_api_conn(conn), "entra", "ada")
    end
  end

  describe "transaction checks" do
    test "deny, missing transaction, wrong state, reused code and reused ticket", %{
      conn: conn
    } do
      setup_providers([entra(), google()])

      assert error_of(to_callback(conn, "entra", "deny")) == "oidc_cancelled"

      {_conn, location} = authorize(build_api_conn(conn), "entra")
      callback_url = decide(location, "ada")
      assert error_of(callback(build_api_conn(conn), callback_url)) == "oidc_failed"

      {conn2, location} = authorize(build_api_conn(conn), "entra")
      callback_url = decide(location, "ada")
      tampered = String.replace(callback_url, ~r/state=[^&]+/, "state=forged")
      assert error_of(callback(conn2, tampered)) == "oidc_failed"

      {conn3, location} = authorize(build_api_conn(conn), "entra")
      callback_url = decide(location, "ada")
      {conn3, location} = callback(conn3, callback_url)
      assert ticket = ticket(location)
      assert error_of(callback(conn3, callback_url)) == "oidc_failed"

      assert json_response(finish(build_api_conn(conn), ticket), 401) == %{
               "error" => "ticket_invalid"
             }

      assert json_response(finish(conn3, ticket), 401) == %{"error" => "ticket_invalid"}
    end

    test "a malformed callback parameter fails without a 500", %{conn: conn} do
      setup_providers([entra()])
      ref = attach_security_events()

      {conn, location} = authorize(conn, "entra")
      callback_url = decide(location, "ada") <> "&scope[]=x"

      assert error_of(callback(conn, callback_url)) == "oidc_failed"
      assert_fail_event(ref, :invalid_callback)
      assert ticket_rows() == 0
    end

    test "a ticket works once", %{conn: conn} do
      setup_providers([entra()])
      {conn, location} = to_callback(conn, "entra", "ada")
      ticket = ticket(location)
      {conn2, location2} = to_callback(build_api_conn(conn), "entra", "ada")

      conn = finish(conn, ticket)
      assert json_response(conn, 200)
      assert json_response(finish(conn, ticket), 401) == %{"error" => "ticket_invalid"}
      assert json_response(finish(conn2, ticket(location2)), 200)
    end

    test "a response at another provider's redirect URI ends before the token request", %{
      conn: conn
    } do
      setup_providers([entra(), google()])
      ref = attach_security_events()

      {conn, location} = authorize(conn, "entra")
      callback_url = decide(location, "ada")

      moved =
        String.replace(callback_url, "/auth/oidc/entra/callback", "/auth/oidc/google/callback")

      assert error_of(callback(conn, moved)) == "oidc_failed"
      assert_fail_event(ref, :provider_mismatch)
      assert token_requests(:entra) == []
    end

    test "a finish from a conn with another user's session replaces that session" do
      setup_providers([entra(%{"MFA" => "idp_trusted"})])
      other = user_fixture()
      conn = signed_in_browser(other)
      assert [_other_session] = session_rows(other.id)

      {conn, _body, 200} = sign_in(conn, "entra", "ben")
      assert session_rows(other.id) == []
      assert [_session] = session_rows()

      assert json_response(get(next_request(conn), "/api/session"), 200)["user"]["display_name"] ==
               "Ben Example"
    end
  end

  describe "linking" do
    setup %{conn: conn} do
      setup_providers([entra(), oidc()])
      user = user_fixture()
      totp_fixture(user)
      %{conn: log_in_user(conn, user), user: user}
    end

    defp intent(conn, key, purpose) do
      conn = api_request(conn, :post, "/api/auth/oidc/#{key}/intents", %{purpose: purpose})
      {conn, conn.resp_body && Jason.decode!(conn.resp_body)}
    end

    test "a recent second factor links the provider at finish", %{conn: conn, user: user} do
      {conn, %{"url" => url}} = intent(conn, "entra", "link")
      assert conn.status == 201
      assert url =~ ~r{\A/auth/oidc/entra\?intent=[A-Za-z0-9_-]+\z}

      {conn, location} =
        authorize(conn, "entra", url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query())

      {conn, location} = callback(conn, decide(location, "ada"))
      assert ticket = ticket(location)
      refute Accounts.provider_linked?(user.id, "entra")

      conn = finish(conn, ticket)
      body = json_response(conn, 200)
      assert body["linked"] == true
      assert body["user"]["id"] == user.id
      assert Accounts.provider_linked?(user.id, "entra")

      assert_enqueued(
        worker: MailWorker,
        args: %{"kind" => "identity_linked", "user_id" => user.id, "provider_key" => "entra"}
      )
    end

    test "an intent needs a recent second factor and an mfa session", %{conn: conn, user: user} do
      override_session(get_session(conn, :user_token),
        mfa_at: DateTime.add(DateTime.utc_now(:second), -3600)
      )

      {conn, body} = intent(conn, "entra", "link")
      assert conn.status == 403
      assert body == %{"error" => "reauth_required"}

      put_setting(:auth_demo, true)
      demo = api_request(build_api_conn(conn), :post, "/api/auth/demo", %{slot: 1})
      {conn, body} = intent(demo, "entra", "link")
      assert conn.status == 403
      assert body == %{"error" => "forbidden"}

      {conn, body} = intent(demo, "nope", "link")
      assert conn.status == 404
      assert body == %{"error" => "unknown_provider"}
      refute Accounts.provider_linked?(user.id, "entra")
    end

    test "an identity of another account ends in oidc_identity_in_use", %{conn: conn} do
      identity_user("entra", :entra, "ada")
      {conn, %{"url" => url}} = intent(conn, "entra", "link")
      query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      {conn, location} = authorize(conn, "entra", query)
      assert error_of(callback(conn, decide(location, "ada"))) == "oidc_identity_in_use"
    end

    test "an intent works only in the session that created it", %{conn: conn, user: user} do
      other_user = user_fixture()

      for opener <- [
            fn -> build_api_conn(conn) end,
            fn -> signed_in_browser(user) end,
            fn -> signed_in_browser(other_user) end
          ] do
        {_conn, %{"url" => url}} = intent(conn, "entra", "link")
        ref = attach_security_events()

        assert error_of({nil, redirected_to(navigate(opener.(), url))}) == "oidc_failed"
        assert_fail_event(ref, :intent_session_mismatch)
        assert Repo.aggregate(from(t in UserToken, where: t.context == :oidc_intent), :count) == 0
      end

      refute Accounts.provider_linked?(user.id, "entra")
    end

    test "a link ticket posted from another user's session links nothing", %{
      conn: conn,
      user: user
    } do
      {conn, %{"url" => url}} = intent(conn, "entra", "link")
      query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      {conn, location} = authorize(conn, "entra", query)
      {conn, location} = callback(conn, decide(location, "ada"))
      ticket = ticket(location)

      {other_token, _session} = session_fixture(user_fixture())

      conn =
        conn
        |> Phoenix.ConnTest.recycle()
        |> init_test_session(%{})
        |> put_session(:user_token, other_token)

      conn = finish(conn, ticket)
      assert json_response(conn, 401) == %{"error" => "ticket_invalid"}
      refute Accounts.provider_linked?(user.id, "entra")
    end
  end

  describe "provisioning off" do
    test "olga links to a local account and then signs in through it", %{conn: conn} do
      setup_providers([oidc()])

      assert error_of(to_callback(conn, "oidc", "olga")) == "oidc_no_account"

      user = user_fixture()
      {_factor, _secret} = totp_fixture(user)
      [recovery | _] = recovery_codes_fixture(user)
      conn = log_in_user(build_api_conn(conn), user)

      conn = api_request(conn, :post, "/api/auth/oidc/oidc/intents", %{purpose: "link"})
      %{"url" => url} = json_response(conn, 201)
      query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      {conn, location} = authorize(conn, "oidc", query)
      {conn, location} = callback(conn, decide(location, "olga"))
      assert json_response(finish(conn, ticket(location)), 200)["linked"]

      # Password sign-in serves only accounts without an external identity.
      conn =
        api_request(build_api_conn(conn), :post, "/api/auth/password", %{
          email: user.email,
          password: valid_user_password()
        })

      assert json_response(conn, 401) == %{"error" => "invalid_credentials"}

      {conn, body, 200} = sign_in(build_api_conn(conn), "oidc", "olga")
      assert body == %{"next" => "second_factor"}

      conn = api_request(conn, :post, "/api/auth/second-factor", %{recovery_code: recovery})
      assert json_response(conn, 200)["session"]["auth_methods"] == ["oidc", "recovery_code"]

      conn =
        api_request(conn, :put, "/api/me/password", %{
          current_password: valid_user_password(),
          password: "plum orbit lantern 4719 renewed"
        })

      assert json_response(conn, 200)
      [session] = session_rows(user.id)
      assert session.provider_key == "oidc"
      assert session.idp_sid_hash == HMAC.hash("sid-olga")

      front_channel_logout("oidc", %{sid: "sid-olga"})
      assert session_rows(user.id) == []
    end
  end

  describe "step-up" do
    setup %{conn: conn} do
      setup_providers([entra(%{"MFA" => "idp_trusted"})])
      conn = sign_in!(conn, "entra", "ben")
      %{conn: conn}
    end

    defp step_up_flow(conn) do
      conn = api_request(conn, :post, "/api/auth/oidc/entra/intents", %{purpose: "step_up"})
      %{"url" => url} = json_response(conn, 201)
      query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      {conn, location} = authorize(conn, "entra", query)
      assert URI.decode_query(URI.parse(location).query)["max_age"] == "0"
      callback(conn, decide(location, "ben"))
    end

    test "replaces the session token, keeps expires_at and sets mfa_at", %{conn: conn} do
      before = current_session(conn)
      old_mfa_at = DateTime.add(DateTime.utc_now(:second), -3600)
      Repo.update_all(from(t in UserToken, where: t.id == ^before.id), set: [mfa_at: old_mfa_at])
      ref = attach_security_events()

      {conn, location} = step_up_flow(conn)
      conn = finish(conn, ticket(location))
      body = json_response(conn, 200)
      assert body["session"]["auth_methods"] == ["oidc", "idp_mfa"]

      assert_received {^ref, %{name: :session_renewed}}
      assert_received {^ref, %{name: :authn_login_success, purpose: "step_up", factor: "idp_mfa"}}

      [after_step_up] = session_rows()
      assert after_step_up.id != before.id
      assert after_step_up.expires_at == before.expires_at
      assert DateTime.after?(after_step_up.mfa_at, old_mfa_at)
      assert after_step_up.idp_sid_hash == HMAC.hash("sid-ben")

      front_channel_logout("entra", %{sid: "sid-ben"})
      assert session_rows() == []
    end

    test "fails without a fresh auth_time or with a single-factor amr", %{conn: conn} do
      for switch <- [:no_auth_time, :stale_auth_time, :amr_single_factor] do
        DevOidc.reset!()
        DevOidc.put_switch(:entra, switch)
        assert error_of(step_up_flow(conn)) == "oidc_failed", "#{switch}"
      end
    end
  end

  describe "logout" do
    test "front-channel logout ends only the sessions of its sid and issuer", %{conn: conn} do
      setup_providers([entra()])
      user = identity_user("entra", :entra, "ada")
      {_factor, secret} = totp_fixture(user)
      {conn, _body, 200} = sign_in(conn, "entra", "ada")
      api_request(conn, :post, "/api/auth/second-factor", %{totp: totp_code(secret)})
      assert [_session] = session_rows(user.id)

      conn = front_channel_logout("entra", %{sid: "sid-unknown"})
      assert response(conn, 200) == ""
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert [_session] = session_rows(user.id)

      front_channel_logout("entra", %{sid: "sid-ada", iss: "https://other.example.org"})
      assert [_session] = session_rows(user.id)

      ref = attach_security_events()
      front_channel_logout("entra", %{sid: "sid-ada", iss: DevOidc.issuer(:entra)})
      assert session_rows(user.id) == []

      assert_received {^ref,
                       %{
                         name: :session_logout,
                         trigger: "front_channel",
                         count: 1,
                         provider: "entra"
                       }}
    end

    test "DELETE /api/session returns the RP-initiated logout URL where one exists", %{
      conn: conn
    } do
      setup_providers([entra(%{"MFA" => "idp_trusted"}), google(%{"MFA" => "idp_trusted"})])

      conn = sign_in!(conn, "entra", "ben")
      conn = api_request(conn, :delete, "/api/session")
      %{"logout_url" => url} = json_response(conn, 200)
      query = URI.decode_query(URI.parse(url).query)
      assert query["client_id"] == "espalier-dev"
      assert query["post_logout_redirect_uri"] == public_url() <> "/signed-out"
      refute Map.has_key?(query, "id_token_hint")
      assert session_rows() == []

      logout = Req.get!(url, redirect: false, retry: false)
      assert logout.status == 302
      assert Req.Response.get_header(logout, "location") == [public_url() <> "/signed-out"]

      conn = sign_in!(build_api_conn(conn), "google", "gina")
      conn = api_request(conn, :delete, "/api/session")
      assert response(conn, 204) == ""
    end
  end

  describe "provider outage" do
    test "an unreachable provider ends only its own sign-ins", %{conn: conn} do
      setup_providers([google(%{"MFA" => "idp_trusted"})])
      old = sign_in!(conn, "google", "gina")
      stop_supervised(Espalier.Identity.Oidc.Supervisor)

      DevOidc.put_switch(:entra, :discovery_down)
      setup_providers([entra(), google(%{"MFA" => "idp_trusted"})], wait: false)
      wait_ready(provider("google"))

      assert error_of(authorize(build_api_conn(conn), "entra")) == "oidc_unavailable"

      conn2 = navigate(build_api_conn(conn), "/auth/oidc/entra/callback?code=x&state=y")
      assert finish_error(redirected_to(conn2)) == "oidc_unavailable"

      assert {_conn, _body, 200} = sign_in(build_api_conn(conn), "google", "gina")
      assert json_response(get(next_request(old), "/api/session"), 200)["user"]

      DevOidc.reset!()
      assert eventually(fn -> match?({_, _, 200}, sign_in_or_error(conn)) end)
    end

    test "a worker that does not answer ends authorize, callback and logout without a 500",
         %{conn: conn} do
      setup_providers([entra(%{"MFA" => "idp_trusted"})])
      conn = sign_in!(conn, "entra", "ben")
      {pending, location} = authorize(build_api_conn(conn), "entra")
      callback_url = decide(location, "ben")

      worker = Process.whereis(provider("entra").worker)
      :sys.suspend(worker)
      on_exit(fn -> if Process.alive?(worker), do: :sys.resume(worker) end)

      # Each request waits for the call timeout of 5 seconds, so they run at once.
      [authorized, called_back, logged_out] =
        [
          fn -> error_of(authorize(build_api_conn(conn), "entra")) end,
          fn -> error_of(callback(pending, callback_url)) end,
          fn -> conn |> api_request(:delete, "/api/session") |> response(204) end
        ]
        |> Enum.map(&Task.async/1)
        |> Task.await_many(15_000)

      :sys.resume(worker)
      assert authorized == "oidc_unavailable"
      assert called_back == "oidc_unavailable"
      assert logged_out == ""
      assert session_rows() == []
      assert ticket_rows() == 0
    end

    defp sign_in_or_error(conn) do
      {conn, location} = authorize(build_api_conn(conn), "entra")

      if finish_error(location) do
        {:error, nil, nil}
      else
        {conn, location} = callback(conn, decide(location, "ada"))
        conn = finish(conn, ticket(location))
        {conn, nil, conn.status}
      end
    end
  end

  describe "security events and log hygiene" do
    test "a complete sign-in emits session_created and authn_login_success", %{conn: conn} do
      setup_providers([entra(%{"MFA" => "idp_trusted"})])
      ref = attach_security_events()

      sign_in!(conn, "entra", "ben")

      assert_received {^ref, %{name: :session_created, provider: "entra"} = created}
      assert created.session_id && created.user_id

      assert_received {^ref,
                       %{name: :authn_login_success, provider: "entra", factor: "oidc+idp_mfa"}}

      DevOidc.put_switch(:entra, :wrong_aud)
      to_callback(build_api_conn(conn), "entra", "ben")

      assert_received {^ref,
                       %{name: :authn_login_fail, provider: "entra", purpose: "sign_in"} = failed}

      assert is_binary(failed.reason)
    end

    test "no log line shows code, state, ticket, intent or sid", %{conn: conn} do
      setup_providers([entra(%{"MFA" => "idp_trusted"})])
      Logger.put_module_level(Phoenix.Logger, :debug)
      Logger.put_module_level(Espalier.SecurityLog, :info)

      on_exit(fn ->
        Logger.delete_module_level(Phoenix.Logger)
        Logger.delete_module_level(Espalier.SecurityLog)
      end)

      {values, log} =
        with_log([level: :debug], fn ->
          {conn, location} = authorize(conn, "entra")
          callback_url = decide(location, "ben")
          query = URI.decode_query(URI.parse(callback_url).query)
          {conn, location} = callback(conn, callback_url)
          ticket = ticket(location)
          conn = finish(conn, ticket)
          json_response(conn, 200)

          conn = api_request(conn, :post, "/api/auth/oidc/entra/intents", %{purpose: "step_up"})
          %{"url" => url} = json_response(conn, 201)

          intent =
            url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("intent")

          authorize(conn, "entra", %{intent: intent})

          front_channel_logout("entra", %{sid: "sid-ben"})
          [query["code"], query["state"], ticket, intent, "sid-ben"]
        end)

      assert log =~ "authn_login_success"
      assert log =~ "Parameters"

      for value <- values do
        refute log =~ value
      end
    end
  end

  defp build_api_conn(_conn), do: api_conn()

  # Polls `fun` for at most five seconds.
  defp eventually(fun, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) > deadline -> false
      true -> Process.sleep(50) && eventually(fun, deadline)
    end
  end
end
