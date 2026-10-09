defmodule Espalier.Integration.LdapLldapTest do
  # Runs against the development lldap of compose.dev.yaml over LDAPS on
  # port 6360 (task 0007, step 29): make ldap-ca services-up services-seed,
  # then make test-integration.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query

  alias Espalier.Accounts
  alias Espalier.Accounts.{ExternalIdentity, FailureCounter, LdapSignIn, RoleGrant}
  alias Espalier.Identity.{Config, Ldap}
  alias Espalier.Identity.Ldap.Config, as: LdapConfig
  alias Espalier.Identity.Ldap.RecordingClient
  alias Espalier.Repo

  @moduletag :ldap

  @authors "cn=espalier-authors,ou=groups,dc=example,dc=org"
  @admins "cn=espalier-admins,ou=groups,dc=example,dc=org"
  @meta %{ip: {127, 0, 0, 1}}

  # The development values of .env.example; the service password has one
  # source, the bootstrap file of lldap.
  defp env(overrides) do
    service_password =
      "dev/lldap/bootstrap/user-configs/espalier-svc.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("password")

    Map.merge(
      %{
        "AUTH_LDAP_TYPE" => "ldap",
        "AUTH_LDAP_LABEL" => "\"Directory account (dev)\"",
        "AUTH_LDAP_HOST" => "localhost",
        "AUTH_LDAP_PORT" => "6360",
        "AUTH_LDAP_TLS" => "ldaps",
        "AUTH_LDAP_CA_CERT_FILE" => "dev/ldap-ca/ca.pem",
        "AUTH_LDAP_DIRECTORY" => "generic",
        "AUTH_LDAP_BIND_DN" => "uid=espalier-svc,ou=people,dc=example,dc=org",
        "AUTH_LDAP_BIND_PASSWORD" => service_password,
        "AUTH_LDAP_BASE_DN" => "dc=example,dc=org",
        "AUTH_LDAP_USER_ATTR" => "uid",
        "AUTH_LDAP_ROLE_MAP" => "\"author=#{@authors};admin=#{@admins}\"",
        "AUTH_LDAP_FAILURE_LIMIT" => "5",
        "AUTH_LDAP_LOCK_MINUTES" => "30"
      },
      overrides
    )
  end

  defp config(overrides \\ %{}), do: LdapConfig.parse!("ldap", env(overrides), :test)

  defp calls do
    receive do
      {:ldap_call, name} -> [name | calls()]
    after
      0 -> []
    end
  end

  test "emil, fay and dora sign in with their groups" do
    config = config()

    assert {:ok, emil, nil} = Ldap.authenticate(config, "emil", "dev-password")
    assert {:ok, _uuid} = Ecto.UUID.cast(emil.subject)
    assert emil.groups == [@authors]
    assert emil.display_name == "Emil Jürgens"
    assert emil.dn == "uid=emil,ou=people,dc=example,dc=org"
    assert emil.email == "emil@example.org"

    assert {:ok, fay, nil} = Ldap.authenticate(config, "fay", "dev-password")
    assert fay.groups == [@admins]

    assert {:ok, dora, nil} = Ldap.authenticate(config, "dora", "dev-password")
    assert dora.groups == []
  end

  test "a wrong password, an unknown user and an empty password fail" do
    config = %{config() | client: RecordingClient}

    assert {:error, :bind_failed, _entry, nil} = Ldap.authenticate(config, "emil", "wrong")
    assert {:error, :not_found, nil, nil} = Ldap.authenticate(config, "nobody", "dev-password")
    calls()

    assert {:error, :invalid_input, nil, nil} = Ldap.authenticate(config, "emil", "")
    assert calls() == []
  end

  test "StartTLS on port 3890 fails without a bind" do
    config = %{
      config(%{"AUTH_LDAP_TLS" => "starttls", "AUTH_LDAP_PORT" => "3890"})
      | client: RecordingClient
    }

    assert {:error, :tls_failed, nil, nil} = Ldap.authenticate(config, "emil", "dev-password")
    assert calls() == [:open, :start_tls, :close]
  end

  test "three wrong passwords lock fay's directory pathway" do
    config = %{config() | failure_limit: 3}

    for _ <- 1..3 do
      assert LdapSignIn.sign_in(config, "fay", "wrong", @meta) == {:error, :invalid_credentials}
    end

    assert LdapSignIn.sign_in(config, "fay", "dev-password", @meta) ==
             {:error, :invalid_credentials}

    {:ok, fay} = Ldap.lookup(config, "fay")

    row =
      Repo.one!(
        from c in FailureCounter,
          where:
            c.authenticator == :ldap and c.provider_key == "ldap" and
              c.subject_hash == ^ExternalIdentity.hash_input("ldap:ldap", nil, fay.subject)
      )

    assert row.consecutive_failures == 3
    assert DateTime.after?(row.locked_until, DateTime.utc_now())
  end

  test "emil's first sign-in through the controller enrolls with the author role", %{conn: conn} do
    config = config()
    put_setting(:identity_providers, [config])
    put_setting(:auth_providers, [Config.public_entry(config)])

    sign_in = fn username, password ->
      api_request(api_conn(), :post, "/api/auth/ldap/ldap", %{
        username: username,
        password: password
      })
    end

    conn =
      api_request(conn, :post, "/api/auth/ldap/ldap", %{
        username: "emil",
        password: "dev-password"
      })

    assert json_response(conn, 200) == %{"next" => "enroll_second_factor"}

    user = Accounts.get_user_by_email("emil@example.org")
    assert Accounts.roles_for(user) == [:learner, :author]

    assert [%RoleGrant{role: :author, source: :idp_claim, provider_key: "ldap"}] =
             Repo.all(from g in RoleGrant, where: g.user_id == ^user.id)

    wrong = sign_in.("emil", "wrong") |> response(401)
    unknown = sign_in.("nobody", "dev-password") |> response(401)
    assert wrong == unknown
  end
end
