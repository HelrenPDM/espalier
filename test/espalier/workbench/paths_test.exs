defmodule Espalier.Workbench.PathsTest do
  @moduledoc """
  Task 0016a, steps 3 and 14 (bullet "Path rules"; ASVS 5.2.2 and 5.3.2):
  `Espalier.Workbench.Paths.check/1` admits exactly the files of the pack
  layout that the loader of task 0008 reads, after the general rules on
  encoding, length, separators and components, and `Paths.language/1`
  names the language of a file. Task 0018, step 16: the general rules are
  the public `general?/1`, a captions file below `media/` is a fourth form
  of a text file, and `check_media/2` admits the delivery path of a media
  entry.
  """
  use ExUnit.Case, async: true

  alias Espalier.Catalog.Pack.Loader
  alias Espalier.Workbench.Paths

  # "modules/a/lessons/" and ".md" take 21 bytes of a lesson path.
  @lesson_prefix "modules/a/lessons/"

  defp lesson_path(bytes),
    do: @lesson_prefix <> String.duplicate("x", bytes - byte_size(@lesson_prefix) - 3) <> ".md"

  describe "check/1 admits the pack layout" do
    test "every top file of the loader" do
      for name <- Loader.top_files() do
        assert Paths.check(name) == :ok, "#{name} should pass"
      end
    end

    test "every module file of the loader below modules/<dir>/" do
      for dir <- ["a", "01-basics", "02-checking-the-output"], name <- Loader.module_files() do
        path = "modules/#{dir}/#{name}"
        assert Paths.check(path) == :ok, "#{path} should pass"
      end
    end

    test "a lesson below modules/<dir>/lessons/" do
      assert Paths.check("modules/01-basics/lessons/01-first-lesson.md") == :ok
      assert Paths.check("modules/a/lessons/x.md") == :ok
    end

    test "a captions file below media/, with up to three directories" do
      assert Paths.check("media/intro-en.vtt") == :ok
      assert Paths.check("media/m1/l2/3/intro-en.vtt") == :ok
    end

    test "a lesson path of 527 bytes with components of 255 bytes" do
      dir = String.duplicate("d", 255)
      path = "modules/#{dir}/lessons/#{String.duplicate("k", 252)}.md"
      assert byte_size(path) == 527
      assert Paths.check(path) == :ok
    end
  end

  describe "check/1 rejects" do
    @rejected [
      "../pack.yaml",
      "/pack.yaml",
      "C:pack.yaml",
      "modules\\a\\module.yaml",
      "modules/a/../b/module.yaml",
      "modules/./a/module.yaml",
      "modules//a/module.yaml",
      "README.md",
      "modules/a/notes.yaml",
      "modules/A/module.yaml",
      "modules/a/lessons/x.txt",
      "modules/a/lessons/x/y.md",
      "modules/a/lessons/-x.md",
      "media/photo.png",
      "media/photo.webp",
      "media/diagram.svg",
      "media/clip.webm",
      "media/intro-en.VTT",
      "media/Intro.vtt",
      "media/a/b/c/d/intro.vtt",
      "intro.vtt",
      "modules/a/intro.vtt"
    ]

    test "each path outside the pack layout or against the general rules" do
      for path <- @rejected do
        assert Paths.check(path) == {:error, :invalid_path}, "#{inspect(path)} should fail"
      end
    end

    test "a path with U+0000" do
      assert Paths.check("pack.yaml" <> <<0>>) == {:error, :invalid_path}
      assert Paths.check("modules/a/lessons/x" <> <<0>> <> ".md") == {:error, :invalid_path}
    end

    test "a component of 256 bytes, which is otherwise a lesson or a module directory of the layout" do
      path = lesson_path(256)
      assert byte_size(path) == 256
      assert Paths.check(path) == :ok

      lesson = "modules/a/lessons/#{String.duplicate("k", 253)}.md"
      assert Paths.check(lesson) == {:error, :invalid_path}

      module = "modules/#{String.duplicate("d", 256)}/module.yaml"
      assert Paths.check(module) == {:error, :invalid_path}
    end

    test "a path of more than 527 bytes" do
      path = String.duplicate("a/", 300) <> "pack.yaml"
      assert byte_size(path) > 527
      assert Paths.check(path) == {:error, :invalid_path}
    end

    test "an empty path" do
      assert Paths.check("") == {:error, :invalid_path}
    end

    test "a binary that is no valid UTF-8" do
      assert Paths.check(<<"modules/a/lessons/", 0xFF, ".md">>) == {:error, :invalid_path}
      assert Paths.check(<<0xC3>>) == {:error, :invalid_path}
    end

    test "a value that is no binary" do
      for value <- [nil, :"pack.yaml", ~c"pack.yaml", 1, ["pack.yaml"], %{path: "pack.yaml"}] do
        assert Paths.check(value) == {:error, :invalid_path}, "#{inspect(value)} should fail"
      end
    end
  end

  describe "general?/1" do
    test "admits a relative UTF-8 path of 1 to 527 bytes with components of at most 255 bytes" do
      assert Paths.general?("pack.yaml")
      assert Paths.general?("anything/at/all.txt")
      assert Paths.general?("media/a/b/c/x.png")
      assert Paths.general?(String.duplicate("a/", 263) <> "b")
    end

    test "rejects what check/1 rejects for the general rules" do
      for path <- [
            "",
            "/pack.yaml",
            "C:pack.yaml",
            "a\\b",
            "a/../b",
            "a/./b",
            "a//b",
            "a" <> <<0>>,
            <<"a", 0xFF>>,
            String.duplicate("a", 256),
            String.duplicate("a/", 300)
          ] do
        refute Paths.general?(path), inspect(path)
      end
    end

    test "rejects a value that is no binary" do
      refute Paths.general?(nil)
      refute Paths.general?(~c"pack.yaml")
    end
  end

  describe "check_media/2" do
    test "admits a media path with the delivery extension of the asset kind" do
      assert Paths.check_media("media/photo.webp", %{kind: :image}) == :ok
      assert Paths.check_media("media/a/b/c/diagram.svg", %{kind: :svg}) == :ok
      assert Paths.check_media("media/clip.webm", %{kind: :video}) == :ok
    end

    test "rejects another extension of the kind and the extension of another kind" do
      for {path, kind} <- [
            {"media/photo.png", :image},
            {"media/photo.jpg", :image},
            {"media/photo.svg", :image},
            {"media/diagram.webp", :svg},
            {"media/clip.mp4", :video},
            {"media/clip.mkv", :video},
            {"media/clip.webp", :video}
          ] do
        assert Paths.check_media(path, %{kind: kind}) == {:error, :invalid_path}, path
      end
    end

    test "rejects every path for a captions asset, which becomes a text file" do
      assert Paths.check_media("media/intro-en.vtt", %{kind: :captions}) ==
               {:error, :invalid_path}
    end

    test "rejects a path that fails the media path rules" do
      for path <- [
            "photo.webp",
            "media/Photo.webp",
            "media/a/b/c/d/photo.webp",
            "media/../photo.webp",
            "/media/photo.webp",
            nil
          ] do
        assert Paths.check_media(path, %{kind: :image}) == {:error, :invalid_path},
               inspect(path)
      end
    end

    test "rejects an asset without a known kind" do
      assert Paths.check_media("media/photo.webp", %{kind: :audio}) == {:error, :invalid_path}
      assert Paths.check_media("media/photo.webp", %{}) == {:error, :invalid_path}
    end
  end

  describe "language/1" do
    test "names YAML for .yaml and Markdown for .md" do
      assert Paths.language("pack.yaml") == :yaml
      assert Paths.language("modules/01-basics/objectives.yaml") == :yaml
      assert Paths.language("modules/01-basics/lessons/01-first-lesson.md") == :markdown
    end

    test "names plain text for a captions file" do
      assert Paths.language("media/intro-en.vtt") == :text
    end

    test "names no language for another extension" do
      assert Paths.language("README.txt") == nil
    end
  end
end
