defmodule Espalier.Identity.ConfigTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  # Elixir's Config.Reader, aliased before Config names the identity module.
  alias Config.Reader, as: ConfigReader
  alias Espalier.Identity.{Config, ConfigError, OidcProvider}

  @tenant "3f0c2a9e-7b1d-4e5a-8c6f-2d9b0e4a1c7d"

  defp env(key, vars) do
    prefix = "AUTH_#{String.upcase(key)}_"

    vars
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
    |> Map.new(fn {name, value} -> {prefix <> name, value} end)
    |> Map.put("AUTH_PROVIDERS", key)
    |> Map.put("PUBLIC_URL", "https://learn.example.org")
  end

  defp entra(vars \\ %{}) do
    env(
      "entra",
      Map.merge(
        %{
          "TYPE" => "entra",
          "LABEL" => "Microsoft 365",
          "TENANT_ID" => @tenant,
          "CLIENT_ID" => "client",
          "CLIENT_CERT_FILE" => "/run/secrets/entra.crt",
          "CLIENT_KEY_FILE" => "/run/secrets/entra.key"
        },
        vars
      )
    )
  end

  defp google(vars \\ %{}) do
    env(
      "google",
      Map.merge(
        %{
          "TYPE" => "google",
          "LABEL" => "Google",
          "CLIENT_ID" => "client",
          "CLIENT_SECRET" => "secret-value",
          "HOSTED_DOMAIN" => "Example.org"
        },
        vars
      )
    )
  end

  defp oidc(vars \\ %{}) do
    env(
      "corp",
      Map.merge(
        %{
          "TYPE" => "oidc",
          "LABEL" => "Company",
          "ISSUER" => "https://id.example.org",
          "CLIENT_ID" => "client",
          "CLIENT_SECRET" => "secret-value"
        },
        vars
      )
    )
  end

  defp parse!(env, config_env \\ :prod) do
    [provider] = Config.parse!(env, config_env)
    provider
  end

  test "no AUTH_PROVIDERS, or a blank one, means no external provider" do
    assert Config.parse!(%{}, :prod) == []
    assert Config.parse!(%{"AUTH_PROVIDERS" => "  "}, :prod) == []
  end

  test "an invalid key names AUTH_PROVIDERS" do
    assert_raise ConfigError, ~r/AUTH_PROVIDERS/, fn ->
      Config.parse!(%{"AUTH_PROVIDERS" => "Bad"}, :prod)
    end
  end

  test "a repeated key names AUTH_PROVIDERS" do
    assert_raise ConfigError, ~r/AUTH_PROVIDERS/, fn ->
      Config.parse!(%{"AUTH_PROVIDERS" => "entra, entra"}, :prod)
    end
  end

  test "a key without AUTH_<KEY>_TYPE names that variable" do
    assert_raise ConfigError, "AUTH_ENTRA_TYPE is required", fn ->
      Config.parse!(%{"AUTH_PROVIDERS" => "entra"}, :prod)
    end
  end

  test "an unknown type names the variable" do
    assert_raise ConfigError, "AUTH_CORP_TYPE=saml is not supported", fn ->
      Config.parse!(%{"AUTH_PROVIDERS" => "corp", "AUTH_CORP_TYPE" => "saml"}, :prod)
    end
  end

  test "public_entry/1 returns exactly the five public fields" do
    provider = %{
      key: "corp",
      type: "oidc",
      kind: "redirect",
      label: "Company",
      start_url: "/auth/oidc/corp",
      client_secret: "do-not-render"
    }

    entry = Config.public_entry(provider)
    assert Map.keys(entry) |> Enum.sort() == [:key, :kind, :label, :start_url, :type]
    refute inspect(entry) =~ "do-not-render"
  end

  describe "OIDC types" do
    test "entra derives issuer, worker, redirect URI and certificate client" do
      provider = parse!(entra(%{"TENANT_ID" => String.upcase(@tenant)}))

      assert %OidcProvider{
               key: "entra",
               type: "entra",
               kind: "redirect",
               start_url: "/auth/oidc/entra",
               tenant_id: @tenant,
               client_auth: :private_key_jwt,
               kid_format: :x5t_s256,
               role_claim: "roles",
               mfa: :local,
               mfa_amr: ["mfa"],
               provision: true,
               allowed_hosts: ["login.microsoftonline.com"]
             } = provider

      assert provider.issuer == "https://login.microsoftonline.com/#{@tenant}/v2.0"
      assert provider.redirect_uri == "https://learn.example.org/auth/oidc/entra/callback"
      assert provider.worker == Espalier.Identity.Oidc.Provider.Entra
    end

    test "every required variable is named per type" do
      for {build, names} <- [
            {&entra/1, ["LABEL", "CLIENT_ID", "TENANT_ID"]},
            {&google/1, ["LABEL", "CLIENT_ID", "HOSTED_DOMAIN", "CLIENT_SECRET"]},
            {&oidc/1, ["LABEL", "CLIENT_ID", "ISSUER", "CLIENT_SECRET"]}
          ],
          name <- names do
        env = build.(%{name => " "})
        [type_var] = env |> Map.keys() |> Enum.filter(&String.ends_with?(&1, "_TYPE"))
        variable = String.replace_suffix(type_var, "TYPE", name)

        assert_raise ConfigError, ~r/\A#{variable} is required/, fn -> parse!(env) end
      end
    end

    test "the message names the variable and the type" do
      assert_raise ConfigError,
                   "AUTH_ENTRA_TENANT_ID is required when AUTH_ENTRA_TYPE=entra",
                   fn ->
                     parse!(entra(%{"TENANT_ID" => ""}))
                   end
    end

    test "a tenant id must be a GUID, and an entra issuer must end in it" do
      assert_raise ConfigError, ~r/AUTH_ENTRA_TENANT_ID must be a GUID/, fn ->
        parse!(entra(%{"TENANT_ID" => "contoso"}))
      end

      assert_raise ConfigError, ~r/AUTH_ENTRA_ISSUER must end in/, fn ->
        parse!(entra(%{"ISSUER" => "https://login.microsoftonline.com/common/v2.0"}))
      end
    end

    test "outside dev and test, http issuers and Entra secrets are refused" do
      assert_raise ConfigError, ~r/AUTH_CORP_ISSUER must start with https/, fn ->
        parse!(oidc(%{"ISSUER" => "http://id.example.org"}))
      end

      assert parse!(oidc(%{"ISSUER" => "http://localhost:4011/oidc"}), :test).issuer ==
               "http://localhost:4011/oidc"

      assert_raise ConfigError, ~r/AUTH_ENTRA_CLIENT_SECRET is refused/, fn ->
        parse!(entra(%{"CLIENT_SECRET" => "dev"}))
      end

      assert_raise ConfigError,
                   ~r/AUTH_ENTRA_CLIENT_CERT_FILE and AUTH_ENTRA_CLIENT_KEY_FILE are required/,
                   fn ->
                     parse!(entra(%{"CLIENT_CERT_FILE" => nil, "CLIENT_KEY_FILE" => nil}))
                   end

      dev =
        parse!(
          entra(%{"CLIENT_CERT_FILE" => nil, "CLIENT_KEY_FILE" => nil, "CLIENT_SECRET" => "dev"}),
          :dev
        )

      assert dev.client_auth == :client_secret_basic
      assert dev.client_secret == "dev"
    end

    test "certificate and key come together" do
      assert_raise ConfigError, ~r/must be set together/, fn ->
        parse!(entra(%{"CLIENT_KEY_FILE" => nil}))
      end
    end

    test "kid format and client authentication" do
      assert parse!(entra(%{"CLIENT_KID_FORMAT" => "sha1_hex"})).kid_format == :sha1_hex

      assert_raise ConfigError, ~r/AUTH_ENTRA_CLIENT_KID_FORMAT must be one of/, fn ->
        parse!(entra(%{"CLIENT_KID_FORMAT" => "md5"}))
      end

      assert parse!(oidc()).client_auth == :client_secret_basic

      assert parse!(oidc(%{"CLIENT_AUTH" => "client_secret_post"})).client_auth ==
               :client_secret_post

      with_cert =
        oidc(%{
          "CLIENT_SECRET" => nil,
          "CLIENT_CERT_FILE" => "/run/c.crt",
          "CLIENT_KEY_FILE" => "/run/c.key"
        })

      assert parse!(with_cert).client_auth == :private_key_jwt

      assert_raise ConfigError, ~r/requires AUTH_CORP_CLIENT_CERT_FILE/, fn ->
        parse!(oidc(%{"CLIENT_AUTH" => "private_key_jwt"}))
      end
    end

    test "role maps: roles may repeat, google and learner are refused" do
      provider = parse!(entra(%{"ROLE_MAP" => "\"admin=Espalier.Admin; author=A;author=B\""}))
      assert provider.role_map == [admin: "Espalier.Admin", author: "A", author: "B"]

      assert_raise ConfigError, ~r/AUTH_GOOGLE_ROLE_MAP is not supported/, fn ->
        parse!(google(%{"ROLE_MAP" => "admin=x"}))
      end

      assert_raise ConfigError, ~r/AUTH_ENTRA_ROLE_MAP maps learner/, fn ->
        parse!(entra(%{"ROLE_MAP" => "learner=x"}))
      end

      assert_raise ConfigError, ~r/AUTH_ENTRA_ROLE_MAP names a role/, fn ->
        parse!(entra(%{"ROLE_MAP" => "owner=x"}))
      end

      assert_raise ConfigError, ~r/AUTH_ENTRA_ROLE_MAP must have the form/, fn ->
        parse!(entra(%{"ROLE_MAP" => "admin"}))
      end

      assert parse!(oidc(%{"ROLE_CLAIM" => "groups"})).role_claim == "groups"
      assert parse!(google()).role_claim == nil
    end

    test "MFA mode and amr values" do
      assert parse!(google(%{"MFA" => "idp_trusted", "MFA_AMR" => "mfa, hwk"})).mfa_amr ==
               ["mfa", "hwk"]

      assert parse!(google(%{"MFA_AMR" => ""})).mfa_amr == ["mfa"]

      assert_raise ConfigError, ~r/AUTH_GOOGLE_MFA_AMR must list at least one value/, fn ->
        parse!(google(%{"MFA_AMR" => " , "}))
      end

      assert_raise ConfigError, ~r/AUTH_GOOGLE_MFA must be one of/, fn ->
        parse!(google(%{"MFA" => "always"}))
      end
    end

    test "provisioning defaults per type" do
      assert parse!(entra()).provision
      assert parse!(google()).provision
      refute parse!(oidc()).provision
      assert parse!(oidc(%{"PROVISION" => "true"})).provision
    end

    test "allowed hosts: defaults per type, lower case, and no scheme, path or port" do
      assert parse!(oidc()).allowed_hosts == ["id.example.org"]

      assert parse!(google()).allowed_hosts == [
               "accounts.google.com",
               "oauth2.googleapis.com",
               "www.googleapis.com"
             ]

      assert parse!(oidc(%{"ALLOWED_HOSTS" => "ID.Example.org, keys.example.org"})).allowed_hosts ==
               ["id.example.org", "keys.example.org"]

      for entry <- ["https://id.example.org", "id.example.org/path", "id.example.org:443"] do
        assert_raise ConfigError, ~r/AUTH_CORP_ALLOWED_HOSTS holds an entry/, fn ->
          parse!(oidc(%{"ALLOWED_HOSTS" => entry}))
        end
      end
    end

    test "values lose surrounding whitespace and one pair of double quotes" do
      provider =
        parse!(
          google(%{"LABEL" => "  \"Google Workspace\"  ", "HOSTED_DOMAIN" => "\"example.org\""})
        )

      assert provider.label == "Google Workspace"
      assert provider.hosted_domain == "example.org"
    end

    test "public_entry/1 of an OIDC provider carries kind and start_url and no secret" do
      provider = parse!(google())
      entry = Config.public_entry(provider)

      assert entry == %{
               key: "google",
               type: "google",
               kind: "redirect",
               label: "Google",
               start_url: "/auth/oidc/google"
             }

      refute inspect(entry) =~ "secret-value"
      refute inspect(provider) =~ "secret-value"
    end

    test "a type outside entra, google and oidc is refused" do
      assert_raise ConfigError, "AUTH_CORP_TYPE=saml is not supported", fn ->
        parse!(oidc(%{"TYPE" => "saml"}))
      end
    end

    test "the supervisor logs a warning at boot for idp_trusted" do
      provider = parse!(google(%{"MFA" => "idp_trusted"}), :test)

      log =
        capture_log([level: :warning], fn ->
          Espalier.Identity.Oidc.Supervisor.init(providers: [%{provider | key: "warned"}])
        end)

      assert log =~ "AUTH_WARNED_MFA=idp_trusted"
    end
  end

  describe "filter_parameters" do
    test "covers the entries of 0004 and the OIDC values" do
      # Phoenix compiles the list at boot, so the test reads the configuration file.
      filters =
        "config/config.exs"
        |> ConfigReader.read!(env: :test, target: :host)
        |> get_in([:phoenix, :filter_parameters])

      ours = ~w(state session_state ticket intent sid id_token)

      for key <-
            ~w(password current_password email token code secret recovery_code totp passkey
               credential response rawId) ++ ours do
        assert key in filters
      end

      params = Map.new(ours, &{&1, "plain"})
      filtered = Phoenix.Logger.filter_values(params)
      assert Enum.all?(filtered, fn {_key, value} -> value == "[FILTERED]" end)
    end
  end
end
