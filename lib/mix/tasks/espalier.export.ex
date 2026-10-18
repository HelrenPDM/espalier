defmodule Mix.Tasks.Espalier.Export do
  @shortdoc "Writes a published program as a content pack"
  @moduledoc """
  Writes a published program as a content pack into a directory.

  ## Synopsis

      mix espalier.export SLUG PATH

  ## Arguments

  | Argument | Meaning |
  |---|---|
  | `SLUG` | The `key` of the program's `pack.yaml`, which is the slug of the published program. |
  | `PATH` | The target directory. It must be empty or missing; the task creates a missing `PATH`. |

  The task accepts no options.

  ## Example

      nix-shell --run "set -a; . ./.env; set +a; mix espalier.export ai-assistant-basics-demo tmp/pack-out"

  `nix-shell --run` loads no `.env`, so the command reads it first, as the
  Makefile does, for the database settings such as `DATABASE_PORT`.

  ## What it reads and writes

  The task starts the application and calls
  `Espalier.Interop.PackWriter.write/2`. It reads the published program from
  the database and writes the files of the content pack below `PATH`, the same
  files that the pack workbench loads into a draft for a published program
  ([Pack workbench](pack-workbench.md)). `mix espalier.validate
  PATH` and `mix espalier.import PATH` read the written pack. See
  [SCORM export](scorm-export.md), section "Pack export", and
  [Content packs](content-packs.md) for the format.

  Like `mix espalier.import`, the task processes no Oban jobs, runs no admin
  bootstrap and starts no development servers, so it runs next to a running
  development server. These settings apply only when the application has not
  been started yet.

  ## Output and exit status

  On success the task prints `Wrote SLUG VERSION to PATH`, where `VERSION` is
  the `version` of the pack it wrote, and ends with status 0. In the following
  cases it prints a message on standard error and ends with status 1:

  | Case | Message |
  |---|---|
  | Missing or surplus argument, or any option | `Usage: mix espalier.export SLUG PATH` |
  | No program with this slug | `Unknown program "SLUG"` |
  | The program is not published | `The program "SLUG" is not published` |
  | `PATH` is not empty | `The directory PATH is not empty` |
  | `PATH` is not a directory | `PATH is not a directory` |
  | A file cannot be written | `Cannot write FILE: REASON` |
  """
  use Mix.Task

  alias Espalier.Catalog
  alias Espalier.Catalog.Program
  alias Espalier.Interop.PackWriter

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {slug, path} = parse_args(args)
    start_app()

    case Catalog.get_program_by_slug(slug) do
      nil -> fail("Unknown program #{inspect(slug)}")
      %Program{} = program -> export(program, path)
    end
  end

  defp parse_args(args) do
    case OptionParser.parse(args, strict: []) do
      {[], [slug, path], []} -> {slug, path}
      _other -> fail("Usage: mix espalier.export SLUG PATH")
    end
  end

  defp export(program, path) do
    case PackWriter.write(program, path) do
      {:ok, version} ->
        Mix.shell().info("Wrote #{program.slug} #{version} to #{path}")

      {:error, :not_published} ->
        fail("The program #{inspect(program.slug)} is not published")

      {:error, :not_empty} ->
        fail("The directory #{path} is not empty")

      {:error, :not_directory} ->
        fail("#{path} is not a directory")

      {:error, {:file, file, reason}} ->
        fail("Cannot write #{file_path(path, file)}: #{:file.format_error(reason)}")
    end
  end

  defp file_path(path, "."), do: path
  defp file_path(path, file), do: Path.join(path, file)

  defp fail(message) do
    Mix.shell().error(message)
    exit({:shutdown, 1})
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
