defmodule Espalier.LdapFixtures do
  @moduledoc """
  Provider configs, directory entries and a Mox directory for the LDAP
  tests of task 0007. Every person and value here is invented.
  """

  import Espalier.Identity.Ldap.Records

  alias Espalier.Identity.Ldap.{ClientMock, Config}

  # MS-ADTS example of an objectGUID and its UUID string (step 10).
  @guid_bytes <<63, 105, 46, 202, 128, 98, 137, 69, 147, 118, 179, 112, 115, 69, 211, 173>>
  @guid_uuid "ca2e693f-6280-4589-9376-b3707345d3ad"

  def guid_bytes, do: @guid_bytes
  def guid_uuid, do: @guid_uuid

  def service_dn, do: "cn=espalier-svc,ou=service,dc=example,dc=org"
  def service_password, do: "invented-service-password"
  def base_dn, do: "dc=example,dc=org"
  def authors_dn, do: "cn=espalier-authors,ou=groups,dc=example,dc=org"
  def admins_dn, do: "cn=espalier-admins,ou=groups,dc=example,dc=org"

  @doc """
  An Active Directory provider with the Mox client, a failure limit of 3
  and a timeout of one second, overridable through `attrs`.
  """
  def ldap_config(attrs \\ %{}) do
    attrs = Map.new(attrs)
    key = Map.get(attrs, :key, "ldap")

    struct!(
      %Config{
        key: key,
        label: "Directory account",
        start_url: "/api/auth/ldap/" <> key,
        client: ClientMock,
        host: ~c"localhost",
        port: 636,
        tls: :ldaps,
        cacerts: [],
        bind_dn: service_dn(),
        bind_password: service_password(),
        base_dn: base_dn(),
        directory: :ad,
        user_attrs: [~c"sAMAccountName", ~c"userPrincipalName"],
        role_map: [{:author, authors_dn()}],
        timeout_ms: 1000,
        failure_limit: 3,
        lock_minutes: 30
      },
      attrs
    )
  end

  @doc """
  The attributes of an Active Directory person as `{name, [value]}` with
  binaries: login `jdoe`, UPN `jdoe@example.org`, the GUID vector, an
  enabled account (512).
  """
  def ad_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "objectGUID" => [@guid_bytes],
        "sAMAccountName" => ["jdoe"],
        "userPrincipalName" => ["jdoe@example.org"],
        "mail" => ["jdoe@example.org"],
        "displayName" => ["Jo Doe"],
        "userAccountControl" => ["512"]
      },
      Map.new(overrides)
    )
    |> Enum.reject(fn {_name, values} -> values == nil end)
  end

  def ad_dn, do: "CN=Jo Doe,OU=People,DC=example,DC=org"

  @doc "An `eldap_entry` record with charlists, as `:eldap.search/2` returns it."
  def eldap_entry_record(dn, attrs) do
    eldap_entry(
      object_name: :erlang.binary_to_list(dn),
      attributes:
        for {name, values} <- attrs do
          {:erlang.binary_to_list(name), Enum.map(values, &:erlang.binary_to_list/1)}
        end
    )
  end

  @doc "A search result with `entries` and the server's controls."
  def search_result(entries, controls \\ :asn1_NOVALUE) do
    {:ok, eldap_search_result(entries: entries, referrals: [], controls: controls)}
  end

  @doc """
  Stubs `ClientMock` as a directory with `people` (`%{login => {dn, attrs}}`,
  found by every value of their attributes `sAMAccountName`,
  `userPrincipalName` or `uid`), `passwords` (`%{dn => password}`), and
  `members` (`%{dn => [group_dn]}`). `opts[:user_bind]` replaces the result
  of a user bind with a function of DN and password. Every user bind sends
  `{:user_bind, dn}` to `opts[:notify]` and counts in `opts[:counter]`.
  """
  def stub_directory(people, passwords, opts \\ []) do
    Mox.stub(ClientMock, :open, fn _hosts, _opts -> {:ok, make_ref()} end)
    Mox.stub(ClientMock, :close, fn _handle -> :ok end)

    Mox.stub(ClientMock, :simple_bind, fn _handle, dn, password ->
      if dn == service_dn(),
        do: service_bind(password),
        else: user_bind(dn, password, passwords, opts)
    end)

    members = Keyword.get(opts, :members, %{})
    Mox.stub(ClientMock, :search, fn _handle, search -> search(search, people, members) end)
    :ok
  end

  defp service_bind(password) do
    if password == service_password(), do: :ok, else: {:error, :invalidCredentials}
  end

  defp user_bind(dn, password, passwords, opts) do
    if notify = opts[:notify], do: send(notify, {:user_bind, dn})
    if counter = opts[:counter], do: :counters.add(counter, 1, 1)

    case Keyword.fetch(opts, :user_bind) do
      {:ok, fun} ->
        fun.(dn, password)

      :error ->
        if Map.get(passwords, dn) == password, do: :ok, else: {:error, :invalidCredentials}
    end
  end

  defp search(search, people, members) do
    case Keyword.fetch!(search, :scope) do
      :wholeSubtree ->
        values = assertion_values(Keyword.fetch!(search, :filter))

        people
        |> Map.values()
        |> Enum.filter(fn {_dn, attrs} -> matches?(attrs, values) end)
        |> Enum.map(fn {dn, attrs} -> eldap_entry_record(dn, attrs) end)
        |> search_result()

      :baseObject ->
        base_search(Keyword.fetch!(search, :base), Keyword.fetch!(search, :filter), members)
    end
  end

  # A base search with a group filter checks membership; any other base
  # search finds the base entry.
  defp base_search(base, filter, members) do
    case assertion_values(filter) do
      [group_dn] ->
        if group_dn in Map.get(members, base, []),
          do: search_result([eldap_entry_record(base, [])]),
          else: {:error, :noSuchObject}

      [] ->
        search_result([eldap_entry_record(base, [])])
    end
  end

  defp matches?(attrs, values) do
    Enum.any?(attrs, fn {name, attr_values} ->
      name in ["sAMAccountName", "userPrincipalName", "uid"] and
        Enum.any?(attr_values, &(&1 in values))
    end)
  end

  @doc "The assertion values of the user part of an `:eldap` filter, as binaries."
  def assertion_values({:and, filters}), do: Enum.flat_map(filters, &assertion_values/1)
  def assertion_values({:or, filters}), do: Enum.flat_map(filters, &assertion_values/1)

  def assertion_values({:equalityMatch, {:AttributeValueAssertion, attr, value}}) do
    if attr in [~c"objectCategory", ~c"objectClass"], do: [], else: [to_binary(value)]
  end

  def assertion_values({:extensibleMatch, {:MatchingRuleAssertion, _rule, _type, value, _dn}}),
    do: [to_binary(value)]

  def assertion_values(_filter), do: []

  defp to_binary(value) when is_binary(value), do: value
  defp to_binary(value) when is_list(value), do: :erlang.list_to_binary(value)
end
