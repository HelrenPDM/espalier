defmodule EspalierWeb.Auth.PasskeyAuthControllerTest do
  # put_setting/2 changes :local_accounts for the node.
  use EspalierWeb.ConnCase, async: false

  alias Espalier.Accounts.{AuthChallenge, FailureCounter, FailureCounters}
  alias Espalier.Repo
  alias Espalier.SoftAuthenticator

  setup do
    user = user_fixture()
    {authenticator, credential} = passkey_fixture(user)
    %{user: user, authenticator: authenticator, credential: credential}
  end

  defp passkey_options(conn, body \\ %{}, opts \\ []) do
    conn = api_request(conn, :post, "/api/auth/passkey/options", body, opts)
    {conn, json_response(conn, 200)}
  end

  test "signs in with a discoverable passkey", %{
    conn: conn,
    user: user,
    authenticator: authenticator
  } do
    {conn, options} = passkey_options(conn)

    assert String.length(options["challenge"]) == 43
    assert options["timeout"] == 300_000
    assert options["userVerification"] == "required"
    assert options["rpId"] == "localhost"
    refute Map.has_key?(options, "allowCredentials")
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    csrf_before = conn |> get_req_header("x-csrf-token") |> hd()

    conn =
      api_request(
        conn,
        :post,
        "/api/auth/passkey",
        SoftAuthenticator.assert(authenticator, options)
      )

    body = json_response(conn, 200)

    assert body["user"]["id"] == user.id
    assert body["session"]["strength"] == "mfa"
    assert body["session"]["auth_methods"] == ["passkey"]
    assert body["session"]["recent_auth_until"]
    refute body["csrf_token"] == csrf_before
  end

  test "the ceremony id lives in the session cookie and works once",
       %{conn: conn, authenticator: authenticator} do
    {options_conn, options} = passkey_options(conn)

    id = get_session(options_conn, "webauthn_ceremony")
    assert %AuthChallenge{purpose: :sign_in, user_id: nil} = Repo.get(AuthChallenge, id)
    refute Map.has_key?(options_conn.resp_cookies, "__Host-espalier_tx")

    assertion = SoftAuthenticator.assert(authenticator, options)
    conn = api_request(options_conn, :post, "/api/auth/passkey", assertion)
    assert json_response(conn, 200)["session"]["strength"] == "mfa"
    assert Repo.get(AuthChallenge, id) == nil
    assert get_session(conn, "webauthn_ceremony") == nil

    # The cookie from before the sign-in still names the consumed challenge.
    replay =
      options_conn
      |> next_request()
      |> put_req_header("x-csrf-token", options_conn |> get_req_header("x-csrf-token") |> hd())
      |> post("/api/auth/passkey", assertion)

    assert json_response(replay, 401) == %{"error" => "authentication_failed"}
  end

  test "a passkey of a user with an external identity serves only as second factor",
       %{conn: conn} do
    federated = user_fixture()
    external_identity_fixture(federated, provider_key: "test")
    {authenticator, _credential} = passkey_fixture(federated)

    {_conn, options} = passkey_options(conn)

    conn =
      api_request(
        conn,
        :post,
        "/api/auth/passkey",
        SoftAuthenticator.assert(authenticator, options)
      )

    assert json_response(conn, 401) == %{"error" => "authentication_failed"}

    conn = put_pending(api_conn(), federated, auth_methods: [:oidc], provider_key: "test")
    {conn, options} = passkey_options(conn, %{purpose: "second_factor"})
    assert [%{"id" => _}] = options["allowCredentials"]

    conn =
      api_request(conn, :post, "/api/auth/second-factor", %{
        passkey: SoftAuthenticator.assert(authenticator, options)
      })

    body = json_response(conn, 200)
    assert body["session"]["strength"] == "mfa"
    assert body["session"]["auth_methods"] == ["oidc", "passkey"]
    assert body["session"]["provider_key"] == "test"
  end

  test "with LOCAL_ACCOUNTS=false the local pathways answer 404",
       %{conn: conn, user: user, authenticator: authenticator} do
    put_setting(:local_accounts, false)

    for {path, body} <- [
          {"/api/auth/passkey/options", %{purpose: "sign_in"}},
          {"/api/auth/passkey/options", %{}},
          {"/api/auth/passkey",
           SoftAuthenticator.assert(authenticator, %{"challenge" => "AA", "rpId" => "localhost"})},
          {"/api/auth/recovery/start", %{email: user.email}},
          {"/api/auth/recovery/verify", %{token: "AA", recovery_code: "AAAA"}}
        ] do
      conn = api_request(api_conn(), :post, path, body)
      assert json_response(conn, 404) == %{"error" => "not_found"}, path
    end

    # Federated users with a local passkey keep the second factor.
    conn = put_pending(conn, user, auth_methods: [:oidc], provider_key: "test")
    {_conn, options} = passkey_options(conn, %{purpose: "second_factor"})
    assert options["allowCredentials"]
  end

  test "failed sign-in assertions count only per IP and never lock the owner",
       %{user: user, authenticator: authenticator} do
    for _ <- 1..60 do
      ip = unique_ip()
      {conn, options} = passkey_options(api_conn(), %{}, ip: ip)
      assertion = SoftAuthenticator.assert(authenticator, options, bad_signature: true)
      conn = api_request(conn, :post, "/api/auth/passkey", assertion, ip: ip)
      assert json_response(conn, 401) == %{"error" => "authentication_failed"}
    end

    assert Repo.get_by(FailureCounter, user_id: user.id, authenticator: :passkey) == nil
    assert FailureCounters.check(user, :passkey) == :ok

    {conn, options} = passkey_options(api_conn())

    conn =
      api_request(
        conn,
        :post,
        "/api/auth/passkey",
        SoftAuthenticator.assert(authenticator, options)
      )

    assert json_response(conn, 200)["session"]["auth_methods"] == ["passkey"]
  end

  test "options of the purposes second_factor and reauth need their state", %{
    conn: conn,
    user: user
  } do
    for purpose <- ["second_factor", "reauth"] do
      conn = api_request(conn, :post, "/api/auth/passkey/options", %{purpose: purpose})
      assert json_response(conn, 401) == %{"error" => "authentication_failed"}
    end

    conn = api_request(conn, :post, "/api/auth/passkey/options", %{purpose: "other"})
    assert json_response(conn, 400) == %{"error" => "bad_request"}

    conn = log_in_user(api_conn(), user)
    {conn, options} = passkey_options(conn, %{purpose: "reauth"})
    assert [_credential] = options["allowCredentials"]
    id = get_session(conn, "webauthn_ceremony")
    assert %AuthChallenge{purpose: :reauth} = row = Repo.get(AuthChallenge, id)
    assert row.user_id == user.id
  end

  test "a new options request replaces the running ceremony", %{conn: conn} do
    {conn, _options} = passkey_options(conn)
    first = get_session(conn, "webauthn_ceremony")
    {conn, _options} = passkey_options(conn)
    second = get_session(conn, "webauthn_ceremony")
    refute first == second
    assert Repo.get(AuthChallenge, first) == nil
    assert Repo.get(AuthChallenge, second)
  end
end
