defmodule Espalier.Accounts.FactorsTest do
  # put_env of :admin_require_passkey changes the node.
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures

  alias Espalier.Accounts
  alias Espalier.Accounts.{Factors, FailureCounters, MailWorker, RoleGrant, Scope}

  setup do
    previous = Application.get_env(:espalier, :admin_require_passkey)
    on_exit(fn -> Application.put_env(:espalier, :admin_require_passkey, previous) end)
    Application.put_env(:espalier, :admin_require_passkey, true)
    :ok
  end

  defp admin(user) do
    %RoleGrant{}
    |> RoleGrant.changeset(%{role: :admin, source: :manual}, Scope.for_user(user))
    |> Repo.insert!()

    user
  end

  describe "satisfied?/1 and enrolled?/1" do
    test "a passkey alone satisfies the rule" do
      user = user_fixture(password: nil)
      refute Factors.satisfied?(user)
      refute Accounts.enrolled?(user)
      passkey_fixture(user)
      assert Factors.satisfied?(user)
      assert Factors.holds_passkey?(user)
      assert Accounts.enrolled?(user)
    end

    test "TOTP counts together with a password or an external identity" do
      without = user_fixture(password: nil)
      totp_fixture(without)
      assert Accounts.enrolled?(without)
      refute Factors.satisfied?(without)

      external_identity_fixture(without)
      assert Factors.satisfied?(without)

      with_password = user_fixture()
      totp_fixture(with_password)
      assert Factors.satisfied?(with_password)
      refute Factors.holds_passkey?(with_password)
    end

    test "an unconfirmed TOTP factor counts for nothing" do
      user = user_fixture()
      totp_fixture(user, enabled_at: nil)
      refute Accounts.enrolled?(user)
      refute Factors.satisfied?(user)
    end
  end

  describe "removable?/2" do
    test "the last factor stays" do
      user = user_fixture()
      {_authenticator, credential} = passkey_fixture(user)
      assert Factors.removable?(user, {:passkey, credential}) == {:error, :last_factor}

      totp_fixture(user)
      assert Factors.removable?(user, {:passkey, credential}) == :ok
      assert Factors.removable?(user, :totp) == :ok

      only_totp = user_fixture()
      totp_fixture(only_totp)
      assert Factors.removable?(only_totp, :totp) == {:error, :last_factor}
    end

    test "an admin keeps a passkey while ADMIN_REQUIRE_PASSKEY is true" do
      user = admin(user_fixture())
      totp_fixture(user)
      {_authenticator, first} = passkey_fixture(user)
      assert Factors.removable?(user, {:passkey, first}) == {:error, :admin_passkey_required}

      {_authenticator, _second} = passkey_fixture(user)
      assert Factors.removable?(user, {:passkey, first}) == :ok

      Application.put_env(:espalier, :admin_require_passkey, false)
      assert Factors.removable?(user, {:passkey, first}) == :ok
    end

    test "admin_passkey_required?/2 holds for an admin without a passkey" do
      user = admin(user_fixture())
      assert Factors.admin_passkey_required?(user, [:learner, :admin])
      refute Factors.admin_passkey_required?(user, [:learner])
      passkey_fixture(user)
      refute Factors.admin_passkey_required?(user, [:learner, :admin])
    end
  end

  describe "verify/5" do
    setup do
      %{user: user_fixture()}
    end

    test "a success after five failures resets the counter and mails the user", %{user: user} do
      ref = attach_security_events()

      for _ <- 1..5 do
        assert Factors.verify(user, :totp, fn -> {:error, :invalid_code} end) ==
                 {:error, :invalid_code}
      end

      Repo.update_all(Espalier.Accounts.FailureCounter, set: [locked_until: nil])
      assert {:ok, nil} = Factors.verify(user, :totp, fn -> :ok end, %{ip: {192, 0, 2, 1}})
      assert FailureCounters.check(user, :totp) == :ok
      assert FailureCounters.reset(user, :totp) == 0

      assert_enqueued(
        worker: MailWorker,
        args: %{
          "kind" => "failed_attempts",
          "user_id" => user.id,
          "count" => 5,
          "factor" => "totp"
        }
      )

      assert_received {^ref, %{name: :authn_login_fail, factor: "totp", reason: "invalid_code"}}
      assert_received {^ref, %{name: :authn_login_successafterfail, factor: "totp", count: 5}}
      assert_received {^ref, %{name: :authn_login_success, factor: "totp", ip: "192.0.2.1"}}
    end

    test "a locked counter fails without running the verification or counting", %{user: user} do
      now = DateTime.utc_now()
      for _ <- 1..5, do: FailureCounters.record_failure(user, :recovery_code, now)
      ref = attach_security_events()

      assert Factors.verify(user, :recovery_code, fn -> raise "not called" end) ==
               {:error, :counter_locked}

      assert_received {^ref, %{name: :authn_login_fail, reason: "counter_locked"}}

      assert Repo.one(from c in Espalier.Accounts.FailureCounter, select: c.consecutive_failures) ==
               5
    end

    test "the fiftieth failure disables the factor and mails the user", %{user: user} do
      now = DateTime.utc_now()
      for _ <- 1..49, do: FailureCounters.record_failure(user, :passkey, now)
      Repo.update_all(Espalier.Accounts.FailureCounter, set: [locked_until: nil])

      assert Factors.verify(user, :passkey, fn -> {:error, :invalid_signature} end) ==
               {:error, :invalid_signature}

      assert FailureCounters.check(user, :passkey) == :disabled

      assert_enqueued(
        worker: MailWorker,
        args: %{"kind" => "authenticator_disabled", "user_id" => user.id, "factor" => "passkey"}
      )

      assert Factors.verify(user, :passkey, fn -> :ok end) == {:error, :counter_disabled}
      assert {:ok, nil} = Factors.verify(user, :passkey, fn -> :ok end, %{}, allow_disabled: true)
    end

    test "clear_all/1 re-enables every factor of the user", %{user: user} do
      now = DateTime.utc_now()
      for _ <- 1..50, do: FailureCounters.record_failure(user, :totp, now)
      for _ <- 1..6, do: FailureCounters.record_failure(user, :password, now)
      assert FailureCounters.check(user, :totp) == :disabled

      assert FailureCounters.clear_all(user) == 2
      assert FailureCounters.check(user, :totp, now) == :ok
      assert FailureCounters.check(user, :password, now) == :ok
    end
  end

  test "summary/1 lists the factors without secrets" do
    user = user_fixture()
    {_authenticator, credential} = passkey_fixture(user)
    {_factor, secret} = totp_fixture(user)
    codes = recovery_codes_fixture(user)

    summary = Factors.summary(user)
    assert [%{id: id, transports: ["internal"]}] = summary.passkeys
    assert id == credential.id
    assert summary.totp.enabled
    assert summary.recovery_codes.remaining == 10
    assert summary.password_set
    refute summary.admin_passkey_required

    dumped = inspect(summary)
    refute dumped =~ Base.encode32(secret, padding: false)
    for code <- codes, do: refute(dumped =~ code)
  end
end
