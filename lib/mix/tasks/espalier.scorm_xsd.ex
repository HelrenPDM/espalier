defmodule Mix.Tasks.Espalier.ScormXsd do
  @shortdoc "Fetches the XML schema files of the SCORM packages"
  @moduledoc """
  Fetches the XML schema files that a SCORM package carries at its root
  into `priv/scorm/xsd/12/` and `priv/scorm/xsd/2004/` (task 0016, step 8):

      mix espalier.scorm_xsd
      mix espalier.scorm_xsd --dir path/to/xsd

  The repository does not hold these files (`priv/scorm/xsd/SOURCE.md`
  names their sources and license terms). The task runs
  `Espalier.Interop.SchemaFiles.install/2`, which checks the archive and
  every file against their pinned SHA-256 and leaves a version alone whose
  files already match. `make scorm-xsd`, `make setup`, `make e2e` and the
  builder stage of the Dockerfile run it. A failure prints its cause and
  exits with status 1; the export worker fails every export of a version
  without its schema files.

  The task needs network access to the URL of each archive. It starts the
  HTTP client Req and no Espalier application.
  """
  use Mix.Task

  alias Espalier.Interop.SchemaFiles

  @default_dir "priv/scorm/xsd"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    dir = parse_args(args)

    case SchemaFiles.install(dir) do
      {:ok, results} ->
        for {source, outcome} <- results do
          Mix.shell().info(
            "#{source.label}: #{map_size(source.files)} schema files #{outcome_text(outcome)} " <>
              "in #{Path.join(dir, source.version)}"
          )
        end

        :ok

      {:error, source, reason} ->
        Mix.shell().error("#{source.label}: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp outcome_text(:present), do: "already present"
  defp outcome_text(:installed), do: "installed"

  defp parse_args(args) do
    case OptionParser.parse(args, strict: [dir: :string]) do
      {opts, [], []} ->
        Keyword.get(opts, :dir, @default_dir)

      _other ->
        Mix.shell().error("Usage: mix espalier.scorm_xsd [--dir DIR]")
        exit({:shutdown, 1})
    end
  end
end
