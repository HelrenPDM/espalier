defmodule Mix.Tasks.Espalier.ScormXsd do
  @shortdoc "Fetches the XML schema files of the SCORM packages"
  @moduledoc """
  Fetches the XML schema files that a SCORM package carries at its root.

  ## Synopsis

      mix espalier.scorm_xsd [--dir DIR]

  ## Options

  | Option | Meaning |
  |---|---|
  | `--dir DIR` | The target directory. The default is `priv/scorm/xsd`. |

  The task accepts no arguments.

  ## Example

      nix-shell --run "mix espalier.scorm_xsd"
      nix-shell --run "mix espalier.scorm_xsd --dir path/to/xsd"

  ## What it reads and writes

  The task runs `Espalier.Interop.SchemaFiles.install/2`. For each SCORM
  version it checks the files in `DIR/12` (SCORM 1.2) and `DIR/2004` (SCORM
  2004 4th edition) against their pinned SHA-256 and leaves a version alone
  whose files already match. Otherwise it fetches the archive of that version
  over HTTPS, checks the archive and every file against the pinned SHA-256
  and replaces the version directory. The repository does not hold these
  files (`priv/scorm/xsd/SOURCE.md` names their sources and license terms).

  The task needs network access to the URL of each archive. It starts the
  HTTP client Req and no Espalier application, so it needs no database.

  `make scorm-xsd`, `make setup` and `make e2e` run the task, and so does the
  builder stage of the Dockerfile. The export worker fails every export of a
  version without its schema files ([SCORM export](scorm-export.md)).

  ## Output and exit status

  For each version the task prints a line such as `SCORM 1.2: 4 schema files
  installed in priv/scorm/xsd/12`, where the outcome is `installed` or
  `already present`, and ends with status 0.

  A failure prints `LABEL: CAUSE` on standard error and ends with status 1; the
  sources after the failed one are not processed. Arguments or unknown
  options print `Usage: mix espalier.scorm_xsd [--dir DIR]` on standard error
  and end the task with status 1.
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
