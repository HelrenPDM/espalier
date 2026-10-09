defmodule Espalier.Identity.LdapConfigTest do
  # Parsing of the AUTH_<KEY>_* variables of an LDAP provider (task 0007,
  # step 26).
  use ExUnit.Case, async: true

  alias Espalier.FakeLdapServer
  alias Espalier.Identity.Config
  alias Espalier.Identity.ConfigError
  alias Espalier.Identity.Ldap.Config, as: LdapConfig

  @moduletag :tmp_dir
  @bind_password "invented-bind-password-7f3a"

  setup %{tmp_dir: tmp_dir} do
    %{cacerts: [der | _]} = FakeLdapServer.tls_fixture()
    ca_file = Path.join(tmp_dir, "ca.pem")
    File.write!(ca_file, :public_key.pem_encode([{:Certificate, der, :not_encrypted}]))

    env = %{
      "AUTH_PROVIDERS" => "ldap",
      "AUTH_LDAP_TYPE" => "ldap",
      "AUTH_LDAP_LABEL" => "\"Directory account\"",
      "AUTH_LDAP_HOST" => "dc01.example.org",
      "AUTH_LDAP_CA_CERT_FILE" => ca_file,
      "AUTH_LDAP_BIND_DN" => "CN=espalier-svc,OU=Service,DC=example,DC=org",
      "AUTH_LDAP_BIND_PASSWORD" => @bind_password,
      "AUTH_LDAP_BASE_DN" => "DC=example,DC=org",
      "AUTH_LDAP_ROLE_MAP" =>
        "\"author=CN=Authors,OU=Groups,DC=example,DC=org;admin=CN=Admins,OU=Groups,DC=example,DC=org;analyst=CN=Authors,OU=Groups,DC=example,DC=org\"",
      "AUTH_LDAP_FAILURE_LIMIT" => "4"
    }

    %{env: env, der: der, tmp_dir: tmp_dir}
  end

  defp parse!(env, config_env \\ :prod), do: LdapConfig.parse!("ldap", env, config_env)

  defp assert_config_error(env, config_env \\ :prod, message) do
    error = assert_raise ConfigError, fn -> parse!(env, config_env) end
    assert error.message =~ message
    refute error.message =~ @bind_password
    error
  end

  test "a complete set returns the struct with the defaults of the ad profile", %{
    env: env,
    der: der
  } do
    config = parse!(env)

    assert %LdapConfig{
             key: "ldap",
             type: "ldap",
             kind: "credentials",
             label: "Directory account",
             start_url: "/api/auth/ldap/ldap",
             client: Espalier.Identity.Ldap.Eldap,
             host: ~c"dc01.example.org",
             port: 636,
             tls: :ldaps,
             cacerts: [^der],
             tls_wildcard: false,
             directory: :ad,
             user_attrs: [~c"sAMAccountName", ~c"userPrincipalName"],
             org_unit_attr: nil,
             mfa: :local,
             timeout_ms: 5000,
             failure_limit: 4,
             lock_minutes: 30,
             provision: true
           } = config

    assert config.role_map == [
             {:author, "CN=Authors,OU=Groups,DC=example,DC=org"},
             {:admin, "CN=Admins,OU=Groups,DC=example,DC=org"},
             {:analyst, "CN=Authors,OU=Groups,DC=example,DC=org"}
           ]

    assert config.bind_password == @bind_password
    refute inspect(config) =~ @bind_password
  end

  test "public_entry/1 returns the public fields only", %{env: env} do
    assert Config.public_entry(parse!(env)) == %{
             key: "ldap",
             type: "ldap",
             kind: "credentials",
             label: "Directory account",
             start_url: "/api/auth/ldap/ldap"
           }
  end

  test "Identity.Config.parse!/2 dispatches the type ldap", %{env: env} do
    assert [%LdapConfig{key: "ldap"}] = Config.parse!(env, :prod)
  end

  test "Identity.Config.parse!/2 requires AUTH_LDAP_TYPE", %{env: env} do
    error =
      assert_raise ConfigError, fn -> Config.parse!(Map.delete(env, "AUTH_LDAP_TYPE"), :prod) end

    assert error.message == "AUTH_LDAP_TYPE is required"
  end

  test "the generic profile, StartTLS and the optional values", %{env: env} do
    config =
      env
      |> Map.merge(%{
        "AUTH_LDAP_DIRECTORY" => "generic",
        "AUTH_LDAP_TLS" => "starttls",
        "AUTH_LDAP_TLS_WILDCARD" => "true",
        "AUTH_LDAP_ORG_UNIT_ATTR" => "department",
        "AUTH_LDAP_TIMEOUT_MS" => "2500",
        "AUTH_LDAP_LOCK_MINUTES" => "45",
        "AUTH_LDAP_MFA" => "local"
      })
      |> parse!()

    assert config.directory == :generic
    assert config.user_attrs == [~c"uid"]
    assert config.tls == :starttls
    assert config.port == 389
    assert config.tls_wildcard
    assert config.org_unit_attr == ~c"department"
    assert config.timeout_ms == 2500
    assert config.lock_minutes == 45
  end

  test "TLS none is refused outside dev and test", %{env: env} do
    env = Map.put(env, "AUTH_LDAP_TLS", "none")
    error = assert_config_error(env, "AUTH_LDAP_TLS=none")
    assert error.message == "AUTH_LDAP_TLS=none is allowed only in dev and test"

    config = parse!(Map.put(env, "AUTH_LDAP_HOST", "127.0.0.1"), :test)
    assert config.tls == :none
    assert config.host == ~c"127.0.0.1"
    assert config.port == 389
    assert config.cacerts == []
  end

  test "an MFA mode other than local fails the boot", %{env: env} do
    assert_config_error(Map.put(env, "AUTH_LDAP_MFA", "idp_trusted"), "AUTH_LDAP_MFA")
  end

  test "a missing failure limit or label fails the boot", %{env: env} do
    assert_config_error(Map.delete(env, "AUTH_LDAP_FAILURE_LIMIT"), "AUTH_LDAP_FAILURE_LIMIT")
    assert_config_error(Map.put(env, "AUTH_LDAP_LABEL", "  "), "AUTH_LDAP_LABEL")
  end

  test "the failure limit stays from 1 to 49", %{env: env} do
    for value <- ["0", "50", "five", "4.5"] do
      assert_config_error(
        Map.put(env, "AUTH_LDAP_FAILURE_LIMIT", value),
        "AUTH_LDAP_FAILURE_LIMIT"
      )
    end

    assert parse!(Map.put(env, "AUTH_LDAP_FAILURE_LIMIT", "49")).failure_limit == 49
  end

  test "an IP literal host with ldaps or starttls fails the boot", %{env: env} do
    for host <- ["192.0.2.10", "::1"], tls <- ["ldaps", "starttls"] do
      env = Map.merge(env, %{"AUTH_LDAP_HOST" => host, "AUTH_LDAP_TLS" => tls})
      assert_config_error(env, :test, "AUTH_LDAP_HOST")
    end
  end

  test "a host with more than one name fails the boot", %{env: env} do
    assert_config_error(Map.put(env, "AUTH_LDAP_HOST", "dc01.example.org dc02"), "AUTH_LDAP_HOST")
  end

  test "a CA file without a certificate or that cannot be read fails the boot", %{
    env: env,
    tmp_dir: tmp_dir
  } do
    empty = Path.join(tmp_dir, "empty.pem")
    File.write!(empty, "no certificate here\n")
    assert_config_error(Map.put(env, "AUTH_LDAP_CA_CERT_FILE", empty), "AUTH_LDAP_CA_CERT_FILE")

    missing = Path.join(tmp_dir, "missing.pem")
    assert_config_error(Map.put(env, "AUTH_LDAP_CA_CERT_FILE", missing), "AUTH_LDAP_CA_CERT_FILE")
    assert_config_error(Map.delete(env, "AUTH_LDAP_CA_CERT_FILE"), "AUTH_LDAP_CA_CERT_FILE")
  end

  test "the bind credentials are required", %{env: env} do
    assert_config_error(Map.delete(env, "AUTH_LDAP_BIND_DN"), "AUTH_LDAP_BIND_DN")
    assert_config_error(Map.put(env, "AUTH_LDAP_BIND_PASSWORD", " "), "AUTH_LDAP_BIND_PASSWORD")
  end

  test "invalid attribute names, ports, timeouts and roles fail the boot", %{env: env} do
    assert_config_error(Map.put(env, "AUTH_LDAP_USER_ATTR", "uid,(cn)"), "AUTH_LDAP_USER_ATTR")
    assert_config_error(Map.put(env, "AUTH_LDAP_ORG_UNIT_ATTR", "1ou"), "AUTH_LDAP_ORG_UNIT_ATTR")
    assert_config_error(Map.put(env, "AUTH_LDAP_PORT", "65536"), "AUTH_LDAP_PORT")
    assert_config_error(Map.put(env, "AUTH_LDAP_TIMEOUT_MS", "0"), "AUTH_LDAP_TIMEOUT_MS")
    assert_config_error(Map.put(env, "AUTH_LDAP_TLS", "plain"), "AUTH_LDAP_TLS")
    assert_config_error(Map.put(env, "AUTH_LDAP_DIRECTORY", "openldap"), "AUTH_LDAP_DIRECTORY")
    assert_config_error(Map.put(env, "AUTH_LDAP_ROLE_MAP", "owner=CN=x"), "AUTH_LDAP_ROLE_MAP")
    assert_config_error(Map.put(env, "AUTH_LDAP_ROLE_MAP", "learner=CN=x"), "AUTH_LDAP_ROLE_MAP")
    assert_config_error(Map.put(env, "AUTH_LDAP_TLS_WILDCARD", "yes"), "AUTH_LDAP_TLS_WILDCARD")
  end
end
