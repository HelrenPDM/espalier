defmodule Espalier.Catalog.Pack.ArchiveTest do
  # Each test points TMPDIR at a directory of its own, two levels below a
  # test root, so that the children of System.tmp_dir!/0 before and after a
  # call are exact and a name that climbs out of the extraction directory
  # points into the test root. TMPDIR belongs to the whole VM, hence
  # async: false.
  use ExUnit.Case, async: false

  import Espalier.PackFixtures, only: [demo_path: 0]

  alias Espalier.Catalog.Pack.Archive
  alias Espalier.ZipFixtures

  @max 1_048_576

  setup do
    root =
      Path.join(System.tmp_dir!(), "espalier-archive-test-#{System.unique_integer([:positive])}")

    tmp = Path.join([root, "outer", "tmp"])
    uploads = Path.join(root, "uploads")
    File.mkdir_p!(tmp)
    File.mkdir_p!(uploads)

    previous = System.get_env("TMPDIR")
    System.put_env("TMPDIR", tmp)

    on_exit(fn ->
      if previous, do: System.put_env("TMPDIR", previous), else: System.delete_env("TMPDIR")
      File.rm_rf!(root)
    end)

    assert System.tmp_dir!() == tmp
    %{root: root, tmp: tmp, uploads: uploads}
  end

  describe "extract/2 rejects before any extraction" do
    test "an entry ../../etc/passwd", ctx do
      archive =
        ZipFixtures.build([
          ZipFixtures.entry("pack.yaml", "schema: 1\n"),
          ZipFixtures.entry("../../etc/passwd", "root::0:0::/:/bin/sh\n")
        ])

      assert rejected!(ctx, archive) == [
               entry("../../etc/passwd", "the name contains a .. component")
             ]

      # The name points two levels above the extraction directory, which
      # lies directly below TMPDIR, so into the test root.
      target = Path.expand("../../etc/passwd", Path.join(ctx.tmp, "espalier-pack-x"))
      assert target == Path.join([ctx.root, "outer", "etc", "passwd"])
      refute File.exists?(target)
      # :zip would write such an entry under its last name component.
      assert Path.wildcard(Path.join(ctx.root, "**/passwd"), match_dot: true) == []
    end

    test "an absolute name", ctx do
      target = Path.join(ctx.root, "absolute.txt")

      archive =
        ZipFixtures.build([
          ZipFixtures.entry("pack.yaml", "schema: 1\n"),
          ZipFixtures.entry(target, "written outside\n")
        ])

      assert rejected!(ctx, archive) == [entry(target, "the name is absolute")]
      refute File.exists?(target)
    end

    test "absolute names in other forms, backslashes and .. components", ctx do
      cases = [
        {"C:/escape.txt", ["the name is absolute"]},
        {"c:escape.txt", ["the name is absolute"]},
        {"\\escape.txt", ["the name is absolute", "the name contains a backslash"]},
        {"modules\\..\\..\\escape.txt", ["the name contains a backslash"]},
        {"modules/../../escape.txt", ["the name contains a .. component"]},
        {"..", ["the name contains a .. component"]},
        {"modules/..", ["the name contains a .. component"]}
      ]

      for {name, messages} <- cases do
        archive = ZipFixtures.build([ZipFixtures.entry(name, "x")])

        assert rejected!(ctx, archive) == Enum.map(messages, &entry(name, &1)),
               "#{inspect(name)} is not rejected as expected"
      end

      assert Path.wildcard(Path.join(ctx.root, "**/escape.txt"), match_dot: true) == []
    end

    test "a symlink entry (Unix mode 0o120777)", ctx do
      # A link to the test root and a file written through it: an extractor
      # that created the link would write `escape.txt` into the test root.
      archive =
        ZipFixtures.build([
          ZipFixtures.symlink_entry("link", "../../.."),
          ZipFixtures.entry("link/escape.txt", "written through the link\n")
        ])

      assert rejected!(ctx, archive) == [entry("link", "the entry is a symbolic link")]
      refute File.exists?(Path.join(ctx.root, "escape.txt"))
      assert Path.wildcard(Path.join(ctx.root, "**/escape.txt"), match_dot: true) == []
    end

    test "a symlink to an absolute target", ctx do
      archive =
        ZipFixtures.build([
          ZipFixtures.entry("pack.yaml", "schema: 1\n"),
          ZipFixtures.symlink_entry("modules", "/etc")
        ])

      assert rejected!(ctx, archive) == [entry("modules", "the entry is a symbolic link")]
    end

    test "declared sizes above five times the limit", ctx do
      # Two deflated entries whose real contents add up to 5,001 bytes,
      # one byte above five times the limit of 1,000 bytes.
      archive =
        ZipFixtures.build([
          ZipFixtures.deflated_entry("a.txt", zeros(2_500)),
          ZipFixtures.deflated_entry("b.txt", zeros(2_501))
        ])

      assert byte_size(archive) < 1_000

      assert rejected!(ctx, archive, 1_000) == [
               entry(".", "the declared sizes exceed 5 times the upload limit")
             ]
    end

    test "a declared size above five times the limit before the data is read", ctx do
      archive = ZipFixtures.build([ZipFixtures.entry("a.txt", "x", size: 5_001)])

      assert rejected!(ctx, archive, 1_000) == [
               entry(".", "the declared sizes exceed 5 times the upload limit")
             ]
    end

    test "more than 2,000 entries", ctx do
      archive =
        1..2_001
        |> Enum.map(&ZipFixtures.entry("f#{&1}.txt", ""))
        |> ZipFixtures.build()

      assert Archive.max_entries() == 2_000

      assert rejected!(ctx, archive) == [
               entry(".", "the archive holds more than 2000 entries")
             ]
    end

    test "names and entries that the module does not extract", ctx do
      cases = [
        {[ZipFixtures.entry("", "x")], [entry("", "the name is empty")]},
        {[ZipFixtures.entry("nul\0name.txt", "x")],
         [entry("nul?name.txt", "the name contains a NUL character")]},
        {[ZipFixtures.entry("a.txt", "x"), ZipFixtures.entry("a.txt", "y")],
         [entry("a.txt", "the archive holds this path twice")]},
        {[ZipFixtures.entry("d/a.txt", "x"), ZipFixtures.entry("d//a.txt", "y")],
         [entry("d/a.txt", "the archive holds this path twice")]},
        {[ZipFixtures.entry("./a.txt", "x"), ZipFixtures.entry("a.txt", "y")],
         [entry("./a.txt", "the archive holds this path twice")]},
        {[ZipFixtures.entry("a.txt", "x", flags: 1)], [entry("a.txt", "the entry is encrypted")]},
        {[ZipFixtures.entry("a.txt", "x", method: 12)],
         [entry("a.txt", "the entry uses an unsupported compression")]}
      ]

      for {entries, expected} <- cases do
        assert rejected!(ctx, ZipFixtures.build(entries)) == expected
      end

      assert [%{"line" => nil, "message" => "the name is no UTF-8"}] =
               rejected!(ctx, ZipFixtures.build([ZipFixtures.entry(<<0xFF, 0xFE>>, "x")]))
    end

    test "uploads that are no single-disk zip archive", ctx do
      one = [ZipFixtures.entry("a.txt", "x")]

      cases = [
        {"no zip at all", "the upload is no zip archive"},
        {ZipFixtures.build(one, disk: 1), "multi-disk archives are not supported"},
        {ZipFixtures.build(one, zip64_locator: true), "ZIP64 archives are not supported"},
        {:binary.copy("x", 2_000), "the upload is larger than the upload limit"}
      ]

      for {archive, message} <- cases do
        assert rejected!(ctx, archive, 1_000) == [entry(".", message)]
      end

      missing = Path.join(ctx.uploads, "missing.zip")

      assert Archive.extract(missing, @max) ==
               {:error, [entry(".", "the upload cannot be read")]}
    end
  end

  describe "extract/2 compares every extracted entry with its declared size" do
    test "a stored entry whose declared size is below its content", ctx do
      # The first entry is written before the second one fails, so the
      # rejection has to remove the extraction directory.
      archive =
        ZipFixtures.build([
          ZipFixtures.entry("pack.yaml", "schema: 1\n"),
          ZipFixtures.entry("modules/a.txt", "hello world", size: 5)
        ])

      assert rejected!(ctx, archive) == [
               entry("modules/a.txt", "the extracted size differs from the declared size")
             ]
    end

    test "a stored entry whose declared size is above its content", ctx do
      archive = ZipFixtures.build([ZipFixtures.entry("a.txt", "hello", size: 11)])

      assert rejected!(ctx, archive) == [
               entry("a.txt", "the extracted size differs from the declared size")
             ]
    end

    test "a deflated entry whose declared size understates its content (bomb shape)", ctx do
      # 16 MiB of zeros deflate to about 16 KiB; the entry declares 1 KiB.
      bomb = ZipFixtures.deflated_entry("bomb.txt", zeros(16 * 1_048_576), size: 1_024)
      archive = ZipFixtures.build([ZipFixtures.entry("pack.yaml", "schema: 1\n"), bomb])

      assert byte_size(archive) < 100_000

      assert rejected!(ctx, archive) == [
               entry("bomb.txt", "the extracted size differs from the declared size")
             ]
    end

    test "a deflated entry whose declared size overstates its content", ctx do
      archive = ZipFixtures.build([ZipFixtures.deflated_entry("a.txt", zeros(100), size: 101)])

      assert rejected!(ctx, archive) == [
               entry("a.txt", "the extracted size differs from the declared size")
             ]
    end

    test "an entry whose CRC-32 differs or whose data cannot be inflated", ctx do
      wrong_crc = ZipFixtures.entry("a.txt", "hello", crc: :erlang.crc32("other"))

      assert rejected!(ctx, ZipFixtures.build([wrong_crc])) == [
               entry("a.txt", "the CRC-32 of the entry differs")
             ]

      broken =
        ZipFixtures.entry("b.txt", "hello", method: 8, compressed_size: 5, size: 5)

      assert rejected!(ctx, ZipFixtures.build([broken])) == [
               entry("b.txt", "the entry cannot be inflated")
             ]
    end
  end

  describe "extract/2 with names that the file system cannot hold" do
    # extract/2 returns {:ok, dir} or {:error, entries}; an archive whose
    # entries cannot all be written is rejected with a report entry.
    test "are rejected with a report entry and leave no directory", ctx do
      cases = [
        [ZipFixtures.entry("a", "x"), ZipFixtures.entry("a/b", "y")],
        [ZipFixtures.directory_entry("a/"), ZipFixtures.entry("a", "y")],
        [ZipFixtures.entry(String.duplicate("n", 300), "x")]
      ]

      for entries <- cases do
        path = upload!(ctx, ZipFixtures.build(entries))
        before = tree(ctx)

        result =
          try do
            Archive.extract(path, @max)
          rescue
            exception -> {:raised, exception}
          end

        assert tree(ctx) == before
        assert {:error, [%{"line" => nil, "message" => _} | _]} = result
      end
    end
  end

  describe "extract/2 with a valid archive" do
    test "extracts every entry into a new directory below System.tmp_dir!/0", ctx do
      text = String.duplicate("A line of the lesson.\n", 200)

      archive =
        ZipFixtures.build([
          ZipFixtures.entry("pack.yaml", "schema: 1\n"),
          ZipFixtures.directory_entry("modules/"),
          ZipFixtures.deflated_entry("modules/01-basics/lessons/01-first-lesson.md", text),
          ZipFixtures.entry("modules/01-basics/empty.yaml", ""),
          # Another host system than Unix: the mode bits carry no file type.
          ZipFixtures.entry("notes.txt", "target",
            made_by: ZipFixtures.version_made_by(0),
            external_attr: ZipFixtures.unix_mode(0o120777)
          )
        ])

      assert {:ok, dir} = Archive.extract(upload!(ctx, archive), @max)
      assert Path.dirname(dir) == ctx.tmp
      assert "espalier-pack-" <> _random = Path.basename(dir)

      assert files(dir) == %{
               "modules/01-basics/empty.yaml" => "",
               "modules/01-basics/lessons/01-first-lesson.md" => text,
               "notes.txt" => "target",
               "pack.yaml" => "schema: 1\n"
             }

      refute File.lstat!(Path.join(dir, "notes.txt")).type == :symlink
      assert File.dir?(Path.join(dir, "modules"))

      File.rm_rf!(dir)
      assert File.ls!(ctx.tmp) == []
    end

    test "extracts exactly 2,000 entries and declared sizes of five times the limit", ctx do
      archive =
        1..2_000
        |> Enum.map(&ZipFixtures.entry("f#{&1}.txt", ""))
        |> ZipFixtures.build()

      assert {:ok, dir} = Archive.extract(upload!(ctx, archive), @max)
      assert length(File.ls!(dir)) == 2_000
      File.rm_rf!(dir)

      archive = ZipFixtures.build([ZipFixtures.deflated_entry("a.txt", zeros(5_000))])
      assert {:ok, dir} = Archive.extract(upload!(ctx, archive), 1_000)
      assert File.read!(Path.join(dir, "a.txt")) == zeros(5_000)
      File.rm_rf!(dir)
    end

    test "extracts the demo pack zipped with :zip.create/3 unchanged", ctx do
      expected = files(demo_path())

      for opts <- [[], [root: "demo"]] do
        archive = ZipFixtures.zip_dir!(demo_path(), opts)
        assert {:ok, dir} = Archive.extract(upload!(ctx, archive), @max)

        extracted =
          case Keyword.fetch(opts, :root) do
            {:ok, root} -> files(Path.join(dir, root))
            :error -> files(dir)
          end

        assert extracted == expected
        File.rm_rf!(dir)
      end

      assert File.ls!(ctx.tmp) == []
    end
  end

  describe "with_extracted/3" do
    test "runs the function on the directory and removes it afterwards", ctx do
      archive = ZipFixtures.build([ZipFixtures.entry("pack.yaml", "schema: 1\n")])
      parent = self()

      result =
        Archive.with_extracted(upload!(ctx, archive), @max, fn dir ->
          send(parent, {:dir, dir})
          File.read!(Path.join(dir, "pack.yaml"))
        end)

      assert result == "schema: 1\n"
      assert_received {:dir, dir}
      assert Path.dirname(dir) == ctx.tmp
      refute File.exists?(dir)
      assert File.ls!(ctx.tmp) == []
    end

    test "removes the directory when the function raises", ctx do
      archive = ZipFixtures.build([ZipFixtures.entry("pack.yaml", "schema: 1\n")])
      path = upload!(ctx, archive)
      parent = self()

      assert_raise RuntimeError, "boom", fn ->
        Archive.with_extracted(path, @max, fn dir ->
          send(parent, {:dir, dir})
          raise "boom"
        end)
      end

      assert_received {:dir, dir}
      refute File.exists?(dir)
      assert File.ls!(ctx.tmp) == []
    end

    test "removes the directory when the function throws or exits", ctx do
      path = upload!(ctx, ZipFixtures.build([ZipFixtures.entry("pack.yaml", "schema: 1\n")]))

      assert catch_throw(Archive.with_extracted(path, @max, fn _dir -> throw(:stop) end)) ==
               :stop

      assert catch_exit(Archive.with_extracted(path, @max, fn _dir -> exit(:stop) end)) ==
               :stop

      assert File.ls!(ctx.tmp) == []
    end

    test "returns the report of a rejected archive without calling the function", ctx do
      archive = ZipFixtures.build([ZipFixtures.entry("../../etc/passwd", "x")])
      before = tree(ctx)

      assert Archive.with_extracted(upload!(ctx, archive), @max, fn _dir -> flunk("called") end) ==
               {:error, [entry("../../etc/passwd", "the name contains a .. component")]}

      assert tree(ctx) == before
    end
  end

  ## Helpers

  # Runs extract/2 on `archive`, asserts that it is rejected and that the
  # test root, System.tmp_dir!/0 included, holds the same paths as before,
  # and returns the report entries.
  defp rejected!(ctx, archive, max \\ @max) do
    path = upload!(ctx, archive)
    tmp_before = File.ls!(System.tmp_dir!())
    before = tree(ctx)

    assert {:error, entries} = Archive.extract(path, max)

    assert File.ls!(System.tmp_dir!()) == tmp_before
    assert tree(ctx) == before
    entries
  end

  defp entry(file, message), do: %{"file" => file, "line" => nil, "message" => message}

  defp upload!(ctx, archive) do
    ZipFixtures.write!(
      Path.join(ctx.uploads, "upload-#{System.unique_integer([:positive])}.zip"),
      archive
    )
  end

  # Every path below the test root apart from the uploads.
  defp tree(%{root: root, uploads: uploads}) do
    root
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&(&1 == uploads or String.starts_with?(&1, uploads <> "/")))
    |> Enum.sort()
  end

  # The regular files below `dir` with their contents, by relative path.
  defp files(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(&{Path.relative_to(&1, dir), File.read!(&1)})
  end

  defp zeros(count), do: :binary.copy(<<0>>, count)
end
