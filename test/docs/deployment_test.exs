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

  Task 0018 adds the media statements of the guides: in `security.md` the
  clamd socket and the browser-side loading of external media (13.1.1),
  ffmpeg and the ClamAV image with their versions (15.1.2), and the media
  queues, threads and timeouts (15.1.3); in `media.md` and
  `content-packs.md` the accepted extensions and the media limits (2.1.3,
  5.1.1); and in `operations.md` the media queues, the cron entries and the
  backup of the media store. Each media limit that these checks look for in
  the guides and in the rows 2.1.3, 5.2.2 and 15.2.2 of `asvs-l2.md` comes
  from `config :espalier, :media` through `Espalier.Media.limit/1`, and the
  limits table of `media.md` must name each fixed limit that
  `config/config.exs` sets with its configured value, so a change of the
  configuration fails these checks until the guides and the matrix follow.
  """
  use ExUnit.Case, async: true

  alias Espalier.Catalog.Pack.{Entries, MediaPath}
  alias Espalier.Media

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

  # A fixed limit of `config :espalier, :media` as the guides write it, so
  # that a change of the configuration fails the checks until the guides
  # follow.
  defp limit(key), do: key |> Media.limit() |> Entries.number()

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
          "LOCAL_ACCOUNTS=false",
          "MEDIA_EMBED_HOSTS=",
          "MEDIA_EMBED_CONSENT=click"
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

  test "security.md states the media connection, components and limits" do
    assert_states("docs/guides/security.md", [
      # ASVS 13.1.1
      "| clamd | the Unix socket of `MEDIA_CLAMAV_SOCKET`",
      "The server fetches no external media.",
      "the browsers of the learners load the file or the player from that host",
      # ASVS 15.1.2
      "| ffmpeg and ffprobe, the Debian package `ffmpeg` | 7.1.5",
      "| `ffmpeg-headless` of nixpkgs | 8.1.2 |",
      ~r/\| ClamAV in the image `clamav\/clamav` \| `clamav\/clamav:\d+\.\d+\.\d+` \|/,
      # ASVS 15.1.3
      "(queue `media: 2`)",
      "(queue `media_video: 1`)",
      "`MEDIA_FFMPEG_THREADS` threads per ffmpeg and ffprobe process",
      "`timeout --kill-after=10`",
      "`image_timeout_seconds` (#{limit(:image_timeout_seconds)})",
      "`video_timeout_floor_seconds` #{limit(:video_timeout_floor_seconds)}",
      "`video_timeout_factor` #{limit(:video_timeout_factor)}",
      "#{limit(:svg_max_bytes)} bytes per SVG file",
      "#{limit(:captions_max_bytes)} bytes per WebVTT file",
      "#{limit(:max_input_pixels)} pixels per image",
      "#{limit(:max_frames)} frames per animated image",
      "at most #{limit(:max_pack_media)} media files per pack and " <>
        "#{limit(:max_draft_media)} media entries per draft",
      "`MEDIA_VIDEO_MAX_MINUTES` (default 60)",
      # Decision D19
      "5.4.3 Untrusted files scanned for malware",
      "nine requirements"
    ])
  end

  test "the media and content pack guides state the accepted files and the media limits" do
    # ASVS 2.1.3 and 5.1.1
    extensions = for {_kind, exts} <- MediaPath.extensions(), ext <- exts, do: ext
    assert length(extensions) == 12

    for path <- ["docs/guides/media.md", "docs/guides/content-packs.md"] do
      text = prose(path)

      for ext <- extensions do
        assert text =~ ~r/`\.?#{ext}`/, "#{path} does not name the extension #{ext}"
      end

      assert_states(path, [
        "`MEDIA_IMAGE_MAX_MB`",
        "`MEDIA_VIDEO_MAX_MB`",
        "`MEDIA_STORAGE_MAX_GB`",
        "`max_pack_media`",
        limit(:svg_max_bytes),
        limit(:captions_max_bytes)
      ])
    end

    assert_states("docs/guides/content-packs.md", [
      "(#{limit(:svg_max_bytes)} bytes) |",
      "(#{limit(:captions_max_bytes)} bytes) |",
      "at most #{limit(:max_pack_media)} media files (`max_pack_media`)",
      "an image above #{limit(:max_input_pixels)} pixels"
    ])

    assert_states("docs/guides/media.md", [
      # The signatures of Espalier.Media.Sniff
      "`89 50 4E 47 0D 0A 1A 0A`",
      "`FF D8 FF`",
      "`GIF87a` or `GIF89a`",
      "`RIFF`, four bytes, `WEBP`",
      "`ftyp` at offset 4",
      "`1A 45 DF A3`",
      "`WEBVTT`",
      # The delivery formats
      "WebM (`.webm`) with VP9 and Opus",
      # The limits outside the limits table
      "#{limit(:svg_max_bytes)} bytes (`svg_max_bytes`)",
      "#{limit(:captions_max_bytes)} bytes (`captions_max_bytes`)",
      "Width times height above #{limit(:max_input_pixels)}",
      "An animated GIF or APNG with at most #{limit(:max_frames)} frames",
      "within #{limit(:max_input_pixels)} pixels and the frames within #{limit(:max_frames)}",
      "| `too_large` | more than #{limit(:captions_max_bytes)} bytes |",
      "| `too_many_pixels` | an image above #{limit(:max_input_pixels)} pixels",
      "at most #{limit(:max_pack_media)} files (`max_pack_media`)",
      "with more than #{limit(:max_frames)} frames |",
      "`export_max_mb`, #{limit(:export_max_mb)} MB"
    ])

    # The rows 2.1.3, 5.2.2 and 15.2.2 of the ASVS matrix name the same limits.
    assert_states("docs/security/asvs-l2.md", [
      "the fixed limits of `config :espalier, :media`: " <>
        "#{limit(:svg_max_bytes)} bytes per SVG file, " <>
        "#{limit(:captions_max_bytes)} bytes per WebVTT file, " <>
        "#{limit(:max_input_pixels)} pixels per image, 3840 by 2160 pixels per video frame, " <>
        "#{limit(:max_frames)} frames, #{limit(:max_pack_media)} media files per pack and " <>
        "#{limit(:max_draft_media)} media entries per draft, and " <>
        "#{limit(:export_max_mb)} MB of media",
      "its header dimensions stay within #{limit(:max_input_pixels)} pixels",
      "the limits of #{limit(:max_frames)} frames"
    ])

    # Every media variable of Espalier.RuntimeConfig appears in the media
    # guide and in .env.example.
    variables =
      Regex.scan(~r/"(MEDIA_[A-Z_]+)"/, read("lib/espalier/runtime_config.ex"),
        capture: :all_but_first
      )
      |> List.flatten()
      |> Enum.uniq()

    assert length(variables) == 12, inspect(variables)
    media = read("docs/guides/media.md")
    env = read(".env.example")

    for variable <- variables do
      assert media =~ "| `#{variable}` |", "docs/guides/media.md lacks #{variable}"
      assert env =~ ~r/^#{variable}=/m, ".env.example lacks #{variable}"
    end
  end

  test "the limits table of media.md holds the values of config :espalier, :media" do
    # ASVS 2.1.3
    [_before, section] = String.split(read("docs/guides/media.md"), "## Limits and quota\n")
    [section | _rest] = String.split(section, "\n## ", parts: 2)

    rows =
      ~r/^\| `([a-z_]+)` \| ([0-9,]+)[ |]/m
      |> Regex.scan(section, capture: :all_but_first)
      |> Map.new(fn [key, value] -> {key, value} end)

    # The keys of `config :espalier, :media` in config/config.exs, so that a
    # new fixed limit needs its row.
    [_before, block] = String.split(read("config/config.exs"), "config :espalier, :media,\n")
    [block | _rest] = String.split(block, "\n\n", parts: 2)
    keys = for [key] <- Regex.scan(~r/^\s+([a-z_]+):/m, block, capture: :all_but_first), do: key

    assert length(keys) >= 11, inspect(keys)
    assert rows |> Map.keys() |> Enum.sort() == Enum.sort(keys)

    for key <- keys do
      value = key |> String.to_existing_atom() |> limit()
      assert rows[key] == value, "docs/guides/media.md states #{key}"
    end

    # The guides and the matrix write the video frame limit as 3840 by 2160.
    assert limit(:max_video_pixels) == Entries.number(3840 * 2160)
  end

  test "operations.md lists the media queues, the cron entries and the backup of MEDIA_DIR" do
    assert_states("docs/guides/operations.md", [
      "| `media` | 2 |",
      "| `media_video` | 1 |",
      "| every 15 minutes | `Espalier.Media.StaleWorker` |",
      "| 03:45 daily | `Espalier.Media.RetentionWorker` |",
      "## Backup and restore of the media store",
      "tar -C /data/media -cf - files incoming"
    ])

    config = read("config/config.exs")
    assert config =~ "media: 2, media_video: 1"
    assert config =~ ~s({"*/15 * * * *", Espalier.Media.StaleWorker})
    assert config =~ ~s({"45 3 * * *", Espalier.Media.RetentionWorker})
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
