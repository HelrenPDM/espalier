defmodule Espalier.Docs.ContentPacksGuideTest do
  @moduledoc """
  The example files of `docs/guides/content-packs.md` form a minimal pack
  that passes the pack validator and the alignment checks with no error and
  no warning (task 0017, step 11).

  The section "Files" of the guide names each file in a heading
  `` ### `path` `` or, for a lesson, in a line `` `path`: ``, and the next
  `yaml` or `markdown` code block holds its content. The test writes these
  files into a directory and runs what `mix espalier.validate` and
  `mix espalier.alignment` run.
  """
  use ExUnit.Case, async: true

  alias Espalier.Catalog.Alignment
  alias Espalier.Catalog.Pack.{Loader, Validator}

  @guide Path.expand("../../docs/guides/content-packs.md", __DIR__)

  @moduletag :tmp_dir

  test "the example files form a pack without errors and warnings", %{tmp_dir: dir} do
    files = example_files()

    # pack.yaml, the top-level files, one module and its lessons.
    assert Map.has_key?(files, "pack.yaml")
    assert Enum.any?(Map.keys(files), &String.ends_with?(&1, "/objectives.yaml"))
    assert Enum.any?(Map.keys(files), &String.contains?(&1, "/lessons/"))

    for {path, content} <- files do
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end

    assert {:ok, loaded} = Loader.load(dir)
    assert %{payload: payload, errors: [], warnings: []} = Validator.run(loaded)
    assert [_ | _] = Alignment.matrix(payload)
  end

  defp example_files do
    text = File.read!(@guide)
    [_before, files] = String.split(text, "\n## Files\n", parts: 2)
    [section, _after] = String.split(files, "\n## Lesson directives\n", parts: 2)

    {files, _path} =
      section
      |> String.split(~r/^```(?:yaml|markdown)\n(.*?)^```$/ms, include_captures: true)
      |> Enum.reduce({%{}, nil}, fn chunk, {files, path} ->
        case Regex.run(~r/\A```(?:yaml|markdown)\n(.*)^```\z/ms, chunk) do
          [_, body] when path != nil -> {Map.put(files, path, body), nil}
          [_, _body] -> {files, nil}
          nil -> {files, last_path(chunk) || path}
        end
      end)

    files
  end

  # The last file name in a stretch of prose before a code block.
  defp last_path(chunk) do
    ~r/^(?:### `([^`]+)`|`([^`]+\.md)`:)$/m
    |> Regex.scan(chunk)
    |> List.last()
    |> case do
      nil -> nil
      captures -> captures |> tl() |> Enum.find(&(&1 != ""))
    end
  end
end
