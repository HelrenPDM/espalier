defmodule EspalierWeb.Auth.SecondFactorControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts.{FailureCounter, MailWorker, UserToken}
  alias Espalier.Repo
  alias Espalier.SoftAuthenticator

  setup do
    user = user_fixture()
    {authenticator, _credential} = passkey_fixture(user)
    {_factor, secret} = totp_fixture(user)
    codes = recovery_codes_fixture(user)
    %{user: user, authenticator: authenticator, secret: secret, codes: codes}
  end

  defp password_step(conn, user) do
    conn =
      api_request(conn, :post, "/api/auth/password", %{
        email: user.email,
        password: valid_user_password()
      })

    assert json_response(conn, 200) == %{"next" => "second_factor"}
    conn
  end

  defp second_factor(conn, body), do: api_request(conn, :post, "/api/auth/second-factor", body)

  defp passkey_assertion(conn, authenticator, purpose) do
    conn = api_request(conn, :post, "/api/auth/passkey/options", %{purpose: purpose})
    {conn, SoftAuthenticator.assert(authenticator, json_response(conn, 200))}
  end

  defp session_count(user) do
    Repo.aggregate(UserToken.user_sessions_query(user.id), :count)
  end

  defp assert_full_session(conn, user, methods) do
    body = json_response(conn, 200)
    assert body["session"]["strength"] == "mfa"
    assert body["session"]["auth_methods"] == methods
    refute body["csrf_token"] == conn |> get_req_header("x-csrf-token") |> hd()
    assert body["pending"] == nil
    token = get_session(conn, :user_token)
    assert %UserToken{strength: :mfa, user_id: user_id} = session_row(token)
    assert user_id == user.id
    assert session_count(user) == 1
    body
  end

  test "TOTP completes the password step", %{conn: conn, user: user, secret: secret} do
    conn = password_step(conn, user)
    assert session_count(user) == 0
    conn = second_factor(conn, %{totp: totp_code(secret)})
    assert_full_session(conn, user, ["password", "totp"])
  end

  test "a passkey completes the password step", %{
    conn: conn,
    user: user,
    authenticator: authenticator
  } do
    conn = password_step(conn, user)
    {conn, assertion} = passkey_assertion(conn, authenticator, "second_factor")
    conn = second_factor(conn, %{passkey: assertion})
    assert_full_session(conn, user, ["password", "passkey"])
  end

  test "a recovery code completes the password step and mails the user",
       %{conn: conn, user: user, codes: [code | _]} do
    conn = password_step(conn, user)
    conn = second_factor(conn, %{recovery_code: code})
    body = assert_full_session(conn, user, ["password", "recovery_code"])
    assert body["recovery_codes_remaining"] == 9

    assert_enqueued(
      worker: MailWorker,
      args: %{"kind" => "recovery_used", "user_id" => user.id, "count" => 9}
    )
  end

  test "the session rows keep the provider and the bytes of idp_sid_hash",
       %{user: user, secret: secret, authenticator: authenticator} do
    sid_hash = :crypto.strong_rand_bytes(32)

    conn =
      put_pending(api_conn(), user,
        auth_methods: [:oidc],
        provider_key: "test",
        idp_sid_hash: sid_hash
      )

    conn = second_factor(conn, %{totp: totp_code(secret)})
    assert json_response(conn, 200)["session"]["auth_methods"] == ["oidc", "totp"]
    first = get_session(conn, :user_token)
    assert session_row(first).provider_key == "test"
    assert raw_idp_sid_hash(first) == sid_hash

    {conn, assertion} = passkey_assertion(conn, authenticator, "reauth")
    conn = api_request(conn, :post, "/api/me/reauth", %{passkey: assertion})
    assert json_response(conn, 200)["recent_auth_until"]
    second = get_session(conn, :user_token)
    refute second == first
    assert session_row(first) == nil
    assert session_row(second).provider_key == "test"
    assert raw_idp_sid_hash(second) == sid_hash

    conn =
      api_request(conn, :put, "/api/me/password", %{
        current_password: valid_user_password(),
        password: "another plum orbit lantern 8213"
      })

    assert json_response(conn, 200)["session"]["strength"] == "mfa"
    third = get_session(conn, :user_token)
    refute third == second
    assert session_row(third).provider_key == "test"
    assert raw_idp_sid_hash(third) == sid_hash
  end

  test "a wrong code, a foreign passkey and a missing pending state answer the same",
       %{conn: conn, user: user} do
    other = user_fixture()
    {foreign, _credential} = passkey_fixture(other)

    conn = password_step(conn, user)
    wrong = second_factor(conn, %{totp: "000000"})

    {conn, assertion} = passkey_assertion(wrong, foreign, "second_factor")
    foreign_passkey = second_factor(conn, %{passkey: assertion})

    missing = second_factor(api_conn(), %{totp: "000000"})

    bodies = for conn <- [wrong, foreign_passkey, missing], do: json_response(conn, 401)
    assert Enum.uniq(bodies) == [%{"error" => "authentication_failed"}]

    # Failures count against the pending user only.
    assert Repo.get_by(FailureCounter, user_id: user.id, authenticator: :passkey).consecutive_failures ==
             1

    assert Repo.get_by(FailureCounter, user_id: other.id, authenticator: :passkey) == nil
  end

  test "the fifth failure clears the pending state", %{conn: conn, user: user, secret: secret} do
    conn = password_step(conn, user)

    conn =
      Enum.reduce(1..4, conn, fn _, conn ->
        conn = second_factor(conn, %{recovery_code: "AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AA"})
        assert json_response(conn, 401)
        conn
      end)

    assert get_session(conn, :pending_second_factor_failures) == 4
    assert get_session(conn, :pending_second_factor)

    conn = second_factor(conn, %{totp: "000000"})
    assert json_response(conn, 401) == %{"error" => "authentication_failed"}
    assert get_session(conn, :pending_second_factor) == nil
    assert get_session(conn, :pending_second_factor_failures) == nil

    conn = second_factor(conn, %{totp: totp_code(secret)})
    assert json_response(conn, 401) == %{"error" => "authentication_failed"}
  end

  test "a body without exactly one factor answers 400", %{conn: conn, user: user} do
    conn = password_step(conn, user)

    for body <- [%{}, %{totp: "123456", recovery_code: "x"}, %{totp: 123_456}] do
      assert json_response(second_factor(conn, body), 400) == %{"error" => "bad_request"}
    end
  end
end
