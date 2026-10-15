import Config

# One boot names every gap of the environment (task 0017, step 4).
# Espalier.BootCheck collects the missing and invalid variables of the
# checks below and of the production block, which no longer raise one at a
# time. No message contains the value of a variable. The production block
# reads the variables that the boot check covers through
# Espalier.RuntimeConfig.value/2, as the check does, so that both see the
# same trimmed values without surrounding double quotes.
env = System.get_env()

case Espalier.BootCheck.errors(env, config_env()) do
  [] ->
    :ok

  messages ->
    raise "The environment stops the boot:\n" <> Enum.map_join(messages, "\n", &("  * " <> &1))
end

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
  http: [port: String.to_integer(Espalier.RuntimeConfig.value(env, "PORT") || "4000")]

# Account, session and mail settings in every environment (README section
# 6.11), config :espalier, :learning with TRACKING_DETAIL and
# INSIGHTS_ORG_UNIT, and config :espalier, :insights with the group
# threshold, the feedback and test-notes switches and the retention periods
# (README section 10), and the directory of the SCORM packages
# (EXPORT_DIR, required in production). An invalid value stops the boot;
# Espalier.RuntimeConfig lists the variables and their defaults.
settings = Espalier.RuntimeConfig.parse!(env, config_env())
config :espalier, settings

# The redirect URIs that the mock OIDC provider of dev and test admits
# (test/support/dev_oidc/), in the form of PUBLIC_URL that the application
# sends (Espalier.RuntimeConfig.normalize_url/1).
if config_env() in [:dev, :test] do
  public_url = Keyword.fetch!(settings, :public_url)

  config :espalier, Espalier.DevOidc,
    redirect_uris:
      for(key <- ["entra", "google", "oidc"], do: "#{public_url}/auth/oidc/#{key}/callback"),
    post_logout_redirect_uris: ["#{public_url}/signed-out"]
end

# External identity providers: the full structs for the sign-in code and the
# public entries for the session payload and GET /auth/providers.
providers = Espalier.Identity.Config.parse!(env, config_env())
config :espalier, :identity_providers, providers
config :espalier, :auth_providers, Enum.map(providers, &Espalier.Identity.Config.public_entry/1)

if config_env() == :prod do
  # Format: ecto://USER:PASS@HOST/DATABASE
  database_url = Espalier.RuntimeConfig.value(env, "DATABASE_URL")

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # PostgreSQL only through TLS with certificate and host name verification
  # (ASVS 12.3.1 and 12.3.4). DATABASE_CA_CERT_FILE names the only trust
  # anchor, in compose.yaml the CA of the service db-certs, and the host of
  # DATABASE_URL must match the server certificate. Postgrex merges these
  # options into its defaults, which verify the peer and match the host
  # name. `ssl: true` would trust every CA of the system store instead
  # (Postgrex 0.22.4, Postgrex.Protocol). Ecto merges the query parameters of
  # the URL over these options, so the boot check stops a DATABASE_URL with
  # the parameter `ssl`, and one without a host.
  config :espalier, Espalier.Repo,
    ssl: [
      verify: :verify_peer,
      cacertfile: Espalier.RuntimeConfig.value(env, "DATABASE_CA_CERT_FILE"),
      server_name_indication: String.to_charlist(URI.parse(database_url).host)
    ],
    url: database_url,
    pool_size: String.to_integer(Espalier.RuntimeConfig.value(env, "POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  # The encrypted session cookies and the rate-limit key derive from it, and
  # the cookie store needs at least 64 bytes; the boot check stops a boot
  # with a missing or shorter value.
  secret_key_base = Espalier.RuntimeConfig.value(env, "SECRET_KEY_BASE")

  # Each CLOAK_KEY_V<n> defines the cipher tag AES.GCM.V<n>. The highest version
  # encrypts new values, and the others only decrypt. An empty or
  # whitespace-only value counts as missing, which the boot check reports.
  # Espalier.Crypto.Keys.check!/0 validates the values at boot
  # (docs/security/key-management.md).
  cloak_keys =
    for {"CLOAK_KEY_V" <> version = name, _value} <- env,
        String.match?(version, ~r/\A[1-9][0-9]*\z/),
        value = Espalier.RuntimeConfig.value(env, name),
        value != nil,
        do: {String.to_integer(version), value}

  hmac_secret = Espalier.RuntimeConfig.value(env, "CLOAK_HMAC_SECRET") || ""

  config :espalier, Espalier.Vault, keys: cloak_keys
  config :espalier, Espalier.Hashed.HMAC, secret: hmac_secret

  # Passkeys (task 0005): the relying party id is the host of PUBLIC_URL, and
  # the only origin is its scheme, host and port (URI.to_string/1 omits the
  # default port). RuntimeConfig lower-cases the host, the form of the origin
  # in the client data of the browser, and also accepts http, which WebAuthn
  # allows only on localhost, so the boot check requires https in production.
  public_uri = URI.parse(Keyword.fetch!(settings, :public_url))

  config :espalier, :webauthn,
    rp_id: public_uri.host,
    origins: [
      URI.to_string(%URI{scheme: public_uri.scheme, host: public_uri.host, port: public_uri.port})
    ]

  # The boot check requires PHX_HOST and the same host in PUBLIC_URL.
  host = Espalier.RuntimeConfig.value(env, "PHX_HOST")

  config :espalier, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :espalier, EspalierWeb.Endpoint,
    # The port of PUBLIC_URL, for example the HTTPS_PORT of the proxy example.
    url: [host: host, port: public_uri.port, scheme: "https"],
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
  case Espalier.RuntimeConfig.value(env, "SMTP_HOST") do
    nil ->
      config :espalier, Espalier.Mailer, adapter: Espalier.Mailer.DisabledAdapter

    smtp_host ->
      config :espalier, Espalier.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: smtp_host,
        port: String.to_integer(Espalier.RuntimeConfig.value(env, "SMTP_PORT") || "587"),
        username: Espalier.RuntimeConfig.value(env, "SMTP_USERNAME"),
        password: Espalier.RuntimeConfig.value(env, "SMTP_PASSWORD"),
        ssl: false,
        tls: :always,
        auth: :always,
        # gen_smtp would otherwise connect to the MX hosts of SMTP_HOST instead of the host.
        no_mx_lookups: true,
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
