defmodule Espalier.Docs.ContentPacksGuideTest do
  @moduledoc """
  The example files of `docs/guides/content-packs.md` form a minimal pack
  that passes the pack validator and the alignment checks with no error and
  no warning (task 0017, step 11).

  The section "Files" of the guide names each file in a heading
  `` ### `path` `` or, for a lesson, in a line `` `path`: ``, and the next
  `yaml` or `markdown` code block holds its content. The test writes these
  files into a directory and runs what `mix espalier.validate` and
  `mix espalier.alignment` run. The example lessons hold a `figure` and a
  `video` block (task 0018, step 9); the loader reads only the path and the
  size of a media file, so the test writes an empty file at every `media/`
  path that a directive of the lessons names.
  """
  use ExUnit.Case, async: true

  alias Espalier.Catalog.Alignment
  alias Espalier.Catalog.Pack.{Loader, MediaPath, Validator}

  @guide Path.expand("../../docs/guides/content-packs.md", __DIR__)

  @moduletag :tmp_dir

  test "the example files form a pack without errors and warnings", %{tmp_dir: dir} do
    files = example_files()

    # pack.yaml, the top-level files, one module and its lessons.
    assert Map.has_key?(files, "pack.yaml")
    assert Enum.any?(Map.keys(files), &String.ends_with?(&1, "/objectives.yaml"))
    assert Enum.any?(Map.keys(files), &String.contains?(&1, "/lessons/"))

    media = media_paths(files)
    assert Enum.any?(media, &(MediaPath.kind(&1) in [:image, :svg]))
    assert Enum.any?(media, &(MediaPath.kind(&1) == :video))

    for {path, content} <- Enum.concat(files, Enum.map(media, &{&1, ""})) do
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end

    assert {:ok, loaded} = Loader.load(dir)
    assert Enum.map(loaded.media, & &1.path) == Enum.sort(media)
    assert %{payload: payload, errors: [], warnings: []} = Validator.run(loaded)
    assert [_ | _] = Alignment.matrix(payload)

    kinds =
      for module <- payload["modules"],
          lesson <- module["lessons"],
          block <- lesson["blocks"],
          do: block["kind"]

    assert "figure" in kinds and "video" in kinds
  end

  test "the guide names the media extensions per kind and the media limits" do
    text = File.read!(@guide)
    [_before, media] = String.split(text, "\n## Media\n", parts: 2)
    [media, _after] = String.split(media, "\n## Provenance\n", parts: 2)

    # ASVS 2.1.3 and 5.1.1
    for {_kind, extensions} <- MediaPath.extensions() do
      row = Enum.map_join(extensions, ", ", &"`#{&1}`")
      assert media =~ row, row
    end

    for statement <- [
          "`MEDIA_IMAGE_MAX_MB` megabytes of 1,048,576 bytes each, default 20",
          "1 MiB (1,048,576 bytes)",
          "`MEDIA_VIDEO_MAX_MB` megabytes, default 1024",
          "512 KiB (524,288 bytes)",
          "at most 500 media files (`max_pack_media`)",
          "`PACK_UPLOAD_MAX_MB`",
          "`MEDIA_STORAGE_MAX_GB`",
          "`MEDIA_EXTERNAL_HOSTS`",
          "`MEDIA_EMBED_HOSTS`",
          "zero to three directories"
        ] do
      assert media =~ statement, statement
    end

    assert Espalier.Media.max_pack_media() == 500
    assert Espalier.Media.max_bytes(:svg) == 1_048_576
    assert Espalier.Media.max_bytes(:captions) == 524_288
    assert MediaPath.max_directories() == 3
  end

  # The media paths that the opening lines of the example lessons name.
  defp media_paths(files) do
    for {path, content} <- files,
        String.ends_with?(path, ".md"),
        line <- String.split(content, "\n"),
        String.starts_with?(line, ":::"),
        [media] <- Regex.scan(~r/media\/[^\s",:}]+/, line),
        uniq: true,
        do: media
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
