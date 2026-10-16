defmodule Espalier.Docs.MediaDocsTest do
  @moduledoc """
  Checks statements of the media documents of task 0018 against the source
  that fixes each of them: the code, its tests or another document.

  The pack example of `docs/guides/media.md` lists in its tree every media
  file that its directives name, as the validator requires of a pack. An
  animated WebP with more than 1,000 frames fails with
  `unsupported_animation` and the reason `too_many_frames`, as
  `Espalier.Media.WebpAnim` answers, and the code `too_many_frames` belongs
  to a GIF or an APNG. A stream above `StreamMaxLength` of clamd fails with
  the reason `size_limit` or `closed`, as `test/espalier/media/clamd_test.exs`
  shows. The compensating controls of the deviation 5.4.3 in `media.md`,
  `security.md` and the ASVS matrix name the animated WebP, whose frame
  bitstreams pass unchanged, and the remuxed video, whose VP9 and Opus
  streams pass unchanged. The backup sections of `media.md` and
  `self-hosting.md` name the directories that the backup command of
  `operations.md` archives. `scripts/smoke.sh` checks the content type,
  `content-disposition` and `nosniff` of the media route, which rows 3.2.1
  and 4.1.1 of the ASVS matrix name as evidence on the container.
  `pack-workbench.md` states that a draft from an import leaves out a media
  file whose asset was deleted.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  defp read(path), do: File.read!(Path.join(@root, path))

  defp prose(text), do: String.replace(text, ~r/\s+/, " ")

  # The text below a heading up to the next heading of the same or a higher
  # level.
  defp section(path, heading) do
    level = heading |> String.split(" ", parts: 2) |> hd() |> byte_size()
    [_before, rest] = String.split(read(path), "\n" <> heading <> "\n", parts: 2)
    [body | _after] = Regex.split(~r/^\#{1,#{level}} /m, rest, parts: 2)
    body
  end

  # The paths of the files of a tree drawn with two spaces per level, below
  # its root directory.
  defp tree_files(tree) do
    {_stack, files} =
      tree
      |> String.split("\n", trim: true)
      |> Enum.reduce({[], []}, fn line, {stack, files} ->
        name = String.trim(line)
        depth = div(byte_size(line) - byte_size(String.trim_leading(line)), 2)
        stack = Enum.take(stack, depth)

        if String.ends_with?(name, "/"),
          do: {stack ++ [String.trim_trailing(name, "/")], files},
          else: {stack, [Path.join(stack ++ [name]) | files]}
      end)

    for file <- files, do: file |> Path.split() |> tl() |> Path.join()
  end

  test "the pack example of media.md holds every media file that its directives name" do
    text = section("docs/guides/media.md", "## Media in content packs")
    [tree] = Regex.run(~r/```text\n(.*?)```/s, text, capture: :all_but_first)
    [directives] = Regex.run(~r/```markdown\n(.*?)```/s, text, capture: :all_but_first)

    named = Regex.scan(~r{media/[A-Za-z0-9._/-]+}, directives) |> List.flatten() |> Enum.uniq()
    assert named != []
    assert named -- tree_files(tree) == []
  end

  test "media.md gives the failure codes of an animated WebP with too many frames" do
    text = read("docs/guides/media.md")

    assert text =~
             "| `too_many_frames` | an animated GIF or APNG with more than 1,000 frames |"

    assert [row] = Regex.run(~r/^\| `unsupported_animation` \|.*$/m, text)
    assert row =~ "`too_many_frames` for more than 1,000 frames"

    assert prose(section("docs/guides/media.md", "### Animated WebP inputs")) =~
             "a file with more than 1,000 frames fails with `unsupported_animation` and the " <>
               "reason `too_many_frames`"
  end

  test "a stream above StreamMaxLength fails with size_limit or closed" do
    clamd = prose(section("docs/guides/media.md", "### The clamd example"))

    deviation =
      prose(section("docs/security/asvs-l2.md", "### 5.4.3 Untrusted files scanned for malware"))

    for text <- [clamd, deviation] do
      [_before, rest] = String.split(text, ~r/stream above `StreamMaxLength`/i, parts: 2)
      assert rest =~ "the reason `size_limit`"
      assert rest =~ "the reason `closed`"
    end
  end

  test "the compensating controls of 5.4.3 name the frames and streams that pass unchanged" do
    [row] = Regex.run(~r/^\| 5\.4\.3 .*$/m, read("docs/guides/security.md"))

    deviation =
      section("docs/security/asvs-l2.md", "### 5.4.3 Untrusted files scanned for malware")

    [reason] = Regex.run(~r/^Reason: .*$/m, deviation)

    for text <- [row, reason, prose(section("docs/guides/media.md", "### Without a scanner"))] do
      refute text =~ "every raster image"
      assert text =~ "every still image, every GIF and APNG and every converted video anew"
      assert text =~ "an animated WebP is written anew in the BEAM without its metadata chunks"
      assert text =~ "frame bitstreams pass unchanged"
      assert text =~ "VP9 and Opus streams"
    end
  end

  test "the backups of media.md and self-hosting.md hold the directories that operations.md archives" do
    [dirs] =
      Regex.run(~r{tar -C /data/media -cf - ([a-z ]+?) >}, read("docs/guides/operations.md"),
        capture: :all_but_first
      )

    dirs = String.split(dirs)
    assert dirs == ["files", "incoming"]
    backup = prose(section("docs/guides/media.md", "## Backup"))
    hosting = prose(section("docs/guides/self-hosting.md", "## Backups"))

    for dir <- dirs do
      assert backup =~ "`MEDIA_DIR/#{dir}/`"
      assert hosting =~ "`#{dir}/`", "self-hosting.md, section Backups, names #{dir}/"
    end

    for sentence <- String.split(backup, ~r/(?<=\.) /), sentence =~ "temporary", dir <- dirs do
      refute sentence =~ "`#{dir}/`", sentence
    end
  end

  test "smoke.sh checks the content type, the disposition and nosniff of the media route" do
    [_before, step] =
      String.split(read("scripts/smoke.sh"), ~s(step "the media route), parts: 2)

    [step, _after] = String.split(step, "\nif [ \"$proxy\" = true ]", parts: 2)

    for statement <- [
          ~s(media_type="image/svg+xml; charset=utf-8"),
          "media_type=video/webm",
          ~s("content-type: $media_type"),
          ~S("content-disposition: inline; filename=\"${url##*/}\""),
          ~s("x-content-type-options: nosniff"),
          "grep -qixF"
        ] do
      assert step =~ statement, statement
    end
  end

  test "pack-workbench.md states that a draft from an import leaves out a deleted asset" do
    text = prose(section("docs/guides/pack-workbench.md", "### An import"))

    assert text =~
             "A media file of a `validated` import whose asset was deleted in the library, " <>
               "which the pack page lists as missing, does not become part of the draft"

    assert text =~ "the check of the draft reports its reference at the line of its block"
  end
end
