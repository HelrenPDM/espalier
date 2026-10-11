defmodule Mix.Tasks.Espalier.SeedDemo do
  @shortdoc "Seeds the demo policy and the demo approved tools"
  @moduledoc """
  Seeds the demo data of the Policies context (task 0013, step 9):

      mix espalier.seed_demo

  The task starts the application and calls `Espalier.Policies.Demo.seed/0`,
  which inserts the policy `usage-policy` with one published version and
  three approved tools, and skips every row whose policy key or tool name
  exists. `make setup` and `make refresh-db` run it after the demo import.

  Like `mix espalier.import`, the task processes no Oban jobs, runs no admin
  bootstrap and starts no development servers, so it runs next to a
  running development server.
  """
  use Mix.Task

  alias Espalier.Policies.Demo

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(_args) do
    start_app()
    {:ok, %{policies: policies, tools: tools}} = Demo.seed()
    Mix.shell().info("Seeded #{policies} policies and #{tools} approved tools.")
    :ok
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
