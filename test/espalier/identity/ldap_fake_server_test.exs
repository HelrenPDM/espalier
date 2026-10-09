defmodule Espalier.Identity.LdapFakeServerTest do
  # Real :eldap against Espalier.FakeLdapServer, no directory (task 0007,
  # step 27). The LdapSignIn cases change the failure floor, so the module
  # runs alone.
  use Espalier.DataCase, async: false

  import Espalier.LdapFixtures

  alias Espalier.Accounts.LdapSignIn
  alias Espalier.FakeLdapServer
  alias Espalier.Identity.Ldap
  alias Espalier.Identity.Ldap.Eldap

  @user_dn "CN=Jo Doe,OU=People,DC=example,DC=org"
  @tls FakeLdapServer.tls_fixture("localhost")

  defp ldaps_config(port, attrs \\ %{}) do
    ldap_config(
      Map.merge(
        %{
          key: "fake#{System.unique_integer([:positive])}",
          client: Eldap,
          port: port,
          tls: :ldaps,
          cacerts: @tls.cacerts,
          role_map: [{:author, authors_dn()}]
        },
        Map.new(attrs)
      )
    )
  end

  defp ad_entries(overrides \\ %{}) do
    attrs =
      %{
        # Lower-case names, as some servers return them.
        "objectguid" => [guid_bytes()],
        "samaccountname" => ["jdoe"],
        "userprincipalname" => ["jdoe@example.org"],
        "mail" => ["jdoe@example.org"],
        "displayname" => ["Jürgen Doe"],
        "useraccountcontrol" => ["512"]
      }
      |> Map.merge(overrides)
      |> Enum.to_list()

    [{@user_dn, attrs}]
  end

  defp fake_ldaps(opts) do
    FakeLdapServer.start!(
      [
        transport: :ldaps,
        server_tls: @tls.server_config,
        binds: %{service_dn() => :success, @user_dn => :success},
        entries: ad_entries(),
        members: %{@user_dn => [authors_dn()]}
      ]
      |> Keyword.merge(opts)
    )
  end

  defp binds_received do
    receive do
      {:fake_ldap, :request, _id, {:bindRequest, {:BindRequest, _v, name, auth}}} ->
        [{:erlang.list_to_binary(name), auth} | binds_received()]

      {:fake_ldap, :request, _id, _op} ->
        binds_received()
    after
      100 -> []
    end
  end

  defp set_floor(ms) do
    previous = Application.get_env(:espalier, LdapSignIn)
    Application.put_env(:espalier, LdapSignIn, failure_floor_ms: ms)
    on_exit(fn -> Application.put_env(:espalier, LdapSignIn, previous) end)
  end

  test "characterization: :eldap sends an empty binary password as an unauthenticated bind" do
    port =
      FakeLdapServer.start!(binds: %{"cn=alice,dc=example,dc=org" => :success})

    {:ok, handle} = :eldap.open([~c"localhost"], port: port, timeout: 1000)

    try do
      assert :eldap.simple_bind(handle, "cn=alice,dc=example,dc=org", "") == :ok
    after
      :eldap.close(handle)
    end

    assert_received {:fake_ldap, :request, _id, {:bindRequest, {:BindRequest, 3, _name, auth}}}
    assert auth == {:simple, []}
  end

  test "blank passwords send no packet" do
    port = fake_ldaps([])
    config = ldaps_config(port)

    for password <- ["", "   ", "\t"] do
      assert {:error, :invalid_input, nil, nil} = Ldap.authenticate(config, "jdoe", password)
    end

    refute_receive {:fake_ldap, :request, _id, _op}, 200
  end

  test "the user bind carries the NFD bytes of the password unchanged" do
    port = fake_ldaps([])
    nfd = String.normalize("Crème brûlée au café du matin", :nfd)

    assert {:ok, _entry, nil} = Ldap.authenticate(ldaps_config(port), "jdoe", nfd)

    assert {@user_dn, {:simple, :erlang.binary_to_list(nfd)}} in binds_received()
  end

  test "a full LDAPS sign-in with the ad profile" do
    port = fake_ldaps([])

    assert {:ok, entry, nil} =
             Ldap.authenticate(ldaps_config(port), "jdoe", "correct horse battery")

    assert entry.subject == guid_uuid()
    assert entry.display_name == "Jürgen Doe"
    assert entry.dn == @user_dn
    assert entry.login == "jdoe"
    assert entry.upn == "jdoe@example.org"
    assert entry.email == "jdoe@example.org"
    assert entry.groups == [authors_dn()]
  end

  test "LDAPS against a certificate for another name fails without a bind and probes once" do
    other = FakeLdapServer.tls_fixture("other.test")
    port = fake_ldaps(server_tls: other.server_config)
    config = ldaps_config(port, cacerts: other.cacerts, failure_limit: 3)

    assert {:error, :connect_failed, nil, nil} = Ldap.authenticate(config, "jdoe", "secret")
    assert binds_received() == []

    handler = "tls-probe-#{System.unique_integer([:positive])}"
    test_pid = self()
    provider = config.key

    :telemetry.attach(
      handler,
      [:espalier, :security, :event],
      fn _event, _measurements, %{name: name} = metadata, _config ->
        if name == :directory_tls_failed and metadata[:provider] == provider,
          do: send(test_pid, {:probe, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:error, :invalid_credentials} =
             LdapSignIn.sign_in(config, "jdoe", "secret", %{ip: {127, 0, 0, 1}})

    assert_receive {:probe, %{reason: reason}}, 2_000
    assert is_binary(reason) and reason != ""

    assert {:error, :invalid_credentials} =
             LdapSignIn.sign_in(config, "jdoe", "secret", %{ip: {127, 0, 0, 1}})

    refute_receive {:probe, _metadata}, 1_000
    assert binds_received() == []
  end

  test "LDAPS against a certificate from another CA fails without a bind" do
    port = fake_ldaps([])
    other = FakeLdapServer.tls_fixture("localhost")

    assert {:error, :connect_failed, nil, nil} =
             Ldap.authenticate(ldaps_config(port, cacerts: other.cacerts), "jdoe", "secret")

    assert binds_received() == []
  end

  test "StartTLS with a certificate for localhost succeeds and binds after the extended request" do
    port =
      FakeLdapServer.start!(
        server_tls: @tls.server_config,
        binds: %{service_dn() => :success, @user_dn => :success},
        entries: ad_entries()
      )

    config = ldaps_config(port, tls: :starttls, role_map: [])
    assert {:ok, _entry, nil} = Ldap.authenticate(config, "jdoe", "secret")

    ops =
      Stream.repeatedly(fn ->
        receive do
          {:fake_ldap, :request, _id, op} -> elem(op, 0)
        after
          100 -> nil
        end
      end)
      |> Enum.take_while(& &1)

    assert [:extendedReq, :bindRequest, :searchRequest | rest] = ops
    assert :extendedReq in rest
    assert :bindRequest in rest
  end

  test "StartTLS answered with a referral fails without a bind" do
    port =
      FakeLdapServer.start!(
        server_tls: @tls.server_config,
        start_tls: :referral,
        binds: %{service_dn() => :success}
      )

    config = ldaps_config(port, tls: :starttls)
    assert {:error, :tls_failed, nil, nil} = Ldap.authenticate(config, "jdoe", "secret")
    assert binds_received() == []
  end

  test "a silent server returns unavailable within one second" do
    port = FakeLdapServer.start!(silent: true)
    config = ldaps_config(port, tls: :none, timeout_ms: 300)

    {micros, result} = :timer.tc(fn -> Ldap.authenticate(config, "jdoe", "secret") end)
    assert {:error, :unavailable, nil, nil} = result
    assert micros < 1_000_000
  end

  test "a disabled account (userAccountControl 514) gets no bind for its DN" do
    port = fake_ldaps(entries: ad_entries(%{"useraccountcontrol" => ["514"]}))

    assert {:error, :disabled, nil, nil} =
             Ldap.authenticate(ldaps_config(port), "jdoe", "secret")

    refute Enum.any?(binds_received(), fn {dn, _auth} -> dn == @user_dn end)
  end

  test "LdapSignIn keeps the floor for an unknown user and a wrong password" do
    set_floor(200)

    port =
      fake_ldaps(
        binds: %{service_dn() => :success, @user_dn => :invalidCredentials},
        entries: ad_entries()
      )

    config = ldaps_config(port)
    meta = %{ip: {127, 0, 0, 1}}

    {unknown_us, unknown} =
      :timer.tc(fn ->
        port_unknown = fake_ldaps(entries: [])
        LdapSignIn.sign_in(ldaps_config(port_unknown, key: config.key), "nobody", "secret", meta)
      end)

    {wrong_us, wrong} = :timer.tc(fn -> LdapSignIn.sign_in(config, "jdoe", "wrong", meta) end)

    assert unknown == {:error, :invalid_credentials}
    assert wrong == unknown
    assert unknown_us >= 200_000
    assert wrong_us >= 200_000
  end
end
