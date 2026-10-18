defmodule Mix.Tasks.Espalier.Import do
  @shortdoc "Imports and publishes a content pack"
  @moduledoc """
  Imports the content pack in a directory and publishes it.

  ## Synopsis

      mix espalier.import PATH [--draft]

  ## Arguments and options

  | Argument or option | Meaning |
  |---|---|
  | `PATH` | The directory of the content pack, the one that holds `pack.yaml`. |
  | `--draft` | Stores the validated import as a draft and does not publish it. Without the option, a validated import is published at once. |

  ## Example

      nix-shell --run "set -a; . ./.env; set +a; mix espalier.import path/to/pack --draft"
      nix-shell --run "set -a; . ./.env; set +a; mix espalier.import path/to/pack"

  `nix-shell --run` loads no `.env`, so the command reads it first, as the
  Makefile does, for the database settings such as `DATABASE_PORT`.

  ## What it reads and writes

  The task starts the application and runs
  `Espalier.Catalog.Pack.Importer.import/2` without an actor, through
  `Espalier.Catalog.Pack.Report.run_import/2`. It reads the files below `PATH`
  and writes to the database: one row of `pack_imports` with the report and,
  for a validated import, the normalized payload. Unless `--draft` is given, it
  then calls `Espalier.Catalog.Pack.Publisher.publish/1`, which applies the
  payload to the catalog tables in one transaction. See
  [Content packs](content-packs.md), section "Versioning with stable keys",
  for what a publish does to existing rows.

  A draft import waits on its pack page in the admin area for the preview and
  the publish ([Content packs](content-packs.md), section "Validation and
  publication").

  Like the eval node of `Espalier.Release`, the task processes no Oban jobs,
  runs no admin bootstrap and starts no development servers such as the mock
  OIDC provider, so it runs next to a running development server. These
  settings apply only when the application has not been started yet.

  ## Output and exit status

  The task prints the report in the form of `mix espalier.validate` (one line
  `file:line: message` per error and `file:line: warning: message` per
  warning) and then one line with the outcome:

  | Outcome | Last line | Exit status |
  |---|---|---|
  | The pack has errors | `Import <id> failed with <n> errors` (`1 error` for a single error) | 1 |
  | Validated, with `--draft` | `Stored <key> <version> as draft import <id>` | 0 |
  | Validated and published | `Published <key> <version> from import <id>` | 0 |
  | Validated, the publish failed | `Import <id> was not published: <reason>` | 1 |
  | The import could not be stored | `The import could not be stored: <changeset errors>` | 1 |

  Missing or surplus arguments and unknown options print
  `Usage: mix espalier.import PATH [--draft]` on standard error and end the
  task with status 1.

  `Espalier.Release.import_pack/2` runs the same flow in a release.
  """
  use Mix.Task

  alias Espalier.Catalog.Pack.Report

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {draft?, path} = parse_args(args)
    start_app()

    case Report.run_import(path, draft: draft?) do
      {:ok, _pack_import} -> :ok
      {:error, _reason} -> exit({:shutdown, 1})
    end
  end

  defp parse_args(args) do
    case OptionParser.parse(args, strict: [draft: :boolean]) do
      {opts, [path], []} ->
        {Keyword.get(opts, :draft, false), path}

      _other ->
        IO.puts(:stderr, "Usage: mix espalier.import PATH [--draft]")
        exit({:shutdown, 1})
    end
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
