defmodule EspalierWeb.Auth.LdapControllerTest do
  # POST /api/auth/ldap/:provider with the Mox client (task 0007, step 25).
  # The provider list and the rate limits are application settings, so the
  # module runs alone.
  use EspalierWeb.ConnCase, async: false

  import Espalier.LdapConnHelpers
  import Mox

  alias Espalier.Accounts
  alias Espalier.Accounts.{FailureCounters, User}
  alias Espalier.Repo

  setup :verify_on_exit!

  setup do
    %{config: put_ldap_provider()}
  end

  defp sign_in(conn, username, password \\ directory_password()) do
    api_request(conn, :post, "/api/auth/ldap/ldap", %{username: username, password: password})
  end

  defp identity_user(person) do
    user = user_fixture()

    external_identity_fixture(user, %{
      provider_key: "ldap",
      issuer: "ldap:ldap",
      subject: subject(person)
    })

    user
  end

  test "every authentication failure answers the identical 401 body", %{conn: conn} do
    known = person("known")
    disabled = person("disabled", %{"userAccountControl" => ["514"]})
    locked = person("locked")
    timeout = person("timeout")
    blocked = person("blocked")

    stub_people([known, disabled, locked, timeout, blocked],
      user_bind: fn dn, password ->
        cond do
          dn == dn(timeout) -> {:error, {:gen_tcp_error, :timeout}}
          password == directory_password() -> :ok
          true -> {:error, :invalidCredentials}
        end
      end
    )

    {:ok, _reservation} = FailureCounters.reserve_directory("ldap", subject(locked), 1, 30)
    blocked_user = identity_user(blocked)
    blocked_user |> Ecto.Changeset.change(status: :disabled) |> Repo.update!()

    bodies =
      for {username, password} <- [
            {"nobody", directory_password()},
            {"known", "a wrong password"},
            {"disabled", directory_password()},
            {"locked", directory_password()},
            {"timeout", directory_password()},
            {"blocked", directory_password()}
          ] do
        conn |> sign_in(username, password) |> response(401)
      end

    assert Enum.uniq(bodies) == [~s({"error":"invalid_credentials"})]
  end

  test "the sixth request within a minute for one username answers 429", %{conn: conn} do
    put_rate_limit(:ldap_account, {:timer.minutes(1), 5})
    stub_people([])

    for _ <- 1..5, do: assert(conn |> sign_in("rate-limited") |> response(401))

    conn = sign_in(conn, "Rate-Limited ")
    assert json_response(conn, 429) == %{"error" => "rate_limited"}
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) in 1..60
  end

  test "an unknown provider answers 404", %{conn: conn} do
    conn = api_request(conn, :post, "/api/auth/ldap/other", %{username: "a", password: "b"})
    assert json_response(conn, 404) == %{"error" => "unknown_provider"}
  end

  test "a request without the CSRF header answers 403 csrf", %{conn: conn} do
    conn = post(conn, "/api/auth/ldap/ldap", %{username: "a", password: "b"})
    assert json_response(conn, 403) == %{"error" => "csrf"}
  end

  test "missing credentials answer 400", %{conn: conn} do
    conn = api_request(conn, :post, "/api/auth/ldap/ldap", %{username: "a"})
    assert json_response(conn, 400) == %{"error" => "bad_request"}
  end

  test "a user with TOTP continues to the second factor", %{conn: conn} do
    ada = person("ada")
    stub_people([ada])
    user = identity_user(ada)
    {_factor, secret} = totp_fixture(user)

    conn = sign_in(conn, "ada")
    assert json_response(conn, 200) == %{"next" => "second_factor"}
    assert get_session(conn, :user_token) == nil

    body = conn |> next_request() |> get("/api/session") |> json_response(200)
    assert body["pending"]["next"] == "second_factor"

    conn = api_request(conn, :post, "/api/auth/second-factor", %{totp: totp_code(secret)})
    session = json_response(conn, 200)["session"]
    assert session["strength"] == "mfa"
    assert session["auth_methods"] == ["ldap", "totp"]
  end

  test "a user without a factor gets an enrollment session", %{conn: conn} do
    stub_people([person("bea")])

    conn = sign_in(conn, "bea")
    assert json_response(conn, 200) == %{"next" => "enroll_second_factor"}

    body = conn |> next_request() |> get("/api/session") |> json_response(200)
    assert body["session"]["strength"] == "enrollment"
    assert body["session"]["auth_methods"] == ["ldap"]

    conn = conn |> next_request() |> get("/api/me/sessions")
    assert json_response(conn, 403) == %{"error" => "enrollment_required"}
  end

  test "a directory address of another account answers 409 link_required", %{conn: conn} do
    user_fixture(email: "cleo@example.org")
    stub_people([person("cleo")])
    users = Repo.aggregate(User, :count)

    conn = sign_in(conn, "cleo")
    assert json_response(conn, 409) == %{"error" => "link_required"}
    assert Repo.aggregate(User, :count) == users
  end

  test "the session payload and GET /auth/providers list the provider", %{conn: conn} do
    entry = %{
      "key" => "ldap",
      "type" => "ldap",
      "kind" => "credentials",
      "label" => "Directory account",
      "start_url" => "/api/auth/ldap/ldap"
    }

    assert entry in (conn |> get("/api/session") |> json_response(200))["providers"]
    assert entry in (api_conn() |> get("/auth/providers") |> json_response(200))["providers"]
  end

  test "the roles of the mapped groups replace the idp_claim grants", %{conn: conn} do
    authors = Espalier.LdapFixtures.authors_dn()
    put_ldap_provider(role_map: [{:author, authors}])
    dora = person("dora")
    stub_people([dora], members: %{dn(dora) => [authors]})

    conn = sign_in(conn, "dora")
    assert json_response(conn, 200) == %{"next" => "enroll_second_factor"}

    user = Accounts.get_user_by_email("dora@example.org")
    assert Accounts.roles_for(user) == [:learner, :author]
  end
end
