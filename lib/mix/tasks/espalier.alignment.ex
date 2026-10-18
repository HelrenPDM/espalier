defmodule Mix.Tasks.Espalier.Alignment do
  @shortdoc "Prints the alignment matrix of a content pack"
  @moduledoc """
  Prints the alignment matrix of a content pack without a database
  connection.

  ## Synopsis

      mix espalier.alignment PATH [--format text|csv|json]

  ## Arguments and options

  | Argument or option | Meaning |
  |---|---|
  | `PATH` | The directory of the content pack, the one that holds `pack.yaml`. |
  | `--format` | The output format: `text` (default), `csv` or `json`. Any other value ends the task with status 1. |

  ## Example

      nix-shell --run "mix espalier.alignment content/demo"
      nix-shell --run "mix espalier.alignment content/demo --format csv"
      nix-shell --run "mix espalier.alignment content/demo --format json"

  ## What it reads and writes

  The task reads the pack through `Espalier.Catalog.Pack.Loader.load/1` and
  `Espalier.Catalog.Pack.Validator.run/1`, as `mix espalier.validate` does,
  and builds the matrix with `Espalier.Catalog.Alignment.matrix/1` (plan,
  `docs/plan/README.md`, section 7, domain rule 14). It loads the
  application configuration (`app.config`) but starts neither the
  application nor the database, and it writes no file.

  ## Output

  The matrix has one row per module, competence area and depth. A row has
  the fields `module`, `area`, `depth`, `objectives`, `lessons`, `evidence`
  and `elsewhere`. The findings of the validator follow, among them the
  alignment findings with file and line.

  | Format | Standard output | Standard error |
  |---|---|---|
  | `text` | A header line and one line per row, fields separated by tab characters, lists joined by commas, `-` for an empty list or a missing `elsewhere`; then the findings in the form of `mix espalier.validate` | none |
  | `csv` | The header `module,area,depth,objectives,lessons,evidence,elsewhere` and one record per row after RFC 4180, lists joined by a space | The findings |
  | `json` | One object with the members `matrix`, `errors` and `warnings` | none |

  When the loader or the checks before the alignment report errors, the
  task prints them in the form of `mix espalier.validate` without a matrix.
  They go to standard output, and for `csv` to standard error.

  ## Exit status

  | Case | Exit status |
  |---|---|
  | No error, with or without warnings | 0 |
  | At least one error | 1 |
  | An unknown `--format` value | 1 |
  | Missing or surplus argument, or an unknown option | 1 |

  An unknown `--format` value prints a message that names the accepted
  values. Invalid arguments print the usage line

      Usage: mix espalier.alignment PATH [--format text|csv|json]

  Both messages go to standard error.

  See [Content packs](content-packs.md), section "The alignment matrix", for
  the meaning of the rows.
  """
  use Mix.Task

  alias Espalier.Catalog.Alignment
  alias Espalier.Catalog.Pack.{Loader, Report, Validator}

  @requirements ["app.config"]

  @formats %{"text" => :text, "csv" => :csv, "json" => :json}

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    case OptionParser.parse(args, strict: [format: :string]) do
      {opts, [path], []} ->
        align(path, parse_format(opts))

      _other ->
        fail("Usage: mix espalier.alignment PATH [--format text|csv|json]")
    end
  end

  defp parse_format(opts) do
    value = Keyword.get(opts, :format, "text")

    case Map.fetch(@formats, value) do
      {:ok, format} -> format
      :error -> fail("Unknown format #{inspect(value)}: use text, csv or json")
    end
  end

  defp align(path, format) do
    case Loader.load(path) do
      {:ok, loaded} ->
        loaded |> Validator.run() |> print_run(format)

      {:error, errors} ->
        Report.print_lines(Report.lines(errors, []), findings_device(format))
        exit({:shutdown, 1})
    end
  end

  defp print_run(%{payload: payload, errors: errors, warnings: warnings}, format)
       when is_map(payload) do
    print(format, Alignment.matrix(payload), errors, warnings)
    if errors != [], do: exit({:shutdown, 1})
    :ok
  end

  defp print_run(%{errors: errors, warnings: warnings}, format) do
    Report.print_lines(Report.lines(errors, warnings), findings_device(format))
    exit({:shutdown, 1})
  end

  defp print(:text, rows, errors, warnings) do
    Report.print_lines(Report.matrix_text(rows) ++ Report.lines(errors, warnings))
  end

  defp print(:csv, rows, errors, warnings) do
    IO.write(Report.matrix_csv(rows))
    Report.print_lines(Report.lines(errors, warnings), :stderr)
  end

  defp print(:json, rows, errors, warnings) do
    IO.puts(Report.matrix_json(rows, errors, warnings))
  end

  # Standard output carries the CSV records alone.
  defp findings_device(:csv), do: :stderr
  defp findings_device(_format), do: :stdio

  defp fail(message) do
    IO.puts(:stderr, message)
    exit({:shutdown, 1})
  end
end
