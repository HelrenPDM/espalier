defmodule Espalier.RuntimeConfigTest do
  use ExUnit.Case, async: true

  alias Espalier.RuntimeConfig

  test "defaults without any variable" do
    config = RuntimeConfig.parse!(%{}, :dev)
    assert config[:session_idle_minutes] == 60
    assert config[:session_max_hours] == 24
    assert config[:session_max_concurrent] == 5
    assert config[:local_accounts] == true
    assert config[:signup] == :closed
    assert config[:password_breach_check] == :off
    assert config[:auth_demo] == false
    assert config[:trusted_proxies] == []
    assert config[:public_url] == "http://localhost:5173"
    assert config[:mail_from] == {"Espalier", "noreply@localhost"}
    assert config[:admin_require_passkey] == true
    assert config[:learning] == [tracking_detail: :minimal, insights_org_unit: false]
  end

  test "TRACKING_DETAIL and INSIGHTS_ORG_UNIT come back under :learning" do
    config =
      RuntimeConfig.parse!(
        %{"TRACKING_DETAIL" => "standard", "INSIGHTS_ORG_UNIT" => "true"},
        :dev
      )

    assert config[:learning] == [tracking_detail: :standard, insights_org_unit: true]

    assert RuntimeConfig.parse!(%{"TRACKING_DETAIL" => ~s("minimal")}, :dev)[:learning][
             :tracking_detail
           ] == :minimal
  end

  test "TRACKING_DETAIL and INSIGHTS_ORG_UNIT reject other values with the variable name" do
    for value <- ["Standard", "full", "1"] do
      assert_raise ArgumentError, ~r/^TRACKING_DETAIL must be one of/, fn ->
        RuntimeConfig.parse!(%{"TRACKING_DETAIL" => value}, :dev)
      end
    end

    for value <- ["TRUE", "1", "yes"] do
      assert_raise ArgumentError, "INSIGHTS_ORG_UNIT must be true or false", fn ->
        RuntimeConfig.parse!(%{"INSIGHTS_ORG_UNIT" => value}, :dev)
      end
    end
  end

  test "ADMIN_REQUIRE_PASSKEY accepts only true and false" do
    assert RuntimeConfig.parse!(%{"ADMIN_REQUIRE_PASSKEY" => "false"}, :dev)[
             :admin_require_passkey
           ] ==
             false

    assert RuntimeConfig.parse!(%{"ADMIN_REQUIRE_PASSKEY" => "true"}, :dev)[
             :admin_require_passkey
           ] ==
             true

    for value <- ["TRUE", "1", "yes"] do
      assert_raise ArgumentError, "ADMIN_REQUIRE_PASSKEY must be true or false", fn ->
        RuntimeConfig.parse!(%{"ADMIN_REQUIRE_PASSKEY" => value}, :dev)
      end
    end
  end

  test "parses the values and strips one pair of surrounding quotes" do
    config =
      RuntimeConfig.parse!(
        %{
          "SESSION_IDLE_MINUTES" => "30",
          "SIGNUP" => "domain",
          "SIGNUP_DOMAINS" => "Example.org, other.example.org",
          "PASSWORD_CONTEXT_WORDS" => "northwind,acme",
          "BOOTSTRAP_ADMIN_EMAILS" => " Admin@Example.org ",
          "TRUSTED_PROXIES" => "10.0.0.0/8,192.0.2.1",
          "MAIL_FROM" => ~s("Espalier <noreply@example.org>"),
          "PUBLIC_URL" => "https://app.example.org/"
        },
        :prod
      )

    assert config[:session_idle_minutes] == 30
    assert config[:signup] == :domain
    assert config[:signup_domains] == ["example.org", "other.example.org"]
    assert config[:password_context_words] == ["northwind", "acme"]
    assert config[:bootstrap_admin_emails] == ["admin@example.org"]
    assert config[:trusted_proxies] == [{{10, 0, 0, 0}, 8}, {{192, 0, 2, 1}, 32}]
    assert config[:mail_from] == {"Espalier", "noreply@example.org"}
    assert config[:public_url] == "https://app.example.org"
  end

  test "invalid values raise with the variable name" do
    for {env, name} <- [
          {%{"SESSION_MAX_HOURS" => "0"}, "SESSION_MAX_HOURS"},
          {%{"LOCAL_ACCOUNTS" => "yes"}, "LOCAL_ACCOUNTS"},
          {%{"SIGNUP" => "open"}, "SIGNUP"},
          {%{"SIGNUP" => "domain"}, "SIGNUP_DOMAINS"},
          {%{"PASSWORD_BREACH_CHECK" => "on"}, "PASSWORD_BREACH_CHECK"},
          {%{"BOOTSTRAP_ADMIN_EMAILS" => "admin"}, "BOOTSTRAP_ADMIN_EMAILS"},
          {%{"PUBLIC_URL" => "localhost"}, "PUBLIC_URL"},
          {%{"MAIL_FROM" => "nobody"}, "MAIL_FROM"}
        ] do
      assert_raise ArgumentError, ~r/#{name}/, fn -> RuntimeConfig.parse!(env, :dev) end
    end
  end

  test "production needs PUBLIC_URL, and MAIL_FROM together with SMTP_HOST" do
    assert_raise ArgumentError, ~r/PUBLIC_URL/, fn -> RuntimeConfig.parse!(%{}, :prod) end

    base = %{"PUBLIC_URL" => "https://app.example.org"}
    assert RuntimeConfig.parse!(base, :prod)[:mail_from] == {"Espalier", "noreply@localhost"}

    assert_raise ArgumentError, ~r/MAIL_FROM/, fn ->
      RuntimeConfig.parse!(Map.put(base, "SMTP_HOST", "smtp.example.org"), :prod)
    end
  end
end
