defmodule Espalier.ZipFixtures do
  @moduledoc """
  Zip archives for the tests of the pack upload (task 0015, step 19).

  `:zip.create/3` writes regular files and directories only, with sizes and
  CRC that match their content. The archive checks of
  `Espalier.Catalog.Pack.Archive` also need archives that `:zip` never
  writes: symbolic links, absolute names and names with `..` components,
  declared sizes that differ from the content, and more entries than the
  limit. `build/2` therefore writes the archive itself, with a local file
  header and the data of every entry, the central directory and the
  end-of-central-directory record. CRC-32 values come from
  `:erlang.crc32/1`.

      ZipFixtures.build([
        ZipFixtures.entry("pack.yaml", "schema: 1\\n"),
        ZipFixtures.symlink_entry("link", "/etc/passwd")
      ])

  An entry is a map that `entry/3`, `deflated_entry/3`, `directory_entry/2`
  and `symlink_entry/3` return; each takes options that override the
  declared values of the headers. `zip_dir!/2` zips a pack directory with
  `:zip.create/3` in memory, and `write!/2` writes an archive to a file for
  `Espalier.Catalog.Pack.Archive.extract/2`.
  """

  import Bitwise

  @local_signature 0x04034B50
  @cd_signature 0x02014B50
  @eocd_signature 0x06054B50
  @zip64_locator_signature 0x07064B50

  @version_needed 20
  # 1980-01-01 00:00 in MS-DOS format.
  @dos_date 1 <<< 5 ||| 1
  @dos_time 0

  @unix 3
  @regular_file 0o100644
  @directory 0o040755
  @symlink 0o120777

  @stored 0
  @deflated 8

  @typedoc """
  An entry of `build/2`: the name, the bytes stored in the archive (`data`),
  the declared values of the headers and the attributes of the central
  directory.
  """
  @type entry :: %{
          name: binary(),
          data: binary(),
          method: non_neg_integer(),
          flags: non_neg_integer(),
          crc: non_neg_integer(),
          compressed_size: non_neg_integer(),
          size: non_neg_integer(),
          made_by: non_neg_integer(),
          external_attr: non_neg_integer()
        }

  @doc """
  A stored entry with `content`. Options override the declared values:
  `:size` (uncompressed size, default the size of `content`),
  `:compressed_size` (default the size of `content`), `:crc`, `:method`,
  `:flags`, `:made_by` (default `version_made_by(3)`, Unix) and
  `:external_attr` (default a regular Unix file with mode `0o644`).
  """
  @spec entry(binary(), binary(), keyword()) :: entry()
  def entry(name, content, opts \\ []) when is_binary(name) and is_binary(content) do
    build_entry(name, content, content, @stored, opts)
  end

  @doc """
  A deflated entry with `content`, compressed with `:zlib` as raw deflate
  data (window bits -15). `:size` declares another uncompressed size, so
  that a small `:size` with a large `content` gives the shape of a zip bomb.
  The other options are the ones of `entry/3`.
  """
  @spec deflated_entry(binary(), binary(), keyword()) :: entry()
  def deflated_entry(name, content, opts \\ []) when is_binary(name) and is_binary(content) do
    build_entry(name, content, deflate(content), @deflated, opts)
  end

  @doc "A directory entry: `name` ends with `/`, and the entry holds no data."
  @spec directory_entry(binary(), keyword()) :: entry()
  def directory_entry(name, opts \\ []) when is_binary(name) do
    build_entry(
      name,
      "",
      "",
      @stored,
      Keyword.put_new(opts, :external_attr, unix_mode(@directory))
    )
  end

  @doc """
  A symbolic link as Info-ZIP writes it on Unix: the link target is the
  content, "version made by" names Unix (upper byte 3), and the upper 16
  bits of the external attributes carry the mode `0o120777`.
  """
  @spec symlink_entry(binary(), binary(), keyword()) :: entry()
  def symlink_entry(name, target, opts \\ []) when is_binary(name) and is_binary(target) do
    entry(name, target, Keyword.put_new(opts, :external_attr, unix_mode(@symlink)))
  end

  @doc "The value of \"version made by\" for the host system `system` (3 is Unix)."
  @spec version_made_by(non_neg_integer()) :: non_neg_integer()
  def version_made_by(system), do: system <<< 8 ||| 30

  @doc "The external attributes that carry the Unix `mode` in their upper 16 bits."
  @spec unix_mode(non_neg_integer()) :: non_neg_integer()
  def unix_mode(mode), do: mode <<< 16

  @doc """
  Builds an archive from `entries` and returns its bytes.

  Options: `:comment` (the archive comment), `:disk` (the number of the disk
  in the end record, default 0; another value gives a multi-disk archive),
  `:total` (the number of entries that the end record declares, default the
  length of `entries`) and `:zip64_locator` (`true` writes a ZIP64 end
  locator before the end record).
  """
  @spec build([entry()], keyword()) :: binary()
  def build(entries, opts \\ []) when is_list(entries) do
    {locals, headers, offset} =
      Enum.reduce(entries, {[], [], 0}, fn entry, {locals, headers, offset} ->
        local = local_header(entry)
        {[local | locals], [central_header(entry, offset) | headers], offset + byte_size(local)}
      end)

    directory = headers |> Enum.reverse() |> IO.iodata_to_binary()
    comment = Keyword.get(opts, :comment, "")
    total = Keyword.get(opts, :total, length(entries))
    disk = Keyword.get(opts, :disk, 0)

    locator =
      if Keyword.get(opts, :zip64_locator, false),
        do: <<@zip64_locator_signature::little-32, 0::little-32, 0::little-64, 1::little-32>>,
        else: <<>>

    eocd =
      <<@eocd_signature::little-32, disk::little-16, disk::little-16, total::little-16,
        total::little-16, byte_size(directory)::little-32, offset::little-32,
        byte_size(comment)::little-16, comment::binary>>

    IO.iodata_to_binary([Enum.reverse(locals), directory, locator, eocd])
  end

  @doc """
  Zips the regular files below `dir` with `:zip.create/3` in memory and
  returns the bytes. With `root: name`, every entry sits below the
  top-level directory `name`, the form that zipping a pack folder gives.
  """
  @spec zip_dir!(Path.t(), keyword()) :: binary()
  def zip_dir!(dir, opts \\ []) do
    prefix = Keyword.get(opts, :root)

    files =
      dir
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()
      |> Enum.map(fn path ->
        name = Path.relative_to(path, dir)
        name = if prefix, do: Path.join(prefix, name), else: name
        {String.to_charlist(name), File.read!(path)}
      end)

    {:ok, {_name, zip}} = :zip.create(~c"pack.zip", files, [:memory])
    zip
  end

  @doc "Writes `archive` to the file `path`, creating its directory, and returns `path`."
  @spec write!(Path.t(), binary()) :: Path.t()
  def write!(path, archive) when is_binary(archive) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, archive)
    path
  end

  ## Headers

  defp build_entry(name, content, data, method, opts) do
    %{
      name: name,
      data: data,
      method: Keyword.get(opts, :method, method),
      flags: Keyword.get(opts, :flags, 0),
      crc: Keyword.get(opts, :crc, :erlang.crc32(content)),
      compressed_size: Keyword.get(opts, :compressed_size, byte_size(data)),
      size: Keyword.get(opts, :size, byte_size(content)),
      made_by: Keyword.get(opts, :made_by, version_made_by(@unix)),
      external_attr: Keyword.get(opts, :external_attr, unix_mode(@regular_file))
    }
  end

  defp local_header(entry) do
    <<@local_signature::little-32, @version_needed::little-16, entry.flags::little-16,
      entry.method::little-16, @dos_time::little-16, @dos_date::little-16, entry.crc::little-32,
      entry.compressed_size::little-32, entry.size::little-32, byte_size(entry.name)::little-16,
      0::little-16, entry.name::binary, entry.data::binary>>
  end

  defp central_header(entry, offset) do
    <<@cd_signature::little-32, entry.made_by::little-16, @version_needed::little-16,
      entry.flags::little-16, entry.method::little-16, @dos_time::little-16, @dos_date::little-16,
      entry.crc::little-32, entry.compressed_size::little-32, entry.size::little-32,
      byte_size(entry.name)::little-16, 0::little-16, 0::little-16, 0::little-16, 0::little-16,
      entry.external_attr::little-32, offset::little-32, entry.name::binary>>
  end

  defp deflate(content) do
    z = :zlib.open()

    try do
      :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
      data = :zlib.deflate(z, content, :finish)
      :ok = :zlib.deflateEnd(z)
      IO.iodata_to_binary(data)
    after
      :zlib.close(z)
    end
  end
end
