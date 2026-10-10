defmodule Mix.Tasks.Espalier.Alignment do
  @shortdoc "Prints the alignment matrix of a content pack"
  @moduledoc """
  Prints the alignment matrix of the content pack in `PATH` (task 0008,
  step 13; README section 7, domain rule 14), without a database connection:

      mix espalier.alignment content/demo
      mix espalier.alignment content/demo --format csv
      mix espalier.alignment content/demo --format json

  The task reads the pack through `Espalier.Catalog.Pack.Loader.load/1` and
  `Espalier.Catalog.Pack.Validator.run/1`, as `mix espalier.validate` does.
  When the loader or the checks before the alignment report errors, it prints
  them in the form of `mix espalier.validate` and exits with status 1 without
  a matrix. Otherwise it prints the matrix of `Espalier.Catalog.Alignment.matrix/1`,
  one row per module, competence area and depth, and the findings of the
  validator, which include the alignment findings with file and line:

    * `text` (default): a header line and one line per row with the fields
      `module`, `area`, `depth`, `objectives`, `lessons`, `evidence` and
      `elsewhere`, separated by tab characters, lists joined by commas and
      `-` for an empty list or a missing `elsewhere`; then the findings.
    * `csv`: the header `module,area,depth,objectives,lessons,evidence,elsewhere`
      and one record per row after RFC 4180, lists joined by a space; the
      findings go to standard error.
    * `json`: one object with `matrix`, `errors` and `warnings`.

  The task exits with status 1 when an error exists, for an unknown
  `--format` value and for invalid arguments, and with status 0 otherwise.
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
