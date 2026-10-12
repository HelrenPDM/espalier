defmodule Espalier.Catalog.Pack.Archive do
  @moduledoc """
  Checks and extracts the zip archive of a content pack upload (task 0015,
  step 7; ASVS 5.2.2, 5.2.3, 5.3.2 and 15.2.2).

  `:zip` in OTP 28.5.0.7 (stdlib 7.3.0.3, `src/zip.erl`) rewrites an
  absolute entry name to a relative one, extracts an entry that climbs above
  the target directory under its last name component, types every entry as
  a regular file or a directory, and inflates an entry without a bound on
  its output (`get_z_data_loop/8`). The module therefore reads the archive
  itself:

    1. It reads the upload, at most `max_bytes` (the parser of the upload
       route has bounded it already), locates the end-of-central-directory
       record and rejects ZIP64 and multi-disk archives.
    2. It reads name, uncompressed size, "version made by", flags,
       compression method and external attributes of every central
       directory header, and rejects the archive, with one report entry per
       finding, when a name is absolute (leading `/` or `\\`, or a drive
       letter), contains a backslash, a `..` component or a NUL character,
       is no UTF-8 or names a path that another entry names as well (after
       empty and `.` components are dropped); when an entry made on Unix (upper byte
       of "version made by" equal to 3) carries the file type `0o120000`
       (symbolic link) in the upper 16 bits of its external attributes;
       when an entry is encrypted or uses another method than stored or
       deflated; when the archive holds more than 2,000 entries; or when the
       declared uncompressed sizes add up to more than five times
       `max_bytes`.
    3. Only then it writes every entry into a new directory below
       `System.tmp_dir!/0`. A deflated entry is inflated in chunks with
       `:zlib.safeInflate/2`, and the extraction stops as soon as the output
       of an entry exceeds its declared size, so the disk receives at most
       the declared sizes. An entry whose output differs from its declared
       size or whose CRC-32 differs rejects the archive.

  A rejection removes the directory before `extract/2` returns, and
  `with_extracted/3` runs a function on the directory and removes it in an
  `after` block.

  A report entry has the shape of the import report (`file`, `line`,
  `message`): `file` is the entry name, or `.` for the archive itself, and
  `line` is `nil`.
  """

  import Bitwise

  @max_entries 2_000
  @size_factor 5

  @eocd_signature 0x06054B50
  @zip64_locator_signature 0x07064B50
  @cd_signature 0x02014B50
  @local_signature 0x04034B50

  @eocd_size 22
  @cd_header_size 46
  @local_header_size 30
  @max_comment 65_535

  @unix 3
  @file_type_mask 0o170000
  @symlink 0o120000

  @stored 0
  @deflated 8

  @typedoc "A report entry: the entry name (or `.`), no line, and the finding."
  @type entry :: %{String.t() => String.t() | nil}

  @doc "The largest number of entries of an archive."
  @spec max_entries() :: pos_integer()
  def max_entries, do: @max_entries

  @doc """
  Checks the archive at `upload_path` and extracts it into a new directory
  below `System.tmp_dir!/0`. Returns `{:ok, dir}`, which the caller removes,
  or `{:error, entries}` with one report entry per finding.
  """
  @spec extract(Path.t(), pos_integer()) :: {:ok, Path.t()} | {:error, [entry()]}
  def extract(upload_path, max_bytes) when is_binary(upload_path) and max_bytes > 0 do
    with {:ok, archive} <- read(upload_path, max_bytes),
         {:ok, headers} <- central_directory(archive),
         :ok <- check(headers, max_bytes) do
      write_all(archive, headers)
    end
  end

  @doc """
  Runs `fun` on the directory of `extract/2` and removes the directory in an
  `after` block. Returns the result of `fun`, or `{:error, entries}` for a
  rejected archive.
  """
  @spec with_extracted(Path.t(), pos_integer(), (Path.t() -> result)) ::
          result | {:error, [entry()]}
        when result: term()
  # The directory comes from extract/2, a new directory below
  # System.tmp_dir!/0 with a random name; no input reaches the path.
  # sobelow_skip ["Traversal.FileModule"]
  def with_extracted(upload_path, max_bytes, fun) when is_function(fun, 1) do
    case extract(upload_path, max_bytes) do
      {:ok, dir} ->
        try do
          fun.(dir)
        after
          File.rm_rf(dir)
        end

      {:error, entries} ->
        {:error, entries}
    end
  end

  ## Reading

  # The path is the temporary file of the multipart parser (Plug.Upload);
  # the request names no path.
  # sobelow_skip ["Traversal.FileModule"]
  defp read(path, max_bytes) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} when size <= max_bytes ->
        {:ok, File.read!(path)}

      {:ok, %File.Stat{type: :regular}} ->
        archive_error("the upload is larger than the upload limit")

      _other ->
        archive_error("the upload cannot be read")
    end
  end

  # The end-of-central-directory record is the last 22 bytes plus a comment
  # of at most 65,535 bytes; the record whose comment ends at the end of the
  # file is the one.
  defp central_directory(archive) do
    with {:ok, eocd_at, eocd} <- find_eocd(archive),
         :ok <- single_disk(eocd),
         :ok <- not_zip64(archive, eocd_at, eocd),
         :ok <- entry_count(eocd.total),
         :ok <- directory_bounds(eocd, eocd_at) do
      read_headers(archive, eocd.cd_offset, eocd.total, [])
    end
  end

  defp find_eocd(archive) when byte_size(archive) < @eocd_size,
    do: archive_error("the upload is no zip archive")

  defp find_eocd(archive) do
    last = byte_size(archive) - @eocd_size
    first = max(0, last - @max_comment)

    last
    |> Range.new(first, -1)
    |> Enum.find_value(fn at -> eocd_at(archive, at) end)
    |> case do
      nil -> archive_error("the upload is no zip archive")
      {at, eocd} -> {:ok, at, eocd}
    end
  end

  defp eocd_at(archive, at) do
    case binary_part(archive, at, @eocd_size) do
      <<@eocd_signature::little-32, disk::little-16, cd_disk::little-16, disk_entries::little-16,
        total::little-16, cd_size::little-32, cd_offset::little-32, comment_length::little-16>>
      when at + @eocd_size + comment_length == byte_size(archive) ->
        {at,
         %{
           disk: disk,
           cd_disk: cd_disk,
           disk_entries: disk_entries,
           total: total,
           cd_size: cd_size,
           cd_offset: cd_offset
         }}

      _other ->
        nil
    end
  end

  defp single_disk(%{disk: 0, cd_disk: 0, disk_entries: same, total: same}), do: :ok
  defp single_disk(_eocd), do: archive_error("multi-disk archives are not supported")

  defp not_zip64(archive, eocd_at, eocd) do
    locator? =
      eocd_at >= 20 and
        match?(
          <<@zip64_locator_signature::little-32, _::binary>>,
          binary_part(archive, eocd_at - 20, 4)
        )

    if locator? or eocd.total == 0xFFFF or eocd.cd_size == 0xFFFFFFFF or
         eocd.cd_offset == 0xFFFFFFFF,
       do: archive_error("ZIP64 archives are not supported"),
       else: :ok
  end

  defp entry_count(total) when total > @max_entries,
    do: archive_error("the archive holds more than #{@max_entries} entries")

  defp entry_count(_total), do: :ok

  defp directory_bounds(%{cd_offset: offset, cd_size: size}, eocd_at) do
    if offset + size <= eocd_at,
      do: :ok,
      else: archive_error("the central directory lies outside the archive")
  end

  defp read_headers(_archive, _at, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp read_headers(archive, at, remaining, acc) do
    with <<@cd_signature::little-32, made_by::little-16, _needed::little-16, flags::little-16,
           method::little-16, _time::little-16, _date::little-16, crc::little-32,
           compressed::little-32, size::little-32, name_length::little-16,
           extra_length::little-16, comment_length::little-16, _disk::little-16,
           _internal::little-16, external::little-32, local_offset::little-32>> <-
           slice(archive, at, @cd_header_size),
         name when is_binary(name) <- slice(archive, at + @cd_header_size, name_length) do
      header = %{
        name: name,
        made_by: made_by,
        flags: flags,
        method: method,
        crc: crc,
        compressed: compressed,
        size: size,
        external: external,
        local_offset: local_offset
      }

      next = at + @cd_header_size + name_length + extra_length + comment_length
      read_headers(archive, next, remaining - 1, [header | acc])
    else
      _other -> archive_error("the central directory is damaged")
    end
  end

  defp slice(archive, at, length) when at >= 0 and at + length <= byte_size(archive),
    do: binary_part(archive, at, length)

  defp slice(_archive, _at, _length), do: nil

  ## Checks

  defp check(headers, max_bytes) do
    duplicates =
      headers
      |> Enum.group_by(&path_key(&1.name), & &1.name)
      |> Enum.filter(fn {_key, names} -> length(names) > 1 end)
      |> Enum.map(fn {_key, [name | _rest]} ->
        finding(name, "the archive holds this path twice")
      end)

    entries = Enum.flat_map(headers, &entry_findings/1) ++ duplicates

    declared = headers |> Enum.map(& &1.size) |> Enum.sum()

    entries =
      if declared > @size_factor * max_bytes,
        do:
          entries ++
            [finding(".", "the declared sizes exceed #{@size_factor} times the upload limit")],
        else: entries

    if entries == [], do: :ok, else: {:error, entries}
  end

  defp entry_findings(header) do
    name = header.name

    [
      {not String.valid?(name), "the name is no UTF-8"},
      {name == "", "the name is empty"},
      {String.contains?(name, <<0>>), "the name contains a NUL character"},
      {absolute?(name), "the name is absolute"},
      {String.contains?(name, "\\"), "the name contains a backslash"},
      {".." in String.split(name, "/"), "the name contains a .. component"},
      {symlink?(header), "the entry is a symbolic link"},
      {(header.flags &&& 1) == 1, "the entry is encrypted"},
      {header.method not in [@stored, @deflated], "the entry uses an unsupported compression"},
      {header.size == 0xFFFFFFFF or header.compressed == 0xFFFFFFFF or
         header.local_offset == 0xFFFFFFFF, "ZIP64 entries are not supported"}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(fn {true, message} -> finding(printable(name), message) end)
  end

  # Names that write the same path, such as `a//b`, `./a/b` and `a/b`, or
  # the directory `a/` and the file `a`, share one key.
  defp path_key(name) do
    name |> String.split("/") |> Enum.reject(&(&1 in ["", "."])) |> Enum.join("/")
  end

  defp absolute?("/" <> _rest), do: true
  defp absolute?("\\" <> _rest), do: true

  defp absolute?(<<letter, ?:, _rest::binary>>) when letter in ?a..?z or letter in ?A..?Z,
    do: true

  defp absolute?(_name), do: false

  defp symlink?(%{made_by: made_by, external: external}) do
    made_by >>> 8 == @unix and (external >>> 16 &&& @file_type_mask) == @symlink
  end

  ## Extraction

  # A rejected entry and an exception remove the directory before the
  # function returns; only a complete extraction leaves it to the caller.
  # The directory is a new directory below System.tmp_dir!/0 with a random
  # name; no input reaches the path.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_all(archive, headers) do
    dir = Path.join(System.tmp_dir!(), "espalier-pack-" <> random_name())
    File.mkdir_p!(dir)

    result =
      try do
        write_entries(archive, headers, dir)
      catch
        kind, reason ->
          File.rm_rf(dir)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    case result do
      :ok ->
        {:ok, dir}

      {:error, _entries} = error ->
        File.rm_rf(dir)
        error
    end
  end

  # A name that the file system cannot hold, such as a file below a file
  # of the same archive or a name beyond the length limit of a path
  # component, rejects the archive with a report entry.
  defp write_entries(archive, headers, dir) do
    Enum.reduce_while(headers, :ok, fn header, :ok ->
      case write_entry_safely(archive, header, dir) do
        :ok -> {:cont, :ok}
        {:error, message} -> {:halt, {:error, [finding(header.name, message)]}}
      end
    end)
  end

  defp write_entry_safely(archive, header, dir) do
    write_entry(archive, header, dir)
  rescue
    File.Error -> {:error, "the entry cannot be written to the file system"}
  end

  # check/2 has rejected every absolute name, backslash, `..` component, NUL
  # character and symbolic link before any write, so the joined path stays
  # inside the new directory.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_entry(archive, header, dir) do
    if String.ends_with?(header.name, "/") do
      File.mkdir_p!(Path.join(dir, header.name))
    else
      write_file(archive, header, dir)
    end
  end

  # The same checks as write_entry/3 keep the path inside the new directory.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_file(archive, header, dir) do
    with {:ok, data} <- local_data(archive, header),
         {:ok, content} <- decompress(header, data),
         :ok <- check_crc(header, content) do
      path = Path.join(dir, header.name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end
  end

  defp local_data(archive, header) do
    with <<@local_signature::little-32, _rest::binary-size(22), name_length::little-16,
           extra_length::little-16>> <- slice(archive, header.local_offset, @local_header_size),
         data_at = header.local_offset + @local_header_size + name_length + extra_length,
         data when is_binary(data) <- slice(archive, data_at, header.compressed) do
      {:ok, data}
    else
      _other -> {:error, "the local header of the entry is damaged"}
    end
  end

  defp decompress(%{method: @stored, size: size}, data) when byte_size(data) == size,
    do: {:ok, data}

  defp decompress(%{method: @stored}, _data),
    do: {:error, "the extracted size differs from the declared size"}

  defp decompress(%{method: @deflated, size: size}, data) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, -15)
      inflate(z, :zlib.safeInflate(z, data), size, [], 0)
    rescue
      ErlangError -> {:error, "the entry cannot be inflated"}
    after
      :zlib.close(z)
    end
  end

  # Each call of safeInflate/2 returns a bounded chunk, so the output stops
  # at the first chunk beyond the declared size.
  defp inflate(z, {status, chunk}, size, acc, count) when status in [:continue, :finished] do
    chunk = IO.iodata_to_binary(chunk)
    count = count + byte_size(chunk)

    cond do
      count > size -> {:error, "the extracted size differs from the declared size"}
      status == :continue -> inflate(z, :zlib.safeInflate(z, []), size, [acc | chunk], count)
      count == size -> {:ok, IO.iodata_to_binary([acc | chunk])}
      true -> {:error, "the extracted size differs from the declared size"}
    end
  end

  defp inflate(_z, _other, _size, _acc, _count), do: {:error, "the entry cannot be inflated"}

  defp check_crc(%{crc: crc}, content) do
    if :erlang.crc32(content) == crc, do: :ok, else: {:error, "the CRC-32 of the entry differs"}
  end

  ## Helpers

  defp random_name, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp archive_error(message), do: {:error, [finding(".", message)]}

  defp finding(file, message),
    do: %{"file" => printable(file), "line" => nil, "message" => message}

  # A name goes into the report as one printable line of at most 1,000
  # characters, like every other report member.
  defp printable(name) do
    name
    |> String.replace_invalid()
    |> String.replace(~r/[\x00-\x1f\x7f]/u, "?")
    |> String.slice(0, 1_000)
  end
end
