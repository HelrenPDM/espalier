defmodule Mix.Tasks.Espalier.Export do
  @shortdoc "Writes a published program as a content pack"
  @moduledoc """
  Writes the published program `SLUG` as a content pack into the directory
  `PATH` (task 0016, step 12):

      mix espalier.export ai-assistant-basics-demo tmp/pack-out

  `SLUG` is the `key` of the program's `pack.yaml`. The task starts the
  application and calls `Espalier.Interop.PackWriter.write/2`, which creates
  a missing `PATH`. `mix espalier.validate PATH` and `mix espalier.import PATH`
  read the written pack.

  The task exits with status 1 and a message on standard error for invalid
  arguments, for an unknown slug, for a program that is not published, for
  a `PATH` that is no directory or a directory that is not empty, and when a
  file cannot be written.

  Like `mix espalier.import`, the task processes no Oban jobs, runs no admin
  bootstrap and starts no development servers, so it runs next to a running
  development server.
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
