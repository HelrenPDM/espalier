defmodule Mix.Tasks.Espalier.DevOidc do
  @shortdoc "Starts the mock OIDC provider"
  @moduledoc """
  Starts the mock OIDC provider of `test/support/dev_oidc/` without
  Phoenix (task 0006):

      mix espalier.dev_oidc --port 4010

  `make run` starts the mock as well, so the two are used one at a time.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [port: :integer])
    port = Keyword.get(opts, :port, 4010)

    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:bandit)
    {:ok, _apps} = Application.ensure_all_started(:jose)
    {:ok, _pid} = Espalier.DevOidc.start_link(port: port)

    Mix.shell().info("Mock OIDC provider on http://localhost:#{port} (entra, google, oidc)")
    Process.sleep(:infinity)
  end
end
