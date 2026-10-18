defmodule Mix.Tasks.Espalier.Validate do
  @shortdoc "Validates a content pack"
  @moduledoc """
  Validates a content pack without a database connection.

  ## Synopsis

      mix espalier.validate PATH

  ## Arguments

  | Argument | Meaning |
  |---|---|
  | `PATH` | The directory of the content pack, the one that holds `pack.yaml`. |

  The task accepts no options.

  ## Example

      nix-shell --run "mix espalier.validate path/to/pack"

  ## What it reads and writes

  The task reads the files below `PATH` through
  `Espalier.Catalog.Pack.Loader.load/1` and checks the loaded pack with
  `Espalier.Catalog.Pack.Validator.validate/1`, which includes the
  alignment checks of the plan (`docs/plan/README.md`, section 7, domain
  rule 14). It loads the application configuration (`app.config`) but
  starts neither the application nor the database, and it writes no file.

  ## Output and exit status

  The task prints one line per error in the form `file:line: message` and
  then one line per warning in the form `file:line: warning: message`, on
  standard output. A pack without a finding prints nothing.

  | Case | Exit status |
  |---|---|
  | No error, with or without warnings | 0 |
  | At least one error | 1 |
  | Missing or surplus argument, or any option | 1 |

  The last case prints the line `Usage: mix espalier.validate PATH` on
  standard error.

  See [Content packs](content-packs.md), sections "Cross-file checks of the
  validator" and "Validation and publication", for the checks and the
  report, and [Course YAML](course-yaml.md) for an introduction to the
  format.
  """
  use Mix.Task

  alias Espalier.Catalog.Pack.{Loader, Report, Validator}

  @requirements ["app.config"]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    path = parse_path(args)

    {errors, warnings} =
      case Loader.load(path) do
        {:ok, loaded} -> Validator.validate(loaded)
        {:error, errors} -> {errors, []}
      end

    Report.print_lines(Report.lines(errors, warnings))
    if errors != [], do: exit({:shutdown, 1})
    :ok
  end

  defp parse_path(args) do
    case OptionParser.parse(args, strict: []) do
      {[], [path], []} ->
        path

      _other ->
        IO.puts(:stderr, "Usage: mix espalier.validate PATH")
        exit({:shutdown, 1})
    end
  end
end
