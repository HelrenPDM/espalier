defmodule Espalier.Docs.GuidesLinksTest do
  @moduledoc """
  The guides in `docs/guides/` and the README link to each other and to the
  repository. A relative link whose target file or directory does not exist
  breaks the reading path of a first-time reader, so every such link must
  resolve. The index `docs/guides/README.md` must list every guide of the
  directory.

  The same files are the extras of the ExDoc site (`docs` in `mix.exs`). ExDoc
  rewrites a relative link only when the target is itself an extra, so a link
  from an extra to any other file of the repository (source, directory,
  diagram, Makefile, task spec) is an absolute URL of the repository. ExDoc also
  finds the target of a link by its file name alone and keeps the last extra of
  that name, so a link to a file name that several extras share must point to
  the last of them.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @guides Path.join(@root, "docs/guides")

  # A Markdown link target in parentheses, without a scheme and without a
  # title; the optional fragment after `#` is not checked here.
  @link ~r/\]\(([^)\s]+)\)/

  test "every relative link in the README, the guides and the extras resolves" do
    broken =
      for file <- checked_files(),
          target <- relative_targets(file),
          not File.exists?(Path.expand(target, Path.dirname(file))) do
        "#{Path.relative_to(file, @root)} -> #{target}"
      end

    assert broken == []
  end

  test "an extra links only to other extras with a relative link" do
    extras = extras()

    outside =
      for file <- extras,
          target <- relative_targets(file),
          path = Path.expand(target, Path.dirname(file)),
          path not in extras do
        "#{Path.relative_to(file, @root)} -> #{target}"
      end

    assert outside == [],
           "write a link to a file that is no extra as an absolute URL: #{inspect(outside)}"
  end

  test "a link to a file name that several extras share points to the last of them" do
    extras = extras()
    last_by_name = Map.new(extras, &{Path.basename(&1), &1})

    shadowed =
      for file <- extras,
          target <- relative_targets(file),
          path = Path.expand(target, Path.dirname(file)),
          path in extras,
          last_by_name[Path.basename(path)] != path do
        "#{Path.relative_to(file, @root)} -> #{target}"
      end

    assert shadowed == []
  end

  test "the extras exist and no two of them produce the same page" do
    for path <- extras(), do: assert(File.regular?(path), "extra #{path} does not exist")

    keys = for entry <- docs_extras(), do: extra_key(entry)
    assert keys == Enum.uniq(keys)
  end

  test "the index lists every guide of the directory" do
    index = File.read!(Path.join(@guides, "README.md"))

    for path <- Path.wildcard(Path.join(@guides, "*.md")),
        name = Path.basename(path),
        name != "README.md" do
      assert index =~ "(#{name})", "docs/guides/README.md does not link #{name}"
    end
  end

  # The files whose relative links are checked: the README, every guide, the
  # architecture index and the extras.
  defp checked_files do
    ([Path.join(@root, "README.md"), Path.join(@root, "docs/architecture/README.md")] ++
       Path.wildcard(Path.join(@guides, "*.md")) ++ extras())
    |> Enum.uniq()
  end

  # The absolute paths of the extras, in the order of `docs` in `mix.exs`.
  defp extras, do: for(entry <- docs_extras(), do: Path.join(@root, extra_path(entry)))

  defp docs_extras, do: Mix.Project.config() |> Keyword.fetch!(:docs) |> Keyword.fetch!(:extras)

  defp extra_path({path, _opts}), do: path
  defp extra_path(path), do: path

  # The page a link target resolves to: the file name unless :filename is set.
  defp extra_key({path, opts}), do: Keyword.get_lazy(opts, :filename, fn -> page_name(path) end)
  defp extra_key(path), do: page_name(path)

  defp page_name(path), do: path |> Path.basename() |> Path.rootname() |> String.downcase()

  defp relative_targets(file) do
    text = file |> File.read!() |> strip_code()

    for [_, target] <- Regex.scan(@link, text),
        path = relative_path(target),
        path != "",
        do: path
  end

  # Fenced code blocks and inline code hold examples, not links.
  defp strip_code(text) do
    text
    |> String.replace(~r/^```.*?^```$/ms, "")
    |> String.replace(~r/`[^`\n]*`/, "")
  end

  defp relative_path(target) do
    cond do
      String.contains?(target, "://") -> nil
      String.starts_with?(target, ["mailto:", "#"]) -> nil
      true -> target |> String.split("#", parts: 2) |> hd()
    end
  end
end
