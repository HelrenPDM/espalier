defmodule Mix.Tasks.Espalier.SeedDemo do
  @shortdoc "Seeds the demo policy and the demo approved tools"
  @moduledoc """
  Seeds the demo policy and the demo approved tools.

  ## Synopsis

      mix espalier.seed_demo

  The task takes no arguments and no options; it ignores any that are given.

  ## Example

      nix-shell --run "set -a; . ./.env; set +a; mix espalier.seed_demo"

  ## What it reads and writes

  The task starts the application and calls `Espalier.Policies.Demo.seed/0`
  in one transaction. It inserts the policy `usage-policy` with one published
  version and three entries of the approved-tool list, with the statuses
  `approved`, `restricted` and `not_approved`. It skips the policy when a
  policy with this key exists and every tool whose name exists, so it can run
  after each demo import. The demo pack requires the policy
  `usage-policy` for its qualification `basics`; import the pack first with
  `mix espalier.import content/demo`.

  `make setup` and `make refresh-db` run the task after the demo import.
  `Espalier.Release.seed_demo/0` is the release counterpart, which imports the
  demo pack as well.

  Like `mix espalier.import`, the task processes no Oban jobs, runs no admin
  bootstrap and starts no development servers, so it runs next to a running
  development server.

  ## Output and exit status

  The task prints `Seeded N policies and M approved tools.` with the numbers of
  rows it inserted; a policy or tool that exists counts as `0`. The task ends with
  status 0.
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
