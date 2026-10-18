defmodule Espalier.BootCheckTest do
  @moduledoc """
  `Espalier.BootCheck.errors/2` (task 0017, step 4): each kind of message,
  several messages from one call, and no secret value in any message; and
  the line of effective settings that the boot logs
  (`Espalier.Application.settings_line/1`), with fixed settings.
  """
  use ExUnit.Case, async: true

  alias Espalier.BootCheck

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    ca_file = Path.join(tmp_dir, "ca.pem")
    File.write!(ca_file, "")

    env = %{
      "DATABASE_URL" => "ecto://postgres:db-password@db/espalier_prod",
      "SECRET_KEY_BASE" => String.duplicate("k", 64),
      "PHX_HOST" => "learn.example.org",
      "PUBLIC_URL" => "https://learn.example.org",
      "DATABASE_CA_CERT_FILE" => ca_file,
      "CLOAK_KEY_V1" => Base.encode64(:binary.copy(<<1>>, 32)),
      "CLOAK_HMAC_SECRET" => Base.encode64(:binary.copy(<<2>>, 32)),
      "EXPORT_DIR" => "/data/exports",
      "MEDIA_DIR" => "/data/media"
    }

    %{env: env}
  end

  # The tool check of the media processing is stubbed, so that no test
  # starts a process (task 0018, step 2).
  defp errors(env, config_env, tools \\ fn -> [] end),
    do: BootCheck.errors(env, config_env, tools)

  describe "the tool check of the media processing" do
    test "runs in production and adds its messages after the production rules", %{env: env} do
      tools = fn -> ["ffmpeg lacks the encoder libvpx-vp9", "ffmpeg 6.1 is older than 7.1"] end

      assert errors(env, :prod, tools) == [
               "ffmpeg lacks the encoder libvpx-vp9",
               "ffmpeg 6.1 is older than 7.1"
             ]

      assert errors(Map.delete(env, "PHX_HOST"), :prod, tools) == [
               "Missing environment variables: PHX_HOST",
               "ffmpeg lacks the encoder libvpx-vp9",
               "ffmpeg 6.1 is older than 7.1"
             ]
    end

    test "does not run in development and tests" do
      tools = fn -> flunk("the tool check runs in production only") end
      assert errors(%{}, :dev, tools) == []
      assert errors(%{}, :test, tools) == []
    end

    test "a missing MEDIA_DIR is reported by RuntimeConfig alone", %{env: env} do
      assert errors(Map.delete(env, "MEDIA_DIR"), :prod) == ["MEDIA_DIR is required"]
    end
  end

  test "a complete production environment has no gap", %{env: env} do
    assert errors(env, :prod) == []
    assert errors(Map.put(env, "PUBLIC_URL", "https://learn.example.org/"), :prod) == []

    # RuntimeConfig lower-cases the host, the form of the origin that
    # browsers send, so a host in other letter case equals PHX_HOST.
    mixed_case = Map.put(env, "PUBLIC_URL", "https://LEARN.example.org")
    assert errors(mixed_case, :prod) == []

    assert Espalier.RuntimeConfig.parse!(mixed_case, :prod)[:public_url] ==
             "https://learn.example.org"

    # Values with surrounding whitespace or double quotes, as
    # `docker run --env-file` passes them.
    quoted =
      Map.merge(env, %{
        "DATABASE_URL" => ~s(" ecto://postgres:db-password@db/espalier_prod "),
        "PHX_HOST" => ~s("learn.example.org"),
        "SMTP_HOST" => " smtp.example.org ",
        "SMTP_PORT" => ~s("465"),
        "MAIL_FROM" => "noreply@example.org"
      })

    assert errors(quoted, :prod) == []
  end

  test "development and tests need none of the production variables" do
    assert errors(%{}, :dev) == []
    assert errors(%{}, :test) == []
  end

  describe "required variables in production" do
    test "one message names every missing variable" do
      assert [missing | rest] = errors(%{}, :prod)

      assert missing ==
               "Missing environment variables: DATABASE_URL, SECRET_KEY_BASE, PHX_HOST, " <>
                 "DATABASE_CA_CERT_FILE, CLOAK_KEY_V1, CLOAK_HMAC_SECRET"

      # RuntimeConfig names PUBLIC_URL, EXPORT_DIR and MEDIA_DIR once each.
      assert rest == ["PUBLIC_URL is required", "EXPORT_DIR is required", "MEDIA_DIR is required"]
    end

    test "an empty or whitespace-only value counts as missing", %{env: env} do
      for name <- ["DATABASE_URL", "SECRET_KEY_BASE", "PHX_HOST", "DATABASE_CA_CERT_FILE"],
          blank <- ["", "   ", ~s("")] do
        assert "Missing environment variables: #{name}" in errors(
                 Map.put(env, name, blank),
                 :prod
               )
      end
    end

    test "the Cloak variables as task 0003 names them", %{env: env} do
      without_keys = Map.delete(env, "CLOAK_KEY_V1")

      assert "Missing environment variables: CLOAK_KEY_V1" in errors(
               without_keys,
               :prod
             )

      # Any CLOAK_KEY_V<n> counts, a name with a leading zero does not.
      assert errors(Map.put(without_keys, "CLOAK_KEY_V2", env["CLOAK_KEY_V1"]), :prod) ==
               []

      assert "Missing environment variables: CLOAK_KEY_V1" in errors(
               Map.put(without_keys, "CLOAK_KEY_V01", env["CLOAK_KEY_V1"]),
               :prod
             )

      assert "Missing environment variables: CLOAK_HMAC_SECRET" in errors(
               Map.put(env, "CLOAK_HMAC_SECRET", " "),
               :prod
             )

      # An empty pair of double quotes counts as missing for both variables.
      assert "Missing environment variables: CLOAK_KEY_V1, CLOAK_HMAC_SECRET" in errors(
               Map.merge(env, %{"CLOAK_KEY_V1" => ~s(""), "CLOAK_HMAC_SECRET" => ~s("")}),
               :prod
             )
    end

    test "SECRET_KEY_BASE needs at least 64 bytes", %{env: env} do
      assert errors(Map.put(env, "SECRET_KEY_BASE", String.duplicate("k", 63)), :prod) ==
               [
                 "SECRET_KEY_BASE is shorter than 64 bytes; generate one with mix phx.gen.secret"
               ]
    end

    test "DATABASE_CA_CERT_FILE must name a file", %{env: env, tmp_dir: tmp_dir} do
      for path <- [Path.join(tmp_dir, "missing.pem"), tmp_dir] do
        assert errors(Map.put(env, "DATABASE_CA_CERT_FILE", path), :prod) ==
                 ["DATABASE_CA_CERT_FILE names no file"]
      end
    end

    test "DATABASE_URL must have a host and a database name", %{env: env} do
      for url <- [
            "not a url",
            "ecto:///espalier_prod",
            "postgres:espalier_prod",
            "ecto://postgres:db-password@db",
            "ecto://postgres:db-password@db/",
            "ecto://postgres:db-password@db/espalier_prod/",
            "ecto://postgres:db-password@db/espalier/prod"
          ] do
        assert errors(Map.put(env, "DATABASE_URL", url), :prod) ==
                 ["DATABASE_URL must be an ecto:// URL with a host and a database name"],
               url
      end
    end

    test "DATABASE_URL gives timeout, pool_size and idle_interval as integers", %{env: env} do
      url = "ecto://postgres:db-password@db/espalier_prod"

      assert errors(
               Map.put(env, "DATABASE_URL", url <> "?pool_size=5&timeout=15000"),
               :prod
             ) ==
               []

      for query <- ["pool_size=ten", "timeout=1.5", "idle_interval="] do
        assert errors(Map.put(env, "DATABASE_URL", "#{url}?#{query}"), :prod) ==
                 ["DATABASE_URL must give timeout, pool_size and idle_interval as integers"],
               query
      end
    end

    test "PORT and POOL_SIZE must be numbers", %{env: env} do
      assert errors(
               Map.merge(env, %{"PORT" => ~s("4000"), "POOL_SIZE" => " 20 "}),
               :prod
             ) ==
               []

      assert errors(Map.merge(env, %{"PORT" => "http", "POOL_SIZE" => "0"}), :prod) ==
               [
                 "PORT must be a port number from 1 to 65535",
                 "POOL_SIZE must be a positive integer"
               ]

      # PORT applies in every environment, POOL_SIZE in production only.
      assert errors(%{"PORT" => "70000", "POOL_SIZE" => "x"}, :dev) ==
               ["PORT must be a port number from 1 to 65535"]
    end

    test "DATABASE_URL must not set ssl, which Ecto would merge over the TLS options",
         %{env: env} do
      for query <- ["ssl=false", "ssl=true", "pool_size=5&ssl=false", "s%73l=false", "ssl"] do
        assert errors(
                 Map.put(
                   env,
                   "DATABASE_URL",
                   "ecto://postgres:db-password@db/espalier_prod?" <> query
                 ),
                 :prod
               ) == ["DATABASE_URL must not set ssl; TLS comes from DATABASE_CA_CERT_FILE"],
               query
      end

      for query <- ["pool_size=5", "sslmode=disable", "SSL=false"] do
        assert errors(
                 Map.put(
                   env,
                   "DATABASE_URL",
                   "ecto://postgres:db-password@db/espalier_prod?" <> query
                 ),
                 :prod
               ) == [],
               query
      end
    end

    test "SMTP is optional, and MAIL_FROM is required only with SMTP_HOST", %{env: env} do
      assert errors(env, :prod) == []

      assert errors(Map.put(env, "SMTP_HOST", "smtp.example.org"), :prod) ==
               ["MAIL_FROM is required with SMTP_HOST"]
    end

    test "SMTP_PORT must be a port number", %{env: env} do
      for port <- ["587", "465", "1", "65535"] do
        assert errors(Map.put(env, "SMTP_PORT", port), :prod) == [], port
      end

      for port <- ["0", "65536", "-1", "587a", "smtp", "5.87"] do
        assert errors(Map.put(env, "SMTP_PORT", port), :prod) ==
                 ["SMTP_PORT must be a port number from 1 to 65535"],
               port
      end
    end
  end

  describe "PUBLIC_URL in production" do
    test "needs the https scheme", %{env: env} do
      assert errors(Map.put(env, "PUBLIC_URL", "http://learn.example.org"), :prod) ==
               [
                 "PUBLIC_URL must use https in production, because passkeys derive their origin from it"
               ]

      # Development and tests accept http.
      assert errors(%{"PUBLIC_URL" => "http://localhost:5173"}, :dev) == []
    end

    test "is an origin without user info, path, query or fragment", %{env: env} do
      for url <- [
            "https://user:pw@learn.example.org",
            "https://user@learn.example.org/",
            "https://@learn.example.org",
            "https://learn.example.org/espalier",
            "https://learn.example.org/?a=1",
            "https://learn.example.org/#top"
          ] do
        assert errors(Map.put(env, "PUBLIC_URL", url), :prod) ==
                 ["PUBLIC_URL must be an origin without user info, path, query or fragment"],
               url
      end
    end

    test "has the host of PHX_HOST", %{env: env} do
      assert errors(Map.put(env, "PUBLIC_URL", "https://other.example.org"), :prod) ==
               ["The host of PUBLIC_URL must equal PHX_HOST"]

      # A port does not change the host.
      assert errors(Map.put(env, "PUBLIC_URL", "https://learn.example.org:8443"), :prod) ==
               []
    end

    test "that is no URL comes from RuntimeConfig alone", %{env: env} do
      assert errors(Map.put(env, "PUBLIC_URL", "learn.example.org"), :prod) ==
               ["PUBLIC_URL must be an http or https URL"]
    end
  end

  describe "sign-in pathway" do
    @pathway "No sign-in pathway: LOCAL_ACCOUNTS=false, AUTH_DEMO is not true " <>
               "and AUTH_PROVIDERS names no provider"

    test "LOCAL_ACCOUNTS=false without demo sign-in and providers has none" do
      assert errors(%{"LOCAL_ACCOUNTS" => "false"}, :dev) == [@pathway]

      assert errors(%{"LOCAL_ACCOUNTS" => "false", "AUTH_PROVIDERS" => " "}, :dev) == [
               @pathway
             ]

      assert errors(%{"LOCAL_ACCOUNTS" => "false", "AUTH_DEMO" => "false"}, :dev) ==
               [@pathway]
    end

    test "local accounts, demo sign-in or a provider is a pathway" do
      assert errors(%{}, :dev) == []
      assert errors(%{"LOCAL_ACCOUNTS" => "true"}, :dev) == []

      # The demo profile of decision D5 (.env.demo.example).
      assert errors(
               %{"LOCAL_ACCOUNTS" => "false", "AUTH_DEMO" => "true", "AUTH_PROVIDERS" => ""},
               :dev
             ) == []

      assert errors(
               %{
                 "LOCAL_ACCOUNTS" => "false",
                 "AUTH_PROVIDERS" => "corp",
                 "AUTH_CORP_TYPE" => "oidc",
                 "AUTH_CORP_LABEL" => "Company sign-in",
                 "AUTH_CORP_ISSUER" => "https://id.example.org",
                 "AUTH_CORP_CLIENT_ID" => "espalier",
                 "AUTH_CORP_CLIENT_SECRET" => "client-secret-value"
               },
               :dev
             ) == []
    end
  end

  describe "identity providers" do
    test "the message of the ConfigError names the variable" do
      assert errors(%{"AUTH_PROVIDERS" => "corp"}, :dev) == [
               "AUTH_CORP_TYPE is required"
             ]
    end

    test "AUTH_<KEY>_TLS=none of an LDAP provider in production", %{env: env} do
      env =
        Map.merge(env, %{
          "AUTH_PROVIDERS" => "dir",
          "AUTH_DIR_TYPE" => "ldap",
          "AUTH_DIR_TLS" => "none"
        })

      assert [message] = errors(env, :prod)
      assert message =~ "AUTH_DIR_TLS"
    end

    test "AUTH_<KEY>_MFA of an LDAP provider accepts local only", %{tmp_dir: tmp_dir} do
      ca_file = Path.join(tmp_dir, "ldap-ca.pem")

      File.write!(
        ca_file,
        :public_key.pem_encode([{:Certificate, "not-a-real-der", :not_encrypted}])
      )

      env = %{
        "AUTH_PROVIDERS" => "dir",
        "AUTH_DIR_TYPE" => "ldap",
        "AUTH_DIR_LABEL" => "Directory",
        "AUTH_DIR_HOST" => "ldap.example.org",
        "AUTH_DIR_CA_CERT_FILE" => ca_file,
        "AUTH_DIR_BIND_DN" => "cn=svc,dc=example,dc=org",
        "AUTH_DIR_BIND_PASSWORD" => "bind-password-value",
        "AUTH_DIR_BASE_DN" => "dc=example,dc=org",
        "AUTH_DIR_FAILURE_LIMIT" => "5",
        "AUTH_DIR_MFA" => "idp_trusted"
      }

      assert [message] = errors(env, :dev)
      assert message =~ "AUTH_DIR_MFA"
      assert errors(Map.put(env, "AUTH_DIR_MFA", "local"), :dev) == []
    end
  end

  test "the messages of RuntimeConfig.errors/2 for each invalid setting" do
    env = %{
      "SESSION_IDLE_MINUTES" => "0",
      "SIGNUP" => "open",
      "PASSWORD_BREACH_CHECK" => "on",
      "TRACKING_DETAIL" => "full",
      "REGISTRAR_ENABLED" => "yes",
      "INSIGHTS_ORG_UNIT" => "1",
      "FEEDBACK_FREE_TEXT" => "TRUE",
      "TEST_NOTES" => "no",
      "INSIGHTS_MIN_GROUP_SIZE" => "0",
      "CREDENTIAL_NOTICE_DAYS" => "-1",
      "CREDENTIAL_GRACE_DAYS" => "x",
      "RETENTION_AUDIT_DAYS" => "1.5",
      "WEBHOOK_ALLOWED_HOSTS" => "https://hooks.example.org",
      "TRUSTED_PROXIES" => "10.0.0.0/33",
      "PACK_UPLOAD_MAX_MB" => "0",
      "BOOTSTRAP_ADMIN_EMAILS" => "admin",
      "ADMIN_REQUIRE_PASSKEY" => "maybe",
      "PUBLIC_URL" => "ftp://learn.example.org"
    }

    errors = errors(env, :dev)

    for name <- [
          "SESSION_IDLE_MINUTES",
          "SIGNUP",
          "PASSWORD_BREACH_CHECK",
          "TRACKING_DETAIL",
          "REGISTRAR_ENABLED",
          "INSIGHTS_ORG_UNIT",
          "FEEDBACK_FREE_TEXT",
          "TEST_NOTES",
          "INSIGHTS_MIN_GROUP_SIZE",
          "CREDENTIAL_NOTICE_DAYS",
          "CREDENTIAL_GRACE_DAYS",
          "RETENTION_AUDIT_DAYS",
          "WEBHOOK_ALLOWED_HOSTS",
          "TRUSTED_PROXIES",
          "PACK_UPLOAD_MAX_MB",
          "BOOTSTRAP_ADMIN_EMAILS",
          "ADMIN_REQUIRE_PASSKEY",
          "PUBLIC_URL"
        ] do
      assert Enum.count(errors, &String.starts_with?(&1, name)) == 1,
             "expected one message for #{name} in #{inspect(errors)}"
    end

    assert length(errors) == 18

    assert "SIGNUP=domain requires SIGNUP_DOMAINS" in errors(
             %{"SIGNUP" => "domain"},
             :dev
           )
  end

  test "one call names several gaps together (acceptance of task 0017)", %{env: env} do
    env =
      env
      |> Map.drop(["SECRET_KEY_BASE", "CLOAK_KEY_V1"])
      |> Map.merge(%{
        "LOCAL_ACCOUNTS" => "false",
        "AUTH_PROVIDERS" => "",
        "TRACKING_DETAIL" => "full"
      })

    assert errors(env, :prod) == [
             "Missing environment variables: SECRET_KEY_BASE, CLOAK_KEY_V1",
             "No sign-in pathway: LOCAL_ACCOUNTS=false, AUTH_DEMO is not true " <>
               "and AUTH_PROVIDERS names no provider",
             "TRACKING_DETAIL must be one of minimal, standard"
           ]
  end

  describe "Espalier.Application.settings_line/1" do
    @names [
      "SESSION_IDLE_MINUTES",
      "SESSION_MAX_HOURS",
      "SESSION_MAX_CONCURRENT",
      "SIGNUP",
      "LOCAL_ACCOUNTS",
      "AUTH_DEMO",
      "PASSWORD_BREACH_CHECK",
      "TRACKING_DETAIL",
      "INSIGHTS_ORG_UNIT",
      "REGISTRAR_ENABLED",
      "INSIGHTS_MIN_GROUP_SIZE",
      "FEEDBACK_FREE_TEXT",
      "TEST_NOTES",
      "RETENTION_ATTEMPTS_DAYS",
      "RETENTION_ITEM_RESPONSES_DAYS",
      "RETENTION_ANONYMOUS_DAYS",
      "RETENTION_AUDIT_DAYS"
    ]

    test "names every setting with its value, false as false and nil as unset" do
      settings = %{
        session_idle_minutes: 60,
        session_max_hours: 24,
        session_max_concurrent: 5,
        signup: :invite,
        local_accounts: true,
        auth_demo: false,
        password_breach_check: :off,
        registrar_enabled: false,
        learning: [tracking_detail: :minimal, insights_org_unit: false],
        insights: [
          min_group_size: 5,
          feedback_free_text: false,
          test_notes: true,
          retention_attempts_days: 365,
          retention_item_responses_days: nil,
          retention_anonymous_days: 730,
          retention_audit_days: nil
        ],
        identity_providers: []
      }

      line = Espalier.Application.settings_line(&Map.get(settings, &1))

      assert line ==
               "Effective settings: SESSION_IDLE_MINUTES=60 SESSION_MAX_HOURS=24 " <>
                 "SESSION_MAX_CONCURRENT=5 SIGNUP=invite LOCAL_ACCOUNTS=true AUTH_DEMO=false " <>
                 "PASSWORD_BREACH_CHECK=off TRACKING_DETAIL=minimal INSIGHTS_ORG_UNIT=false " <>
                 "REGISTRAR_ENABLED=false INSIGHTS_MIN_GROUP_SIZE=5 FEEDBACK_FREE_TEXT=false " <>
                 "TEST_NOTES=true RETENTION_ATTEMPTS_DAYS=365 RETENTION_ITEM_RESPONSES_DAYS=unset " <>
                 "RETENTION_ANONYMOUS_DAYS=730 RETENTION_AUDIT_DAYS=unset; providers: none"

      # Without any setting, every name is present and unset.
      empty = Espalier.Application.settings_line(fn _key -> nil end)

      assert empty ==
               "Effective settings: " <>
                 Enum.map_join(@names, " ", &"#{&1}=unset") <> "; providers: none"
    end

    test "names each provider by key, type and MFA mode and leaves out its other fields" do
      oidc = %Espalier.Identity.OidcProvider{
        key: "corp",
        type: "oidc",
        label: "Company sign-in",
        issuer: "https://id.example.org/realms/staff",
        client_id: "learn-portal-client",
        client_secret: "oidc-client-secret-value",
        client_auth: :client_secret_basic,
        redirect_uri: "https://learn.example.org/auth/oidc/corp/callback",
        start_url: "/auth/oidc/corp",
        allowed_hosts: ["id.example.org"],
        mfa: :idp_trusted
      }

      ldap = %Espalier.Identity.Ldap.Config{
        key: "dir",
        label: "Directory",
        start_url: "/auth/ldap/dir",
        host: ~c"ldap.example.org",
        port: 636,
        bind_dn: "cn=svc-learn,ou=services,dc=example,dc=org",
        bind_password: "ldap-bind-password-value",
        base_dn: "ou=staff,dc=example,dc=org",
        failure_limit: 5
      }

      settings = %{identity_providers: [oidc, ldap]}
      line = Espalier.Application.settings_line(&Map.get(settings, &1))

      assert line =~ ~r/; providers: corp \(oidc, MFA idp_trusted\), dir \(ldap, MFA local\)$/

      for value <- [
            "oidc-client-secret-value",
            "learn-portal-client",
            "id.example.org",
            "learn.example.org",
            "ldap-bind-password-value",
            "ldap.example.org",
            "svc-learn",
            "dc=example",
            "Eldap"
          ] do
        refute line =~ value, value
      end
    end
  end

  test "no message contains the value of a secret variable", %{env: env} do
    secrets = %{
      "SECRET_KEY_BASE" => "short-secret-key-base-value",
      "CLOAK_HMAC_SECRET" => "  ",
      "SMTP_HOST" => "smtp.example.org",
      "SMTP_PASSWORD" => "smtp-password-value",
      "DATABASE_URL" => "ecto://postgres:db-password-value@db/espalier_prod?ssl=false",
      "AUTH_PROVIDERS" => "corp",
      "AUTH_CORP_TYPE" => "oidc",
      "AUTH_CORP_LABEL" => "Company sign-in",
      "AUTH_CORP_ISSUER" => "https://id.example.org",
      "AUTH_CORP_CLIENT_ID" => "espalier",
      "AUTH_CORP_CLIENT_SECRET" => "client-secret-value",
      "AUTH_CORP_CLIENT_AUTH" => "private_key_jwt"
    }

    errors = errors(Map.merge(env, secrets), :prod)
    assert "DATABASE_URL must not set ssl; TLS comes from DATABASE_CA_CERT_FILE" in errors
    assert length(errors) >= 4

    for message <- errors,
        value <- [
          "short-secret-key-base-value",
          "smtp-password-value",
          "db-password-value",
          "client-secret-value"
        ] do
      refute message =~ value
    end
  end
end
