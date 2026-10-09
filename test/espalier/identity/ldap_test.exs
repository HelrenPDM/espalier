defmodule Espalier.Identity.LdapTest do
  # Unit tests of the :eldap wrapper with the Mox client (task 0007, step 23).
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Espalier.LdapFixtures
  import Mox

  alias Espalier.Identity.Ldap
  alias Espalier.Identity.Ldap.ClientMock

  setup :verify_on_exit!

  @password "correct horse battery"
  @c1 :connection_1
  @c2 :connection_2

  defp expect_lookup(config, handle, entries) do
    expect(ClientMock, :open, fn [~c"localhost"], _opts -> {:ok, handle} end)

    expect(ClientMock, :simple_bind, fn ^handle, dn, password ->
      assert dn == config.bind_dn
      assert password == config.bind_password
      :ok
    end)

    expect(ClientMock, :search, fn ^handle, opts ->
      assert opts[:scope] == :eldap.wholeSubtree()
      search_result(entries)
    end)
  end

  defp expect_groups(handle, results) do
    for result <- results do
      expect(ClientMock, :search, fn ^handle, opts ->
        assert opts[:scope] == :eldap.baseObject()
        assert opts[:attributes] == [~c"1.1"]
        assert opts[:size_limit] == 1
        result
      end)
    end
  end

  defp expect_close(handle), do: expect(ClientMock, :close, fn ^handle -> :ok end)

  defp ad_entry(overrides \\ %{}), do: eldap_entry_record(ad_dn(), ad_attrs(overrides))

  defp member, do: search_result([eldap_entry_record(ad_dn(), [])])

  defp expect_user_bind(handle, result) do
    expect(ClientMock, :open, fn [~c"localhost"], _opts -> {:ok, handle} end)

    expect(ClientMock, :simple_bind, fn ^handle, dn, password ->
      assert dn == ad_dn()
      assert password == @password
      result
    end)

    expect_close(handle)
  end

  describe "input guards" do
    test "invalid usernames and passwords return invalid_input without a call" do
      config = ldap_config()

      for {username, password} <- [
            {"", @password},
            {"   ", @password},
            {"\t\n", @password},
            {nil, @password},
            {~c"jdoe", @password},
            {<<0xFF, 0xFE>>, @password},
            {String.duplicate("a", 257), @password},
            {"jdoe", ""},
            {"jdoe", "   "},
            {"jdoe", "\t"},
            {"jdoe", nil},
            {"jdoe", ~c"secret"},
            {"jdoe", <<0xC3, 0x28>>},
            {"jdoe", String.duplicate("p", 1025)}
          ] do
        assert Ldap.authenticate(config, username, password) ==
                 {:error, :invalid_input, nil, nil}
      end
    end

    test "the limits allow 256 username bytes and 1,024 password bytes" do
      config = ldap_config(role_map: [])
      expect_lookup(config, @c1, [])
      expect_close(@c1)

      assert {:error, :not_found, nil, nil} =
               Ldap.authenticate(config, String.duplicate("a", 256), String.duplicate("p", 1024))
    end
  end

  describe "connection options" do
    test "ldaps opens with port, ssl, sslopts and a positive timeout only" do
      config = ldap_config(role_map: [], timeout_ms: 2500)

      expect(ClientMock, :open, fn [~c"localhost"], opts ->
        assert Enum.sort(Keyword.keys(opts)) == [:port, :ssl, :sslopts, :timeout]
        assert opts[:port] == 636
        assert opts[:ssl] == true
        assert opts[:timeout] == 2500
        assert opts[:sslopts][:verify] == :verify_peer
        assert opts[:sslopts][:server_name_indication] == ~c"localhost"
        assert opts[:sslopts][:versions] == [:"tlsv1.3", :"tlsv1.2"]
        assert opts[:sslopts][:cacerts] == config.cacerts
        refute Keyword.has_key?(opts[:sslopts], :customize_hostname_check)
        {:ok, @c1}
      end)

      expect(ClientMock, :simple_bind, fn @c1, _dn, _password -> :ok end)

      expect(ClientMock, :search, fn @c1, opts ->
        assert opts[:base] == base_dn()
        assert opts[:size_limit] == 2
        assert opts[:timeout] == 2
        search_result([])
      end)

      expect_close(@c1)
      assert {:error, :not_found, nil, nil} = Ldap.authenticate(config, "jdoe", @password)
    end

    test "starttls opens without sslopts and passes the TLS options to start_tls/3" do
      config = ldap_config(role_map: [], tls: :starttls, port: 389, tls_wildcard: true)

      expect(ClientMock, :open, fn [~c"localhost"], opts ->
        assert Enum.sort(Keyword.keys(opts)) == [:port, :timeout]
        assert opts[:timeout] == 1000
        {:ok, @c1}
      end)

      expect(ClientMock, :start_tls, fn @c1, tls_opts, 1000 ->
        assert tls_opts[:verify] == :verify_peer
        assert tls_opts[:server_name_indication] == ~c"localhost"
        assert [match_fun: fun] = tls_opts[:customize_hostname_check]
        assert is_function(fun)
        :ok
      end)

      expect(ClientMock, :simple_bind, fn @c1, _dn, _password -> :ok end)
      expect(ClientMock, :search, fn @c1, _opts -> search_result([]) end)
      expect_close(@c1)

      assert {:error, :not_found, nil, nil} = Ldap.authenticate(config, "jdoe", @password)
    end

    test "a StartTLS referral closes the handle without a bind" do
      config = ldap_config(tls: :starttls)
      expect(ClientMock, :open, fn _hosts, _opts -> {:ok, @c1} end)

      expect(ClientMock, :start_tls, fn @c1, _tls, _timeout ->
        {:ok, {:referral, [~c"ldap://x/"]}}
      end)

      expect_close(@c1)

      assert {:error, :tls_failed, nil, nil} = Ldap.authenticate(config, "jdoe", @password)
    end

    test "a referral on the service bind closes the handle" do
      config = ldap_config()
      expect(ClientMock, :open, fn _hosts, _opts -> {:ok, @c1} end)

      expect(ClientMock, :simple_bind, fn @c1, _dn, _password ->
        {:ok, {:referral, [~c"ldap://x/"]}}
      end)

      expect_close(@c1)

      assert {:error, :service_bind_failed, nil, nil} =
               Ldap.authenticate(config, "jdoe", @password)
    end

    test "a referral on the search closes the handle" do
      config = ldap_config()
      expect(ClientMock, :open, fn _hosts, _opts -> {:ok, @c1} end)
      expect(ClientMock, :simple_bind, fn @c1, _dn, _password -> :ok end)
      expect(ClientMock, :search, fn @c1, _opts -> {:ok, {:referral, [~c"ldap://x/"]}} end)
      expect_close(@c1)

      assert {:error, :referral, nil, nil} = Ldap.authenticate(config, "jdoe", @password)
    end

    test "a failed open returns connect_failed" do
      expect(ClientMock, :open, fn _hosts, _opts -> {:error, ~c"connect failed"} end)

      assert {:error, :connect_failed, nil, nil} =
               Ldap.authenticate(ldap_config(), "jdoe", @password)
    end
  end

  describe "the entry" do
    for {name, entries, reason} <- [
          {"zero entries", quote(do: []), :not_found},
          {"two entries", quote(do: [ad_entry(), ad_entry()]), :ambiguous},
          {"an empty DN", quote(do: [eldap_entry_record("", ad_attrs())]), :invalid_input},
          {"a blank DN", quote(do: [eldap_entry_record("  ", ad_attrs())]), :invalid_input},
          {"userAccountControl 514", quote(do: [ad_entry(%{"userAccountControl" => ["514"]})]),
           :disabled},
          {"no userAccountControl", quote(do: [ad_entry(%{"userAccountControl" => nil})]),
           :disabled},
          {"a malformed userAccountControl",
           quote(do: [ad_entry(%{"userAccountControl" => ["x512"]})]), :disabled},
          {"a 15-byte objectGUID",
           quote(do: [ad_entry(%{"objectGUID" => [binary_part(guid_bytes(), 0, 15)]})]),
           :no_identity_attribute},
          {"no objectGUID", quote(do: [ad_entry(%{"objectGUID" => nil})]), :no_identity_attribute}
        ] do
      test "#{name} fails without a second open" do
        config = ldap_config()
        expect_lookup(config, @c1, unquote(entries))
        expect_close(@c1)

        assert {:error, unquote(reason), nil, nil} = Ldap.authenticate(config, "jdoe", @password)
      end
    end

    test "attributes are compared case-insensitively and converted byte by byte" do
      config = ldap_config(role_map: [], org_unit_attr: ~c"department")

      entry =
        eldap_entry_record(ad_dn(), [
          {"OBJECTGUID", [guid_bytes()]},
          {"samaccountname", ["jdoe"]},
          {"userprincipalname", ["jdoe@example.org"]},
          {"Mail", ["jdoe@example.org"]},
          {"displayname", ["  Jürgen " <> String.duplicate("x", 300)]},
          {"userAccountControl", ["66048"]},
          {"Department", ["Großküche"]}
        ])

      expect_lookup(config, @c1, [entry])
      expect_close(@c1)

      assert {:ok, entry} = Ldap.lookup(config, " jdoe ")
      assert entry.subject == guid_uuid()
      assert entry.login == "jdoe"
      assert entry.upn == "jdoe@example.org"
      assert entry.email == "jdoe@example.org"
      assert entry.org_unit == "Großküche"
      assert String.starts_with?(entry.display_name, "Jürgen x")
      assert String.length(entry.display_name) == 200
      assert entry.groups == []
    end

    test "the generic profile reads entryUUID, uid and cn" do
      config = ldap_config(directory: :generic, user_attrs: [~c"uid"], role_map: [])

      entry =
        eldap_entry_record("uid=emil,ou=people,dc=example,dc=org", [
          {"entryUUID", ["5C6F0A3B-1D2E-4F5A-8B7C-9D0E1F2A3B4C"]},
          {"uid", ["emil"]},
          {"cn", ["Emil"]},
          {"mail", ["emil@example.org"]}
        ])

      expect_lookup(config, @c1, [entry])
      expect_close(@c1)

      assert {:ok, entry} = Ldap.lookup(config, "emil")
      assert entry.subject == "5c6f0a3b-1d2e-4f5a-8b7c-9d0e1f2a3b4c"
      assert entry.login == "emil"
      assert entry.upn == nil
      assert entry.display_name == "Emil"
    end

    test "a controls list in the search result is accepted" do
      config = ldap_config(role_map: [])
      expect(ClientMock, :open, fn _hosts, _opts -> {:ok, @c1} end)
      expect(ClientMock, :simple_bind, fn @c1, _dn, _password -> :ok end)

      expect(ClientMock, :search, fn @c1, _opts ->
        search_result([ad_entry()], [{:"1.2.840.113556.1.4.319", false, ~c""}])
      end)

      expect_close(@c1)
      assert {:ok, _entry} = Ldap.lookup(config, "jdoe")
    end
  end

  describe "filters" do
    test "the ad filter matches person users by sAMAccountName or userPrincipalName" do
      config = ldap_config(role_map: [])
      username = "jdoe*)(uid=*"

      expected =
        :eldap.and([
          :eldap.equalityMatch(~c"objectCategory", ~c"person"),
          :eldap.equalityMatch(~c"objectClass", ~c"user"),
          :eldap.or([
            :eldap.equalityMatch(~c"sAMAccountName", username),
            :eldap.equalityMatch(~c"userPrincipalName", username)
          ])
        ])

      expect(ClientMock, :open, fn _hosts, _opts -> {:ok, @c1} end)
      expect(ClientMock, :simple_bind, fn @c1, _dn, _password -> :ok end)

      expect(ClientMock, :search, fn @c1, opts ->
        assert opts[:filter] == expected
        assert assertion_values(opts[:filter]) == [username, username]

        assert opts[:attributes] == [
                 ~c"objectGUID",
                 ~c"userPrincipalName",
                 ~c"sAMAccountName",
                 ~c"mail",
                 ~c"displayName",
                 ~c"userAccountControl"
               ]

        search_result([])
      end)

      expect_close(@c1)

      assert {:error, :not_found, nil, nil} =
               Ldap.authenticate(config, " #{username} ", @password)
    end

    test "the generic filter matches persons by uid" do
      config =
        ldap_config(
          directory: :generic,
          user_attrs: [~c"uid"],
          role_map: [],
          org_unit_attr: ~c"ou"
        )

      expected =
        :eldap.and([
          :eldap.equalityMatch(~c"objectClass", ~c"person"),
          :eldap.or([:eldap.equalityMatch(~c"uid", "emil")])
        ])

      expect(ClientMock, :open, fn _hosts, _opts -> {:ok, @c1} end)
      expect(ClientMock, :simple_bind, fn @c1, _dn, _password -> :ok end)

      expect(ClientMock, :search, fn @c1, opts ->
        assert opts[:filter] == expected

        assert opts[:attributes] ==
                 [~c"entryUUID", ~c"uid", ~c"mail", ~c"displayName", ~c"cn", ~c"ou"]

        search_result([])
      end)

      expect_close(@c1)
      assert {:error, :not_found, nil, nil} = Ldap.authenticate(config, "emil", @password)
    end

    test "group filters use the in-chain rule for ad and memberOf equality for generic" do
      assert Ldap.group_filter(:ad, authors_dn()) ==
               :eldap.extensibleMatch(authors_dn(),
                 type: ~c"memberOf",
                 matchingRule: ~c"1.2.840.113556.1.4.1941"
               )

      assert Ldap.group_filter(:generic, authors_dn()) ==
               :eldap.equalityMatch(~c"memberOf", authors_dn())
    end
  end

  describe "groups" do
    test "one entry adds the group, noSuchObject and no entry add nothing" do
      config =
        ldap_config(
          role_map: [{:author, authors_dn()}, {:admin, admins_dn()}, {:analyst, authors_dn()}]
        )

      expect_lookup(config, @c1, [ad_entry()])
      expect_groups(@c1, [member(), {:error, :noSuchObject}])
      expect_close(@c1)
      expect_user_bind(@c2, :ok)

      assert {:ok, entry, nil} = Ldap.authenticate(config, "jdoe", @password)
      assert entry.groups == [authors_dn()]

      expect_lookup(config, @c1, [ad_entry()])
      expect_groups(@c1, [search_result([]), member()])
      expect_close(@c1)
      expect_user_bind(@c2, :ok)

      assert {:ok, entry, nil} = Ldap.authenticate(config, "jdoe", @password)
      assert entry.groups == [admins_dn()]
    end

    test "a failed group search returns group_lookup_failed without a user bind" do
      config = ldap_config(role_map: [{:author, authors_dn()}, {:admin, admins_dn()}])
      expect_lookup(config, @c1, [ad_entry()])
      expect_groups(@c1, [{:error, {:gen_tcp_error, :timeout}}])
      expect_close(@c1)

      assert {:error, :group_lookup_failed, nil, nil} =
               Ldap.authenticate(config, "jdoe", @password)
    end
  end

  describe "user bind" do
    for {result, reason} <- [
          {:ok, nil},
          {quote(do: {:error, :invalidCredentials}), :bind_failed},
          {quote(do: {:ok, {:referral, [~c"ldap://other.example.org/"]}}), :referral},
          {quote(do: {:error, :unwillingToPerform}), :bind_rejected},
          {quote(do: {:error, {:gen_tcp_error, :timeout}}), :unavailable}
        ] do
      test "#{Macro.to_string(result)} maps to #{inspect(reason)}" do
        config = ldap_config(role_map: [])
        expect_lookup(config, @c1, [ad_entry()])
        expect_close(@c1)
        expect_user_bind(@c2, unquote(result))

        case unquote(reason) do
          nil -> assert {:ok, %{subject: _}, :ticket} = run(config)
          reason -> assert {:error, ^reason, %{subject: _}, :ticket} = run(config)
        end
      end
    end

    test "a failed open of connection 2 returns connect_failed" do
      config = ldap_config(role_map: [])
      expect_lookup(config, @c1, [ad_entry()])
      expect_close(@c1)
      expect(ClientMock, :open, fn _hosts, _opts -> {:error, ~c"connect failed"} end)

      assert {:error, :connect_failed, _entry, :ticket} = run(config)
    end
  end

  defp run(config) do
    Ldap.authenticate(config, "jdoe", @password, before_bind: fn _entry -> {:ok, :ticket} end)
  end

  describe "orchestration" do
    test "a search that raises closes the handle, returns internal and logs no password" do
      config = ldap_config()
      expect(ClientMock, :open, fn _hosts, _opts -> {:ok, @c1} end)
      expect(ClientMock, :simple_bind, fn @c1, _dn, _password -> :ok end)
      expect(ClientMock, :search, fn @c1, _opts -> raise FunctionClauseError end)
      expect_close(@c1)

      log =
        capture_log(fn ->
          assert {:error, :internal, nil, nil} = Ldap.authenticate(config, "jdoe", @password)
        end)

      assert log =~ "FunctionClauseError"
      refute log =~ @password
      refute log =~ service_password()
    end

    test "a before_bind error prevents the second open" do
      config = ldap_config(role_map: [])
      expect_lookup(config, @c1, [ad_entry()])
      expect_close(@c1)

      assert {:error, :locked, %{subject: subject}, nil} =
               Ldap.authenticate(config, "jdoe", @password,
                 before_bind: fn entry ->
                   send(self(), {:before_bind, entry.subject})
                   {:error, :locked}
                 end
               )

      assert subject == guid_uuid()
    end

    test "the ticket of before_bind comes back" do
      config = ldap_config(role_map: [])
      expect_lookup(config, @c1, [ad_entry()])
      expect_close(@c1)
      expect_user_bind(@c2, :ok)

      assert {:ok, _entry, %{id: 42}} =
               Ldap.authenticate(config, "jdoe", @password,
                 before_bind: fn _entry -> {:ok, %{id: 42}} end
               )
    end

    test "a task past its deadline is killed and returns unavailable" do
      config = ldap_config(timeout_ms: 50)

      expect(ClientMock, :open, fn _hosts, _opts ->
        Process.sleep(1_000)
        {:ok, @c1}
      end)

      assert {:error, :unavailable, nil, nil} = Ldap.authenticate(config, "jdoe", @password)
    end
  end

  test "object_guid_to_uuid/1 converts the MS-ADTS example" do
    assert Ldap.object_guid_to_uuid(guid_bytes()) == {:ok, guid_uuid()}
    assert Ldap.object_guid_to_uuid(binary_part(guid_bytes(), 0, 15)) == :error
    assert Ldap.object_guid_to_uuid(nil) == :error
  end

  test "reason_tag/1 keeps the alert name and atoms only" do
    assert Ldap.reason_tag({:tls_alert, {:handshake_failure, ~c"details"}}) == :handshake_failure
    assert Ldap.reason_tag(:econnrefused) == :econnrefused
    assert Ldap.reason_tag({:options, {:cacerts, []}}) == :other
  end
end
