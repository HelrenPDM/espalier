defmodule Espalier.Release do
  @moduledoc """
  Operator functions of a release, called with `bin/espalier eval`.

  A release carries no Mix, so the operator calls these functions instead of
  Mix tasks. Each call starts a node of its own next to the running
  application. In the container of a Docker Compose installation a call
  reads:

      docker compose exec app bin/espalier eval 'Espalier.Release.encryption_status()'

  `grant_role/2`, `invite_user/1`, `end_all_sessions/0`,
  `create_api_client/2`, `reset_directory_lock/2`, `import_pack/2` and
  `seed_demo/1` start the application with the Oban queues and plugins off
  and the admin bootstrap disabled, so a job that a function inserts (an
  invitation mail, for example) is processed by the running application and
  not by the eval node. `import_pack/2` and `seed_demo/1` process the media
  jobs of a pack in the calling process before they publish. The calls with
  their arguments are listed in
  [Operations](operations.md), section "Release functions", and the
  first-admin, content and upgrade procedures that use them are in
  [Self-hosting](self-hosting.md) and [Setup](setup.md).

  ## Functions

  | Group | Function | Effect |
  |---|---|---|
  | Database | `migrate/0` | Runs every pending migration. `bin/migrate` calls it. |
  | Database | `rollback/2` | Reverts the migrations of a repo down to and including a version. |
  | Keys | `rotate_encryption/0` | Re-encrypts the encrypted columns under the current key and prints the counts. |
  | Keys | `encryption_status/0` | Prints the cipher tags per encrypted column. |
  | Accounts | `grant_role/2` | Grants a `manual` role to the account of an address. |
  | Accounts | `invite_user/1` | Invites a new address or sends a new invitation. |
  | Accounts | `end_all_sessions/0` | Ends every session of every user. |
  | Accounts | `create_api_client/2` | Creates a machine client of the integration API and prints its token once. |
  | LDAP | `check_ldap/1` | Checks the connection to an LDAP provider step by step. |
  | LDAP | `reset_directory_lock/2` | Clears the directory failure counter of a user name. |
  | Content | `import_pack/2` | Imports a content pack directory and publishes it, as `mix espalier.import` does. |
  | Content | `seed_demo/1` | Imports and publishes the demo pack of the image and seeds the demo policy and tools. |

  Every function except `migrate/0` and `rollback/2` prints its output, so
  that `bin/espalier eval` shows it. The documentation of each function
  states what it prints and what it returns.
  """
  @app :espalier

  alias Espalier.Accounts
  alias Espalier.Accounts.{FailureCounters, RoleGrant, Scope}
  alias Espalier.Catalog.Pack.Report
  alias Espalier.Crypto.{Keys, Rotation}
  alias Espalier.Identity.Ldap
  alias Espalier.Policies.Demo
  alias Espalier.Repo

  @doc """
  Runs every pending migration of every repo in `:ecto_repos`.

  Returns one `{:ok, versions, apps}` tuple per repo, where `versions` lists
  the migration versions that ran.

      bin/migrate
      bin/espalier eval 'Espalier.Release.migrate()'

  `bin/migrate` is the form that the upgrade procedure of
  [Self-hosting](self-hosting.md) uses.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Reverts the migrations of `repo` down to and including `version`.

  `version` is a number from the column `version` of the table
  `schema_migrations`. Run the function in the newer image, which carries
  the migrations to revert, before the older image starts. Returns
  `{:ok, versions, apps}`, where `versions` lists the migration versions that
  ran down.

      bin/espalier eval 'Espalier.Release.rollback(Espalier.Repo, VERSION)'

  See [Operations](operations.md), section "Release functions", for the
  query that lists the versions.
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Re-encrypts every encrypted column of the registered rotation-only schemas
  under the current key, then prints the rows per schema and the cipher tags
  per column. Prints no value and no key.

  Returns `:ok`. The function raises when `Espalier.Crypto.Keys.check!/0`
  finds the Cloak keys invalid.

      bin/espalier eval "Espalier.Release.rotate_encryption()"

  The runbook is `docs/security/key-management.md`.
  """
  def rotate_encryption do
    with_vault(fn repo ->
      for {schema, rows} <- Rotation.run(repo, Rotation.schemas()) do
        IO.puts("#{inspect(schema)}: #{rows} rows re-encrypted")
      end

      print_tag_counts(repo)
    end)
  end

  @doc """
  Prints the cipher tags per encrypted column and the number of values under
  each tag. Prints no value and no key. Returns `:ok`.

      bin/espalier eval "Espalier.Release.encryption_status()"
  """
  def encryption_status do
    with_vault(&print_tag_counts/1)
  end

  @doc """
  Grants the `manual` role `role` to the account of `email` and prints the
  result, which the function also returns. `role` is the name of a value of
  the field `role` of `Espalier.Accounts.RoleGrant`: `learner`,
  `facilitator`, `author`, `registrar`, `analyst` or `admin`.

  | Result | Case |
  |---|---|
  | `{:ok, grant}` | The role is granted, or the account holds this manual grant already. |
  | `{:error, :unknown_role}` | `role` names no role. |
  | `{:error, :not_found}` | No account has this address. |
  | `{:error, :demo_user}` | The account is a demo user, which receives no grant. |

  A new grant ends every session of the user, so the change takes effect at
  the next sign-in. This is the explicit operator action that grants `admin`
  to a federated account (plan section 6.11 in `docs/plan/README.md`).

      bin/espalier eval 'Espalier.Release.grant_role("admin", "a@example.org")'
  """
  def grant_role(role, email) when is_binary(role) and is_binary(email) do
    start_app()

    result =
      case Enum.find(Ecto.Enum.values(RoleGrant, :role), &(Atom.to_string(&1) == role)) do
        nil ->
          {:error, :unknown_role}

        role ->
          case Accounts.get_user_by_email(email) do
            nil -> {:error, :not_found}
            user -> Accounts.grant_role(Scope.system(), user, role)
          end
      end

    print(result)
  end

  @doc """
  Invites a new address, or sends a new invitation to an invitable account,
  and prints the result, which the function also returns.

  | Result | Case |
  |---|---|
  | `{:ok, user}` | The address was unknown; the function created the invited user. |
  | `:ok` | The account exists and is invitable; the function sent a new invitation. |
  | `{:error, :not_invitable}` | The account exists but is not invitable. |
  | `{:error, changeset}` | The invited user could not be stored. |

  An account is invitable when it is an active local user with an address,
  without an external identity and without an enrolled factor
  (`Espalier.Accounts.invitable?/1`). The function inserts the mail job; the
  running application sends the mail.

      bin/espalier eval 'Espalier.Release.invite_user("a@example.org")'
  """
  def invite_user(email) when is_binary(email) do
    start_app()

    result =
      case Accounts.get_user_by_email(email) do
        nil -> Accounts.invite_user(Scope.system(), %{email: email})
        user -> Accounts.resend_invitation(Scope.system(), user)
      end

    print(result)
  end

  @doc """
  Ends every session of every user and prints the result `{:ok, count}`,
  where `count` is the number of ended sessions. The function returns the
  same value.

      bin/espalier eval 'Espalier.Release.end_all_sessions()'
  """
  def end_all_sessions do
    start_app()
    print(Accounts.end_all_sessions(Scope.system()))
  end

  @doc """
  Checks the connection to the LDAP provider `provider_key` and prints one
  line per step: for `ldaps` first the TLS handshake, because `:eldap`
  reports every connect failure as `connect failed`, then the connect, the
  StartTLS step for `starttls`, the service bind and a base-scope search on
  the base DN. It prints no password and no directory data beyond the step
  results.

  `provider_key` is the key of a provider in `AUTH_PROVIDERS`. The function
  returns `:ok` when every step succeeded and `:error` otherwise. For a key
  that names no LDAP provider it prints and returns
  `{:error, :unknown_provider}`.

      bin/espalier eval 'Espalier.Release.check_ldap("ldap")'
  """
  def check_ldap(provider_key) when is_binary(provider_key) do
    load_app()

    case Ldap.provider(provider_key) do
      {:ok, config} ->
        if config.tls == :ldaps, do: print_tls_probe(config)
        steps = Ldap.check_service(config)

        for {step, result} <- steps do
          IO.puts("#{step}: #{format_step(result)}")
        end

        if Enum.all?(steps, &(elem(&1, 1) == :ok)), do: :ok, else: :error

      :error ->
        print({:error, :unknown_provider})
    end
  end

  defp print_tls_probe(config) do
    case Ldap.tls_probe(config) do
      :ok -> IO.puts("tls_handshake: ok")
      {:error, reason} -> IO.puts("tls_handshake: error #{Ldap.reason_tag(reason)}")
    end
  end

  defp format_step(:ok), do: "ok"
  defp format_step({:error, reason}), do: "error #{reason}"

  @doc """
  Clears the directory failure counter of `username` at the LDAP provider
  `provider_key`, also for a person without a platform account. It looks the
  person up through the service account and prints the result, which the
  function also returns: `:ok`, `{:error, :not_found}` when the directory
  has no such person, or `{:error, :unavailable}` when the provider is
  unknown or the lookup failed.

      bin/espalier eval 'Espalier.Release.reset_directory_lock("ldap", "jdoe")'
  """
  def reset_directory_lock(provider_key, username)
      when is_binary(provider_key) and is_binary(username) do
    start_app()

    result =
      with {:ok, config} <- provider_or_unavailable(provider_key),
           {:ok, entry} <- lookup_for_reset(config, username) do
        FailureCounters.reset_directory(Scope.system(), provider_key, entry.subject)
      end

    print(result)
  end

  defp provider_or_unavailable(provider_key) do
    case Ldap.provider(provider_key) do
      {:ok, config} -> {:ok, config}
      :error -> {:error, :unavailable}
    end
  end

  defp lookup_for_reset(config, username) do
    case Ldap.lookup(config, username) do
      {:ok, entry} -> {:ok, entry}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  @doc """
  Imports the content pack at `path` as `mix espalier.import` does. The
  function starts the application with the Oban queues and plugins off and
  the admin bootstrap disabled, so that the ingest of the media of the pack
  finds a running Oban instance.
  It prints the report in the form of `mix espalier.validate` and a line with
  the outcome, and publishes a validated import unless `draft: true` is
  given, which stops after the draft. The lines of the outcome are listed in
  [Content packs](content-packs.md), section "On the command line".

  Before the publish, the function processes the media of the pack in the
  calling process (`Espalier.Catalog.Pack.Report.run_import/2`), because
  the eval node inserts jobs without processing them. With `draft: true` the
  media jobs stay queued for the running server.

  `path` is the pack directory as the node sees it. `opts` takes `draft`
  (default `false`).

  Returns `{:ok, pack_import}` with the published import or the draft, and
  `{:error, reason}` otherwise: the failed import, the changeset of an import
  that could not be stored, `:not_validated`, or the reason why the repo did
  not start.

      bin/espalier eval 'Espalier.Release.import_pack("/srv/packs/my-pack")'
      bin/espalier eval 'Espalier.Release.import_pack("/srv/packs/my-pack", draft: true)'

  The image holds no content pack other than the demo pack, so the operator mounts the pack
  directory into the container, read-only, for example with
  `docker compose run --rm -v "$PWD/content/demo:/srv/packs/my-pack:ro" app`
  in front of the command. See [Content packs](content-packs.md), section
  "In a release".
  """
  @spec import_pack(Path.t(), keyword()) :: {:ok, Ecto.Schema.schema()} | {:error, term()}
  def import_pack(path, opts \\ []) when is_binary(path) and is_list(opts) do
    start_app()
    draft? = Keyword.get(opts, :draft, false)

    case Ecto.Migrator.with_repo(Repo, fn _repo -> Report.run_import(path, draft: draft?) end) do
      {:ok, result, _apps} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a machine client of the integration API with the name `name` and
  the scopes `scopes` and prints its token once; the table stores only its
  hash. Prints `{:ok, name}` with the token on the next line, and returns
  `{:ok, id}` of the client.

  `name` has 1 to 100 characters. `scopes` holds at least one scope, and the
  only scope that exists is `credentials:read`. For an invalid value the
  function prints and returns `{:error, errors}` with the errors of the
  changeset.

      bin/espalier eval 'Espalier.Release.create_api_client("hr-system", ["credentials:read"])'

  The admin area creates and deletes clients as well. A token rotation
  creates a new client and then deletes the old one
  (`docs/security/key-management.md`).
  """
  @spec create_api_client(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, term()}
  def create_api_client(name, scopes) when is_binary(name) and is_list(scopes) do
    start_app()

    case Accounts.create_api_client(Scope.system(), %{name: name, scopes: scopes}) do
      {:ok, {client, token}} ->
        IO.puts(inspect({:ok, client.name}))
        IO.puts("token: " <> token)
        {:ok, client.id}

      {:error, %Ecto.Changeset{} = changeset} ->
        print({:error, changeset.errors})

      {:error, reason} ->
        print({:error, reason})
    end
  end

  @doc """
  Imports and publishes the demo pack that the image carries in
  `priv/demo_pack`, then seeds the policy `usage-policy`, which the demo
  qualification `basics` requires, and the approved tools of the demo
  (`Espalier.Policies.Demo.seed/0`). This is the release counterpart of
  `mix espalier.import content/demo` followed by `mix espalier.seed_demo`,
  and `make demo-up` and `scripts/smoke.sh` run it. See
  [Demo instance](demo-instance.md) and [Self-hosting](self-hosting.md),
  section "Content".

  `path` is the directory of the demo pack and defaults to
  `priv/demo_pack` of the release.

      bin/espalier eval 'Espalier.Release.seed_demo()'

  The import publishes the pack as `import_pack/2` without `draft: true`
  does. The seed skips every policy key and tool name that exists. Returns
  `{:ok, %{pack: pack_import, policies: count, tools: count}}` or the error
  of the import.
  """
  @spec seed_demo(Path.t()) :: {:ok, map()} | {:error, term()}
  def seed_demo(path \\ Application.app_dir(@app, "priv/demo_pack")) when is_binary(path) do
    start_app()

    # Ecto.Migrator.with_repo/2 of ecto_sql 3.14.0 reuses the running Repo:
    # start_link answers already_started, and the cleanup leaves the running
    # pool in place.
    with {:ok, pack_import} <- import_pack(path),
         {:ok, %{policies: policies, tools: tools}} <- Demo.seed() do
      IO.puts("Seeded #{policies} policies and #{tools} approved tools.")
      {:ok, %{pack: pack_import, policies: policies, tools: tools}}
    end
  end

  defp print(result) do
    IO.puts(inspect(result))
    result
  end

  # An eval node inserts jobs without processing them and runs no bootstrap.
  # The order matters: fetch_env!/2 can raise before the application is
  # loaded, and loading can replace a value set before it.
  defp start_app do
    load_app()

    Application.put_env(
      @app,
      Oban,
      Keyword.merge(Application.fetch_env!(@app, Oban), queues: false, plugins: false)
    )

    Application.put_env(@app, :bootstrap_on_boot, false)
    {:ok, _apps} = Application.ensure_all_started(@app)
    :ok
  end

  defp with_vault(fun) do
    load_app()
    Keys.check!()

    case Espalier.Vault.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fun)
    end

    :ok
  end

  defp print_tag_counts(repo) do
    case Rotation.tag_counts(repo, Rotation.schemas()) do
      counts when counts == %{} ->
        IO.puts("No encrypted column is registered for rotation.")

      counts ->
        for {{table, column}, tags} <- Enum.sort(counts) do
          IO.puts("#{table}.#{column}: #{format_tags(tags)}")
        end
    end
  end

  defp format_tags(tags) when tags == %{}, do: "no values"

  defp format_tags(tags) do
    tags |> Enum.sort() |> Enum.map_join(", ", fn {tag, count} -> "#{tag}: #{count}" end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
