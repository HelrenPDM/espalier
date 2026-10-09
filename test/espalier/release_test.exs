defmodule Espalier.ReleaseTest do
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures
  import ExUnit.CaptureIO

  alias Espalier.{Accounts, Release}

  setup do
    oban = Application.fetch_env!(:espalier, Oban)
    on_exit(fn -> Application.put_env(:espalier, Oban, oban) end)
  end

  test "grant_role/2 grants a known role and refuses unknown roles and addresses" do
    user = user_fixture()

    capture_io(fn -> assert {:ok, _grant} = Release.grant_role("admin", user.email) end)
    assert :admin in Accounts.roles_for(user)

    capture_io(fn ->
      assert Release.grant_role("owner", user.email) == {:error, :unknown_role}
    end)

    capture_io(fn ->
      assert Release.grant_role("admin", "nobody@example.org") == {:error, :not_found}
    end)
  end

  test "invite_user/1 creates a user named after the local part and enqueues an invitation" do
    capture_io(fn -> assert {:ok, _user} = Release.invite_user("ada@example.org") end)
    user = Accounts.get_user_by_email("ada@example.org")
    assert user.display_name == "ada"

    assert_enqueued(
      worker: Accounts.MailWorker,
      args: %{"kind" => "invitation", "user_id" => user.id}
    )

    capture_io(fn -> assert :ok = Release.invite_user("ADA@example.org") end)
  end

  test "end_all_sessions/0 ends every session" do
    {token, _session} = session_fixture(user_fixture())
    capture_io(fn -> assert {:ok, _count} = Release.end_all_sessions() end)
    assert Accounts.get_session_by_token(token) == {:error, :not_found}
  end

  describe "LDAP release functions (task 0007)" do
    import Espalier.LdapFixtures
    import Mox

    alias Espalier.Accounts.{FailureCounter, FailureCounters}
    alias Espalier.Identity.Ldap.ClientMock
    alias EspalierWeb.ConnCase

    setup :verify_on_exit!

    setup do
      config = ldap_config(tls: :starttls, role_map: [])
      ConnCase.put_setting(:identity_providers, [config])
      %{config: config}
    end

    test "check_ldap/1 prints one line per step without directory data" do
      stub_directory(%{}, %{})
      stub(ClientMock, :start_tls, fn _handle, _tls, _timeout -> :ok end)

      output = capture_io(fn -> assert Release.check_ldap("ldap") == :ok end)
      assert output == "connect: ok\nstart_tls: ok\nservice_bind: ok\nbase_search: ok\n"
      refute output =~ service_password()

      stub(ClientMock, :simple_bind, fn _handle, _dn, _password ->
        {:error, :invalidCredentials}
      end)

      output = capture_io(fn -> assert Release.check_ldap("ldap") == :error end)
      assert output =~ "service_bind: error service_bind_failed"

      output = capture_io(fn -> Release.check_ldap("other") end)
      assert output =~ "{:error, :unknown_provider}"
    end

    test "reset_directory_lock/2 clears the counter of a directory account", %{config: config} do
      stub_directory(%{"jdoe" => {ad_dn(), ad_attrs()}}, %{})
      stub(ClientMock, :start_tls, fn _handle, _tls, _timeout -> :ok end)
      {:ok, _reservation} = FailureCounters.reserve_directory(config.key, guid_uuid(), 1, 30)

      capture_io(fn -> assert Release.reset_directory_lock("ldap", "jdoe") == :ok end)
      assert Repo.aggregate(FailureCounter, :count) == 0

      capture_io(fn ->
        assert Release.reset_directory_lock("ldap", "jdoe") == {:error, :not_found}
        assert Release.reset_directory_lock("ldap", "nobody") == {:error, :not_found}
        assert Release.reset_directory_lock("other", "jdoe") == {:error, :unavailable}
      end)

      stub(ClientMock, :open, fn _hosts, _opts -> {:error, ~c"connect failed"} end)

      capture_io(fn ->
        assert Release.reset_directory_lock("ldap", "jdoe") == {:error, :unavailable}
      end)
    end
  end
end
