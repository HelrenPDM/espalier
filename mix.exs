defmodule Espalier.MixProject do
  use Mix.Project

  def project do
    [
      app: :espalier,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      package: [licenses: ["Apache-2.0"]],
      hex: [
        # With a cooldown, Hex resolves only releases that are at least seven
        # days old (README section 13, `mix help hex.config`).
        cooldown: "7d",
        # cloak 1.1.4 and cloak_ecto 1.3.0 have no release that fixes these advisories.
        # EEF-CVE-2026-95105 concerns Cloak.Ciphers.AES.CTR and
        # Cloak.Ciphers.Deprecated.AES.CTR. EEF-CVE-2026-94206 concerns
        # Cloak.Ecto.PBKDF2. Espalier uses neither module: the vault holds only
        # Espalier.Crypto.StrictAESGCM over Cloak.Ciphers.AES.GCM, and lookups use
        # Cloak.Ecto.HMAC. test/espalier/crypto/cipher_allowlist_test.exs fails if
        # that changes. Review rules: docs/security/key-management.md.
        ignore_advisories: ["EEF-CVE-2026-95105", "EEF-CVE-2026-94206"]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Espalier.Application, []},
      extra_applications: [:logger, :runtime_tools, :eldap, :ssl, :public_key]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  # The mock OIDC provider of test/support/dev_oidc/ runs in dev and test
  # only (task 0006).
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support/dev_oidc"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.15"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:swoosh, "~> 1.28"},
      {:gen_smtp, "~> 1.1"},
      {:req, "~> 0.7"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:cloak, "1.1.4"},
      {:cloak_ecto, "1.3.0"},
      {:argon2_elixir, "~> 4.1"},
      {:hammer, "~> 7.5"},
      {:oban, "~> 2.24"},
      {:wax_, "~> 0.7.0"},
      {:x509, "~> 0.9"},
      {:cbor, "~> 1.0"},
      {:nimble_totp, "~> 1.0"},
      {:eqrcode, "~> 0.2.1"},
      # oidcc is listed directly, because oidcc_plug 0.5.1 accepts oidcc ~> 3.7,
      # and oidcc 3.2.0-beta.1 through 3.8.x accept an encrypted ID token
      # without a signature (CVE-2026-75759, task 0006).
      {:oidcc, "~> 3.9"},
      {:oidcc_plug, "~> 0.5.1"},
      {:jose, "~> 1.11"},
      {:mox, "~> 1.3", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.16", only: [:dev, :test], runtime: false, warn_if_outdated: true},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # hex.audit runs before any task that loads or starts the application
      # (`mix help hex.audit`).
      precommit: [
        "hex.audit",
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "sobelow --config --exit",
        "deps.audit",
        "test"
      ]
    ]
  end
end
