defmodule Espalier.Accounts.SessionsTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Accounts
  alias Espalier.Accounts.{PurgeExpiredTokensWorker, UserToken}
  alias Espalier.Hashed.HMAC

  setup do
    %{user: user_fixture()}
  end

  describe "create_session/2" do
    test "stores the SHA-256 hash of a 32-byte token", %{user: user} do
      {token, session} = session_fixture(user)
      assert byte_size(token) == 32
      assert session.token_hash == :crypto.hash(:sha256, token)
      assert session.token_hash != token
      assert session.context == :session
      assert DateTime.diff(session.expires_at, session.authenticated_at, :hour) == 24
    end

    # Rows of 0004 step 45 and of 0005 step 12: {strength, methods, attrs}.
    @accepted [
      {:mfa, [:password, :totp], []},
      {:mfa, [:oidc, :totp], []},
      {:mfa, [:ldap, :totp], []},
      {:mfa, [:passkey], []},
      {:mfa, [:oidc, :idp_mfa], []},
      {:enrollment, [:email_code], []},
      {:demo, [:demo], []},
      {:recovery, [:recovery_code, :email_code], []},
      {:mfa, [:password, :recovery_code], []},
      {:mfa, [:oidc, :recovery_code], []},
      {:mfa, [:ldap, :recovery_code], []},
      {:mfa, [:email_code, :totp], [completes: :enrollment]},
      {:mfa, [:recovery_code, :email_code, :totp], [completes: :recovery]},
      {:mfa, [:email_code, :passkey], []},
      {:mfa, [:recovery_code, :email_code, :passkey], []},
      {:enrollment, [:oidc], []},
      {:enrollment, [:ldap], []}
    ]

    @rejected [
      {:mfa, [:password], []},
      {:mfa, [:email_code], []},
      {:enrollment, [:password], []},
      {:demo, [:password], []},
      {:mfa, [:email_code, :totp], []},
      {:mfa, [:email_code, :totp], [completes: :recovery]},
      {:mfa, [:recovery_code, :email_code, :totp], []},
      {:mfa, [:recovery_code, :email_code, :totp], [completes: :enrollment]},
      {:mfa, [:recovery_code], []},
      {:mfa, [:recovery_code, :email_code], []},
      {:enrollment, [:oidc, :totp], []},
      {:enrollment, [:passkey], []}
    ]

    for {strength, methods, attrs} <- @accepted do
      test "accepts #{inspect(methods)} with #{strength} #{inspect(attrs)}", %{user: user} do
        assert {_token, session} =
                 Accounts.create_session(
                   user,
                   [strength: unquote(strength), auth_methods: unquote(methods)] ++
                     unquote(attrs)
                 )

        assert session.strength == unquote(strength)
        assert session.auth_methods == unquote(methods)
      end
    end

    for {strength, methods, attrs} <- @rejected do
      test "raises for #{inspect(methods)} with #{strength} #{inspect(attrs)}", %{user: user} do
        assert_raise ArgumentError, fn ->
          Accounts.create_session(
            user,
            [strength: unquote(strength), auth_methods: unquote(methods)] ++ unquote(attrs)
          )
        end
      end
    end

    test "enrollment and recovery sessions live 30 minutes", %{user: user} do
      {_token, session} =
        Accounts.create_session(user, strength: :enrollment, auth_methods: [:email_code])

      assert DateTime.diff(session.expires_at, session.authenticated_at, :minute) == 30
    end

    test "the sixth session deletes the oldest", %{user: user} do
      start = DateTime.add(DateTime.utc_now(), -30, :minute)

      tokens =
        for n <- 0..5 do
          {token, _session} = session_fixture(user, now: DateTime.add(start, n, :minute))
          token
        end

      [oldest | rest] = tokens
      assert Accounts.get_session_by_token(oldest) == {:error, :not_found}
      for token <- rest, do: assert({:ok, _user, _session} = Accounts.get_session_by_token(token))
      assert length(Accounts.list_sessions(user)) == 5
    end

    test "deletes the replaced row of another user", %{user: user} do
      {token, _session} = session_fixture(user_fixture())
      {_new, _session} = session_fixture(user, replaces: token)
      assert Accounts.get_session_by_token(token) == {:error, :not_found}
    end
  end

  describe "get_session_by_token/2" do
    test "returns the user and the session", %{user: user} do
      {token, session} = session_fixture(user)
      assert {:ok, found, ^session} = Accounts.get_session_by_token(token)
      assert found.id == user.id
    end

    test "expires after 60 idle minutes, deletes the row and logs it", %{user: user} do
      {token, session} = session_fixture(user)
      ref = attach_security_events()

      now = DateTime.add(session.last_seen_at, 59, :minute)
      assert {:ok, _user, _session} = Accounts.get_session_by_token(token, now)

      now = DateTime.add(session.last_seen_at, 60, :minute)
      assert Accounts.get_session_by_token(token, now) == {:error, :expired}
      assert_received {^ref, %{name: :session_expired, reason: "idle", session_id: id}}
      assert id == session.id
      assert Accounts.get_session_by_token(token) == {:error, :not_found}
    end

    test "expires after 24 hours of absolute lifetime", %{user: user} do
      {token, session} = session_fixture(user)
      ref = attach_security_events()

      # Activity every minute keeps the idle timeout away.
      override_session(token, last_seen_at: DateTime.add(session.authenticated_at, 24, :hour))
      now = DateTime.add(session.authenticated_at, 24, :hour)

      assert Accounts.get_session_by_token(token, now) == {:error, :expired}
      assert_received {^ref, %{name: :session_expired, reason: "absolute"}}
      assert session_row(token) == nil
    end

    test "returns not_found for a disabled user", %{user: user} do
      {token, _session} = session_fixture(user)
      user |> Ecto.Changeset.change(status: :disabled) |> Repo.update!()
      assert Accounts.get_session_by_token(token) == {:error, :not_found}
    end
  end

  test "touch_session/2 writes last_seen_at only when it is older than a minute", %{user: user} do
    {token, session} = session_fixture(user)

    assert Accounts.touch_session(session, DateTime.add(session.last_seen_at, 30, :second)) ==
             session

    later = DateTime.add(session.last_seen_at, 2, :minute)

    assert Accounts.touch_session(session, later).last_seen_at ==
             DateTime.truncate(later, :second)

    assert session_row(token).last_seen_at == DateTime.truncate(later, :second)
  end

  describe "reissue_session/2" do
    test "deletes the previous row, keeps expires_at and the device, applies changes",
         %{user: user} do
      {token, session} = session_fixture(user, device_summary: "Firefox on Linux")
      mfa_at = DateTime.add(session.authenticated_at, 5, :minute)

      assert {:ok, new_token} = Accounts.reissue_session(token, %{mfa_at: mfa_at})
      assert Accounts.get_session_by_token(token) == {:error, :not_found}
      assert {:ok, _user, reissued} = Accounts.get_session_by_token(new_token)
      assert reissued.expires_at == session.expires_at
      assert reissued.device_summary == "Firefox on Linux"
      assert reissued.mfa_at == mfa_at
      assert reissued.id != session.id
    end

    test "raises on a row whose sent_to_hash holds a value", %{user: user} do
      {token, _session} = session_fixture(user)

      Repo.update_all(from(t in UserToken, where: t.token_hash == ^UserToken.hash(token)),
        set: [sent_to_hash: HMAC.hash(user.email)]
      )

      assert_raise ArgumentError, fn -> Accounts.reissue_session(token) end
    end
  end

  describe "idp_sid_hash" do
    test "hash_idp_sid/1 is HMAC-SHA256 under the HMAC secret" do
      secret = Base.decode64!(Application.fetch_env!(:espalier, Espalier.Hashed.HMAC)[:secret])
      assert UserToken.hash_idp_sid("sid-1") == :crypto.mac(:hmac, :sha256, secret, "sid-1")
      assert UserToken.hash_idp_sid(nil) == nil
    end

    test "reissue_session/2 keeps the bytes", %{user: user} do
      sid_hash = UserToken.hash_idp_sid("sid-1")
      {token, _session} = session_fixture(user, idp_sid_hash: sid_hash, provider_key: "x")
      assert {:ok, new_token} = Accounts.reissue_session(token)

      assert [row] = sessions_with_idp_sid("x", sid_hash)

      assert row.token_hash == UserToken.hash(new_token)
    end
  end

  test "list_sessions/1 and delete_session/2 work on the user's own rows", %{user: user} do
    {_token, session} = session_fixture(user)
    {_other_token, other_session} = session_fixture(user_fixture())

    assert [%{id: id}] = Accounts.list_sessions(user)
    assert id == session.id
    assert Accounts.delete_session(user, other_session.id) == {:error, :not_found}
    assert Accounts.delete_session(user, "not-a-uuid") == {:error, :not_found}
    assert Accounts.delete_session(user, session.id) == :ok
    assert Accounts.list_sessions(user) == []
  end

  test "the purge worker removes expired and idle rows and keeps live ones", %{user: user} do
    {live, _} = session_fixture(user)
    {expired, _} = session_fixture(user)
    {idle, _} = session_fixture(user)
    {_invite, invite_row} = email_token_fixture(user, :invite)

    past = DateTime.add(DateTime.utc_now(:second), -1, :minute)
    override_session(expired, expires_at: past)
    override_session(idle, last_seen_at: DateTime.add(DateTime.utc_now(:second), -61, :minute))
    Repo.update_all(from(t in UserToken, where: t.id == ^invite_row.id), set: [expires_at: past])

    assert :ok = perform_job(PurgeExpiredTokensWorker, %{})
    assert Repo.all(from t in UserToken, select: t.token_hash) == [UserToken.hash(live)]
  end
end
