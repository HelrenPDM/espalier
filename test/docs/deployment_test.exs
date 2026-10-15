defmodule Espalier.Docs.DeploymentTest do
  @moduledoc """
  Source checks of task 0017 for the deployment files and the guides that
  describe them: the dependency inventory (ASVS 15.1.2), the documented
  exceptions of `mix hex.audit` (15.2.1), the empty secret placeholders of
  the env examples (13.2.3, 13.3.1), the reverse proxy example (3.4.1, 4.1.2,
  12.1.1, 13.4.4, 14.2.2), the published port of the application (4.1.2),
  the cipher suites of the database (12.1.2), the image and its build
  context (13.3.1), the log forwarding example (16.4.3), and the upload
  limits and the business limits that the guides state (2.1.3, 5.1.1). The
  checks of the running container are `scripts/smoke.sh`,
  `scripts/check-headers.sh` and `scripts/check-release.sh`.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  # Variables whose value is a secret or contains one.
  @secret ~r/^(SECRET_KEY_BASE|CLOAK_KEY_V\d+|CLOAK_HMAC_SECRET|POSTGRES_PASSWORD|DATABASE_URL|SMTP_PASSWORD|AUTH_[A-Z0-9_]+_(CLIENT_SECRET|BIND_PASSWORD)|WEBHOOK_SECRET_[A-Z0-9_]+|RELEASE_COOKIE)=(.*)$/m

  defp read(path), do: File.read!(Path.join(@root, path))

  # The text of a guide with every run of whitespace as one space, so that a
  # statement may wrap at any word.
  defp prose(path), do: path |> read() |> String.replace(~r/\s+/, " ")

  defp assert_states(path, statements) do
    text = prose(path)

    for statement <- statements do
      assert text =~ statement, "#{path} does not state #{inspect(statement)}"
    end
  end

  test "every entry of mix.lock comes from the repository hexpm" do
    # Elixir 1.20 warns about the quoted keys of mix.lock.
    {lock, _binding} =
      read("mix.lock") |> Code.string_to_quoted!(emit_warnings: false) |> Code.eval_quoted()

    for {name, entry} <- lock do
      assert {:hex, ^name, _version, _inner, _managers, _deps, "hexpm", _outer} = entry
    end
  end

  test "every package of frontend/package-lock.json comes from registry.npmjs.org" do
    %{"packages" => packages} = JSON.decode!(read("frontend/package-lock.json"))

    resolved =
      for {path, package} <- packages, path != "", do: {path, package["resolved"]}

    assert resolved != []

    for {path, url} <- resolved do
      assert is_binary(url) and String.starts_with?(url, "https://registry.npmjs.org/"), path
    end
  end

  test "every ignored advisory has a reason in mix.exs and a line in security.md" do
    mix = read("mix.exs")
    security = read("docs/guides/security.md")
    [_, list] = Regex.run(~r/ignore_advisories: \[([^\]]*)\]/, mix)
    ids = Regex.scan(~r/"([^"]+)"/, list, capture: :all_but_first) |> List.flatten()

    assert ids != []

    for id <- ids do
      assert Regex.match?(~r/^\s*#.*#{Regex.escape(id)}/m, mix), "#{id} has no comment"
      assert security =~ id, "#{id} is missing in docs/guides/security.md"
    end
  end

  test "the env examples hold empty secret placeholders only" do
    for file <- [".env.example", ".env.demo.example"] do
      lines = Regex.scan(@secret, read(file))
      assert length(lines) >= 5

      for [line, _name, _kind, value] <- lines do
        assert value == "", "#{file}: #{line}"
      end
    end

    demo = read(".env.demo.example")

    for line <- [
          "TRACKING_DETAIL=minimal",
          "REGISTRAR_ENABLED=false",
          "AUTH_DEMO=true",
          "AUTH_PROVIDERS=",
          "LOCAL_ACCOUNTS=false"
        ] do
      assert demo =~ ~r/^#{Regex.escape(line)}$/m, line
    end
  end

  test "the Caddyfile limits TLS, sends HSTS, refuses TRACE and caches nothing" do
    caddyfile = read("docs/guides/examples/Caddyfile")

    assert caddyfile =~ ~r/^\s*protocols tls1\.2 tls1\.3$/m
    assert caddyfile =~ ~s(header Strict-Transport-Security "max-age=63072000; includeSubDomains")
    assert caddyfile =~ ~r/^\s*@trace method TRACE\n\s*respond @trace 405$/m
    assert caddyfile =~ ~r/^\s*reverse_proxy app:4000$/m

    # No cache handler, and no trusted_proxies, so Caddy writes the client
    # address into X-Forwarded-For itself.
    refute caddyfile =~ ~r/\bcache\b|trusted_proxies/
  end

  test "compose publishes the application on the loopback address and Caddy on HTTPS only" do
    compose = read("compose.yaml")
    caddy = read("docs/guides/examples/compose.caddy.yaml")

    assert compose =~ ~s(- "127.0.0.1:${APP_PORT:-4000}:4000")
    assert [_one] = Regex.scan(~r/^\s+ports:$/m, compose)
    assert compose =~ "hostssl all all all scram-sha-256"
    assert compose =~ "ssl_min_protocol_version=TLSv1.2"
    # ASVS 12.1.2: TLS 1.2 with ECDHE and AES-GCM or ChaCha20-Poly1305 only.
    assert compose =~ "ssl_ciphers=ECDHE+AESGCM:ECDHE+CHACHA20"
    assert compose =~ "DATABASE_CA_CERT_FILE: /etc/espalier/db-ca/ca.pem"

    assert caddy =~ ~s(- "${HTTPS_PORT:-443}:443")
    assert [_one] = Regex.scan(~r/^\s+ports:$/m, caddy)
    refute caddy =~ ":80"
  end

  test "the logging example forwards over TLS with the options of the syslog driver" do
    logging = read("docs/guides/examples/compose.logging.yaml")

    assert logging =~ "driver: syslog"
    assert logging =~ ~s(syslog-address: "tcp+tls://)
    assert logging =~ "syslog-tls-ca-cert:"
    assert logging =~ "syslog-format: rfc5424micro"
    assert logging =~ "tag: espalier"
  end

  test "self-hosting.md states the rules of the deployment" do
    assert_states("docs/guides/self-hosting.md", [
      # ASVS 3.5.4
      ~r/dedicated host name/i,
      # ASVS 12.3.1 and 12.3.3, decision D17
      "Run the proxy and the application on the same host. A proxy on another host needs TLS on the hop to the application.",
      # ASVS 12.2.2
      "A public deployment uses a publicly trusted certificate",
      ~r/ACME/,
      "The local CA serves `localhost` only",
      # SECRET_KEY_BASE and the optional mail setup
      "64 bytes",
      "SMTP_HOST"
    ])
  end

  test "security.md states the policies and measurements of the V12, V13 and V15 rows" do
    assert_states("docs/guides/security.md", [
      # ASVS 13.3.1
      "The environment is the interface to the operator's secrets manager",
      # ASVS 15.1.1
      "| critical | within 7 days |",
      "| high | within 30 days |",
      "| medium | within 90 days |",
      "| low | with the next regular update |",
      "Dependencies are updated once a month.",
      # ASVS 15.1.2
      "maintenance risk",
      # ASVS 13.1.1
      "api.pwnedpasswords.com",
      "WEBHOOK_ALLOWED_HOSTS",
      "DNS_CLUSTER_QUERY",
      "4369 (epmd)",
      "-proto_dist inet_tls",
      # ASVS 12.1.2, measured on 2026-10-15
      "2026-10-15",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
      # ASVS 15.1.3
      "Argon2",
      "PACK_UPLOAD_MAX_MB",
      # ASVS 3.3.3, the revisit of step 7
      "__Host-Http-",
      # Decision D17
      "D17"
    ])

    # Every TLS 1.2 suite in the guide uses ECDHE and an AEAD cipher.
    for [suite] <- Regex.scan(~r/TLS_[A-Z0-9_]+_WITH_[A-Z0-9_]+/, read("docs/guides/security.md")),
        not String.starts_with?(suite, "TLS_AKE_") do
      assert suite =~
               ~r/^TLS_ECDHE_(ECDSA|RSA)_WITH_(AES_(128|256)_GCM_SHA(256|384)|CHACHA20_POLY1305_SHA256)$/,
             suite
    end
  end

  test "the guides state the upload limits and link the business limits" do
    # ASVS 2.1.3 and 5.1.1
    assert_states("docs/guides/content-packs.md", [
      "## Upload limits",
      "`PACK_UPLOAD_MAX_MB` megabytes",
      "default 20",
      "At most 2,000",
      "five times the upload limit",
      "absolute",
      "backslash",
      "a `..` component",
      "symbolic link"
    ])

    # ASVS 2.1.3
    assert_states("docs/guides/security.md", [
      "../security/authentication.md#rate-limits",
      "../security/authentication.md#concurrent-session-limit"
    ])
  end

  test "operations.md restricts log access and forwards the logs" do
    assert_states("docs/guides/operations.md", [
      # ASVS 16.4.2
      ~r/operators/,
      "The application writes to standard output and keeps no log file.",
      # ASVS 16.4.3
      "compose.logging.yaml",
      "tcp+tls"
    ])
  end

  test "the image carries LICENSE and NOTICE and keeps metadata, env files and the cookie out" do
    dockerfile = read("Dockerfile")
    dockerignore = read(".dockerignore")

    assert dockerfile =~ ~r/^COPY --chmod=0644 LICENSE NOTICE \.\/$/m
    assert dockerfile =~ ~r/^USER nobody$/m
    assert dockerfile =~ ~r/^HEALTHCHECK /m

    # The release belongs to root, and no layer holds the cookie that
    # mix release writes (ASVS 13.3.1).
    assert dockerfile =~ "\nCOPY --from=builder /app/_build/${MIX_ENV}/rel/espalier ./\n"
    refute dockerfile =~ ~r/chown nobody \/app$/m
    assert dockerfile =~ "rm _build/${MIX_ENV}/rel/espalier/releases/COOKIE"

    for line <- [
          ".git",
          ".env",
          "**/.env",
          "**/.env.*",
          "/deps/",
          "/_build/",
          "/tmp/",
          "/dev/",
          "/frontend/node_modules/"
        ] do
      assert dockerignore =~ ~r/^#{Regex.escape(line)}$/m, line
    end

    refute dockerignore =~ ~r/^!\.git/m
    refute dockerignore =~ ~r/^\/?(LICENSE|NOTICE)$/m
  end
end
