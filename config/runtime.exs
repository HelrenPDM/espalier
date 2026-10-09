import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/espalier start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :espalier, EspalierWeb.Endpoint, server: true
end

config :espalier, EspalierWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Account, session and mail settings in every environment (README section
# 6.11). An invalid value stops the boot; Espalier.RuntimeConfig lists the
# variables and their defaults.
settings = Espalier.RuntimeConfig.parse!(System.get_env(), config_env())
config :espalier, settings

# External identity providers: the full structs for the sign-in code and the
# public entries for the session payload and GET /auth/providers.
providers = Espalier.Identity.Config.parse!(System.get_env(), config_env())
config :espalier, :identity_providers, providers
config :espalier, :auth_providers, Enum.map(providers, &Espalier.Identity.Config.public_entry/1)

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :espalier, Espalier.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  # The encrypted session cookies and the rate-limit key derive from it, and
  # the cookie store needs at least 64 bytes; an empty value stops the boot.
  secret_key_base =
    case String.trim(System.get_env("SECRET_KEY_BASE", "")) do
      value when byte_size(value) >= 64 ->
        value

      _ ->
        raise """
        environment variable SECRET_KEY_BASE is missing or shorter than 64 bytes.
        You can generate one by calling: mix phx.gen.secret
        """
    end

  # Each CLOAK_KEY_V<n> defines the cipher tag AES.GCM.V<n>. The highest version
  # encrypts new values, and the others only decrypt. An empty or
  # whitespace-only value counts as missing. Espalier.Crypto.Keys.check!/0
  # validates the values at boot (docs/security/key-management.md).
  cloak_keys =
    for {"CLOAK_KEY_V" <> version, value} <- System.get_env(),
        String.match?(version, ~r/\A[1-9][0-9]*\z/),
        String.trim(value) != "",
        do: {String.to_integer(version), value}

  hmac_secret = System.get_env("CLOAK_HMAC_SECRET", "")

  missing_cloak =
    for {name, missing?} <- [
          {"CLOAK_KEY_V1", cloak_keys == []},
          {"CLOAK_HMAC_SECRET", String.trim(hmac_secret) == ""}
        ],
        missing?,
        do: name

  if missing_cloak != [] do
    raise "Missing environment variables: #{Enum.join(missing_cloak, ", ")}"
  end

  config :espalier, Espalier.Vault, keys: cloak_keys
  config :espalier, Espalier.Hashed.HMAC, secret: hmac_secret

  # Passkeys (task 0005): the relying party id is the host of PUBLIC_URL, and
  # the only origin is its scheme, host and port (URI.to_string/1 omits the
  # default port). RuntimeConfig also accepts http, which WebAuthn allows
  # only on localhost, so production requires https.
  public_uri = URI.parse(Keyword.fetch!(settings, :public_url))

  if public_uri.scheme != "https" do
    raise "PUBLIC_URL must use https in production, because passkeys derive their origin from it"
  end

  config :espalier, :webauthn,
    rp_id: public_uri.host,
    origins: [
      URI.to_string(%URI{scheme: public_uri.scheme, host: public_uri.host, port: public_uri.port})
    ]

  host = System.get_env("PHX_HOST") || "example.com"

  config :espalier, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :espalier, EspalierWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :espalier, EspalierWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :espalier, EspalierWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Production mail goes out over SMTP with STARTTLS, authentication and
  # certificate verification; gen_smtp receives `tls_options` for the
  # STARTTLS upgrade (Swoosh.Adapters.SMTP 1.28, "TLS options and certificate
  # verification"). Without SMTP_HOST, an instance sends no mail:
  # Espalier.Mailer.DisabledAdapter refuses every delivery, and the boot logs
  # a warning.
  case String.trim(System.get_env("SMTP_HOST", "")) do
    "" ->
      config :espalier, Espalier.Mailer, adapter: Espalier.Mailer.DisabledAdapter

    smtp_host ->
      config :espalier, Espalier.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: smtp_host,
        port: String.to_integer(System.get_env("SMTP_PORT", "587")),
        username: System.get_env("SMTP_USERNAME"),
        password: System.get_env("SMTP_PASSWORD"),
        ssl: false,
        tls: :always,
        auth: :always,
        tls_options: [
          versions: [:"tlsv1.2", :"tlsv1.3"],
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: String.to_charlist(smtp_host),
          depth: 99,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
  end
end
