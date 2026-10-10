defmodule Espalier.Catalog.Pack.Report do
  @moduledoc """
  Formats the findings of a content pack and the alignment matrix for the
  command line (task 0008, steps 9, 11 and 13), and runs the import flow that
  `mix espalier.import` and `Espalier.Release.import_pack/2` share.

  A report entry is a map with `file`, `line` and `message`, an entry of the
  alignment checks carries `check`, `module` and `key` in addition, and a
  closing entry of `Espalier.Catalog.Pack.Entries` carries `omitted`. The
  validator returns entries with atom keys, and an entry read back from the
  `report` column of `Espalier.Catalog.PackImport` has string keys; every
  function here accepts both.

  The line forms are those of `mix espalier.validate`:

      modules/01-basics/items.yaml:12: message
      modules/01-basics/items.yaml:12: warning: message

  Each entry prints as exactly one line: `format/2` writes `file` and
  `message` through `Espalier.Catalog.Pack.Entries.clean/1`, which escapes
  every control character as `\\xNN` and shortens a member to 1,000
  characters. The loader and the validator have done so already for the
  entries they return.
  """

  alias Espalier.Catalog.Pack.{Entries, Importer, Publisher}
  alias Espalier.Catalog.PackImport

  @matrix_columns [:module, :area, :depth, :objectives, :lessons, :evidence, :elsewhere]

  @typedoc "A `%Espalier.Catalog.PackImport{}`."
  @type pack_import :: Ecto.Schema.schema()

  @typedoc "A report entry with atom keys or with string keys."
  @type entry :: %{optional(atom() | String.t()) => term()}

  @typedoc "A row of `Espalier.Catalog.Alignment.matrix/1`."
  @type row :: %{
          module: integer(),
          area: String.t(),
          depth: String.t(),
          objectives: [String.t()],
          lessons: [String.t()],
          evidence: [String.t()],
          elsewhere: String.t() | nil
        }

  @doc """
  Formats one entry as `file:line: message` for an error and as
  `file:line: warning: message` for a warning, on one line.
  """
  @spec format(entry(), :error | :warning) :: String.t()
  def format(entry, :error),
    do: "#{file(entry)}:#{member(entry, :line)}: #{message(entry)}"

  def format(entry, :warning),
    do: "#{file(entry)}:#{member(entry, :line)}: warning: #{message(entry)}"

  @doc "Formats the errors and then the warnings, one line per entry."
  @spec lines([entry()], [entry()]) :: [String.t()]
  def lines(errors, warnings) do
    Enum.map(errors, &format(&1, :error)) ++ Enum.map(warnings, &format(&1, :warning))
  end

  @doc """
  Formats a report as stored in `Espalier.Catalog.PackImport`: the errors and
  then the warnings, one line per entry.
  """
  @spec report_lines(map()) :: [String.t()]
  def report_lines(report) when is_map(report) do
    lines(Map.get(report, "errors", []), Map.get(report, "warnings", []))
  end

  @doc """
  Builds the `report` of a `PackImport` from the errors and warnings of the
  validator: `%{"errors" => [...], "warnings" => [...]}` with string keys in
  every entry and every member of each entry kept.

  The size of the report is bounded whatever the pack holds. Each list passes
  through `Espalier.Catalog.Pack.Entries.limit/2` (at most 100 entries per
  file, every string member one line of at most 1,000 characters, with every
  control character, NUL included, written as `\\xNN`) and then
  `Espalier.Catalog.Pack.Entries.cap/2` (at most 1,000 entries and a closing
  entry `and N further errors` at file `.` and line 1). A closing entry also
  holds `omitted`, the number of entries it stands for, so that
  `Espalier.Catalog.Pack.Entries.count/1` gives the total.
  """
  @spec stored([entry()], [entry()]) :: %{String.t() => [%{String.t() => term()}]}
  def stored(errors, warnings) do
    %{
      "errors" => bounded(errors, :error),
      "warnings" => bounded(warnings, :warning)
    }
  end

  @doc """
  Formats the alignment matrix as text: a header line and one line per row,
  with the fields separated by tab characters, lists joined by commas, and
  `-` for an empty list or a missing `elsewhere`.
  """
  @spec matrix_text([row()]) :: [String.t()]
  def matrix_text(rows) do
    header = Enum.map_join(@matrix_columns, "\t", &Atom.to_string/1)
    [header | Enum.map(rows, &text_row/1)]
  end

  @doc """
  Formats the alignment matrix as CSV after RFC 4180: the header
  `module,area,depth,objectives,lessons,evidence,elsewhere` and one record per
  row, lists joined by a space, each record ended by CRLF. A field that holds
  a comma, a double quote or a line break is enclosed in double quotes, with
  every double quote inside it doubled.
  """
  @spec matrix_csv([row()]) :: String.t()
  def matrix_csv(rows) do
    header = csv_record(Enum.map(@matrix_columns, &Atom.to_string/1))

    records =
      Enum.map(rows, fn row -> csv_record(Enum.map(@matrix_columns, &csv_value(row, &1))) end)

    IO.iodata_to_binary([header | records])
  end

  @doc """
  Encodes the alignment matrix and the findings as one JSON object with
  `matrix`, `errors` and `warnings`.
  """
  @spec matrix_json([row()], [entry()], [entry()]) :: String.t()
  def matrix_json(rows, errors, warnings) do
    JSON.encode!(%{"matrix" => rows, "errors" => errors, "warnings" => warnings})
  end

  @doc """
  Imports the pack at `path` without an actor, prints the report in the form
  of `mix espalier.validate` and one line with the outcome, and publishes a
  validated import unless `draft: true` is given.

  Returns `{:ok, pack_import}` with the published import, or with the draft
  for `draft: true`, and `{:error, reason}` otherwise: the failed import, the
  changeset of an import that could not be stored, or `:not_validated` when
  the import was published by someone else first.
  """
  @spec run_import(Path.t(), keyword()) :: {:ok, pack_import()} | {:error, term()}
  def run_import(path, opts \\ []) when is_binary(path) and is_list(opts) do
    case Importer.import(path, nil) do
      {:ok, %PackImport{status: :validated} = draft} ->
        print_lines(report_lines(draft.report))
        finish(draft, Keyword.get(opts, :draft, false))

      {:ok, %PackImport{} = failed} ->
        print_lines(report_lines(failed.report))
        IO.puts("Import #{failed.id} failed with #{error_count(failed.report)}")
        {:error, failed}

      {:error, changeset} ->
        IO.puts("The import could not be stored: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc "Prints each line to `device`, standard output by default."
  @spec print_lines([String.t()], IO.device()) :: :ok
  def print_lines(lines, device \\ :stdio) do
    Enum.each(lines, &IO.puts(device, &1))
  end

  defp finish(draft, true) do
    IO.puts("Stored #{describe(draft)} as draft import #{draft.id}")
    {:ok, draft}
  end

  defp finish(draft, false) do
    case Publisher.publish(draft) do
      {:ok, published} ->
        IO.puts("Published #{describe(published)} from import #{published.id}")
        {:ok, published}

      {:error, reason} ->
        IO.puts("Import #{draft.id} was not published: #{reason}")
        {:error, reason}
    end
  end

  defp describe(%PackImport{pack_key: key, pack_version: version}), do: "#{key} #{version}"

  # The total of the stored errors, the entries that closing entries stand
  # for included, so that it matches the lines printed before it.
  defp error_count(report) do
    case report |> Map.get("errors", []) |> Entries.count() do
      1 -> "1 error"
      count -> "#{Entries.number(count)} errors"
    end
  end

  defp text_row(row), do: Enum.map_join(@matrix_columns, "\t", &text_value(row, &1))

  defp text_value(row, column) do
    case Map.fetch!(row, column) do
      nil -> "-"
      [] -> "-"
      list when is_list(list) -> Enum.join(list, ",")
      value -> to_string(value)
    end
  end

  defp csv_value(row, column) do
    case Map.fetch!(row, column) do
      nil -> ""
      list when is_list(list) -> Enum.join(list, " ")
      value -> to_string(value)
    end
  end

  defp csv_record(fields), do: [Enum.map_join(fields, ",", &csv_field/1), "\r\n"]

  defp csv_field(field) do
    if String.contains?(field, [",", "\"", "\r", "\n"]),
      do: ~s("#{String.replace(field, "\"", "\"\"")}"),
      else: field
  end

  defp bounded(entries, kind) do
    entries
    |> Entries.limit(kind)
    |> Entries.cap(kind)
    |> Enum.map(&stringify/1)
  end

  defp stringify(entry), do: Map.new(entry, fn {key, value} -> {to_string(key), value} end)

  defp file(entry), do: entry |> member(:file) |> one_line()

  defp message(entry), do: entry |> member(:message) |> one_line()

  defp one_line(value) when is_binary(value), do: Entries.clean(value)
  defp one_line(value), do: value

  defp member(entry, key), do: Map.get(entry, key, Map.get(entry, Atom.to_string(key)))
end
