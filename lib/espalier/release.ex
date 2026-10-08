defmodule Espalier.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :espalier

  alias Espalier.Crypto.{Keys, Rotation}

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
