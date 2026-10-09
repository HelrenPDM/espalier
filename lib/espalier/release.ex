defmodule Espalier.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :espalier

  alias Espalier.Accounts
  alias Espalier.Accounts.{FailureCounters, RoleGrant, Scope}
  alias Espalier.Crypto.{Keys, Rotation}
  alias Espalier.Identity.Ldap

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Re-encrypts every encrypted column of the registered rotation-only schemas
  under the current key, then prints the rows per schema and the cipher tags
  per column. Prints no value and no key.

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
  each tag. Prints no value and no key.

      bin/espalier eval "Espalier.Release.encryption_status()"
  """
  def encryption_status do
    with_vault(&print_tag_counts/1)
  end

  @doc """
  Grants the `manual` role `role` to the account of `email` and prints the
  result: `{:ok, grant}`, `{:error, :unknown_role}` or `{:error, :not_found}`.
  This is the explicit operator action that grants `admin` to a federated
  account (README section 6.11).

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
  and prints the result.

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
  Ends every session of every user and prints the number of ended sessions.

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
  `provider_key`, also for a person without a platform account (task 0007,
  step 15). It looks the person up through the service account and prints
  `:ok`, `{:error, :not_found}` or `{:error, :unavailable}`.

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
