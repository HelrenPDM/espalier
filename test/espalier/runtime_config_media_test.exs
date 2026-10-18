defmodule Espalier.RuntimeConfigMediaTest do
  @moduledoc """
  The media settings of `Espalier.RuntimeConfig` (task 0018, step 2): the
  defaults per environment, the ranges of `integer_in/4` with their
  messages, `MEDIA_DIR` in production, the socket path rule and the 2047
  rule of `MEDIA_CLAMAV_SOCKET`, the host lists without IPv6 addresses,
  `MEDIA_EMBED_HOSTS` against the host of `PUBLIC_URL`, the dev default
  `embed.espalier.test`, `MEDIA_EMBED_CONSENT`, and the unchanged messages
  of `WEBHOOK_ALLOWED_HOSTS` on top of `host_entry/2`.
  """
  use ExUnit.Case, async: true

  alias Espalier.RuntimeConfig

  @prod %{
    "PUBLIC_URL" => "https://learn.example.org",
    "EXPORT_DIR" => "/data/exports",
    "MEDIA_DIR" => "/data/media"
  }

  defp media(env, config_env \\ :test), do: RuntimeConfig.parse!(env, config_env)[:media]

  defp message(env, config_env \\ :test) do
    error = assert_raise ArgumentError, fn -> RuntimeConfig.parse!(env, config_env) end
    error.message
  end

  describe "defaults" do
    test "in development" do
      assert media(%{}, :dev) == [
               dir: "tmp/media",
               image_max_mb: 20,
               video_max_mb: 1024,
               video_max_minutes: 60,
               video_max_height: 1080,
               image_max_edge: 2560,
               storage_max_gb: 50,
               external_hosts: [],
               embed_hosts: [{"embed.espalier.test", nil}],
               embed_consent: :click,
               clamav_socket: nil,
               ffmpeg_threads: 2
             ]
    end

    test "in tests" do
      assert media(%{}, :test) == [
               dir: "tmp/test-media",
               image_max_mb: 20,
               video_max_mb: 1024,
               video_max_minutes: 60,
               video_max_height: 1080,
               image_max_edge: 2560,
               storage_max_gb: 50,
               external_hosts: [],
               embed_hosts: [],
               embed_consent: :click,
               clamav_socket: nil,
               ffmpeg_threads: 2
             ]
    end

    test "in production with the required variables" do
      config = media(@prod, :prod)
      assert config[:dir] == "/data/media"
      assert config[:embed_hosts] == []
      assert config[:external_hosts] == []
      assert config[:embed_consent] == :click
      assert config[:clamav_socket] == nil
    end

    test "valid values come back as integers, atoms and lists" do
      config =
        media(%{
          "MEDIA_DIR" => "/srv/media",
          "MEDIA_IMAGE_MAX_MB" => "8",
          "MEDIA_VIDEO_MAX_MB" => "4096",
          "MEDIA_VIDEO_MAX_MINUTES" => "\"90\"",
          "MEDIA_VIDEO_MAX_HEIGHT" => "720",
          "MEDIA_IMAGE_MAX_EDGE" => "1920",
          "MEDIA_STORAGE_MAX_GB" => "200",
          "MEDIA_EXTERNAL_HOSTS" => "CDN.Example.org, videos.example.net:8443",
          "MEDIA_EMBED_HOSTS" => "player.example.org",
          "MEDIA_EMBED_CONSENT" => "auto",
          "MEDIA_FFMPEG_THREADS" => "4"
        })

      assert config == [
               dir: "/srv/media",
               image_max_mb: 8,
               video_max_mb: 4096,
               video_max_minutes: 90,
               video_max_height: 720,
               image_max_edge: 1920,
               storage_max_gb: 200,
               external_hosts: [{"cdn.example.org", nil}, {"videos.example.net", 8443}],
               embed_hosts: [{"player.example.org", nil}],
               embed_consent: :auto,
               clamav_socket: nil,
               ffmpeg_threads: 4
             ]
    end
  end

  describe "ranges" do
    for {name, first, last} <- [
          {"MEDIA_VIDEO_MAX_HEIGHT", 240, 2160},
          {"MEDIA_IMAGE_MAX_EDGE", 320, 8192},
          {"MEDIA_FFMPEG_THREADS", 1, 16}
        ] do
      test "#{name} admits #{first} to #{last} and names the range otherwise" do
        name = unquote(name)
        first = unquote(first)
        last = unquote(last)
        key = media_key(name)

        assert media(%{name => "#{first}"})[key] == first
        assert media(%{name => "#{last}"})[key] == last

        for value <- ["#{first - 1}", "#{last + 1}", "0", "-1", "abc", "1.5", "#{first}x", "1e3"] do
          assert message(%{name => value}) ==
                   "#{name} must be an integer from #{first} to #{last}",
                 "#{name}=#{value}"
        end
      end
    end

    test "the size, duration and quota variables take positive integers" do
      for name <- [
            "MEDIA_IMAGE_MAX_MB",
            "MEDIA_VIDEO_MAX_MB",
            "MEDIA_VIDEO_MAX_MINUTES",
            "MEDIA_STORAGE_MAX_GB"
          ],
          value <- ["0", "-5", "ten", "2.5"] do
        assert message(%{name => value}) == "#{name} must be a positive integer",
               "#{name}=#{value}"
      end
    end

    test "a message never holds the value" do
      for {name, value} <- [
            {"MEDIA_VIDEO_MAX_HEIGHT", "secret-4711"},
            {"MEDIA_IMAGE_MAX_MB", "secret-4711"},
            {"MEDIA_EMBED_CONSENT", "secret-4711"},
            {"MEDIA_EXTERNAL_HOSTS", "secret-4711.example.org/path"},
            {"MEDIA_CLAMAV_SOCKET", "secret-4711"}
          ] do
        refute message(%{name => value}) =~ "secret-4711", name
      end
    end
  end

  describe "MEDIA_DIR" do
    test "is required in production" do
      assert message(Map.delete(@prod, "MEDIA_DIR"), :prod) == "MEDIA_DIR is required"

      assert "MEDIA_DIR is required" in RuntimeConfig.errors(
               Map.delete(@prod, "MEDIA_DIR"),
               :prod
             )

      assert RuntimeConfig.errors(@prod, :prod) == []
    end

    test "an empty or whitespace value counts as missing" do
      for value <- ["", "   ", ~s("")] do
        assert message(Map.put(@prod, "MEDIA_DIR", value), :prod) == "MEDIA_DIR is required"
        assert media(%{"MEDIA_DIR" => value}, :dev)[:dir] == "tmp/media"
      end
    end
  end

  describe "MEDIA_CLAMAV_SOCKET" do
    test "takes an absolute path of at most 107 bytes" do
      assert media(%{"MEDIA_CLAMAV_SOCKET" => "/run/clamav/clamd.sock"})[:clamav_socket] ==
               "/run/clamav/clamd.sock"

      path = "/" <> String.duplicate("s", 106)
      assert byte_size(path) == 107
      assert media(%{"MEDIA_CLAMAV_SOCKET" => path})[:clamav_socket] == path
    end

    test "rejects a relative path and a path above 107 bytes" do
      expected = "MEDIA_CLAMAV_SOCKET must be an absolute path of at most 107 bytes"

      for value <- [
            "clamd.sock",
            "run/clamav/clamd.sock",
            "./clamd.sock",
            "~/clamd.sock",
            "/" <> String.duplicate("s", 107),
            # 107 characters, 108 bytes.
            "/" <> String.duplicate("s", 105) <> "é"
          ] do
        assert message(%{"MEDIA_CLAMAV_SOCKET" => value}) == expected, value
      end
    end

    test "MEDIA_VIDEO_MAX_MB stays at most 2047 while a socket is set" do
      socket = "/run/clamav/clamd.sock"

      assert media(%{"MEDIA_VIDEO_MAX_MB" => "2047", "MEDIA_CLAMAV_SOCKET" => socket})[
               :video_max_mb
             ] == 2047

      for value <- ["2048", "4096"] do
        assert message(%{"MEDIA_VIDEO_MAX_MB" => value, "MEDIA_CLAMAV_SOCKET" => socket}) ==
                 "MEDIA_VIDEO_MAX_MB must be at most 2047 while MEDIA_CLAMAV_SOCKET is set"
      end

      assert media(%{"MEDIA_VIDEO_MAX_MB" => "4096"})[:video_max_mb] == 4096
    end

    test "errors/2 names both an invalid socket and an invalid size" do
      assert RuntimeConfig.errors(
               %{"MEDIA_CLAMAV_SOCKET" => "clamd.sock", "MEDIA_IMAGE_MAX_MB" => "0"},
               :test
             ) == [
               "MEDIA_IMAGE_MAX_MB must be a positive integer",
               "MEDIA_CLAMAV_SOCKET must be an absolute path of at most 107 bytes"
             ]
    end
  end

  describe "MEDIA_EXTERNAL_HOSTS and MEDIA_EMBED_HOSTS" do
    test "take host and host:port entries as {host, port} with the host lower-case" do
      for {name, key} <- [
            {"MEDIA_EXTERNAL_HOSTS", :external_hosts},
            {"MEDIA_EMBED_HOSTS", :embed_hosts}
          ] do
        assert media(%{name => " Videos.Example.org ,cdn.example.net:8443,, 10.0.0.5"})[key] == [
                 {"videos.example.org", nil},
                 {"cdn.example.net", 8443},
                 {"10.0.0.5", nil}
               ]
      end
    end

    test "reject an IPv6 entry with a message that names the variable" do
      for name <- ["MEDIA_EXTERNAL_HOSTS", "MEDIA_EMBED_HOSTS"],
          entry <- ["[::1]", "[2001:db8::1]:8443", "[::ffff:10.0.0.1]"] do
        assert message(%{name => "cdn.example.org, " <> entry}) ==
                 "#{name} holds an IPv6 address, which a CSP source cannot name",
               "#{name}=#{entry}"
      end
    end

    test "reject a scheme, a path and an invalid entry with the variable name" do
      for name <- ["MEDIA_EXTERNAL_HOSTS", "MEDIA_EMBED_HOSTS"] do
        for entry <- [
              "https://cdn.example.org",
              "cdn.example.org/videos",
              "cdn.example.org?x=1",
              "user@cdn.example.org"
            ] do
          assert message(%{name => entry}) == "#{name} holds an entry with a scheme or a path",
                 "#{name}=#{entry}"
        end

        for entry <- [
              "cdn.example.org:0",
              "cdn.example.org:70000",
              "cdn.example.org:",
              ":443",
              "[]"
            ] do
          assert message(%{name => entry}) == "#{name} holds an invalid entry", "#{name}=#{entry}"
        end
      end
    end

    test "MEDIA_EMBED_HOSTS must not name the host of PUBLIC_URL, with or without a port" do
      expected = "MEDIA_EMBED_HOSTS must not name the host of PUBLIC_URL"

      for {public_url, entry} <- [
            {"https://learn.example.org", "learn.example.org"},
            {"https://learn.example.org", "learn.example.org:443"},
            {"https://learn.example.org", "Learn.Example.org:8443"},
            {"https://learn.example.org:8443", "learn.example.org"},
            {"https://learn.example.org:8443", "learn.example.org:8443"},
            {"https://LEARN.example.org/", "player.example.org, learn.example.org"}
          ] do
        assert message(%{"PUBLIC_URL" => public_url, "MEDIA_EMBED_HOSTS" => entry}) == expected,
               "#{public_url} with #{entry}"

        assert message(
                 Map.merge(@prod, %{"PUBLIC_URL" => public_url, "MEDIA_EMBED_HOSTS" => entry}),
                 :prod
               ) ==
                 expected
      end

      # Another host, a subdomain of it included, passes.
      assert media(%{
               "PUBLIC_URL" => "https://learn.example.org",
               "MEDIA_EMBED_HOSTS" => "player.learn.example.org, example.org"
             })[:embed_hosts] == [{"player.learn.example.org", nil}, {"example.org", nil}]

      # MEDIA_EXTERNAL_HOSTS may name the own host.
      assert media(%{
               "PUBLIC_URL" => "https://learn.example.org",
               "MEDIA_EXTERNAL_HOSTS" => "learn.example.org"
             })[:external_hosts] == [{"learn.example.org", nil}]
    end

    test "the default PUBLIC_URL of development counts for MEDIA_EMBED_HOSTS" do
      assert message(%{"MEDIA_EMBED_HOSTS" => "localhost:5173"}, :dev) ==
               "MEDIA_EMBED_HOSTS must not name the host of PUBLIC_URL"

      assert message(%{"MEDIA_EMBED_HOSTS" => "localhost"}, :test) ==
               "MEDIA_EMBED_HOSTS must not name the host of PUBLIC_URL"
    end

    test "development defaults to embed.espalier.test only without a value" do
      assert media(%{}, :dev)[:embed_hosts] == [{"embed.espalier.test", nil}]

      assert media(%{"MEDIA_EMBED_HOSTS" => "player.example.org"}, :dev)[:embed_hosts] == [
               {"player.example.org", nil}
             ]

      assert media(%{"MEDIA_EMBED_HOSTS" => "  "}, :dev)[:embed_hosts] == [
               {"embed.espalier.test", nil}
             ]

      assert media(%{}, :test)[:embed_hosts] == []
      assert media(@prod, :prod)[:embed_hosts] == []
    end
  end

  describe "MEDIA_EMBED_CONSENT" do
    test "takes click and auto" do
      assert media(%{"MEDIA_EMBED_CONSENT" => "click"})[:embed_consent] == :click
      assert media(%{"MEDIA_EMBED_CONSENT" => "auto"})[:embed_consent] == :auto
      assert media(%{"MEDIA_EMBED_CONSENT" => ~s("auto")})[:embed_consent] == :auto
    end

    test "rejects other values with the variable name" do
      for value <- ["Auto", "CLICK", "yes", "true", "never"] do
        assert message(%{"MEDIA_EMBED_CONSENT" => value}) ==
                 "MEDIA_EMBED_CONSENT must be one of auto, click",
               value
      end
    end
  end

  describe "WEBHOOK_ALLOWED_HOSTS on top of host_entry/2" do
    test "keeps its messages and its IPv6 entries" do
      assert RuntimeConfig.parse!(
               %{"WEBHOOK_ALLOWED_HOSTS" => "[::1]:4100, hooks.example.org"},
               :test
             )[
               :webhook_allowed_hosts
             ] == [{"::1", 4100}, {"hooks.example.org", nil}]

      assert message(%{"WEBHOOK_ALLOWED_HOSTS" => "https://hooks.example.org"}) ==
               "WEBHOOK_ALLOWED_HOSTS holds an entry with a scheme or a path"

      assert message(%{"WEBHOOK_ALLOWED_HOSTS" => "hooks.example.org:70000"}) ==
               "WEBHOOK_ALLOWED_HOSTS holds an invalid entry"

      # WEBHOOK_ALLOWED_HOSTS may name the host of PUBLIC_URL.
      assert RuntimeConfig.parse!(
               %{
                 "PUBLIC_URL" => "https://learn.example.org",
                 "WEBHOOK_ALLOWED_HOSTS" => "learn.example.org"
               },
               :test
             )[:webhook_allowed_hosts] == [{"learn.example.org", nil}]
    end

    test "webhook_host!/1 keeps its behaviour" do
      assert RuntimeConfig.webhook_host!("Hooks.Example.org:8443") == {"hooks.example.org", 8443}
      assert RuntimeConfig.webhook_host!("[::1]") == {"::1", nil}

      assert_raise ArgumentError, "WEBHOOK_ALLOWED_HOSTS holds an invalid entry", fn ->
        RuntimeConfig.webhook_host!("hooks.example.org:0")
      end

      assert_raise ArgumentError,
                   "WEBHOOK_ALLOWED_HOSTS holds an entry with a scheme or a path",
                   fn ->
                     RuntimeConfig.webhook_host!("hooks.example.org/path")
                   end
    end
  end

  describe "errors/2" do
    test "names every invalid media value in the order of the variables" do
      env = %{
        "MEDIA_VIDEO_MAX_HEIGHT" => "100",
        "MEDIA_IMAGE_MAX_EDGE" => "9000",
        "MEDIA_EXTERNAL_HOSTS" => "[::1]",
        "MEDIA_EMBED_HOSTS" => "https://player.example.org",
        "MEDIA_EMBED_CONSENT" => "never",
        "MEDIA_FFMPEG_THREADS" => "17"
      }

      assert RuntimeConfig.errors(env, :test) == [
               "MEDIA_VIDEO_MAX_HEIGHT must be an integer from 240 to 2160",
               "MEDIA_IMAGE_MAX_EDGE must be an integer from 320 to 8192",
               "MEDIA_EXTERNAL_HOSTS holds an IPv6 address, which a CSP source cannot name",
               "MEDIA_EMBED_HOSTS holds an entry with a scheme or a path",
               "MEDIA_EMBED_CONSENT must be one of auto, click",
               "MEDIA_FFMPEG_THREADS must be an integer from 1 to 16"
             ]
    end
  end

  defp media_key("MEDIA_VIDEO_MAX_HEIGHT"), do: :video_max_height
  defp media_key("MEDIA_IMAGE_MAX_EDGE"), do: :image_max_edge
  defp media_key("MEDIA_FFMPEG_THREADS"), do: :ffmpeg_threads
end
