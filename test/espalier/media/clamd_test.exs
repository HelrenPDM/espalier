defmodule Espalier.Media.ClamdTest do
  @moduledoc """
  The clamd client of task 0018, step 7: against a fake server on a Unix
  socket for every reply and failure, and, tagged `:clamav`, against
  `clamd` of the shell with the test signatures (`make test-integration`).

  Each socket lies in a directory `espalier-clamd-<8 hex digits>` below
  `System.tmp_dir!/0`, which keeps its path within the 107 bytes of a Unix
  socket address. The module runs synchronously because one test sets
  `MEDIA_CLAMAV_SOCKET` in the application environment.
  """
  use ExUnit.Case, async: false

  alias Espalier.Media.{Asset, Clamd}

  @mib 1_048_576

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "espalier-clamd-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp write_file!(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  ## Fake clamd

  # Starts a server that accepts one connection on a socket in `dir` and
  # answers it as `behaviour` says; it reports the command and the chunks
  # it read to the test process.
  defp fake_clamd(dir, behaviour) do
    socket = Path.join(dir, "clamd.sock")
    test = self()

    start_supervised!(
      Supervisor.child_spec({Task, fn -> serve(socket, test, behaviour) end}, id: make_ref())
    )

    assert_receive :listening
    socket
  end

  defp serve(socket, test, behaviour) do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, ifaddr: {:local, socket}, active: false, packet: :raw])

    send(test, :listening)
    {:ok, connection} = :gen_tcp.accept(listen, 5_000)
    {:ok, command} = :gen_tcp.recv(connection, 10, 5_000)
    send(test, {:command, command})
    respond(connection, test, behaviour)
  end

  defp respond(connection, test, {:reply, reply}) do
    send(test, {:chunks, read_chunks(connection, [])})
    :ok = :gen_tcp.send(connection, reply)
    :gen_tcp.close(connection)
  end

  defp respond(connection, test, :silent) do
    send(test, {:chunks, read_chunks(connection, [])})

    receive do
      :never -> :ok
    end
  end

  defp respond(connection, _test, :close), do: :gen_tcp.close(connection)

  # Answers after the first chunk header and closes, as clamd does for a
  # stream above StreamMaxLength.
  defp respond(connection, _test, {:early, reply}) do
    {:ok, <<_length::32>>} = :gen_tcp.recv(connection, 4, 5_000)
    :ok = :gen_tcp.send(connection, reply)
    :gen_tcp.close(connection)
  end

  defp read_chunks(connection, chunks) do
    {:ok, <<length::32>>} = :gen_tcp.recv(connection, 4, 5_000)

    if length == 0 do
      Enum.reverse(chunks)
    else
      {:ok, chunk} = :gen_tcp.recv(connection, length, 5_000)
      read_chunks(connection, [chunk | chunks])
    end
  end

  describe "scan/2 against a fake clamd" do
    test "sends zINSTREAM, chunks of 1 MiB with big-endian lengths and a zero end, and reads OK",
         %{
           dir: dir
         } do
      content = :crypto.strong_rand_bytes(2 * @mib + 1234)
      path = write_file!(dir, "upload", content)
      socket = fake_clamd(dir, {:reply, "stream: OK\0"})

      assert Clamd.scan(path, socket: socket) == :clean
      assert_receive {:command, "zINSTREAM\0"}
      assert_receive {:chunks, chunks}
      assert Enum.map(chunks, &byte_size/1) == [@mib, @mib, 1234]
      assert IO.iodata_to_binary(chunks) == content
    end

    test "an empty file sends only the zero end", %{dir: dir} do
      path = write_file!(dir, "empty", "")
      socket = fake_clamd(dir, {:reply, "stream: OK\0"})

      assert Clamd.scan(path, socket: socket) == :clean
      assert_receive {:chunks, []}
    end

    test "a FOUND reply answers the signature", %{dir: dir} do
      path = write_file!(dir, "upload", "content")
      socket = fake_clamd(dir, {:reply, "stream: Win.Test.EICAR_HDB-1 FOUND\0"})

      assert Clamd.scan(path, socket: socket) == {:found, "Win.Test.EICAR_HDB-1"}
    end

    test "a Heuristics.Limits.Exceeded reply answers limits_exceeded", %{dir: dir} do
      path = write_file!(dir, "upload", "content")
      socket = fake_clamd(dir, {:reply, "stream: Heuristics.Limits.Exceeded.MaxFileSize FOUND\0"})

      assert Clamd.scan(path, socket: socket) == {:error, {:limits_exceeded, "MaxFileSize"}}
    end

    # When clamd answers and closes while the client still sends, the reply
    # races with the close (step 1 of task 0018 saw the same with clamd 1.5.4):
    # the client reads size_limit or sees closed, and both fail the scan.
    test "the size limit reply answers size_limit, and closed when clamd closes during the stream",
         %{dir: dir} do
      path = write_file!(dir, "upload", "content")
      socket = fake_clamd(dir, {:reply, "INSTREAM size limit exceeded. ERROR\0"})
      assert Clamd.scan(path, socket: socket) == {:error, :size_limit}

      large = write_file!(dir, "large", :binary.copy(<<0>>, 8 * @mib))
      File.rm!(socket)
      socket = fake_clamd(dir, {:early, "INSTREAM size limit exceeded. ERROR\0"})
      assert Clamd.scan(large, socket: socket) in [{:error, :size_limit}, {:error, :closed}]
    end

    test "no reply within the timeout answers timeout", %{dir: dir} do
      path = write_file!(dir, "upload", "content")
      socket = fake_clamd(dir, :silent)

      assert Clamd.scan(path, socket: socket, timeout: 200) == {:error, :timeout}
    end

    test "a socket that closes before the reply answers closed", %{dir: dir} do
      path = write_file!(dir, "upload", :binary.copy(<<1>>, 3 * @mib))
      socket = fake_clamd(dir, :close)

      assert Clamd.scan(path, socket: socket) == {:error, :closed}
    end

    test "an unexpected or oversized reply answers reply", %{dir: dir} do
      path = write_file!(dir, "upload", "content")

      for reply <- [
            "UNKNOWN COMMAND\0",
            "stream: FOUND\0",
            "stream: Bad\nName FOUND\0",
            "stream: Heuristics.Limits.Exceeded. FOUND\0",
            "stream: OK" <> String.duplicate(" ", 1100) <> "\0",
            String.duplicate("x", 1100)
          ] do
        File.rm_rf!(Path.join(dir, "clamd.sock"))
        socket = fake_clamd(dir, {:reply, reply})

        assert Clamd.scan(path, socket: socket, timeout: 2_000) == {:error, :reply},
               inspect(reply)
      end
    end

    test "a failed connect answers connect, also when gen_tcp.connect/4 exits", %{dir: dir} do
      path = write_file!(dir, "upload", "content")

      assert Clamd.scan(path, socket: Path.join(dir, "missing.sock")) == {:error, :connect}

      assert Clamd.scan(path, socket: Path.join(dir, String.duplicate("s", 200))) ==
               {:error, :connect}

      assert Clamd.scan(path, socket: nil) == {:error, :connect}
    end

    test "a file that cannot be read answers its POSIX error", %{dir: dir} do
      assert Clamd.scan(Path.join(dir, "missing"), socket: Path.join(dir, "clamd.sock")) ==
               {:error, :enoent}
    end

    test "scan/1 connects to MEDIA_CLAMAV_SOCKET", %{dir: dir} do
      path = write_file!(dir, "upload", "content")
      socket = fake_clamd(dir, {:reply, "stream: OK\0"})
      previous = Application.get_env(:espalier, :media)
      on_exit(fn -> Application.put_env(:espalier, :media, previous) end)

      refute Clamd.enabled?()
      Application.put_env(:espalier, :media, Keyword.put(previous, :clamav_socket, socket))
      assert Clamd.enabled?()
      assert Clamd.scan(path) == :clean
    end
  end

  describe "helpers" do
    test "reason_tag/1 maps every error to a reason tag of failure_detail" do
      assert Clamd.reason_tag({:limits_exceeded, "MaxScanSize"}) == :limits_exceeded

      for tag <- [:size_limit, :timeout, :closed, :connect, :reply] do
        assert Clamd.reason_tag(tag) == tag
      end

      assert Clamd.reason_tag(:enoent) == :reply

      assert Enum.all?(
               [:limits_exceeded, :size_limit, :timeout, :closed, :connect, :reply],
               &(&1 in Asset.failure_details())
             )
    end

    test "scan_timeout_ms/1 is 60 seconds plus one second per started 4 MiB" do
      assert Clamd.scan_timeout_ms(0) == 60_000
      assert Clamd.scan_timeout_ms(1) == 61_000
      assert Clamd.scan_timeout_ms(4 * @mib) == 61_000
      assert Clamd.scan_timeout_ms(4 * @mib + 1) == 62_000
      assert Clamd.scan_timeout_ms(1024 * @mib) == 60_000 + 256_000
    end

    test "signature_reason/1 replaces characters outside the set and cuts to 100 characters" do
      assert Clamd.signature_reason("Win.Test.EICAR_HDB-1") ==
               "malware_found:Win.Test.EICAR_HDB-1"

      assert Clamd.signature_reason("Bad name/ü:\n\"<x>") == "malware_found:Bad_name______x_"

      long = Clamd.signature_reason(String.duplicate("a", 200))
      assert String.length(long) == 100
      assert long == "malware_found:" <> String.duplicate("a", 86)

      assert Clamd.signature_reason(<<"x", 0xFF, "y">>) == "malware_found:x_y"
    end
  end

  describe "scan/2 against clamd of the shell" do
    @describetag :clamav

    # The EICAR test file, split so that no scanner flags this source.
    @eicar "X5O!P%@AP[4\\PZX54(P^)7CC)7}$" <> "EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
    @marker "ESPALIER-CLAMAV-TEST-MARKER"

    setup %{dir: dir} do
      database = Path.join(dir, "db")
      File.mkdir_p!(database)

      File.write!(
        Path.join(database, "espalier-test.ndb"),
        "Espalier.Test.Marker:0:*:#{Base.encode16(@marker, case: :lower)}\n"
      )

      md5 = Base.encode16(:crypto.hash(:md5, @eicar), case: :lower)

      File.write!(
        Path.join(database, "espalier-eicar.hdb"),
        "#{md5}:#{byte_size(@eicar)}:Espalier.Test.Eicar\n"
      )

      socket = Path.join(dir, "clamd.sock")
      config = Path.join(dir, "clamd.conf")

      File.write!(config, """
      LocalSocket #{socket}
      LocalSocketMode 600
      DatabaseDirectory #{database}
      TemporaryDirectory #{dir}
      Foreground yes
      AlertExceedsMax yes
      StreamMaxLength 4M
      MaxFileSize 2M
      MaxScanSize 4M
      MaxScanTime 60000
      """)

      port =
        Port.open({:spawn_executable, System.find_executable("clamd")}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:line, 4096},
          args: ["--foreground", "--config-file=#{config}"]
        ])

      {:os_pid, os_pid} = Port.info(port, :os_pid)
      on_exit(fn -> System.cmd("kill", ["-TERM", Integer.to_string(os_pid)]) end)
      await_ready(port)
      %{socket: socket}
    end

    # clamd prints "Self checking every <n> seconds." once it listens.
    defp await_ready(port) do
      receive do
        {^port, {:data, {:eol, "Self checking every" <> _rest}}} -> :ok
        {^port, {:data, _line}} -> await_ready(port)
        {^port, {:exit_status, status}} -> flunk("clamd exited with status #{status}")
      after
        60_000 -> flunk("clamd did not start within 60 seconds")
      end
    end

    test "a clean file, the marker in a WebVTT NOTE block and the EICAR file", %{
      dir: dir,
      socket: socket
    } do
      clean = write_file!(dir, "clean.vtt", "WEBVTT\n\n00:00.000 --> 00:01.000\nHello\n")
      assert Clamd.scan(clean, socket: socket) == :clean

      marked =
        write_file!(
          dir,
          "marked.vtt",
          "WEBVTT\n\nNOTE #{@marker}\n\n00:00.000 --> 00:01.000\nHello\n"
        )

      assert Clamd.scan(marked, socket: socket) == {:found, "Espalier.Test.Marker.UNOFFICIAL"}

      eicar = write_file!(dir, "sample.txt", @eicar)
      assert Clamd.scan(eicar, socket: socket) == {:found, "Espalier.Test.Eicar.UNOFFICIAL"}
    end

    test "exceeded limits answer limits_exceeded and size_limit", %{dir: dir, socket: socket} do
      above_max_file = write_file!(dir, "three.bin", :crypto.strong_rand_bytes(3 * @mib))

      assert Clamd.scan(above_max_file, socket: socket) ==
               {:error, {:limits_exceeded, "MaxFileSize"}}

      above_stream = write_file!(dir, "eight.bin", :crypto.strong_rand_bytes(8 * @mib))
      assert Clamd.scan(above_stream, socket: socket) == {:error, :size_limit}
    end
  end
end
