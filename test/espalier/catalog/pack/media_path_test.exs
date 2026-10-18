defmodule Espalier.Catalog.Pack.MediaPathTest do
  @moduledoc """
  Task 0018, steps 9 and 23 (ASVS 5.3.2): `MediaPath.check/1` admits
  `media/`, zero to three directories in the key format and a file
  `<key>.<extension>` with an extension of step 5, after the general path
  rules of `Espalier.Workbench.Paths.general?/1`; `kind/1` and
  `delivery_path/1` follow the extension.
  """
  use ExUnit.Case, async: true

  alias Espalier.Catalog.Pack.MediaPath

  @step5 ~w(png jpg jpeg gif webp svg mp4 m4v mov webm mkv vtt)

  # A media path of `bytes` bytes below three directories of 150 bytes.
  defp long_path(bytes) do
    dirs = Enum.map_join(~w(a b c), "/", &String.duplicate(&1, 150))
    prefix = "media/" <> dirs <> "/"
    prefix <> String.duplicate("k", bytes - byte_size(prefix) - 4) <> ".png"
  end

  describe "extensions/0 and extensions/1" do
    test "list the extensions of step 5 per kind" do
      assert MediaPath.extensions() == [
               image: ~w(png jpg jpeg gif webp),
               svg: ~w(svg),
               video: ~w(mp4 m4v mov webm mkv),
               captions: ~w(vtt)
             ]

      assert MediaPath.extensions() |> Enum.flat_map(&elem(&1, 1)) |> Enum.sort() ==
               Enum.sort(@step5)

      assert MediaPath.extensions(:video) == ~w(mp4 m4v mov webm mkv)
    end

    test "name the delivery extension of each kind" do
      assert Enum.map(~w(image svg video captions)a, &MediaPath.delivery_extension/1) ==
               ~w(webp svg webm vtt)
    end
  end

  describe "check/1 admits" do
    test "a file of every extension directly below media/" do
      for ext <- @step5 do
        assert MediaPath.check("media/photo-1.#{ext}") == :ok, ext
        assert MediaPath.valid?("media/photo-1.#{ext}")
      end
    end

    test "zero to three directories in the key format" do
      assert MediaPath.check("media/a.png") == :ok
      assert MediaPath.check("media/module-1/a.png") == :ok
      assert MediaPath.check("media/module-1/lesson-2/a.png") == :ok
      assert MediaPath.check("media/module-1/lesson-2/3/a.png") == :ok
    end

    test "a path of 527 bytes with components of at most 255 bytes" do
      path = long_path(527)
      assert byte_size(path) == 527
      assert MediaPath.check(path) == :ok
    end
  end

  describe "check/1 rejects" do
    test "a path of 600 bytes whose components each fit" do
      path = long_path(600)
      assert byte_size(path) == 600
      assert path |> String.split("/") |> Enum.all?(&(byte_size(&1) <= 255))
      assert {:error, message} = MediaPath.check(path)
      assert message =~ "at most 527 bytes"
    end

    test "a path against the general rules" do
      for path <- [
            "",
            "/media/a.png",
            "C:media/a.png",
            "media\\a.png",
            "media/../a.png",
            "media/./a.png",
            "media//a.png",
            "media/a.png" <> <<0>>,
            <<"media/a", 0xFF, ".png">>,
            "media/" <> String.duplicate("d", 256) <> "/a.png"
          ] do
        assert {:error, message} = MediaPath.check(path), inspect(path)
        assert message =~ "a media path is valid UTF-8", inspect(path)
      end
    end

    test "a path outside media/" do
      for path <- ["media", "media.png", "photo.png", "modules/media/a.png", "assets/media/a.png"] do
        assert MediaPath.check(path) == {:error, "a media path starts with `media/`"}, path
      end
    end

    test "four directories below media/" do
      assert MediaPath.check("media/a/b/c/d/x.png") ==
               {:error, "a media path has at most 3 directories below `media/`"}
    end

    test "a directory outside the key format" do
      assert MediaPath.check("media/Photos/x.png") ==
               {:error, "the media directory `Photos` does not match the key format"}

      assert MediaPath.check("media/a/-b/x.png") ==
               {:error, "the media directory `-b` does not match the key format"}
    end

    test "a file name outside the form <key>.<extension>" do
      for name <- [
            "photo",
            "photo.PNG",
            "Photo.png",
            "photo.tiff",
            "photo.avif",
            "photo.heic",
            "photo.m3u8",
            "photo.tar.gz",
            "photo.png.svg",
            "clip.webm.vtt",
            "photo.jpg.png",
            "my photo.png",
            ".png",
            "photo.",
            "-photo.png"
          ] do
        assert {:error, message} = MediaPath.check("media/" <> name), name
        assert message =~ "the media file name `#{name}` must have the form", name
      end
    end

    test "a value that is no string" do
      for value <- [nil, :"media/a.png", ~c"media/a.png", 1, ["media/a.png"]] do
        assert MediaPath.check(value) == {:error, "a media path is a string"}
        refute MediaPath.valid?(value)
      end
    end
  end

  describe "kind/1" do
    test "maps each extension to its kind" do
      for {kind, exts} <- MediaPath.extensions(), ext <- exts do
        assert MediaPath.kind("media/a/x.#{ext}") == kind
      end
    end

    test "names no kind for another extension" do
      assert MediaPath.kind("media/x.tiff") == nil
      assert MediaPath.kind("media/x") == nil
      assert MediaPath.kind("media/x.PNG") == nil
    end
  end

  describe "delivery_path/1" do
    test "replaces the extension by the delivery extension of the kind" do
      assert MediaPath.delivery_path("media/photo.jpg") == "media/photo.webp"
      assert MediaPath.delivery_path("media/photo.jpeg") == "media/photo.webp"
      assert MediaPath.delivery_path("media/a/photo.png") == "media/a/photo.webp"
      assert MediaPath.delivery_path("media/anim.gif") == "media/anim.webp"
      assert MediaPath.delivery_path("media/photo.webp") == "media/photo.webp"
      assert MediaPath.delivery_path("media/diagram.svg") == "media/diagram.svg"
      assert MediaPath.delivery_path("media/clip.mp4") == "media/clip.webm"
      assert MediaPath.delivery_path("media/clip.m4v") == "media/clip.webm"
      assert MediaPath.delivery_path("media/clip.mov") == "media/clip.webm"
      assert MediaPath.delivery_path("media/clip.mkv") == "media/clip.webm"
      assert MediaPath.delivery_path("media/clip.webm") == "media/clip.webm"
      assert MediaPath.delivery_path("media/clip-en.vtt") == "media/clip-en.vtt"
    end

    test "keeps the directories, also one named like an extension" do
      assert MediaPath.delivery_path("media/png/photo.png") == "media/png/photo.webp"
    end

    test "raises for a path whose extension names no kind" do
      assert_raise ArgumentError, fn -> MediaPath.delivery_path("media/photo.tiff") end
    end
  end
end
