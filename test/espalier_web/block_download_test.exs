defmodule EspalierWeb.BlockDownloadTest do
  @moduledoc """
  Tests `EspalierWeb.BlockDownload.send_download/3` over a real socket
  (task 0018, step 16; ASVS 15.2.2). Each test starts its own Bandit on an
  ephemeral port with `Espalier.Test.FunctionPlug`, and a `:gen_tcp` client
  reads the raw response.

  A client that reads the whole response receives the bytes of
  `Phoenix.Controller.send_download/3` with `{:file, path}` for a client
  that asks to close the connection, the `date` header aside, for GET and
  HEAD and for a file name that needs percent-encoding (ASVS 5.4.2). A
  client that stops reading ends the send within the send timeout of the
  socket and receives less than its `content-length`. A client that reads
  below the minimum rate loses the connection at the deadline, and one
  that reads a little above it receives the whole file.

  The tests run apart from the asynchronous tests, because the paced
  clients and the deadline measure time on a loaded machine.
  """
  use ExUnit.Case, async: false

  alias Espalier.Test.FunctionPlug
  alias EspalierWeb.BlockDownload
  alias EspalierWeb.Plugs.SecurityHeaders

  @moduletag :tmp_dir

  # The send timeout of the stall test, in place of the 30 seconds of
  # ThousandIsland, and the margin for the zip to start and the socket to
  # close.
  @send_timeout 1_000
  @margin 5_000

  # A file larger than the socket buffers of both ends together: 4 MiB for
  # the send buffer of the server at most (tcp_wmem), the receive buffer of
  # 4096 bytes that the client sets, and the block in the queue of the
  # port.
  @stall_bytes 32 * 1_048_576

  # The deadline tests: the server has a send buffer of 4096 bytes and the
  # client a receive buffer of 4096 bytes, so the server sends at the pace
  # of the client, about one block ahead. A file of 3 MiB at a minimum rate
  # of 1 MiB per second gives a deadline of 3 seconds.
  @min_rate 1_048_576
  @paced_bytes 3 * 1_048_576
  @deadline_ms 3_000

  # Options without a deadline that a test could reach.
  @no_deadline [min_rate: 1, floor_ms: 0]

  test "a client that reads the response receives the bytes of Phoenix.Controller.send_download/3",
       %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "draft.zip")
    content = :crypto.strong_rand_bytes(2 * BlockDownload.block_bytes() + 3)
    File.write!(path, content)

    for name <- ["new-pack-draft.zip", ~s(a "b" ü.zip)] do
      opts = [filename: name, content_type: "application/zip"]

      phoenix =
        serve(fn conn ->
          conn
          |> SecurityHeaders.call([])
          |> Phoenix.Controller.send_download({:file, path}, opts)
        end)

      blocks =
        serve(fn conn ->
          conn
          |> SecurityHeaders.call([])
          |> BlockDownload.send_download(path, opts ++ @no_deadline)
        end)

      for {method, expected} <- [{"GET", content}, {"HEAD", ""}] do
        {head, body} = request(blocks, method)
        {phoenix_head, phoenix_body} = request(phoenix, method)
        assert head == phoenix_head
        assert body == expected, "the body of #{method} for #{name} differs"
        assert phoenix_body == expected, "the body of Phoenix differs"
        assert "content-length: #{byte_size(content)}" in head
        assert "connection: close" in head
        refute Enum.any?(head, &String.starts_with?(&1, "transfer-encoding"))
      end
    end

    # The name that needs encoding gets it in both parameters.
    opts = [filename: ~s(a "b" ü.zip), content_type: "application/zip"] ++ @no_deadline
    {head, _body} = request(serve(&BlockDownload.send_download(&1, path, opts)), "HEAD")

    disposition =
      ~s(content-disposition: attachment; filename="a%20%22b%22%20%C3%BC.zip"; ) <>
        "filename*=utf-8''a%20%22b%22%20%C3%BC.zip"

    assert disposition in head
  end

  test "a response closes the connection also for a client that keeps it open",
       %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "draft.zip")
    content = :crypto.strong_rand_bytes(BlockDownload.block_bytes() + 1)
    File.write!(path, content)
    opts = [filename: "draft.zip", content_type: "application/zip"] ++ @no_deadline
    port = serve(&BlockDownload.send_download(&1, path, opts))

    socket = connect(port)
    :ok = :gen_tcp.send(socket, "GET /draft.zip HTTP/1.1\r\nhost: localhost\r\n\r\n")
    [head, body] = socket |> read_all([]) |> String.split("\r\n\r\n", parts: 2)
    assert "connection: close" in String.split(head, "\r\n")
    assert body == content
  end

  test "transfer_ms/3 gives the time at the minimum rate, rounded up, and at least the floor" do
    assert BlockDownload.transfer_ms(0, 262_144, 60_000) == 60_000
    assert BlockDownload.transfer_ms(262_144 * 60, 262_144, 60_000) == 60_000
    assert BlockDownload.transfer_ms(262_144 * 60 + 1, 262_144, 60_000) == 60_001
    # 1,024 MB at 256 KiB per second: 4,096 seconds, about 68 minutes.
    assert BlockDownload.transfer_ms(1_024 * 1_048_576, 262_144, 60_000) == 4_096_000
  end

  test "a client that stops reading ends the send within the send timeout", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "large.zip")
    File.write!(path, :binary.copy(<<0>>, @stall_bytes))
    test = self()

    port =
      serve(
        fn conn ->
          conn =
            BlockDownload.send_download(
              conn,
              path,
              [filename: "large.zip", content_type: "application/zip"] ++ @no_deadline
            )

          send(test, {:returned, conn.state})
          conn
        end,
        send_timeout: @send_timeout
      )

    socket = connect(port, recbuf: 4_096)
    :ok = :gen_tcp.send(socket, "GET /large.zip HTTP/1.1\r\nhost: localhost\r\n\r\n")
    assert {:ok, "HTTP/1.1 200 OK\r\n" <> _rest} = :gen_tcp.recv(socket, 0, @margin)

    # The client reads nothing more, so the send of a block waits for the
    # send timeout, and the function returns.
    assert_receive {:returned, :chunked}, @send_timeout + @margin

    # The socket is closed: the client reads what the buffers held and
    # then the end of the connection, short of the content-length.
    assert {received, reason} = read_until_closed(socket, 0)
    assert reason in [:closed, :econnreset]
    assert received < @stall_bytes
  end

  test "a client that reads slowly and steadily keeps the connection under the send timeout",
       %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "steady.zip")
    content = :crypto.strong_rand_bytes(768 * 1_024)
    File.write!(path, content)
    test = self()

    port =
      serve(
        fn conn ->
          conn =
            BlockDownload.send_download(
              conn,
              path,
              [filename: "steady.zip", content_type: "application/zip"] ++ @no_deadline
            )

          send(test, {:returned, conn.state, System.monotonic_time(:millisecond)})
          conn
        end,
        send_timeout: @send_timeout,
        sndbuf: 4_096
      )

    # At 256 KiB per second, a block of 64 KiB drains in a quarter of the
    # send timeout of one second, while the whole file takes three seconds.
    # The client keeps its rate after the plug returns, while Bandit ends
    # the response.
    {response, _started} = paced_request(port, 262_144, :always)

    [_head, body] = String.split(response, "\r\n\r\n", parts: 2)
    assert body == content
  end

  test "a client below the minimum rate loses the connection at the deadline",
       %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "slow.zip")
    File.write!(path, :crypto.strong_rand_bytes(@paced_bytes))
    port = serve_paced(path)

    # A quarter of the minimum rate: the send timeout of 30 seconds never
    # fires, because a block drains in a quarter of a second.
    {received, started} = paced_request(port, div(@min_rate, 4))

    assert_received {:returned, :chunked, at}
    # The deadline of the server starts after the request arrived, and the
    # send stops at the first block after it. The margin of 3 seconds covers
    # a client that a loaded machine wakes late; the whole file would take
    # 12 seconds at this rate.
    assert at - started >= @deadline_ms
    assert at - started < @deadline_ms + 3_000
    assert byte_size(received) < @paced_bytes
  end

  test "a client a little above the minimum rate receives the whole file", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "steady.zip")
    content = :crypto.strong_rand_bytes(@paced_bytes)
    File.write!(path, content)
    port = serve_paced(path)

    # 1.5 times the minimum rate: 2 of the 3 seconds.
    {response, _started} = paced_request(port, div(@min_rate * 3, 2))

    assert_received {:returned, :chunked, _at}
    [head, body] = String.split(response, "\r\n\r\n", parts: 2)
    assert "content-length: #{@paced_bytes}" in String.split(head, "\r\n")
    assert body == content
  end

  ## Helpers

  # Starts Bandit on an ephemeral port with `fun` as the plug and returns
  # the port. `transport_options` replace the defaults of ThousandIsland.
  defp serve(fun, transport_options \\ []) do
    options = [
      plug: {FunctionPlug, fun},
      ip: :loopback,
      port: 0,
      startup_log: false,
      thousand_island_options: [transport_options: transport_options]
    ]

    pid = start_supervised!({Bandit, options}, id: make_ref())
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    port
  end

  # Serves the file at `path` with the deadline of @min_rate and a send
  # buffer of 4096 bytes; the plug tells the test when it returned.
  defp serve_paced(path) do
    test = self()

    serve(
      fn conn ->
        conn =
          BlockDownload.send_download(conn, path,
            filename: Path.basename(path),
            content_type: "application/zip",
            min_rate: @min_rate,
            floor_ms: 0
          )

        send(test, {:returned, conn.state, System.monotonic_time(:millisecond)})
        conn
      end,
      sndbuf: 4_096
    )
  end

  # Sends a GET with a receive buffer of 4096 bytes and reads at `rate`
  # bytes per second until the connection closes. With `pace`
  # `:until_return`, the default, the client reads at full speed once the
  # plug has returned; with `:always`, it keeps its rate. Returns the
  # response and the time of the request.
  defp paced_request(port, rate, pace \\ :until_return) do
    socket = connect(port, recbuf: 4_096)
    started = System.monotonic_time(:millisecond)
    :ok = :gen_tcp.send(socket, "GET /file.zip HTTP/1.1\r\nhost: localhost\r\n\r\n")
    {read_paced(socket, {rate, pace}, started, 0, []), started}
  end

  defp read_paced(socket, {rate, pace} = pacing, started, received, acc) do
    case :gen_tcp.recv(socket, 0, @margin) do
      {:ok, data} ->
        received = received + byte_size(data)

        if pace == :always or not returned?(),
          do: wait_until(started + div(received * 1_000, rate))

        read_paced(socket, pacing, started, received, [acc | data])

      {:error, reason} when reason in [:closed, :econnreset] ->
        IO.iodata_to_binary(acc)

      {:error, reason} ->
        flunk("the connection stayed open: #{inspect(reason)}")
    end
  end

  # Sleeps until the monotonic time `at`, when the bytes read so far are due
  # at the rate of the client.
  defp wait_until(at) do
    wait = at - System.monotonic_time(:millisecond)
    if wait > 0, do: Process.sleep(wait)
  end

  # Whether the plug has returned, without taking its message.
  defp returned? do
    {:messages, messages} = Process.info(self(), :messages)
    Enum.any?(messages, &match?({:returned, _state, _at}, &1))
  end

  defp connect(port, options \\ []) do
    {:ok, socket} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false] ++ options, @margin)

    on_exit(fn -> :gen_tcp.close(socket) end)
    socket
  end

  # The header lines without `date` and the body of a request that asks the
  # server to close the connection after the response.
  defp request(port, method) do
    socket = connect(port)
    request = "#{method} /draft.zip HTTP/1.1\r\nhost: localhost\r\nconnection: close\r\n\r\n"
    :ok = :gen_tcp.send(socket, request)
    response = read_all(socket, [])
    [head, body] = String.split(response, "\r\n\r\n", parts: 2)
    {head |> String.split("\r\n") |> Enum.reject(&String.starts_with?(&1, "date: ")), body}
  end

  defp read_all(socket, acc) do
    case :gen_tcp.recv(socket, 0, @margin) do
      {:ok, data} -> read_all(socket, [acc | data])
      {:error, :closed} -> IO.iodata_to_binary(acc)
      {:error, reason} -> flunk("the response did not end: #{inspect(reason)}")
    end
  end

  defp read_until_closed(socket, received) do
    case :gen_tcp.recv(socket, 0, @margin) do
      {:ok, data} -> read_until_closed(socket, received + byte_size(data))
      {:error, reason} when reason in [:closed, :econnreset] -> {received, reason}
      {:error, reason} -> flunk("the connection stayed open: #{inspect(reason)}")
    end
  end
end
