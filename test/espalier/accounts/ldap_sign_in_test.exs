defmodule Espalier.Accounts.LdapSignInTest do
  # The directory sign-in service with the Mox client (task 0007, step 24).
  # The rate-limit cases set real buckets and the floor cases change the
  # failure floor, so the module runs alone.
  use Espalier.DataCase, async: false

  import ExUnit.CaptureLog
  import Espalier.AccountsFixtures
  import Espalier.LdapFixtures
  import Mox

  alias Espalier.Accounts
  alias Espalier.Accounts.{FailureCounter, FailureCounters, LdapSignIn, Scope}
  alias Espalier.Audit.AuditEvent
  alias Espalier.Identity.Ldap.ClientMock
  alias EspalierWeb.ConnCase

  # Mox and the SQL sandbox find the test process through $callers, which
  # Task and Task.Supervisor set.
  setup :verify_on_exit!

  @password "correct horse battery"
  @upn "jdoe@example.org"

  setup do
    # One provider key per test keeps the per-provider buckets apart.
    config = ldap_config(key: "ldap#{System.unique_integer([:positive])}", role_map: [])
    people = %{"jdoe" => {ad_dn(), ad_attrs()}}
    %{config: config, people: people, meta: %{ip: ConnCase.unique_ip()}}
  end

  defp stub(people, opts \\ []) do
    stub_directory(people, %{ad_dn() => @password}, Keyword.put_new(opts, :notify, self()))
  end

  defp counter_row(config) do
    Repo.one(
      from c in FailureCounter,
        where: c.authenticator == :ldap and c.provider_key == ^config.key
    )
  end

  defp events(ref, name) do
    Stream.repeatedly(fn ->
      receive do
        {^ref, %{name: ^name} = metadata} -> metadata
        {^ref, _other} -> :skip
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(& &1)
    |> Enum.reject(&(&1 == :skip))
  end

  defp set_floor(ms) do
    previous = Application.get_env(:espalier, LdapSignIn)
    Application.put_env(:espalier, LdapSignIn, failure_floor_ms: ms)
    on_exit(fn -> Application.put_env(:espalier, LdapSignIn, previous) end)
  end

  test "the sixth attempt for one name within a minute is rate limited without a connection",
       %{config: config, meta: meta} do
    ConnCase.put_rate_limit(:ldap_account, {:timer.minutes(1), 5})
    opens = :counters.new(1, [])

    stub(%{})

    stub(ClientMock, :open, fn _hosts, _opts ->
      :counters.add(opens, 1, 1) && {:ok, make_ref()}
    end)

    for _ <- 1..5 do
      assert LdapSignIn.sign_in(config, "Nobody ", @password, meta) ==
               {:error, :invalid_credentials}
    end

    assert :counters.get(opens, 1) == 5
    assert {:error, :rate_limited, ms} = LdapSignIn.sign_in(config, "nobody", @password, meta)
    assert ms > 0
    assert :counters.get(opens, 1) == 5
  end

  test "the subject bucket counts sAMAccountName and userPrincipalName together",
       %{config: config, people: people, meta: meta} do
    ConnCase.put_rate_limit(:ldap_subject, {:timer.minutes(1), 5})
    stub(people)
    ref = attach_security_events()

    for login <- ["jdoe", "jdoe", "jdoe", @upn, @upn] do
      assert {:ok, _user} = LdapSignIn.sign_in(config, login, @password, meta)
      assert_received {:user_bind, _dn}
    end

    assert LdapSignIn.sign_in(config, @upn, @password, meta) == {:error, :invalid_credentials}
    refute_received {:user_bind, _dn}

    assert [%{reason: "ldap_subject", provider: provider, factor: "ldap"}] =
             events(ref, :excess_rate_limit_exceeded)

    assert provider == config.key
  end

  test "three wrong passwords lock the account for lock_minutes",
       %{config: config, people: people, meta: meta} do
    stub(people)
    ref = attach_security_events()

    for _ <- 1..3 do
      assert LdapSignIn.sign_in(config, "jdoe", "wrong", meta) == {:error, :invalid_credentials}
    end

    row = counter_row(config)
    assert row.consecutive_failures == 3
    assert row.user_id == nil
    assert_in_delta DateTime.diff(row.locked_until, DateTime.utc_now(), :minute), 30, 1
    assert [%{count: 3}] = events(ref, :authn_login_fail_max)

    for _ <- 1..3, do: assert_received({:user_bind, _dn})
    assert LdapSignIn.sign_in(config, "jdoe", @password, meta) == {:error, :invalid_credentials}
    refute_received {:user_bind, _dn}
  end

  test "an expired lock lets one attempt through and sets a new lock",
       %{config: config, people: people, meta: meta} do
    stub(people)
    for _ <- 1..3, do: LdapSignIn.sign_in(config, "jdoe", "wrong", meta)
    for _ <- 1..3, do: assert_received({:user_bind, _dn})

    Repo.update_all(from(c in FailureCounter, where: c.provider_key == ^config.key),
      set: [locked_until: DateTime.add(DateTime.utc_now(:second), -60)]
    )

    assert LdapSignIn.sign_in(config, "jdoe", "wrong", meta) == {:error, :invalid_credentials}
    assert_received {:user_bind, _dn}

    row = counter_row(config)
    assert row.consecutive_failures == 4
    assert DateTime.after?(row.locked_until, DateTime.utc_now())

    assert LdapSignIn.sign_in(config, "jdoe", "wrong", meta) == {:error, :invalid_credentials}
    refute_received {:user_bind, _dn}
  end

  test "the fiftieth failure disables the pathway until an admin reset",
       %{config: config, people: people, meta: meta} do
    stub(people)
    LdapSignIn.sign_in(config, "jdoe", "wrong", meta)
    assert_received {:user_bind, _dn}

    Repo.update_all(from(c in FailureCounter, where: c.provider_key == ^config.key),
      set: [consecutive_failures: 49, locked_until: DateTime.add(DateTime.utc_now(:second), -60)]
    )

    ref = attach_security_events()
    assert LdapSignIn.sign_in(config, "jdoe", "wrong", meta) == {:error, :invalid_credentials}
    assert_received {:user_bind, _dn}
    assert counter_row(config).disabled_at
    assert [%{count: 50}] = events(ref, :authn_login_lock)

    Repo.update_all(from(c in FailureCounter, where: c.provider_key == ^config.key),
      set: [locked_until: DateTime.add(DateTime.utc_now(:second), -60)]
    )

    assert LdapSignIn.sign_in(config, "jdoe", @password, meta) == {:error, :invalid_credentials}
    refute_received {:user_bind, _dn}

    learner = Scope.for_user(user_fixture())

    assert FailureCounters.reset_directory(learner, config.key, guid_uuid()) ==
             {:error, :forbidden}

    assert counter_row(config)

    assert FailureCounters.reset_directory(Scope.system(), config.key, guid_uuid()) == :ok
    assert counter_row(config) == nil

    assert [%AuditEvent{details: details}] =
             Repo.all(from e in AuditEvent, where: e.action == "failure_counter.reset")

    assert details["provider_key"] == config.key

    assert FailureCounters.reset_directory(Scope.system(), config.key, guid_uuid()) ==
             {:error, :not_found}
  end

  test "reset_directory_for_user/2 deletes the counter of the user's directory identity",
       %{config: config, people: people, meta: meta} do
    stub(people)
    assert {:ok, user} = LdapSignIn.sign_in(config, "jdoe", @password, meta)
    LdapSignIn.sign_in(config, "jdoe", "wrong", meta)
    assert counter_row(config).consecutive_failures == 1

    assert FailureCounters.reset_directory_for_user(Scope.for_user(user), user) ==
             {:error, :forbidden}

    assert FailureCounters.reset_directory_for_user(Scope.system(), user) == {:ok, 1}
    assert counter_row(config) == nil
  end

  test "directory errors after the reservation leave the count unchanged",
       %{config: config, people: people, meta: meta} do
    stub(people)
    LdapSignIn.sign_in(config, "jdoe", "wrong", meta)
    assert counter_row(config).consecutive_failures == 1

    for result <- [{:error, {:gen_tcp_error, :timeout}}, {:error, :unwillingToPerform}] do
      stub(people, user_bind: fn _dn, _password -> result end)
      assert LdapSignIn.sign_in(config, "jdoe", @password, meta) == {:error, :invalid_credentials}
      assert counter_row(config).consecutive_failures == 1
      assert counter_row(config).locked_until == nil
    end

    # Connection 2 cannot open: the first open serves the lookup.
    stub(people)
    opens = :counters.new(1, [])

    stub(ClientMock, :open, fn _hosts, _opts ->
      :counters.add(opens, 1, 1)

      if :counters.get(opens, 1) == 1,
        do: {:ok, make_ref()},
        else: {:error, ~c"connect failed"}
    end)

    assert LdapSignIn.sign_in(config, "jdoe", @password, meta) == {:error, :invalid_credentials}
    assert counter_row(config).consecutive_failures == 1
  end

  test "a released reservation restores the lock it set",
       %{config: config, people: people, meta: meta} do
    stub(people)
    for _ <- 1..2, do: LdapSignIn.sign_in(config, "jdoe", "wrong", meta)

    stub(people, user_bind: fn _dn, _password -> {:error, {:gen_tcp_error, :timeout}} end)
    assert LdapSignIn.sign_in(config, "jdoe", @password, meta) == {:error, :invalid_credentials}

    row = counter_row(config)
    assert row.consecutive_failures == 2
    assert row.locked_until == nil
  end

  test "five concurrent wrong passwords cause at most three user binds",
       %{config: config, people: people, meta: meta} do
    binds = :counters.new(1, [])
    stub(people, counter: binds, notify: nil)

    results =
      1..5
      |> Task.async_stream(fn _ -> LdapSignIn.sign_in(config, "jdoe", "wrong", meta) end,
        max_concurrency: 5,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &(&1 == {:error, :invalid_credentials}))
    assert :counters.get(binds, 1) <= 3
    assert counter_row(config).consecutive_failures == 3
  end

  test "a success after two failures deletes the row",
       %{config: config, people: people, meta: meta} do
    stub(people)
    for _ <- 1..2, do: LdapSignIn.sign_in(config, "jdoe", "wrong", meta)
    assert counter_row(config).consecutive_failures == 2

    assert {:ok, user} = LdapSignIn.sign_in(config, "jdoe", @password, meta)
    assert counter_row(config) == nil
    assert user.display_name == "Jo Doe"
  end

  test "an unknown user and a wrong password take at least the floor and answer the same",
       %{config: config, people: people, meta: meta} do
    set_floor(200)
    stub(people)

    {unknown_us, unknown} =
      :timer.tc(fn -> LdapSignIn.sign_in(config, "nobody", @password, meta) end)

    {wrong_us, wrong} = :timer.tc(fn -> LdapSignIn.sign_in(config, "jdoe", "wrong", meta) end)

    assert unknown == {:error, :invalid_credentials}
    assert wrong == unknown
    assert unknown_us >= 200_000
    assert wrong_us >= 200_000
  end

  test "the log shows bind_failed without the username or the password",
       %{config: config, people: people, meta: meta} do
    stub(people)

    log =
      capture_log([level: :warning, metadata: :all], fn ->
        assert LdapSignIn.sign_in(config, "jdoe", "s3cret-wrong-pw", meta) ==
                 {:error, :invalid_credentials}
      end)

    assert log =~ "authn_login_fail"
    assert log =~ "reason=bind_failed"
    assert log =~ "factor=ldap"
    refute log =~ "jdoe"
    refute log =~ "s3cret-wrong-pw"
    refute log =~ "Jo Doe"
  end

  test "a first sign-in provisions the account with roles, org unit and directory fields",
       %{config: config, meta: meta} do
    config = %{config | role_map: [{:author, authors_dn()}], org_unit_attr: ~c"department"}
    people = %{"jdoe" => {ad_dn(), ad_attrs(%{"department" => ["Research"]})}}
    stub(people, members: %{ad_dn() => [authors_dn()]})

    assert {:ok, user} = LdapSignIn.sign_in(config, @upn, @password, meta)
    assert user.org_unit == "Research"
    assert Accounts.roles_for(user) == [:learner, :author]

    [identity] = Repo.all(from i in Accounts.ExternalIdentity, where: i.user_id == ^user.id)
    assert identity.issuer == "ldap:" <> config.key
    assert identity.subject == guid_uuid()
    assert identity.directory_dn == ad_dn()
    assert identity.directory_upn == @upn
    assert identity.directory_login == "jdoe"

    renamed = %{
      "jdoe" =>
        {"CN=Jo Doe-Lee,OU=People,DC=example,DC=org",
         ad_attrs(%{"department" => ["Teaching"], "sAMAccountName" => ["jdoelee"]})}
    }

    stub_directory(renamed, %{"CN=Jo Doe-Lee,OU=People,DC=example,DC=org" => @password})

    assert {:ok, same} = LdapSignIn.sign_in(config, "jdoelee", @password, meta)
    assert same.id == user.id
    assert same.org_unit == "Teaching"
    assert Accounts.roles_for(same) == [:learner]

    identity = Repo.reload!(identity)
    assert identity.directory_dn == "CN=Jo Doe-Lee,OU=People,DC=example,DC=org"
    assert identity.directory_login == "jdoelee"
  end

  test "a directory address of another account requires a link",
       %{config: config, people: people, meta: meta} do
    user_fixture(email: @upn)
    stub(people)

    assert LdapSignIn.sign_in(config, "jdoe", @password, meta) == {:error, :link_required}
  end

  test "a disabled platform account answers invalid_credentials",
       %{config: config, people: people, meta: meta} do
    stub(people)
    assert {:ok, user} = LdapSignIn.sign_in(config, "jdoe", @password, meta)
    user |> Ecto.Changeset.change(status: :disabled) |> Repo.update!()

    ref = attach_security_events()
    assert LdapSignIn.sign_in(config, "jdoe", @password, meta) == {:error, :invalid_credentials}

    assert [%{reason: "account_disabled", user_id: user_id}] = events(ref, :authn_login_fail)
    assert user_id == user.id
  end
end
