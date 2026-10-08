# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule EspalierWeb.UserAuthTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts
  alias Espalier.Accounts.{Scope, UserToken}
  alias EspalierWeb.UserAuth

  setup do
    %{user: user_fixture()}
  end

  # A conn with the session of `token`, the way the :api pipeline fetches it.
  defp session_conn(token) do
    build_conn()
    |> Map.put(:secret_key_base, EspalierWeb.Endpoint.config(:secret_key_base))
    |> init_test_session(if token, do: %{user_token: token}, else: %{})
  end

  defp scoped_conn(token),
    do: token |> session_conn() |> UserAuth.fetch_current_scope_for_user([])

  describe "fetch_current_scope_for_user/2" do
    test "assigns the user, the session and the roles", %{user: user} do
      {token, session} = session_fixture(user)
      conn = scoped_conn(token)

      assert %Scope{user: %{id: id}, roles: [:learner], session: %{id: session_id}} =
               conn.assigns.current_scope

      assert id == user.id
      assert session_id == session.id
    end

    test "drops an expired token from the session", %{user: user} do
      {token, _session} = session_fixture(user)
      override_session(token, last_seen_at: DateTime.add(DateTime.utc_now(:second), -61, :minute))

      conn = scoped_conn(token)
      assert conn.assigns.current_scope == nil
      assert get_session(conn, :user_token) == nil
      assert session_row(token) == nil
    end

    test "assigns nil without a token" do
      assert scoped_conn(nil).assigns.current_scope == nil
    end
  end

  describe "require_enrollment_session/2" do
    for {strength, methods} <- [
          enrollment: [:email_code],
          recovery: [:recovery_code, :email_code],
          mfa: [:password, :totp]
        ] do
      test "passes #{strength}", %{user: user} do
        {token, _} =
          session_fixture(user, strength: unquote(strength), auth_methods: unquote(methods))

        conn = token |> scoped_conn() |> UserAuth.require_enrollment_session([])
        refute conn.halted
      end
    end

    test "answers 401 without a session" do
      conn = nil |> scoped_conn() |> UserAuth.require_enrollment_session([])
      assert conn.halted
      assert json_response(conn, 401) == %{"error" => "unauthenticated"}
    end

    test "answers 403 forbidden for a demo session and logs authz_fail", %{user: user} do
      {token, _} = session_fixture(user, strength: :demo, auth_methods: [:demo])
      ref = attach_security_events()

      conn = token |> scoped_conn() |> UserAuth.require_enrollment_session([])
      assert conn.halted
      assert json_response(conn, 403) == %{"error" => "forbidden"}
      assert_received {^ref, %{name: :authz_fail, reason: "forbidden"}}
    end
  end

  describe "require_authenticated_user/2" do
    test "passes mfa and demo sessions", %{user: user} do
      {mfa, _} = session_fixture(user)
      {demo, _} = session_fixture(user, strength: :demo, auth_methods: [:demo])

      for token <- [mfa, demo] do
        refute (token |> scoped_conn() |> UserAuth.require_authenticated_user([])).halted
      end
    end

    test "answers 403 enrollment_required for enrollment and recovery sessions", %{user: user} do
      {token, _} = session_fixture(user, strength: :enrollment, auth_methods: [:email_code])
      conn = token |> scoped_conn() |> UserAuth.require_authenticated_user([])
      assert json_response(conn, 403) == %{"error" => "enrollment_required"}
    end
  end

  describe "require_recent_auth/2" do
    test "needs a second factor within 10 minutes", %{user: user} do
      {fresh, _} = session_fixture(user)

      {stale, _} =
        session_fixture(user, mfa_at: DateTime.add(DateTime.utc_now(:second), -11, :minute))

      refute (fresh |> scoped_conn() |> UserAuth.require_recent_auth([])).halted

      conn = stale |> scoped_conn() |> UserAuth.require_recent_auth([])
      assert json_response(conn, 403) == %{"error" => "reauth_required"}
    end
  end

  describe "require_role/2" do
    test "answers 403 forbidden without the role and passes with it", %{user: user} do
      {token, _} = session_fixture(user)
      ref = attach_security_events()

      conn = token |> scoped_conn() |> UserAuth.require_role(:admin)
      assert json_response(conn, 403) == %{"error" => "forbidden"}
      assert_received {^ref, %{name: :authz_fail}}

      {:ok, _grant} = Accounts.grant_role(Scope.system(), user, :admin)
      {token, _} = session_fixture(user)
      refute (token |> scoped_conn() |> UserAuth.require_role(:admin)).halted
    end

    test "the role pipelines check the role on the server", %{user: user} do
      {token, _} = session_fixture(user)

      for role <- [:facilitator, :author, :registrar, :analyst, :admin] do
        conn =
          token
          |> scoped_conn()
          |> UserAuth.require_authenticated_user([])
          |> UserAuth.require_role(role)

        assert conn.halted
        assert conn.status == 403
      end
    end
  end

  describe "log_in_user/3" do
    test "creates a session with the device summary and deletes the previous row", %{user: user} do
      {previous, _} = session_fixture(user)

      conn =
        previous
        |> session_conn()
        |> put_req_header("user-agent", "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Firefox/131.0")
        |> UserAuth.log_in_user(user, auth_methods: [:password, :totp], strength: :mfa)

      token = get_session(conn, :user_token)
      assert token != previous
      assert %UserToken{device_summary: "Firefox on Linux"} = session_row(token)
      assert session_row(previous) == nil
      assert Accounts.get_user!(user.id).last_login_at
    end
  end

  describe "pending second-factor state" do
    test "a password sign-in in a conn that holds a session deletes that row", %{user: user} do
      {token, _} = session_fixture(user)

      conn =
        token
        |> session_conn()
        |> UserAuth.put_pending_second_factor(user, auth_methods: [:password])

      assert get_session(conn, :user_token) == nil
      assert session_row(token) == nil

      assert {:ok, %{auth_methods: [:password], user: %{id: id}}} =
               UserAuth.fetch_pending_second_factor(conn)

      assert id == user.id
    end

    test "expires after five minutes", %{user: user} do
      conn =
        nil
        |> session_conn()
        |> UserAuth.put_pending_second_factor(user, auth_methods: [:password])

      pending = get_session(conn, :pending_second_factor)

      expired =
        put_session(conn, :pending_second_factor, %{
          pending
          | "expires_at" => System.os_time(:second) - 1
        })

      assert UserAuth.fetch_pending_second_factor(expired) == :error
      assert (pending["expires_at"] - System.os_time(:second)) in 299..300

      conn = UserAuth.fetch_current_scope_for_user(expired, [])
      assert get_session(conn, :pending_second_factor) == nil
    end

    test "idp_sid_hash keeps its bytes through the pending state and log_in_user/3", %{user: user} do
      sid_hash = UserToken.hash_idp_sid("sid-1")

      conn =
        nil
        |> session_conn()
        |> UserAuth.put_pending_second_factor(user,
          auth_methods: [:oidc],
          provider_key: "x",
          idp_sid_hash: sid_hash
        )

      assert {:ok, pending} = UserAuth.fetch_pending_second_factor(conn)
      assert pending.idp_sid_hash == sid_hash

      conn =
        UserAuth.log_in_user(conn, pending.user,
          auth_methods: pending.auth_methods ++ [:totp],
          strength: :mfa,
          mfa_at: DateTime.utc_now(:second),
          provider_key: pending.provider_key,
          idp_sid_hash: pending.idp_sid_hash
        )

      assert [row] = sessions_with_idp_sid("x", sid_hash)

      assert row.token_hash == UserToken.hash(get_session(conn, :user_token))
      assert get_session(conn, :pending_second_factor) == nil
    end
  end

  describe "log_out_user/1" do
    test "deletes the row and clears the session", %{user: user} do
      {token, _} = session_fixture(user)
      conn = token |> scoped_conn() |> UserAuth.log_out_user()
      assert get_session(conn, :user_token) == nil
      assert session_row(token) == nil
    end
  end
end
