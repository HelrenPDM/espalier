defmodule EspalierWeb.MediaMultipart do
  @moduledoc """
  The multipart parser of the media upload (task 0018, step 15). The body
  holds exactly one part: `file`, with a file name. The parser streams that
  part to a temporary file of `Plug.Upload` below `PLUG_TMPDIR`, up to the
  larger of `MEDIA_IMAGE_MAX_MB` and `MEDIA_VIDEO_MAX_MB`, and answers 413
  above it (`Plug.Parsers.RequestTooLargeError`, ASVS 5.2.1). The headers
  of a part hold at most 16 KiB, and a larger header block answers 413 as
  well. `Espalier.Media` then applies the limit of the detected kind.

  The parser keeps no part in memory (ASVS 15.2.2). A first part that is no
  file part named `file` and every further part stay unread: the params
  name them so that the operation answers 422, and a part `file` without a
  file name becomes the text `"text"`, which the controller answers with
  `fields.file` `["invalid_type"]`. Every answer of the request removes the
  temporary file through a `before_send` callback, also the 422 answers of
  the plugs before the action, because Bandit keeps the request process of a
  keep-alive connection, which owns the file, until the connection closes.
  The answer of an exception goes out without that callback, so the parser
  removes the file itself before it raises. A file that the ingest moved
  into the store is gone already.

  When the volume of `PLUG_TMPDIR` is full, so that the temporary file
  fails to open, to take a write or to close with ENOSPC, or with EDQUOT
  when the disk quota of the user that runs the node is exhausted, the
  parser removes the file and puts the text `"storage_full"` into `file`,
  which the controller answers with 409 `storage_full`. A text part never
  gives that value. Any other error of the file system raises `File.Error`
  and answers 500. Before it answers `"storage_full"`, the parser reads the
  rest of the part and drops it, up to the same limit and with 413 above
  it, so that the 409 reaches a client that still sends: Bandit reads at
  most 8,000,000 bytes of a body that the action left unread and then
  closes the connection, which a browser reports as a network error.

  A body that `Plug.Conn` cannot read as multipart, such as an empty body or
  one that ends before its closing boundary, answers 400
  (`Plug.Parsers.ParseError`), as `Plug.Parsers.MULTIPART` does. That error
  names only the type of the exception that the parser raised, and no stack
  frame of a raised error carries its arguments, so that no log line holds
  the conn with its cookie, its CSRF token and its session (ASVS 16.2.5).

  The endpoint parses no multipart body, so only the router pipeline
  `:media_upload` reads one, behind the checks of `:author_write` and
  `EspalierWeb.PackMultipart.require_multipart/2`.
  """
  @behaviour Plug.Parsers

  alias Espalier.Media
  alias Espalier.Media.Store
  alias Plug.Conn.Utils
  alias Plug.Parsers.{BadEncodingError, ParseError, RequestTooLargeError}

  @part_headers [length: 16_384, read_length: 16_384, read_timeout: 15_000]
  @part_body [length: 1_048_576, read_length: 1_048_576, read_timeout: 15_000]

  @impl Plug.Parsers
  def init(opts), do: opts

  @impl Plug.Parsers
  def parse(conn, "multipart", "form-data", _headers, _opts) do
    case Plug.Conn.read_part_headers(conn, @part_headers) do
      {:ok, headers, conn} -> first_part(conn, headers)
      {:done, conn} -> {:ok, %{}, conn}
      {:error, :too_large, _conn} -> raise RequestTooLargeError
    end
  rescue
    error in [RequestTooLargeError, BadEncodingError, Plug.UploadError, File.Error] ->
      reraise error, without_arguments(__STACKTRACE__)

    error ->
      reraise ParseError.exception(exception: malformed(error)),
              without_arguments(__STACKTRACE__)
  end

  def parse(conn, _type, _subtype, _headers, _opts), do: {:next, conn}

  # The message of the raised exception can hold the conn, as the message of
  # a CaseClauseError does, so the parse error names only its type.
  defp malformed(%type{}),
    do: RuntimeError.exception("malformed multipart body: #{inspect(type)}")

  # The arguments of a stack frame can hold the conn, as the top frame of a
  # FunctionClauseError does; the frame keeps the arity.
  defp without_arguments(stacktrace) do
    Enum.map(stacktrace, fn
      {module, function, arguments, location} when is_list(arguments) ->
        {module, function, length(arguments), location}

      frame ->
        frame
    end)
  end

  defp first_part(conn, headers) do
    case part(headers) do
      {:file, filename} ->
        path = Plug.Upload.random_file!("media")
        conn = Plug.Conn.register_before_send(conn, &remove(&1, path))
        upload = %Plug.Upload{path: path, filename: filename, content_type: content_type(headers)}
        file_part(conn, upload)

      :text ->
        {:ok, %{"file" => "text"}, conn}

      :other ->
        {:ok, %{unexpected(headers) => "unexpected"}, conn}
    end
  end

  # The path comes from Plug.Upload.random_file!/1 below PLUG_TMPDIR.
  # sobelow_skip ["Traversal.FileModule"]
  defp file_part(conn, %Plug.Upload{path: path} = upload) do
    case stream(conn, path) do
      {:ok, conn} ->
        {:ok, Map.merge(%{"file" => upload}, rest(conn)), conn}

      {:storage_full, conn} ->
        _ignored = File.rm(path)
        {:ok, %{"file" => "storage_full"}, conn}
    end
  rescue
    error ->
      _ignored = File.rm(path)
      reraise error, __STACKTRACE__
  end

  # A further part stays unread and makes the request invalid.
  defp rest(conn) do
    case Plug.Conn.read_part_headers(conn, @part_headers) do
      {:done, _conn} -> %{}
      {:ok, headers, _conn} -> %{unexpected(headers) => "unexpected"}
      {:error, :too_large, _conn} -> raise RequestTooLargeError
    end
  end

  # The name of an unexpected part when it is a plain identifier other than
  # `file`, so that the answer names it, and `part` otherwise.
  defp unexpected(headers) do
    with {_key, disposition} <- List.keyfind(headers, "content-disposition", 0),
         [_form_data, params] <- :binary.split(disposition, ";"),
         %{"name" => name} <- Utils.params(params),
         true <- name != "file" and Regex.match?(~r/\A[a-z][a-z0-9_]{0,63}\z/, name) do
      name
    else
      _other -> "part"
    end
  end

  # The path comes from Plug.Upload.random_file!/1 below PLUG_TMPDIR.
  # sobelow_skip ["Traversal.FileModule"]
  defp remove(conn, path) do
    _ignored = File.rm(path)
    conn
  end

  # Writes the part body to the file at `path` and answers `{:ok, conn}`,
  # or `{:storage_full, conn}` after an ENOSPC or EDQUOT, each with the conn
  # after the whole part.
  # sobelow_skip ["Traversal.FileModule"]
  defp stream(conn, path) do
    case file_result(File.open(sink(path), [:write, :binary, :delayed_write, :raw]), "open", path) do
      {:ok, file} ->
        try do
          write(Plug.Conn.read_part_body(conn, @part_body), file, path, Media.max_upload_bytes())
        rescue
          error ->
            _ignored = File.close(file)
            reraise error, __STACKTRACE__
        else
          {:ok, conn} ->
            {file_result(File.close(file), "close", path), conn}

          {:storage_full, _conn} = full ->
            _ignored = File.close(file)
            full
        end

      :storage_full ->
        {:storage_full,
         discard(Plug.Conn.read_part_body(conn, @part_body), Media.max_upload_bytes())}
    end
  end

  # The file that takes the body: the temporary file, unless the tests put
  # /dev/full, which answers every write with ENOSPC, under the key
  # {__MODULE__, :sink} of the request process.
  defp sink(path), do: Process.get({__MODULE__, :sink}, path)

  defp write({_more_or_ok, data, _conn}, _file, _path, room) when byte_size(data) > room,
    do: raise(RequestTooLargeError)

  defp write({:more, data, conn}, file, path, room) do
    room = room - byte_size(data)

    case file_result(:file.write(file, data), "write to", path) do
      :ok -> write(Plug.Conn.read_part_body(conn, @part_body), file, path, room)
      :storage_full -> {:storage_full, discard(Plug.Conn.read_part_body(conn, @part_body), room)}
    end
  end

  defp write({:ok, data, conn}, file, path, _room),
    do: {file_result(:file.write(file, data), "write to", path), conn}

  # After a full volume, the rest of the part is read and dropped up to the
  # same limit (module documentation); the answer is the conn after the
  # part.
  defp discard({_more_or_ok, data, _conn}, room) when byte_size(data) > room,
    do: raise(RequestTooLargeError)

  defp discard({:more, data, conn}, room),
    do: discard(Plug.Conn.read_part_body(conn, @part_body), room - byte_size(data))

  defp discard({:ok, _data, conn}, _room), do: conn

  @doc false
  # The result of a file operation on the temporary file: `:storage_full`
  # for ENOSPC, a full volume, and EDQUOT, an exhausted disk quota
  # (Espalier.Media.Store.full?/1), a raise of File.Error for any other
  # error of the file system, which is a fault of the server, and the result
  # itself otherwise. Public, so that a test can pass EDQUOT, which no test
  # can produce on its file system.
  @spec file_result(term(), String.t(), Path.t()) :: term()
  def file_result({:error, reason}, action, path) do
    if Store.full?(reason),
      do: :storage_full,
      else: raise(File.Error, reason: reason, action: action, path: path)
  end

  def file_result(result, _action, _path), do: result

  defp part(headers) do
    with {_key, disposition} <- List.keyfind(headers, "content-disposition", 0),
         [_form_data, params] <- :binary.split(disposition, ";"),
         %{"name" => "file"} = params <- Utils.params(params) do
      filename(params)
    else
      _other -> :other
    end
  end

  defp filename(%{"filename" => filename}) when filename != "", do: {:file, filename}

  defp filename(%{"filename*" => "utf-8''" <> encoded}) when encoded != "",
    do: {:file, URI.decode(encoded)}

  defp filename(_params), do: :text

  defp content_type(headers) do
    case List.keyfind(headers, "content-type", 0) do
      {_key, type} -> type
      nil -> nil
    end
  end
end
