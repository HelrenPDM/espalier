defmodule Mix.Tasks.Espalier.Validate do
  @shortdoc "Validates a content pack"
  @moduledoc """
  Validates the content pack in `PATH` without a database connection
  (task 0008, step 11):

      mix espalier.validate content/demo

  The task runs `Espalier.Catalog.Pack.Loader.load/1` and
  `Espalier.Catalog.Pack.Validator.validate/1`, which includes the alignment
  checks of README section 7, domain rule 14. It prints one line per error in
  the form `file:line: message` and then one line per warning in the form
  `file:line: warning: message`, and exits with status 1 when an error
  exists. Warnings alone leave the exit status at 0.
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
