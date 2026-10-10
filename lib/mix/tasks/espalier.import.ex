defmodule Mix.Tasks.Espalier.Import do
  @shortdoc "Imports and publishes a content pack"
  @moduledoc """
  Imports the content pack in `PATH` and publishes it (task 0008, step 11):

      mix espalier.import content/demo
      mix espalier.import content/demo --draft

  The task starts the application and runs
  `Espalier.Catalog.Pack.Importer.import/2` without an actor. A failed import
  prints its report in the form of `mix espalier.validate` and exits with
  status 1. A validated import prints its warnings in that form and is
  published right away through `Espalier.Catalog.Pack.Publisher.publish/1`,
  unless `--draft` is given, which keeps it as a draft. A last line names the
  outcome and the id of the import.

  Like the eval node of `Espalier.Release`, the task processes no Oban jobs,
  runs no admin bootstrap and starts no development servers such as the mock
  OIDC provider, so it runs next to a running development server. These
  settings apply only when the application has not been started yet.
  """
  use Mix.Task

  alias Espalier.Catalog.Pack.Report

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {draft?, path} = parse_args(args)
    start_app()

    case Report.run_import(path, draft: draft?) do
      {:ok, _pack_import} -> :ok
      {:error, _reason} -> exit({:shutdown, 1})
    end
  end

  defp parse_args(args) do
    case OptionParser.parse(args, strict: [draft: :boolean]) do
      {opts, [path], []} ->
        {Keyword.get(opts, :draft, false), path}

      _other ->
        IO.puts(:stderr, "Usage: mix espalier.import PATH [--draft]")
        exit({:shutdown, 1})
    end
  end

  defp start_app do
    Mix.Task.run("app.config")

    if not List.keymember?(Application.started_applications(), :espalier, 0) do
      oban = Application.fetch_env!(:espalier, Oban)
      Application.put_env(:espalier, Oban, Keyword.merge(oban, queues: false, plugins: false))
      Application.put_env(:espalier, :bootstrap_on_boot, false)
      Application.put_env(:espalier, :dev_children, [])
    end

    Mix.Task.run("app.start")
  end
end
