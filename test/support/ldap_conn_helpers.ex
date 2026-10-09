defmodule Espalier.LdapConnHelpers do
  @moduledoc """
  Helpers of the LDAP controller tests (task 0007, step 25): the provider
  `ldap` with the Mox client in the application environment, and the
  directory people of these tests.
  """

  import Espalier.LdapFixtures

  alias Espalier.Identity.{Config, Ldap}
  alias EspalierWeb.ConnCase

  @password "correct horse battery"

  def directory_password, do: @password

  @doc "Puts the provider `ldap` with the Mox client into the application environment."
  def put_ldap_provider(attrs \\ %{}) do
    config = ldap_config(Map.merge(%{key: "ldap", role_map: []}, Map.new(attrs)))
    ConnCase.put_setting(:identity_providers, [config])
    ConnCase.put_setting(:auth_providers, [Config.public_entry(config)])
    config
  end

  @doc """
  A directory person with the login `login`, its own `objectGUID` and the
  address `<login>@example.org`. Returns `{login, {dn, attrs}}`.
  """
  def person(login, overrides \\ %{}) do
    dn = "CN=#{login},OU=People,DC=example,DC=org"

    attrs =
      ad_attrs(
        Map.merge(
          %{
            "objectGUID" => [:crypto.strong_rand_bytes(16)],
            "sAMAccountName" => [login],
            "userPrincipalName" => ["#{login}@example.org"],
            "mail" => ["#{login}@example.org"],
            "displayName" => [String.capitalize(login)]
          },
          Map.new(overrides)
        )
      )

    {login, {dn, attrs}}
  end

  def dn({_login, {dn, _attrs}}), do: dn

  @doc "The UUID subject of a person of `person/2`."
  def subject({_login, {_dn, attrs}}) do
    {"objectGUID", [guid]} = List.keyfind(attrs, "objectGUID", 0)
    {:ok, uuid} = Ldap.object_guid_to_uuid(guid)
    uuid
  end

  @doc "Stubs the Mox directory with `people`, each with the password of this module."
  def stub_people(people, opts \\ []) do
    stub_directory(
      Map.new(people),
      Map.new(people, fn person -> {dn(person), @password} end),
      opts
    )
  end
end
