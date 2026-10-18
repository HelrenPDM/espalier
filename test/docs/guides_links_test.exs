defmodule Espalier.Docs.GuidesLinksTest do
  @moduledoc """
  The guides in `docs/guides/` and the README link to each other and to the
  repository. A relative link whose target file or directory does not exist
  breaks the reading path of a first-time reader, so every such link must
  resolve. The index `docs/guides/README.md` must list every guide of the
  directory.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @guides Path.join(@root, "docs/guides")

  # A Markdown link target in parentheses, without a scheme and without a
  # title; the optional fragment after `#` is not checked here.
  @link ~r/\]\(([^)\s]+)\)/

  test "every relative link in the README and the guides resolves" do
    files = [Path.join(@root, "README.md") | Path.wildcard(Path.join(@guides, "*.md"))]

    broken =
      for file <- files,
          text = file |> File.read!() |> strip_code(),
          [_, target] <- Regex.scan(@link, text),
          path = relative_path(target),
          path != "",
          not File.exists?(Path.expand(path, Path.dirname(file))) do
        "#{Path.relative_to(file, @root)} -> #{target}"
      end

    assert broken == []
  end

  test "the index lists every guide of the directory" do
    index = File.read!(Path.join(@guides, "README.md"))

    for path <- Path.wildcard(Path.join(@guides, "*.md")),
        name = Path.basename(path),
        name != "README.md" do
      assert index =~ "(#{name})", "docs/guides/README.md does not link #{name}"
    end
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
