defmodule Espalier.Accounts.FailureCountersTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Accounts
  alias Espalier.Accounts.{FailureCounters, MailWorker}

  setup do
    %{user: user_fixture(), now: DateTime.utc_now(:second)}
  end

  defp fail(user, times, now) do
    for _ <- 1..times, do: FailureCounters.record_failure(user, :password, now)
    {:ok, counter} = FailureCounters.record_failure(user, :password, now)
    counter
  end

  test "four failures leave the authenticator open", %{user: user, now: now} do
    for _ <- 1..4, do: FailureCounters.record_failure(user, :password, now)
    assert FailureCounters.check(user, :password, now) == :ok
  end

  test "the fifth failure locks for 30 seconds, doubling, up to one hour", %{user: user, now: now} do
    counter = fail(user, 4, now)
    assert counter.consecutive_failures == 5
    assert DateTime.diff(counter.locked_until, now) == 30
    assert FailureCounters.check(user, :password, now) == {:locked, counter.locked_until}
    assert FailureCounters.check(user, :password, DateTime.add(now, 31)) == :ok

    later = DateTime.add(now, 31)
    {:ok, sixth} = FailureCounters.record_failure(user, :password, later)
    assert DateTime.diff(sixth.locked_until, later) == 60

    for _ <- 7..9, do: FailureCounters.record_failure(user, :password, later)
    {:ok, tenth} = FailureCounters.record_failure(user, :password, later)
    assert tenth.consecutive_failures == 10
    assert DateTime.diff(tenth.locked_until, later) == 960

    FailureCounters.record_failure(user, :password, later)
    {:ok, twelfth} = FailureCounters.record_failure(user, :password, later)
    assert DateTime.diff(twelfth.locked_until, later) == 3600
  end

  test "the fiftieth failure disables the authenticator", %{user: user, now: now} do
    counter = fail(user, 49, now)
    assert counter.consecutive_failures == 50
    assert counter.disabled_at
    assert FailureCounters.check(user, :password, DateTime.add(now, 7200)) == :disabled
    assert FailureCounters.check(user, :totp, now) == :ok
  end

  test "reaching 5 and 50 logs authn_login_fail_max and authn_login_lock", %{user: user, now: now} do
    ref = attach_security_events()
    fail(user, 49, now)
    assert_received {^ref, %{name: :authn_login_fail_max, count: 5}}
    assert_received {^ref, %{name: :authn_login_lock, count: 50}}
  end

  describe "authenticate_password/3" do
    test "a success after five failures resets the counter and enqueues failed_attempts",
         %{user: user, now: now} do
      for _ <- 1..5 do
        assert Accounts.authenticate_password(user.email, "wrong long password!!", %{now: now}) ==
                 {:error, :invalid_credentials}
      end

      later = DateTime.add(now, 31)
      ref = attach_security_events()

      assert {:ok, _user} =
               Accounts.authenticate_password(user.email, valid_user_password(), %{now: later})

      assert FailureCounters.reset(user, :password) == 0

      assert_enqueued(
        worker: MailWorker,
        args: %{"kind" => "failed_attempts", "user_id" => user.id, "count" => 5}
      )

      assert_received {^ref, %{name: :authn_login_successafterfail, count: 5}}
    end

    test "an attempt during a lock leaves the count unchanged", %{user: user, now: now} do
      for _ <- 1..5 do
        Accounts.authenticate_password(user.email, "wrong long password!!", %{now: now})
      end

      assert Accounts.authenticate_password(user.email, valid_user_password(), %{now: now}) ==
               {:error, :invalid_credentials}

      assert Repo.get_by!(Espalier.Accounts.FailureCounter, user_id: user.id).consecutive_failures ==
               5
    end
  end
end
