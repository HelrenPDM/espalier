defmodule Espalier.RuntimeConfigTest do
  @moduledoc """
  `Espalier.RuntimeConfig.parse!/2` with the defaults, valid values and
  invalid values of its variables: the account and session settings of
  task 0004 (section "Addendum: implementation"), `TRACKING_DETAIL` and
  `INSIGHTS_ORG_UNIT` of task 0009 (step 9), the credential settings of
  task 0013 (step 2), and the insights settings of task 0014 (steps 4, 10
  and 13) together with the crontab entry of the retention job and the
  bucket `insights_write` in `config/config.exs`, `PACK_UPLOAD_MAX_MB` of
  task 0015 (step 7), and `EXPORT_DIR` of task 0016 (step 7) together with
  the queue `exports` with one slot in `config/config.exs`.
  """
  use ExUnit.Case, async: true

  alias Espalier.RuntimeConfig

  # The retention variables of task 0014 and their keys under :insights.
  @retention_keys %{
    "RETENTION_ITEM_RESPONSES_DAYS" => :retention_item_responses_days,
    "RETENTION_ANONYMOUS_DAYS" => :retention_anonymous_days,
    "RETENTION_AUDIT_DAYS" => :retention_audit_days,
    "RETENTION_ATTEMPTS_DAYS" => :retention_attempts_days
  }

  defp insights(env), do: RuntimeConfig.parse!(env, :dev)[:insights]

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
          "PUBLIC_URL" => "https://app.example.org/",
          "EXPORT_DIR" => ~s("/data/exports")
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
    assert config[:export_dir] == "/data/exports"
  end

  test "PUBLIC_URL comes back as the origin that browsers send" do
    for {url, origin} <- [
          {"https://LEARN.example.org", "https://learn.example.org"},
          {"https://Learn.Example.org:443/", "https://learn.example.org"},
          {"https://learn.example.org:8443", "https://learn.example.org:8443"},
          {"http://LOCALHOST:5173", "http://localhost:5173"},
          {"http://[::1]:4000/", "http://[::1]:4000"}
        ] do
      assert RuntimeConfig.parse!(%{"PUBLIC_URL" => url}, :test)[:public_url] == origin, url
    end
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

  describe "the variable of task 0016 (spec step 7)" do
    test "EXPORT_DIR defaults to tmp/exports in development and tmp/test-exports in tests" do
      assert RuntimeConfig.parse!(%{}, :dev)[:export_dir] == "tmp/exports"
      assert RuntimeConfig.parse!(%{}, :test)[:export_dir] == "tmp/test-exports"

      # The empty value of .env.example counts as unset.
      assert RuntimeConfig.parse!(%{"EXPORT_DIR" => ""}, :dev)[:export_dir] == "tmp/exports"

      assert RuntimeConfig.parse!(%{"EXPORT_DIR" => "  "}, :test)[:export_dir] ==
               "tmp/test-exports"
    end

    test "EXPORT_DIR takes a path and strips one pair of surrounding quotes" do
      assert RuntimeConfig.parse!(%{"EXPORT_DIR" => "/data/exports"}, :dev)[:export_dir] ==
               "/data/exports"

      assert RuntimeConfig.parse!(%{"EXPORT_DIR" => ~s("/srv/espalier exports")}, :test)[
               :export_dir
             ] == "/srv/espalier exports"
    end

    test "production stops the boot without EXPORT_DIR" do
      base = %{"PUBLIC_URL" => "https://app.example.org"}

      for env <- [base, Map.put(base, "EXPORT_DIR", ""), Map.put(base, "EXPORT_DIR", ~s(""))] do
        assert_raise ArgumentError, "EXPORT_DIR is required", fn ->
          RuntimeConfig.parse!(env, :prod)
        end
      end

      assert RuntimeConfig.parse!(Map.put(base, "EXPORT_DIR", "/data/exports"), :prod)[
               :export_dir
             ] == "/data/exports"
    end

    test "the defaults lie below tmp/, which .gitignore covers" do
      assert "/tmp/" in String.split(File.read!(".gitignore"), "\n", trim: true)
    end

    test "config/config.exs gives the Oban queue exports one slot" do
      config = Config.Reader.read!("config/config.exs", env: :prod, target: :host)
      assert get_in(config, [:espalier, Oban, :queues, :exports]) == 1
    end
  end

  describe "the variable of task 0015 (spec step 7)" do
    test "PACK_UPLOAD_MAX_MB defaults to 20 and accepts a positive integer" do
      assert RuntimeConfig.parse!(%{}, :dev)[:pack_upload_max_mb] == 20
      assert RuntimeConfig.parse!(%{"PACK_UPLOAD_MAX_MB" => "5"}, :dev)[:pack_upload_max_mb] == 5
    end

    test "PACK_UPLOAD_MAX_MB rejects other values with the variable name" do
      for value <- ["0", "-1", "twenty", "1.5", "20MB"] do
        assert_raise ArgumentError, ~r/^PACK_UPLOAD_MAX_MB /, fn ->
          RuntimeConfig.parse!(%{"PACK_UPLOAD_MAX_MB" => value}, :dev)
        end
      end
    end
  end

  describe "the variables of task 0013 (spec step 2)" do
    test "default to 30 notice days, 30 grace days, no registrar and no webhook host" do
      config = RuntimeConfig.parse!(%{}, :dev)
      assert config[:credential_notice_days] == 30
      assert config[:credential_grace_days] == 30
      assert config[:registrar_enabled] == false
      assert config[:webhook_allowed_hosts] == []
    end

    test "CREDENTIAL_NOTICE_DAYS and CREDENTIAL_GRACE_DAYS accept positive integers" do
      config =
        RuntimeConfig.parse!(
          %{"CREDENTIAL_NOTICE_DAYS" => "1", "CREDENTIAL_GRACE_DAYS" => ~s("365")},
          :dev
        )

      assert config[:credential_notice_days] == 1
      assert config[:credential_grace_days] == 365
    end

    test "CREDENTIAL_NOTICE_DAYS and CREDENTIAL_GRACE_DAYS reject other values with the variable name" do
      for name <- ["CREDENTIAL_NOTICE_DAYS", "CREDENTIAL_GRACE_DAYS"],
          value <- ["0", "-5", "thirty", "1.5", "30d"] do
        assert_raise ArgumentError, ~r/^#{name} /, fn ->
          RuntimeConfig.parse!(%{name => value}, :dev)
        end
      end
    end

    test "REGISTRAR_ENABLED accepts only true and false" do
      assert RuntimeConfig.parse!(%{"REGISTRAR_ENABLED" => "true"}, :dev)[:registrar_enabled] ==
               true

      assert RuntimeConfig.parse!(%{"REGISTRAR_ENABLED" => "false"}, :dev)[:registrar_enabled] ==
               false

      for value <- ["TRUE", "1", "yes", "on"] do
        assert_raise ArgumentError, ~r/^REGISTRAR_ENABLED /, fn ->
          RuntimeConfig.parse!(%{"REGISTRAR_ENABLED" => value}, :dev)
        end
      end
    end

    test "WEBHOOK_ALLOWED_HOSTS gives {host, port} with the host lower-case" do
      config =
        RuntimeConfig.parse!(
          %{
            "WEBHOOK_ALLOWED_HOSTS" => "Hooks.Example.org, receiver.example.org:8443, [::1]:4100"
          },
          :dev
        )

      assert config[:webhook_allowed_hosts] == [
               {"hooks.example.org", nil},
               {"receiver.example.org", 8443},
               {"::1", 4100}
             ]

      assert RuntimeConfig.parse!(%{"WEBHOOK_ALLOWED_HOSTS" => ~s("localhost:4100")}, :dev)[
               :webhook_allowed_hosts
             ] == [{"localhost", 4100}]
    end

    test "WEBHOOK_ALLOWED_HOSTS rejects a scheme, a path, a query, userinfo, a port out of range and an empty host" do
      for entry <- [
            "https://hooks.example.org",
            "hooks.example.org/espalier",
            "hooks.example.org?event=issued",
            "hooks.example.org#issued",
            "user@hooks.example.org",
            "user:pass@hooks.example.org:8443",
            "hooks.example.org:0",
            "hooks.example.org:70000",
            "hooks.example.org:",
            ":8443",
            "[]:8443",
            "[:::]:8443",
            "[1.2.3.4]",
            "[::1"
          ] do
        assert_raise ArgumentError, ~r/^WEBHOOK_ALLOWED_HOSTS /, fn ->
          RuntimeConfig.parse!(
            %{"WEBHOOK_ALLOWED_HOSTS" => "receiver.example.org, " <> entry},
            :dev
          )
        end
      end
    end
  end

  describe "the variables of task 0014 (spec step 10)" do
    test "default to a group size of 5, no free text, no test notes and no retention period" do
      config = RuntimeConfig.parse!(%{}, :dev)

      assert config[:insights] == [
               min_group_size: 5,
               feedback_free_text: false,
               test_notes: false,
               retention_item_responses_days: nil,
               retention_anonymous_days: nil,
               retention_audit_days: nil,
               retention_attempts_days: nil
             ]

      # The settings sit under :insights alone, so that config/runtime.exs
      # sets config :espalier, :insights.
      for key <- Keyword.keys(config[:insights]), do: refute(Keyword.has_key?(config, key))
    end

    test "INSIGHTS_MIN_GROUP_SIZE accepts an integer of at least 1" do
      assert insights(%{"INSIGHTS_MIN_GROUP_SIZE" => "3"})[:min_group_size] == 3
      assert insights(%{"INSIGHTS_MIN_GROUP_SIZE" => "1"})[:min_group_size] == 1
      assert insights(%{"INSIGHTS_MIN_GROUP_SIZE" => ~s("10")})[:min_group_size] == 10
    end

    test "INSIGHTS_MIN_GROUP_SIZE rejects other values with the variable name" do
      for value <- ["0", "-1", "x", "1.5"] do
        assert_raise ArgumentError, ~r/^INSIGHTS_MIN_GROUP_SIZE /, fn ->
          RuntimeConfig.parse!(%{"INSIGHTS_MIN_GROUP_SIZE" => value}, :dev)
        end
      end
    end

    test "FEEDBACK_FREE_TEXT and TEST_NOTES accept true and false" do
      assert insights(%{"FEEDBACK_FREE_TEXT" => "true"})[:feedback_free_text] == true
      assert insights(%{"FEEDBACK_FREE_TEXT" => "false"})[:feedback_free_text] == false
      assert insights(%{"TEST_NOTES" => "true"})[:test_notes] == true
      assert insights(%{"TEST_NOTES" => "false"})[:test_notes] == false

      # Each variable sets its own key.
      assert insights(%{"TEST_NOTES" => "true"})[:feedback_free_text] == false
      assert insights(%{"FEEDBACK_FREE_TEXT" => "true"})[:test_notes] == false
    end

    test "FEEDBACK_FREE_TEXT and TEST_NOTES reject other values with the variable name" do
      for name <- ["FEEDBACK_FREE_TEXT", "TEST_NOTES"], value <- ["yes", "TRUE", "1"] do
        assert_raise ArgumentError, "#{name} must be true or false", fn ->
          RuntimeConfig.parse!(%{name => value}, :dev)
        end
      end
    end

    test "each RETENTION_* variable is unset by default and accepts a positive number of days" do
      for {name, key} <- @retention_keys do
        assert insights(%{})[key] == nil
        assert insights(%{name => "30"})[key] == 30
        assert insights(%{name => ~s("365")})[key] == 365

        # The empty value of .env.example counts as unset.
        assert insights(%{name => ""})[key] == nil

        # A variable sets its own period and no other.
        others = Map.values(@retention_keys) -- [key]
        assert Enum.all?(others, &(insights(%{name => "30"})[&1] == nil)), name
      end
    end

    test "each RETENTION_* variable rejects other values with the variable name" do
      for name <- Map.keys(@retention_keys), value <- ["0", "abc", "-7", "30d"] do
        assert_raise ArgumentError, ~r/^#{name} /, fn ->
          RuntimeConfig.parse!(%{name => value}, :dev)
        end
      end
    end

    test "config/config.exs registers the retention job at 03:30 and the bucket insights_write" do
      config = Config.Reader.read!("config/config.exs", env: :prod, target: :host)

      crontab =
        config
        |> get_in([:espalier, Oban, :plugins])
        |> Enum.find_value(fn
          {Oban.Plugins.Cron, opts} -> opts[:crontab]
          _plugin -> nil
        end)

      assert {"30 3 * * *", Espalier.Insights.RetentionWorker} in crontab
      assert config[:espalier][:rate_limits][:insights_write] == {:timer.minutes(1), 30}

      # config/test.exs replaces the map of config/config.exs as a whole, so
      # it names the bucket as well.
      test_config = Config.Reader.read!("config/config.exs", env: :test, target: :host)
      assert {_scale, _limit} = test_config[:espalier][:rate_limits][:insights_write]
    end
  end

  test "production needs PUBLIC_URL, and MAIL_FROM together with SMTP_HOST" do
    assert_raise ArgumentError, ~r/PUBLIC_URL/, fn ->
      RuntimeConfig.parse!(%{"EXPORT_DIR" => "/data/exports"}, :prod)
    end

    base = %{"PUBLIC_URL" => "https://app.example.org", "EXPORT_DIR" => "/data/exports"}
    assert RuntimeConfig.parse!(base, :prod)[:mail_from] == {"Espalier", "noreply@localhost"}

    assert_raise ArgumentError, ~r/MAIL_FROM/, fn ->
      RuntimeConfig.parse!(Map.put(base, "SMTP_HOST", "smtp.example.org"), :prod)
    end
  end
end
