defmodule Espalier.Docs.AsvsMatrixTest do
  @moduledoc """
  Checks the ASVS matrix `docs/security/asvs-l2.md` against the task specs
  (README section 15, decision D16).

  The section "Security requirements" of every task spec lists exactly the
  rows whose `Task` column names that task. A bullet that starts with a row
  id, or with `ASVS` and a row id, names the rows before its first colon;
  parentheses there hold annotations, and "3.3.1 to 3.3.4" stands for every
  row of that range. The ownership table names every row with the tasks of
  its `Task` column in the same order, task 0004 (step 42) holds the same
  table, and the section "Deviations" has an entry for exactly the rows that
  the ownership table marks as a deviation. A marked row has the status
  `open` or `deviation`.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @matrix Path.join(@root, "docs/security/asvs-l2.md")
  @specs Path.join(@root, "docs/plan/tasks/*.md")
  @ownership_copy Path.join(@root, "docs/plan/tasks/0004-accounts-sessions.md")

  @row ~r/^\| (\d+\.\d+\.\d+) \| (\d) \| [^|]* \| ([^|]*) \| ([^|]*) \|/m
  @ids ~r/(\d+\.\d+\.\d+)(?:\s+to\s+(\d+\.\d+\.\d+))?/
  @task ~r/\b\d{4}[a-z]?\b/
  @spec_file ~r/^(\d{4}[a-z]?)-/

  test "every task spec lists exactly the rows whose Task column names it" do
    by_task = rows_by_task(matrix_rows())
    specs = spec_rows()

    diffs =
      for task <- Enum.sort(Enum.uniq(Map.keys(by_task) ++ Map.keys(specs))),
          diff = row_diff(task, Map.get(by_task, task, []), Map.get(specs, task, [])),
          diff != nil,
          do: diff

    assert diffs == [],
           "Security requirements and Task column differ:\n" <> Enum.join(diffs, "\n")
  end

  test "the ownership table names every row with the tasks of its Task column" do
    rows = matrix_rows()
    entries = ownership_entries(File.read!(@matrix))
    owned = Map.new(entries)

    assert length(entries) == map_size(owned), "a row appears twice in the ownership table"
    assert Enum.sort(Map.keys(owned)) == Enum.sort(Enum.map(rows, & &1.id))

    for row <- rows do
      assert Map.fetch!(owned, row.id) == row.tasks,
             "#{row.id}: Task column #{inspect(row.tasks)}, ownership table #{inspect(owned[row.id])}"
    end
  end

  test "task 0004 holds the same ownership table as the matrix" do
    assert ownership_lines(File.read!(@ownership_copy)) == ownership_lines(File.read!(@matrix))
  end

  test "the section Deviations covers exactly the rows marked as a deviation" do
    text = File.read!(@matrix)
    [_, deviations] = String.split(text, "\n## Deviations\n", parts: 2)

    entries =
      MapSet.new(
        List.flatten(Regex.scan(~r/^### (\d+\.\d+\.\d+) /m, deviations, capture: :all_but_first))
      )

    marked = MapSet.new(for cell <- ownership_cells(text), id <- marked_deviations(cell), do: id)
    rows = matrix_rows()
    statuses = MapSet.new(for row <- rows, row.status == "deviation", do: row.id)

    assert entries == marked,
           "entries without a mark: #{inspect(MapSet.difference(entries, marked))}, " <>
             "marks without an entry: #{inspect(MapSet.difference(marked, entries))}"

    assert MapSet.subset?(statuses, marked),
           "status deviation without a mark: #{inspect(MapSet.difference(statuses, marked))}"

    other =
      for row <- rows,
          MapSet.member?(marked, row.id),
          row.status not in ["open", "deviation"],
          do: "#{row.id} (#{row.status})"

    assert other == [], "marked as a deviation with another status: #{Enum.join(other, ", ")}"
  end

  defp matrix_rows do
    rows =
      for [_, id, level, tasks, status] <- Regex.scan(@row, File.read!(@matrix)) do
        %{
          id: id,
          level: level,
          tasks: Regex.scan(@task, tasks) |> List.flatten(),
          status: String.trim(status)
        }
      end

    assert length(rows) > 200, "the matrix parser found #{length(rows)} rows"
    rows
  end

  defp rows_by_task(rows) do
    for row <- rows, task <- row.tasks, reduce: %{} do
      acc -> Map.update(acc, task, [row.id], &[row.id | &1])
    end
  end

  defp spec_rows do
    for path <- Path.wildcard(@specs),
        [_, task] <- [Regex.run(@spec_file, Path.basename(path))],
        into: %{},
        do: {task, path |> File.read!() |> requirement_ids()}
  end

  defp requirement_ids(text) do
    case Regex.run(~r/^## Security requirements\n(.*?)(?=^## |\z)/ms, text) do
      [_, section] ->
        for line <- String.split(section, "\n"),
            Regex.match?(~r/^- (ASVS )?\d+\.\d+\.\d+/, line),
            id <- line |> strip_parentheses() |> head() |> expand(),
            do: id

      nil ->
        []
    end
  end

  defp head(line), do: line |> String.split(":", parts: 2) |> hd()

  defp strip_parentheses(text) do
    case Regex.replace(~r/\([^()]*\)/, text, "") do
      ^text -> text
      stripped -> strip_parentheses(stripped)
    end
  end

  defp expand(text) do
    Enum.flat_map(Regex.scan(@ids, text), fn
      [_, id] -> [id]
      [_, first, last] -> range(first, last)
    end)
  end

  defp range(first, last) do
    case {String.split(first, "."), String.split(last, ".")} do
      {[a, b, from], [a, b, to]} ->
        for n <- String.to_integer(from)..String.to_integer(to)//1, do: "#{a}.#{b}.#{n}"

      _other ->
        flunk("the range #{first} to #{last} crosses a section")
    end
  end

  defp row_diff(task, matrix_ids, spec_ids) do
    only_matrix = sort_ids(matrix_ids -- spec_ids)
    only_spec = sort_ids(spec_ids -- matrix_ids)
    duplicates = sort_ids(spec_ids -- Enum.uniq(spec_ids))

    if only_matrix == [] and only_spec == [] and duplicates == [] do
      nil
    else
      "#{task}: Task column only #{inspect(only_matrix)}, spec only #{inspect(only_spec)}, " <>
        "listed twice #{inspect(duplicates)}"
    end
  end

  defp sort_ids(ids) do
    Enum.sort_by(ids, fn id -> id |> String.split(".") |> Enum.map(&String.to_integer/1) end)
  end

  defp ownership_lines(text) do
    for line <- String.split(text, "\n"),
        trimmed = String.trim(line),
        Regex.match?(~r/^\| V\d+ \|/, trimmed),
        do: trimmed
  end

  defp ownership_cells(text) do
    for line <- ownership_lines(text),
        [_, cell] <- [Regex.run(~r/^\| V\d+ \| (.*) \|$/, line)],
        do: cell
  end

  defp ownership_entries(text) do
    for cell <- ownership_cells(text),
        entry <- split_top_level(cell),
        entry_row <- entry_rows(String.trim(entry)),
        do: entry_row
  end

  defp entry_rows("not applicable:" <> ids), do: for(id <- expand(ids), do: {id, []})

  defp entry_rows(entry) do
    case String.split(entry, "(", parts: 2) do
      [ids, annotation] ->
        [tasks | _] = String.split(annotation, ";")
        tasks = Regex.scan(@task, tasks) |> List.flatten()
        for id <- expand(ids), do: {id, tasks}

      [_ids] ->
        flunk("the ownership entry #{inspect(entry)} names no task")
    end
  end

  defp marked_deviations(cell) do
    for entry <- split_top_level(cell),
        String.contains?(entry, "deviation"),
        id <- entry |> String.split("(", parts: 2) |> hd() |> expand(),
        do: id
  end

  # Splits at semicolons outside parentheses.
  defp split_top_level(text) do
    {parts, current, _depth} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        ";", {parts, current, 0} -> {[current | parts], "", 0}
        "(", {parts, current, depth} -> {parts, current <> "(", depth + 1}
        ")", {parts, current, depth} -> {parts, current <> ")", depth - 1}
        char, {parts, current, depth} -> {parts, current <> char, depth}
      end)

    Enum.reverse([current | parts])
  end
end
