defmodule Espalier.Media.StoreTest do
  @moduledoc """
  Task 0018, steps 4 and 23 (ASVS 5.3.2): `Espalier.Media.Store` builds
  every path from a lower-case SHA-256 digest, a delivery extension or a
  UUID and raises `ArgumentError` for anything else, and `work_asset_id/1`
  reads an asset id only from a name `<asset id>-<run id>`; `put/2` stores
  a file under its digest in `files/<aa>/<bb>/`, with mode 0640, and keeps
  an existing file of the same digest; `accept_incoming/2` moves or copies
  a file to `incoming/<asset id>`; `remove/2` deletes a file only when no
  asset names its digest.

  `MEDIA_DIR` is shared by every test of the suite, and `remove/2` takes the
  advisory lock of the store in the sandbox transaction, hence no `async`.
  Every file of these tests has random contents, so no other test meets its
  digest.
  """
  use Espalier.DataCase, async: false

  import Bitwise

  alias Espalier.Media
  alias Espalier.Media.{Asset, Store}

  @moduletag :tmp_dir

  @sha "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  @uuid "3c0d8a52-9b1e-4f7a-8e2d-5a6b7c8d9e0f"

  describe "paths" do
    test "the root is MEDIA_DIR expanded, with the four directories below it" do
      root = Path.expand(Media.dir())

      assert Store.root() == root
      assert Store.files_root() == Path.join(root, "files")
      assert Store.incoming_root() == Path.join(root, "incoming")
      assert Store.work_root() == Path.join(root, "work")
      assert Store.uploads_root() == Path.join(root, "uploads")
    end

    test "path/2 lays out files/aa/bb/<sha256>.<ext> for every delivery extension" do
      for ext <- ~w(webp svg webm vtt) do
        assert Store.path(@sha, ext) ==
                 Path.join([Store.root(), "files", "01", "23", @sha <> "." <> ext])
      end

      assert Store.extensions() == ~w(webp svg webm vtt)
    end

    test "path/2 raises for a digest that is not 64 lower-case hex digits" do
      for digest <- [
            String.upcase(@sha),
            "0123456789ABCDEF" <> binary_part(@sha, 16, 48),
            binary_part(@sha, 0, 63),
            @sha <> "0",
            "",
            "../" <> binary_part(@sha, 3, 61),
            binary_part(@sha, 0, 62) <> "/.",
            binary_part(@sha, 0, 63) <> "g",
            @sha <> "\n",
            " " <> binary_part(@sha, 1, 63),
            nil,
            :sha,
            123
          ] do
        assert_raise ArgumentError, fn -> Store.path(digest, "webp") end
      end
    end

    test "path/2 raises for an extension outside the closed list" do
      for ext <- [
            "png",
            "jpg",
            "WEBP",
            "Webp",
            ".webp",
            "webp/../x",
            "../webp",
            "",
            "webp\n",
            nil,
            :webp
          ] do
        assert_raise ArgumentError, fn -> Store.path(@sha, ext) end
      end
    end

    test "incoming_path/1 and work_dir/2 take lower-case UUIDs" do
      run = "9f8e7d6c-5b4a-4392-8170-6f5e4d3c2b1a"

      assert Store.incoming_path(@uuid) == Path.join([Store.root(), "incoming", @uuid])
      assert Store.work_dir(@uuid, run) == Path.join([Store.root(), "work", @uuid <> "-" <> run])

      for id <- [
            String.upcase(@uuid),
            String.replace(@uuid, "-", ""),
            "../" <> binary_part(@uuid, 3, 33),
            "../../etc/passwd",
            @uuid <> "/..",
            @uuid <> "\n",
            binary_part(@uuid, 0, 35),
            String.replace(@uuid, "c", "g", global: false),
            "",
            nil,
            42
          ] do
        assert_raise ArgumentError, fn -> Store.incoming_path(id) end
        assert_raise ArgumentError, fn -> Store.work_dir(id, run) end
        assert_raise ArgumentError, fn -> Store.work_dir(@uuid, id) end
      end
    end

    test "work_asset_id/1 reads the asset id of <asset id>-<run id> and nothing else" do
      run = "9f8e7d6c-5b4a-4392-8170-6f5e4d3c2b1a"
      assert Store.work_asset_id(@uuid <> "-" <> run) == {:ok, @uuid}
      assert Store.work_asset_id(Path.basename(Store.work_dir(@uuid, run))) == {:ok, @uuid}

      for name <- [
            @uuid,
            @uuid <> "-x",
            @uuid <> "-" <> String.upcase(run),
            String.upcase(@uuid) <> "-" <> run,
            @uuid <> "-" <> run <> "\n",
            "../" <> @uuid <> "-" <> run,
            @uuid <> "-" <> run <> "-" <> run
          ] do
        assert Store.work_asset_id(name) == :error, name
      end
    end

    test "staging_dir/0 creates a fresh directory work/<uuid>" do
      dirs = [Store.staging_dir(), Store.staging_dir()]

      for dir <- dirs do
        on_exit(fn -> File.rm_rf(dir) end)

        assert File.dir?(dir)
        assert Path.dirname(dir) == Store.work_root()
        assert {:ok, _uuid} = Ecto.UUID.cast(Path.basename(dir))
        assert Store.work_asset_id(Path.basename(dir)) == :error
      end

      assert Enum.uniq(dirs) == dirs
    end

    test "full?/1 is true for a full volume and an exhausted disk quota only" do
      assert Store.full?(:enospc)
      assert Store.full?(:edquot)

      for reason <- [:eacces, :eio, :enoent, :exdev, :ok, nil] do
        refute Store.full?(reason), inspect(reason)
      end
    end

    test "parse_name/1 reads <sha256>.<ext> and nothing else" do
      assert Store.parse_name(@sha <> ".webm") == {:ok, {@sha, "webm"}}

      for name <- [
            String.upcase(@sha) <> ".webm",
            @sha <> ".png",
            @sha <> ".webm.webm",
            "../" <> @sha <> ".webm",
            @sha,
            @sha <> ".webm\n"
          ] do
        assert Store.parse_name(name) == :error, name
      end
    end
  end

  describe "put/2" do
    test "stores a file under its SHA-256 with mode 0640 and moves it", %{tmp_dir: dir} do
      # More than three blocks of 1 MiB and a rest.
      data = :crypto.strong_rand_bytes(3 * 1_048_576 + 17)
      file = write!(dir, "out.webp", data)
      expected = sha256(data)

      assert Store.put(file, "webp") == {expected, byte_size(data)}
      track(Store.path(expected, "webp"))

      target = Store.path(expected, "webp")
      <<aa::binary-size(2), bb::binary-size(2), _rest::binary>> = expected
      assert target == Path.join([Store.root(), "files", aa, bb, expected <> ".webp"])
      assert File.read!(target) == data
      assert (File.stat!(target).mode &&& 0o777) == 0o640
      refute File.exists?(file)
    end

    test "digests an empty file and a file of exactly one block", %{tmp_dir: dir} do
      for data <- ["", :crypto.strong_rand_bytes(1_048_576)] do
        file = write!(dir, "out.vtt", data)
        assert {digest, bytes} = Store.digest(file)
        assert digest == sha256(data)
        assert bytes == byte_size(data)
        assert Store.sha256_file(file) == digest
      end
    end

    test "keeps an existing file of the same digest, touches it and removes the duplicate",
         %{tmp_dir: dir} do
      data = :crypto.strong_rand_bytes(4096)
      first = write!(dir, "first.webp", data)
      {sha, bytes} = Store.put(first, "webp")
      target = Store.path(sha, "webp")
      track(target)

      past = {{2020, 1, 1}, {0, 0, 0}}
      File.touch!(target, past)
      inode = File.stat!(target).inode
      assert File.stat!(target, time: :universal).mtime == past

      second = write!(dir, "second.webp", data)
      assert Store.put(second, "webp") == {sha, bytes}

      stat = File.stat!(target, time: :posix)
      assert stat.inode == inode
      assert abs(stat.mtime - System.os_time(:second)) < 60
      assert File.read!(target) == data
      refute File.exists?(second)
    end

    test "the same bytes with another extension are another file", %{tmp_dir: dir} do
      data = :crypto.strong_rand_bytes(512)
      {sha, _bytes} = Store.put(write!(dir, "a", data), "webp")
      assert Store.put(write!(dir, "b", data), "webm") == {sha, 512}
      track(Store.path(sha, "webp"))
      track(Store.path(sha, "webm"))

      assert File.regular?(Store.path(sha, "webp"))
      assert File.regular?(Store.path(sha, "webm"))
    end

    test "raises for an extension outside the closed list", %{tmp_dir: dir} do
      file = write!(dir, "x", :crypto.strong_rand_bytes(64))
      assert_raise ArgumentError, fn -> Store.put(file, "png") end
      assert File.exists?(file)
    end
  end

  describe "accept_incoming/2" do
    test "{:move, path} renames the file to incoming/<id>", %{tmp_dir: dir} do
      id = Ecto.UUID.generate()
      data = :crypto.strong_rand_bytes(2048)
      source = write!(dir, "upload", data)
      File.chmod!(source, 0o600)
      on_exit(fn -> File.rm(Store.incoming_path(id)) end)

      assert Store.accept_incoming({:move, source}, id) == :ok

      target = Store.incoming_path(id)
      assert File.read!(target) == data
      assert (File.stat!(target).mode &&& 0o777) == 0o640
      refute File.exists?(source)
    end

    test "{:copy, path} copies a pack file, which stays", %{tmp_dir: dir} do
      id = Ecto.UUID.generate()
      data = :crypto.strong_rand_bytes(2048)
      source = write!(dir, "figure.png", data)
      on_exit(fn -> File.rm(Store.incoming_path(id)) end)

      assert Store.accept_incoming({:copy, source}, id) == :ok

      target = Store.incoming_path(id)
      assert File.read!(target) == data
      assert (File.stat!(target).mode &&& 0o777) == 0o640
      assert File.read!(source) == data
    end

    test "a missing source answers an error and leaves no incoming file", %{tmp_dir: dir} do
      for mode <- [:move, :copy] do
        id = Ecto.UUID.generate()
        assert {:error, :enoent} = Store.accept_incoming({mode, Path.join(dir, "absent")}, id)
        refute File.exists?(Store.incoming_path(id))
      end
    end

    test "raises for an id that is no UUID and leaves the source", %{tmp_dir: dir} do
      source = write!(dir, "upload", "data")

      assert_raise ArgumentError, fn ->
        Store.accept_incoming({:move, source}, "../../files/evil")
      end

      assert File.exists?(source)
    end

    test "{:move, path} from another file system copies the file" do
      shm = "/dev/shm"

      if File.dir?(shm) and device(shm) != device(Path.dirname(Store.root())) do
        id = Ecto.UUID.generate()
        data = :crypto.strong_rand_bytes(1024)
        source = Path.join(shm, "espalier-store-test-#{id}")
        File.write!(source, data)

        on_exit(fn ->
          File.rm(source)
          File.rm(Store.incoming_path(id))
        end)

        assert Store.accept_incoming({:move, source}, id) == :ok
        assert File.read!(Store.incoming_path(id)) == data
        assert (File.stat!(Store.incoming_path(id)).mode &&& 0o777) == 0o640
      end
    end

    test "{:move, path} from another file system removes the source" do
      shm = "/dev/shm"

      if File.dir?(shm) and device(shm) != device(Path.dirname(Store.root())) do
        id = Ecto.UUID.generate()
        source = Path.join(shm, "espalier-store-test-#{id}")
        File.write!(source, "data")

        on_exit(fn ->
          File.rm(source)
          File.rm(Store.incoming_path(id))
        end)

        assert Store.accept_incoming({:move, source}, id) == :ok
        refute File.exists?(source)
      end
    end
  end

  describe "remove/2" do
    test "deletes a file that no asset names", %{tmp_dir: dir} do
      {sha, _bytes} = Store.put(write!(dir, "out", :crypto.strong_rand_bytes(256)), "webp")
      track(Store.path(sha, "webp"))
      refute Store.named?(sha)

      assert Store.remove(sha, "webp") == :ok
      refute File.exists?(Store.path(sha, "webp"))
    end

    test "keeps a file that an asset names as its delivery file", %{tmp_dir: dir} do
      {sha, bytes} = Store.put(write!(dir, "out", :crypto.strong_rand_bytes(256)), "webm")
      track(Store.path(sha, "webm"))
      insert_asset!(sha256: sha, ext: "webm", bytes: bytes, kind: :video)

      assert Store.named?(sha)
      assert Store.remove(sha, "webm") == :ok
      assert File.regular?(Store.path(sha, "webm"))
    end

    test "keeps a file that an asset names as its poster", %{tmp_dir: dir} do
      {poster, bytes} = Store.put(write!(dir, "poster", :crypto.strong_rand_bytes(256)), "webp")
      track(Store.path(poster, "webp"))
      insert_asset!(sha256: random_sha256(), poster_sha256: poster, poster_bytes: bytes)

      assert Store.named?(poster)
      assert Store.remove(poster, "webp") == :ok
      assert File.regular?(Store.path(poster, "webp"))
    end

    test "a missing file is no error" do
      assert Store.remove(random_sha256(), "vtt") == :ok
    end

    test "raises for a digest or an extension outside the rules" do
      assert_raise ArgumentError, fn ->
        Store.remove("../" <> binary_part(@sha, 3, 61), "webp")
      end

      assert_raise ArgumentError, fn -> Store.remove(@sha, "png") end
    end
  end

  ## Helpers

  defp write!(dir, name, data) do
    path = Path.join(dir, name)
    File.write!(path, data)
    path
  end

  defp sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)

  defp random_sha256, do: 32 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  defp device(path), do: File.stat!(path).major_device * 65_536 + File.stat!(path).minor_device

  # A store file of a test, removed after it.
  defp track(path), do: on_exit(fn -> File.rm(path) end)

  defp insert_asset!(fields) do
    Repo.insert!(
      struct!(
        %Asset{
          kind: :image,
          status: :ready,
          title: "Invented figure",
          source_name: "figure.png",
          source_sha256: random_sha256(),
          ext: "webp",
          incoming_bytes: 0,
          progress: 100,
          origin: :upload
        },
        fields
      )
    )
  end
end
