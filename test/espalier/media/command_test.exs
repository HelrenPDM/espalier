defmodule Espalier.Media.CommandTest do
  @moduledoc """
  Task 0018, steps 5 and 23 (ASVS 1.2.5): `Espalier.Media.Command.run/3`
  starts the executable under `timeout` with an argument list and no shell,
  in the given directory, returns the output for exit status 0, the last 20
  lines (each at most 300 characters) for another status, `:timeout` at the
  deadline and for a deadline below one second without starting a process,
  keeps at most 1 MiB of output, and passes `out_time_us=` lines to the
  progress callback. A `:halt` of the callback or a request of `cancel/1`
  ends `timeout` and its child, also a child that ignores `TERM`, and
  answers `:cancelled`; a request before the start starts no process. An
  exception, a throw or an exit in the progress callback ends both
  processes before it goes on.

  The commands are coreutils executables, found on the `PATH`. The
  processes of a command are found through their working directory in
  `/proc`.
  """
  use ExUnit.Case, async: true

  alias Espalier.Media.Command

  @moduletag :tmp_dir

  describe "exit status" do
    test "exit 0 returns the output", %{tmp_dir: dir} do
      assert Command.run(tool("printf"), ["%s\n", "first", "second"], timeout: 10, cd: dir) ==
               {:ok, "first\nsecond\n"}
    end

    test "the arguments reach the executable unchanged, no shell reads them", %{tmp_dir: dir} do
      text = "title; rm -rf / $(id) `id` * ~ $HOME | > out.txt \"'"

      assert Command.run(tool("printf"), ["%s", text], timeout: 10, cd: dir) == {:ok, text}
      assert File.ls!(dir) == []
    end

    test "the process runs in the directory cd", %{tmp_dir: dir} do
      {expected, 0} = System.cmd(tool("pwd"), [], cd: dir)
      assert Command.run(tool("pwd"), [], timeout: 10, cd: dir) == {:ok, expected}
    end

    test "standard error is merged into the output", %{tmp_dir: dir} do
      missing = Path.join(dir, "absent.txt")

      assert {:error, {:exit, 1, [line]}} =
               Command.run(tool("cat"), [missing], timeout: 10, cd: dir)

      assert line =~ "absent.txt"
      assert line =~ "No such file or directory"
    end

    test "a non-zero exit returns the last 20 lines, each cut to 300 characters",
         %{tmp_dir: dir} do
      lines =
        for i <- 1..30 do
          if rem(i, 2) == 0, do: "line #{i} " <> String.duplicate("x", 500), else: "line #{i}"
        end

      file = Path.join(dir, "lines.txt")
      File.write!(file, Enum.join(lines, "\n") <> "\n")
      missing = Path.join(dir, "absent.txt")

      assert {:error, {:exit, 1, tail}} =
               Command.run(tool("cat"), [file, missing], timeout: 10, cd: dir)

      assert length(tail) == 20
      assert Enum.all?(tail, &(String.length(&1) <= 300))

      expected =
        lines
        |> Enum.slice(11..29)
        |> Enum.map(&String.slice(&1, 0, 300))

      assert Enum.take(tail, 19) == expected
      assert List.last(tail) =~ "absent.txt"
    end

    test "the tail splits CRLF lines and turns bytes that are no UTF-8 into text",
         %{tmp_dir: dir} do
      file = Path.join(dir, "latin1.txt")
      File.write!(file, "caf" <> <<0xE9>> <> "\r\n" <> String.duplicate(<<0xFC>>, 400) <> "\r\n")

      assert {:error, {:exit, 1, [first, second, _error]}} =
               Command.run(tool("cat"), [file, Path.join(dir, "absent")], timeout: 10, cd: dir)

      assert first == "café"
      assert String.valid?(second)
      assert String.length(second) == 300
    end

    test "an executable that does not exist exits with the status of timeout", %{tmp_dir: dir} do
      assert {:error, {:exit, 127, tail}} =
               Command.run(Path.join(dir, "no-such-tool"), [], timeout: 10, cd: dir)

      assert Enum.join(tail) =~ "no-such-tool"
    end
  end

  describe "output cap" do
    test "the output is cut at 1 MiB", %{tmp_dir: dir} do
      assert {:ok, output} =
               Command.run(tool("head"), ["-c", "3000000", "/dev/zero"], timeout: 30, cd: dir)

      assert byte_size(output) == 1_048_576
      assert output == :binary.copy(<<0>>, 1_048_576)
    end

    test "an output of exactly 1 MiB stays whole", %{tmp_dir: dir} do
      assert {:ok, output} =
               Command.run(tool("head"), ["-c", "1048576", "/dev/zero"], timeout: 30, cd: dir)

      assert byte_size(output) == 1_048_576
    end

    test "a non-zero exit after more than 1 MiB of output keeps the last lines",
         %{tmp_dir: dir} do
      file = Path.join(dir, "long.txt")
      File.write!(file, String.duplicate(String.duplicate("p", 99) <> "\n", 20_000))
      missing = Path.join(dir, "absent.txt")

      assert {:error, {:exit, 1, tail}} =
               Command.run(tool("cat"), [file, missing], timeout: 30, cd: dir)

      assert List.last(tail) =~ "absent.txt"
    end
  end

  describe "deadline" do
    test "a command past its deadline answers :timeout", %{tmp_dir: dir} do
      started = System.monotonic_time(:millisecond)
      assert Command.run(tool("sleep"), ["5"], timeout: 1, cd: dir) == {:error, :timeout}
      assert System.monotonic_time(:millisecond) - started < 4_000
    end

    test "a command that ignores TERM is killed ten seconds after the deadline",
         %{tmp_dir: dir} do
      started = System.monotonic_time(:millisecond)

      assert Command.run(tool("env"), ["--ignore-signal=TERM", tool("sleep"), "60"],
               timeout: 1,
               cd: dir
             ) == {:error, :timeout}

      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed >= 10_000
      assert elapsed < 20_000
    end

    test "a deadline below one second answers :timeout without starting a process",
         %{tmp_dir: dir} do
      marker = Path.join(dir, "started")

      for seconds <- [0, -1, -60] do
        assert Command.run(tool("touch"), [marker], timeout: seconds, cd: dir) ==
                 {:error, :timeout}
      end

      refute File.exists?(marker)

      # The same command with a deadline starts.
      assert {:ok, ""} = Command.run(tool("touch"), [marker], timeout: 5, cd: dir)
      assert File.exists?(marker)
    end
  end

  describe "progress" do
    test "out_time_us lines go to the callback in order, also past the output cap",
         %{tmp_dir: dir} do
      test = self()
      values = Enum.map(1..60_000, &(&1 * 1_000))

      args = ["out_time_us=%s\n" | Enum.map(values, &Integer.to_string/1)]
      on_progress = fn us -> send(test, {:progress, us}) end

      assert {:ok, output} =
               Command.run(tool("printf"), args, timeout: 30, cd: dir, on_progress: on_progress)

      # More than 1 MiB in many reads of the pipe, so lines span chunk
      # boundaries and the last ones arrive after the cap.
      assert byte_size(output) == 1_048_576
      assert received() == values
    end

    test "other lines and values that are no count do not reach the callback", %{tmp_dir: dir} do
      test = self()

      args = [
        "%s\n",
        "frame=12",
        "out_time_us=N/A",
        "out_time_us=-9223372036854775807",
        "out_time_ms=5000",
        "out_time_us=1500000\r",
        "out_time_us=2500000 ",
        "progress=continue",
        " out_time_us=7",
        "out_time_us=3000000"
      ]

      assert {:ok, _output} =
               Command.run(tool("printf"), args,
                 timeout: 10,
                 cd: dir,
                 on_progress: &send(test, {:progress, &1})
               )

      assert received() == [1_500_000, 2_500_000, 3_000_000]
    end

    test "a last line without its line break is not passed", %{tmp_dir: dir} do
      test = self()

      assert {:ok, "out_time_us=1\nout_time_us=2"} =
               Command.run(tool("printf"), ["out_time_us=1\nout_time_us=2"],
                 timeout: 10,
                 cd: dir,
                 on_progress: &send(test, {:progress, &1})
               )

      assert received() == [1]
    end
  end

  describe "cancel" do
    test "a :halt of the progress callback ends the process and answers :cancelled",
         %{tmp_dir: dir} do
      test = self()

      on_progress = fn us ->
        send(test, {:progress, us})
        :halt
      end

      started = System.monotonic_time(:millisecond)

      # yes prints the line until a signal ends it.
      assert Command.run(tool("yes"), ["out_time_us=1000"],
               timeout: 60,
               cd: dir,
               on_progress: on_progress
             ) == {:error, :cancelled}

      assert System.monotonic_time(:millisecond) - started < 5_000
      # The lines after the :halt do not reach the callback.
      assert received() == [1000]
      assert processes_in(dir) == []
    end

    test "an exception, a throw or an exit in the progress callback ends the process and goes on",
         %{tmp_dir: dir} do
      callbacks = [
        error: fn _us -> raise "progress failed" end,
        throw: fn _us -> throw(:progress_failed) end,
        exit: fn _us -> exit(:progress_failed) end
      ]

      for {kind, on_progress} <- callbacks do
        started = System.monotonic_time(:millisecond)

        # yes prints the line until a signal ends it.
        {caught, stacktrace} =
          try do
            Command.run(tool("yes"), ["out_time_us=1000"],
              timeout: 60,
              cd: dir,
              on_progress: on_progress
            )
          catch
            kind, reason -> {{kind, reason}, __STACKTRACE__}
          end

        assert {^kind, _reason} = caught
        # The error goes on with the stack trace of the callback.
        assert [{__MODULE__, _function, _arity, _location} | _frames] = stacktrace
        # timeout and yes have ended when the error goes on.
        assert processes_in(dir) == []
        assert System.monotonic_time(:millisecond) - started < 5_000
      end
    end

    test "cancel/1 ends the running command of a process, timeout and its child",
         %{tmp_dir: dir} do
      task = Task.async(fn -> Command.run(tool("sleep"), ["60"], timeout: 60, cd: dir) end)
      wait_until(fn -> length(processes_in(dir)) == 2 end)
      started = System.monotonic_time(:millisecond)

      assert Command.cancel(task.pid) == :ok
      assert Task.await(task, 15_000) == {:error, :cancelled}
      assert System.monotonic_time(:millisecond) - started < 5_000
      assert processes_in(dir) == []
    end

    test "a command that ignores TERM is killed ten seconds after the cancel", %{tmp_dir: dir} do
      task =
        Task.async(fn ->
          Command.run(tool("env"), ["--ignore-signal=TERM", tool("sleep"), "60"],
            timeout: 60,
            cd: dir
          )
        end)

      wait_until(fn -> length(processes_in(dir)) == 2 end)
      started = System.monotonic_time(:millisecond)
      Command.cancel(task.pid)

      assert Task.await(task, 30_000) == {:error, :cancelled}
      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed >= 10_000
      assert elapsed < 20_000
      assert processes_in(dir) == []
    end

    test "a cancel before the start answers :cancelled without starting a process, once",
         %{tmp_dir: dir} do
      marker = Path.join(dir, "started")

      Command.cancel(self())
      assert Command.run(tool("touch"), [marker], timeout: 5, cd: dir) == {:error, :cancelled}
      refute File.exists?(marker)

      # The request is used up, so the next command runs.
      assert {:ok, ""} = Command.run(tool("touch"), [marker], timeout: 5, cd: dir)
      assert File.exists?(marker)
    end

    test "drop_cancel/0 drops the requests that no command took", %{tmp_dir: dir} do
      marker = Path.join(dir, "started")

      Command.cancel(self())
      Command.cancel(self())
      assert Command.drop_cancel() == :ok

      assert {:ok, ""} = Command.run(tool("touch"), [marker], timeout: 5, cd: dir)
      assert File.exists?(marker)
    end
  end

  describe "executables" do
    test "timeout_path/0 and executable!/1 return absolute paths" do
      assert Path.type(Command.timeout_path()) == :absolute
      assert Command.executable!("ffmpeg") == System.find_executable("ffmpeg")
    end

    test "executable!/1 raises for a tool that is not installed" do
      assert_raise RuntimeError, "espalier-no-such-tool is not installed", fn ->
        Command.executable!("espalier-no-such-tool")
      end
    end
  end

  defp tool(name), do: System.find_executable(name) || flunk("#{name} is not on the PATH")

  # The processes whose working directory is `dir`, from /proc.
  defp processes_in(dir) do
    for entry <- File.ls!("/proc"),
        match?({_pid, ""}, Integer.parse(entry)),
        {:ok, cwd} <- [File.read_link(Path.join(["/proc", entry, "cwd"]))],
        cwd == dir,
        do: entry
  end

  defp wait_until(fun, timeout \\ 5_000) do
    wait(fun, System.monotonic_time(:millisecond) + timeout)
  end

  defp wait(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("the condition was not met in time")

      true ->
        Process.sleep(20)
        wait(fun, deadline)
    end
  end

  defp received do
    receive do
      {:progress, us} -> [us | received()]
    after
      0 -> []
    end
  end
end
