defmodule EspalierWeb.BlockDownload do
  @moduledoc """
  Sends a file as an attachment in blocks of 64 KiB within a deadline
  (task 0018, step 16; ASVS 15.2.2). The draft download of the pack
  workbench sends its zip with it, because the download keeps its slot of
  `Espalier.Workbench.DownloadLimiter` while the zip is sent.

  `Phoenix.Controller.send_download/3` with `{:file, path}` hands the file
  to Bandit, which sends it with `:file.sendfile/5`. That call ignores the
  send timeout of the socket (`send_timeout` of ThousandIsland, 30 seconds
  by default), so a client that stops reading and keeps its connection
  open keeps the request process waiting, and with it the slot.
  `send_download/3` of this module sends each block with
  `Plug.Conn.chunk/2`, which Bandit writes with one `:gen_tcp.send/2`. When
  the client reads nothing for the send timeout, that call answers
  `{:error, :timeout}`, the socket closes, and the function returns at the
  first error. A send waits for about one block to drain, and a block of
  64 KiB takes 30 seconds only below about 2.1 KiB per second, so the send
  timeout ends a transfer that has all but stopped.

  A client that keeps reading slowly passes the send timeout. The function
  therefore sets a deadline for the whole transfer before it sends the
  headers: the time of the file at `min_rate` bytes per second, and at least
  `floor_ms` (`transfer_ms/3`). It checks the deadline before each block and
  sends no block after it, so a transfer ends at the latest one send timeout
  after its deadline.

  A client that reads the whole response receives the bytes that
  `send_download/3` of Phoenix sends to a client that asks the server to
  close the connection after the response: the same `content-type` and the
  same `content-disposition`, whose file name is percent-encoded as Phoenix
  encodes it (ASVS 5.4.2), and `connection: close` and `content-length`
  with the size of the file ahead of the headers of the conn, where Bandit
  puts them for a file. With `content-length`, Bandit sends the blocks as
  they are, without the chunked transfer coding and without compression.
  With `connection: close`, Bandit closes the connection after the
  response, also when the deadline ends it early; HTTP/2 has no such header
  (RFC 9113, section 8.2.2), so a response over HTTP/2 goes without it.
  """
  import Plug.Conn

  @block_bytes 65_536

  @doc "The size of a block in bytes (64 KiB)."
  @spec block_bytes() :: pos_integer()
  def block_bytes, do: @block_bytes

  @doc """
  The time in milliseconds that the transfer of `size` bytes may take: the
  time at `min_rate` bytes per second, rounded up to the next millisecond,
  and at least `floor_ms`.
  """
  @spec transfer_ms(non_neg_integer(), pos_integer(), non_neg_integer()) :: non_neg_integer()
  def transfer_ms(size, min_rate, floor_ms)
      when is_integer(size) and size >= 0 and is_integer(min_rate) and min_rate > 0 and
             is_integer(floor_ms) and floor_ms >= 0,
      do: max(floor_ms, div(size * 1_000 + min_rate - 1, min_rate))

  @doc """
  Sends the file at `path` as an attachment and returns the conn. Options:
  `filename`, the name of the attachment, `content_type`, and `min_rate`
  and `floor_ms` for the deadline of `transfer_ms/3`. The function stops at
  the first block that `Plug.Conn.chunk/2` cannot deliver and at the first
  block after the deadline, and returns the conn as well; the client then
  holds a truncated response, shorter than its `content-length`.
  """
  @spec send_download(Plug.Conn.t(), Path.t(), keyword()) :: Plug.Conn.t()
  # The callers pass a path that they built themselves, such as the zip in
  # the staging directory of Espalier.Media.Store.staging_dir/0, and a fixed
  # content type.
  # sobelow_skip ["Traversal.FileModule", "XSS.ContentType"]
  def send_download(%Plug.Conn{} = conn, path, opts) when is_binary(path) do
    filename = Keyword.fetch!(opts, :filename)
    content_type = Keyword.fetch!(opts, :content_type)
    %File.Stat{type: :regular, size: size} = File.stat!(path)

    deadline =
      System.monotonic_time(:millisecond) +
        transfer_ms(size, Keyword.fetch!(opts, :min_rate), Keyword.fetch!(opts, :floor_ms))

    conn
    |> put_resp_content_type(content_type, nil)
    |> put_resp_header("content-disposition", disposition(filename))
    |> prepend_resp_headers(close(conn) ++ [{"content-length", Integer.to_string(size)}])
    |> send_chunked(conn.status || 200)
    |> send_blocks(path, deadline)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp send_blocks(conn, path, deadline) do
    path
    |> File.stream!(@block_bytes)
    |> Enum.reduce_while(conn, fn block, conn ->
      with true <- System.monotonic_time(:millisecond) <= deadline,
           {:ok, conn} <- chunk(conn, block) do
        {:cont, conn}
      else
        _stop -> {:halt, conn}
      end
    end)
  end

  defp close(conn) do
    if get_http_protocol(conn) == :"HTTP/2", do: [], else: [{"connection", "close"}]
  end

  # The value of `content-disposition` that Phoenix.Controller.send_download/3
  # sets for an attachment: every character outside the unreserved
  # characters of RFC 3986 is percent-encoded, and `filename*` with the same
  # encoding follows when the encoding changed the name.
  defp disposition(filename) do
    encoded = URI.encode(filename, &URI.char_unreserved?/1)
    disposition = ~s[attachment; filename="#{encoded}"]

    if encoded == filename,
      do: disposition,
      else: disposition <> "; filename*=utf-8''#{encoded}"
  end
end
