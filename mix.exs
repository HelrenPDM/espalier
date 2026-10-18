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
      docs: docs(),
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
  # The mock OIDC provider of test/support/dev_oidc/ (task 0006) and the
  # end-to-end seeding controller of test/support/dev_e2e/ (task 0011)
  # compile in dev and test only.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support/dev_oidc", "test/support/dev_e2e"]
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
      {:yaml_elixir, "~> 2.12"},
      {:ymlr, "~> 5.1"},
      {:open_api_spex, "~> 3.22"},
      {:mox, "~> 1.3", only: :test},
      {:stream_data, "~> 1.4", only: :test},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.16", only: [:dev, :test], runtime: false, warn_if_outdated: true},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  # Configuration of `mix docs` (ExDoc, dev environment only; `make docs-api`).
  #
  # The landing page is the README, which holds the quick start and the links to
  # the introductions. ExDoc resolves a relative link to an extra by the file
  # name alone, so two extras named README.md would shadow each other. The
  # README of the repository root and docs/plan/README.md are the only ones in
  # the list, and links to docs/guides/README.md and docs/architecture/README.md
  # are absolute URLs of the repository. The same holds for every file outside
  # the list (test/docs/guides_links_test.exs checks both rules).
  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/HelrenPDM/espalier",
      source_ref: "main",
      homepage_url: "https://github.com/HelrenPDM/espalier",
      formatters: ["html"],
      extras: docs_extras(),
      groups_for_extras: [
        Introductions: [
          "README.md",
          "docs/guides/purpose.md",
          "docs/guides/setup.md",
          "docs/guides/tenant-and-authentication.md",
          "docs/guides/course-yaml.md"
        ],
        Guides: ~r{^docs/guides/},
        Security: ~r{^docs/security/},
        Project: [
          "docs/plan/README.md",
          "CHANGELOG.md",
          "CONTRIBUTING.md",
          "SECURITY.md"
        ]
      ],
      nest_modules_by_prefix: [
        Espalier.Accounts.Passkeys,
        Espalier.Catalog.Pack.Schema,
        Espalier.Crypto.Rotation,
        Espalier.DevOidc,
        Espalier.Identity.Ldap,
        Espalier.Identity.Oidc,
        Espalier.Workbench,
        EspalierWeb.Admin,
        EspalierWeb.Auth,
        EspalierWeb.Me,
        EspalierWeb.Plugs,
        EspalierWeb.Schemas.Admin,
        EspalierWeb.Schemas
      ],
      groups_for_modules: docs_groups_for_modules(),
      # The security guides cite functions that carry `@doc false` (callbacks
      # and generated Cloak.Vault functions) and the module
      # Espalier.Application (`@moduledoc false`) as the place where a control
      # sits. They have no page, so ExDoc leaves exactly these references as
      # code.
      skip_code_autolink_to: [
        "Cloak.Ecto.Type",
        "Espalier.Application",
        "Espalier.Application.settings_line/0",
        "Espalier.Application.start/2",
        "Espalier.Identity.Oidc.Supervisor.init/1",
        "Espalier.Vault.decrypt!/1",
        "Espalier.Vault.encrypt!/1",
        "Espalier.Vault.format_status/1",
        "EspalierWeb.OidcController.authorize_opts/2",
        "EspalierWeb.OidcController.callback_opts/1"
      ]
    ]
  end

  # The order is the order of the sidebar. The Guides group collects the
  # reference guides in the order of docs/guides/README.md.
  defp docs_extras do
    [
      {"README.md", title: "Overview"},
      "docs/guides/purpose.md",
      "docs/guides/setup.md",
      "docs/guides/tenant-and-authentication.md",
      "docs/guides/course-yaml.md",
      "docs/guides/content-packs.md",
      "docs/guides/media.md",
      "docs/guides/pack-workbench.md",
      "docs/guides/scorm-export.md",
      "docs/guides/self-hosting.md",
      "docs/guides/operations.md",
      "docs/guides/demo-instance.md",
      "docs/guides/identity-providers.md",
      {"docs/guides/security.md", title: "Security guide"},
      "docs/security/asvs-l2.md",
      "docs/security/authentication.md",
      "docs/security/crypto-inventory.md",
      "docs/security/key-management.md",
      "docs/security/logging.md",
      {"docs/security/wax-spike.md", title: "Spike: wax_ on the target toolchain"},
      {"docs/plan/README.md", filename: "implementation-plan", title: "Implementation plan"},
      "CHANGELOG.md",
      "CONTRIBUTING.md",
      {"SECURITY.md", filename: "security-policy", title: "Security policy"}
    ]
  end

  # The first group that matches a module takes it. Inside a group ExDoc sorts
  # by module name and puts nested modules (nest_modules_by_prefix) after the
  # others, so Espalier.Catalog.Pack heads the content pack format.
  defp docs_groups_for_modules do
    [
      "Content pack format": [
        Espalier.Catalog.Pack,
        Espalier.Catalog.Pack.Directives,
        Espalier.Catalog.Pack.Entries,
        Espalier.Catalog.Pack.LineIndex,
        Espalier.Catalog.Pack.MediaPath,
        Espalier.Catalog.Pack.Spdx,
        ~r/^Espalier\.Catalog\.Pack\.Schema\./
      ],
      "Content pack processing": [
        Espalier.Catalog.Alignment,
        Espalier.Catalog.Pack.Archive,
        Espalier.Catalog.Pack.Diff,
        Espalier.Catalog.Pack.Hosts,
        Espalier.Catalog.Pack.Importer,
        Espalier.Catalog.Pack.Loader,
        Espalier.Catalog.Pack.Normalizer,
        Espalier.Catalog.Pack.Publisher,
        Espalier.Catalog.Pack.Report,
        Espalier.Catalog.Pack.Validator,
        Espalier.Catalog.PackImport,
        ~r/^Espalier\.Workbench/
      ],
      "Mix tasks": ~r/^Mix\.Tasks\./,
      "Release and operations": [
        Espalier,
        Espalier.Application,
        Espalier.BootCheck,
        Espalier.Logger.JSONFormatter,
        Espalier.Mailer,
        Espalier.Mailer.DisabledAdapter,
        Espalier.Release,
        Espalier.Repo,
        Espalier.RuntimeConfig,
        Espalier.Telemetry.QueryLog,
        EspalierWeb.Telemetry
      ],
      "Development tools": [~r/^Espalier\.DevOidc/, EspalierWeb.DevE2EController],
      Media: [~r/^Espalier\.Media(\.|$)/, Espalier.Catalog.ProgramMedia],
      Catalog: ~r/^Espalier\.Catalog(\.|$)/,
      Learning: ~r/^Espalier\.Learning(\.|$)/,
      Credentials: ~r/^Espalier\.Credentials(\.|$)/,
      Policies: ~r/^Espalier\.Policies(\.|$)/,
      Insights: ~r/^Espalier\.Insights(\.|$)/,
      Interop: ~r/^Espalier\.Interop(\.|$)/,
      Accounts: ~r/^Espalier\.Accounts(\.|$)/,
      Identity: ~r/^Espalier\.Identity(\.|$)/,
      "Encryption and audit": [
        ~r/^Espalier\.(Crypto|Encrypted|Hashed|Audit)(\.|$)/,
        Espalier.RateLimit,
        Espalier.SecurityLog,
        Espalier.Vault
      ],
      "Web: framework layer": [
        EspalierWeb,
        EspalierWeb.BlockDownload,
        EspalierWeb.CastErrorRenderer,
        EspalierWeb.ChangesetJSON,
        EspalierWeb.Endpoint,
        EspalierWeb.ErrorJSON,
        EspalierWeb.FactorInput,
        EspalierWeb.FallbackController,
        EspalierWeb.Gettext,
        EspalierWeb.HealthController,
        EspalierWeb.MediaMultipart,
        EspalierWeb.PackMultipart,
        EspalierWeb.Router,
        EspalierWeb.SpaController,
        EspalierWeb.TransactionCookie,
        EspalierWeb.UserAuth,
        EspalierWeb.WebauthnCeremony,
        ~r/^EspalierWeb\.Plugs\./
      ],
      "Web: sign-in and account API": [
        EspalierWeb.OidcController,
        EspalierWeb.OidcIntentController,
        EspalierWeb.ProviderController,
        EspalierWeb.SessionController,
        EspalierWeb.SessionJSON,
        ~r/^EspalierWeb\.(Auth|Me)\./
      ],
      "Web: admin and integration API": [
        EspalierWeb.ReportController,
        ~r/^EspalierWeb\.(Admin|Facilitator|Integration|Registrar)\./
      ],
      "Web: OpenAPI schemas": [EspalierWeb.ApiSpec, ~r/^EspalierWeb\.(ApiSpec|Schemas)\./],
      "Web: learner API": ~r/^EspalierWeb\./
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
