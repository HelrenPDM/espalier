defmodule Espalier.Media.Clamd do
  @moduledoc """
  The malware scan of uploaded and imported media files through clamd
  (task 0018, step 7; ASVS 5.4.3).

  The scan runs only while `MEDIA_CLAMAV_SOCKET` is set (`enabled?/0`), and
  it reads the incoming file before ffprobe, ffmpeg, xmerl or the WebVTT
  check touch it. The client connects only to that Unix socket (ASVS
  1.3.6) and speaks the `INSTREAM` command of `clamd(8)`: `zINSTREAM\\0`,
  the file in chunks of 1 MiB, each preceded by its length as a 32-bit
  big-endian integer, and four zero bytes at the end. It reads the reply up
  to a NUL byte, at most 1 KiB, within `scan_timeout_ms/1`.

  ## Replies

  | Reply | Result |
  |---|---|
  | `stream: OK` | `:clean` |
  | `stream: Heuristics.Limits.Exceeded.<limit> FOUND` | `{:error, {:limits_exceeded, limit}}` |
  | `stream: <signature> FOUND` | `{:found, signature}` |
  | `INSTREAM size limit exceeded. ERROR` | `{:error, :size_limit}` |
  | any other reply, or more than 1 KiB without a NUL byte | `{:error, :reply}` |
  | no reply within the timeout | `{:error, :timeout}` |
  | the socket closes before the reply ends | `{:error, :closed}` |
  | the connect fails or exits | `{:error, :connect}` |

  With `AlertExceedsMax yes` in `clamd.conf`, clamd answers every exceeded
  scan limit with a `Heuristics.Limits.Exceeded` finding, so a file that
  clamd did not scan completely fails with `scan_failed` and never passes.
  clamd closes the connection when a stream exceeds `StreamMaxLength`; when
  a chunk cannot be sent, the client still reads the reply that clamd sent
  before it closed. A file that cannot be read answers its POSIX error,
  such as `{:error, :enoent}`.

  `reason_tag/1` maps an error to the reason tag of `failure_detail`, and
  `signature_reason/1` builds the `reason` of the security event
  `upload_validation` from a signature name.
  """

  alias Espalier.Media

  @chunk_bytes 1_048_576
  @reply_max_bytes 1024
  @connect_timeout 5_000
  @base_timeout 60_000
  @bytes_per_second 4 * 1_048_576
  @reason_max 100

  # A signature name is printable ASCII; any other reply answers :reply.
  @limits_reply ~r/\Astream: Heuristics\.Limits\.Exceeded\.([A-Za-z0-9_.-]+) FOUND\z/
  @found_reply ~r/\Astream: ([\x21-\x7E][\x20-\x7E]*) FOUND\z/

  @typedoc "The errors of a scan."
  @type error :: {:limits_exceeded, String.t()} | atom()

  @typedoc "The reason tags of a failed scan."
  @type reason_tag :: :limits_exceeded | :size_limit | :timeout | :closed | :connect | :reply

  @doc "Whether the scan runs: true while `MEDIA_CLAMAV_SOCKET` is set."
  @spec enabled?() :: boolean()
  def enabled?, do: Media.clamav_socket() != nil

  @doc """
  The timeout in milliseconds of the scan of a file of `bytes`: 60 seconds
  plus one second per started 4 MiB, so that the scan limit `MaxScanTime` of
  clamd (220 seconds in the example for a file of 1,024 MiB) answers first.
  """
  @spec scan_timeout_ms(non_neg_integer()) :: pos_integer()
  def scan_timeout_ms(bytes) when is_integer(bytes) and bytes >= 0 do
    @base_timeout + div(bytes + @bytes_per_second - 1, @bytes_per_second) * 1000
  end

  @doc """
  Scans the file at `path` through clamd.

  ## Options

    * `:socket` - the path of the clamd socket, by default
      `Espalier.Media.clamav_socket/0`. Without a socket the scan answers
      `{:error, :connect}`.
    * `:timeout` - the timeout in milliseconds of the whole scan, by
      default `scan_timeout_ms/1` of the file size.
  """
  @spec scan(Path.t(), keyword()) :: :clean | {:found, String.t()} | {:error, error()}
  # The caller passes the incoming file of an asset, whose path
  # Espalier.Media.Store builds from a UUID below MEDIA_DIR; no request value
  # reaches it.
  # sobelow_skip ["Traversal.FileModule"]
  def scan(path, opts \\ []) do
    socket_path = Keyword.get_lazy(opts, :socket, &Media.clamav_socket/0)

    with {:ok, %File.Stat{size: size}} <- File.stat(path),
         {:ok, file} <- File.open(path, [:read, :binary, :raw]) do
      deadline = now() + Keyword.get_lazy(opts, :timeout, fn -> scan_timeout_ms(size) end)

      try do
        connect_and_scan(socket_path, file, deadline)
      after
        File.close(file)
      end
    end
  end

  @doc """
  The reason tag of `failure_detail` for an error of `scan/2`. An error
  that names none of the tags, such as a POSIX error of the file read,
  maps to `reply`.
  """
  @spec reason_tag(error()) :: reason_tag()
  def reason_tag({:limits_exceeded, _limit}), do: :limits_exceeded
  def reason_tag(reason) when reason in [:size_limit, :timeout, :closed, :connect], do: reason
  def reason_tag(_reason), do: :reply

  @doc """
  The `reason` of the security event `upload_validation` for a finding:
  `malware_found:` followed by the signature name, in which every
  character outside `[A-Za-z0-9._-]` becomes `_`, the whole cut to 100
  characters.

      iex> Espalier.Media.Clamd.signature_reason("Win.Test.EICAR_HDB-1")
      "malware_found:Win.Test.EICAR_HDB-1"
  """
  @spec signature_reason(String.t()) :: String.t()
  def signature_reason(signature) when is_binary(signature) do
    name =
      signature
      |> String.replace_invalid("_")
      |> String.replace(~r/[^A-Za-z0-9._-]/u, "_")

    String.slice("malware_found:" <> name, 0, @reason_max)
  end

  ## Connection

  defp connect_and_scan(nil, _file, _deadline), do: {:error, :connect}

  defp connect_and_scan(socket_path, file, deadline) do
    case connect(socket_path) do
      {:ok, socket} ->
        try do
          stream(socket, file, deadline)
        after
          :gen_tcp.close(socket)
          flush(socket)
        end

      {:error, _reason} ->
        {:error, :connect}
    end
  end

  # gen_tcp.connect/4 exits for an address that it cannot use, such as a
  # path beyond the length of a Unix socket address.
  defp connect(socket_path) do
    :gen_tcp.connect(
      {:local, socket_path},
      0,
      [:binary, active: false, packet: :raw],
      @connect_timeout
    )
  catch
    :exit, _reason -> {:error, :connect}
  end

  defp stream(socket, file, deadline) do
    with :ok <- set_options(socket, deadline),
         :ok <- :gen_tcp.send(socket, "zINSTREAM\0"),
         :ok <- send_chunks(socket, file) do
      read_reply(socket, deadline)
    else
      {:error, :timeout} -> {:error, :timeout}
      {:error, {:file, reason}} -> {:error, reason}
      {:error, _reason} -> reply_after_send_error(socket)
    end
  end

  # The socket delivers the reply as a message (active once), so a reply
  # that clamd sends while a chunk is still being sent survives the failed
  # send. A send blocks while clamd does not read; the send timeout bounds
  # it by the deadline of the scan.
  defp set_options(socket, deadline) do
    :inet.setopts(socket,
      active: :once,
      send_timeout: max(deadline - now(), 0),
      send_timeout_close: true
    )
  end

  defp send_chunks(socket, file) do
    case :file.read(file, @chunk_bytes) do
      {:ok, chunk} ->
        with :ok <- :gen_tcp.send(socket, [<<byte_size(chunk)::32>>, chunk]) do
          send_chunks(socket, file)
        end

      :eof ->
        :gen_tcp.send(socket, <<0::32>>)

      {:error, reason} ->
        {:error, {:file, reason}}
    end
  end

  # clamd closes the connection after its reply to a stream above
  # StreamMaxLength, which can make a send fail; the reply may still be
  # readable.
  defp reply_after_send_error(socket) do
    case read_reply(socket, now() + 1_000) do
      {:error, :timeout} -> {:error, :closed}
      result -> result
    end
  end

  defp read_reply(socket, deadline), do: read_reply(socket, deadline, <<>>)

  defp read_reply(socket, deadline, acc) do
    case :binary.split(acc, <<0>>) do
      [reply, _rest] when byte_size(reply) <= @reply_max_bytes ->
        parse_reply(reply)

      [_reply, _rest] ->
        {:error, :reply}

      [_incomplete] when byte_size(acc) > @reply_max_bytes ->
        {:error, :reply}

      [_incomplete] ->
        receive do
          {:tcp, ^socket, data} ->
            _ = :inet.setopts(socket, active: :once)
            read_reply(socket, deadline, acc <> data)

          {:tcp_closed, ^socket} ->
            {:error, :closed}

          {:tcp_error, ^socket, _reason} ->
            {:error, :closed}
        after
          max(deadline - now(), 0) -> {:error, :timeout}
        end
    end
  end

  # Drops the messages of the closed socket from the mailbox of the caller.
  defp flush(socket) do
    receive do
      {:tcp, ^socket, _data} -> flush(socket)
      {:tcp_closed, ^socket} -> flush(socket)
      {:tcp_error, ^socket, _reason} -> flush(socket)
    after
      0 -> :ok
    end
  end

  defp parse_reply("stream: OK"), do: :clean
  defp parse_reply("INSTREAM size limit exceeded. ERROR"), do: {:error, :size_limit}

  defp parse_reply(reply) do
    with nil <- limits_exceeded(reply),
         nil <- found(reply),
         do: {:error, :reply}
  end

  defp limits_exceeded(reply) do
    case Regex.run(@limits_reply, reply, capture: :all_but_first) do
      [limit] -> {:error, {:limits_exceeded, limit}}
      nil -> nil
    end
  end

  # A heuristic limit without a limit name is a malformed reply, no finding.
  defp found(reply) do
    case Regex.run(@found_reply, reply, capture: :all_but_first) do
      ["Heuristics.Limits.Exceeded" <> _rest] -> nil
      [signature] -> {:found, signature}
      nil -> nil
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
