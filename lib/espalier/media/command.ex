defmodule Espalier.Media.Command do
  @moduledoc """
  Runs ffmpeg and ffprobe for the media processors (task 0018, step 5).

  Every process starts through `Port.open/2` with `:spawn_executable` and an
  argument list, never through a shell (ASVS 1.2.5): the port runs
  `timeout --kill-after=10 <seconds> <executable> <args>` in the work
  directory of the job. `timeout` ends the process at the deadline and
  kills it ten seconds later, so a crash of the BEAM leaves an ffmpeg
  running at most until that deadline.

  The output (standard output and standard error merged) is collected up to
  1 MiB; the rest is counted and dropped. Lines `out_time_us=<n>` of
  `-progress pipe:1` go to the callback `:on_progress`.

  A command stops early when the callback answers `:halt` or when the
  calling process receives the request of `cancel/1`. `kill`, started
  through `System.cmd/3` with the signal and the process id of `timeout` as
  its only arguments, then sends `TERM` to `timeout`, which passes it to
  its child and kills the child ten seconds later, and `run/3` answers
  `{:error, :cancelled}` once the process has ended. Closing the port
  alone would not end ffmpeg, which ignores the broken pipe of its
  progress output. Without `kill` on the `PATH`, a cancelled command runs
  until it ends or reaches its deadline, and the answer is still
  `{:error, :cancelled}`. A request of `cancel/1` that arrives between two
  commands stops the next one before its start.

  An exception, a throw or an exit while a command runs, such as one of
  the callback `:on_progress`, ends the process in the same way: `run/3`
  sends `TERM`, waits for the exit status up to the deadline of the
  command and its grace period, and then raises the error again with its
  stack trace.
  """

  require Logger

  @max_output 1_048_576
  # The end of the output, from which the tail of an error comes, also when
  # the output passed @max_output.
  @recent_bytes 32_768
  @tail_lines 20
  @tail_line_chars 300
  # Beyond the deadline of timeout and its kill, the port is closed here.
  @grace_ms 20_000
  @cancel {__MODULE__, :cancel}

  @typedoc "The result of a command."
  @type result ::
          {:ok, binary()}
          | {:error, :timeout}
          | {:error, :cancelled}
          | {:error, {:exit, non_neg_integer(), [String.t()]}}

  @doc """
  Runs `executable` (an absolute path) with `args` in `opts[:cd]` and the
  deadline `opts[:timeout]` in seconds. Returns `{:ok, output}` for exit
  status 0, `{:error, :timeout}` for status 124 (the deadline) or 137 (the
  kill), `{:error, :cancelled}` after a cancel (the callback `:on_progress`
  answered `:halt`, or `cancel/1` reached the calling process), and
  `{:error, {:exit, status, tail}}` with the last 20 lines of the output,
  each at most 300 characters, otherwise.
  """
  @spec run(Path.t(), [String.t()], keyword()) :: result()
  def run(executable, args, opts) when is_binary(executable) and is_list(args) do
    seconds = Keyword.fetch!(opts, :timeout)
    cd = Keyword.fetch!(opts, :cd)
    on_progress = Keyword.get(opts, :on_progress)

    cond do
      seconds < 1 ->
        {:error, :timeout}

      cancel_requested?() ->
        {:error, :cancelled}

      true ->
        start(executable, args, seconds, cd, on_progress)
    end
  end

  defp start(executable, args, seconds, cd, on_progress) do
    port =
      Port.open({:spawn_executable, timeout_path()}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :use_stdio,
        {:args, ["--kill-after=10", Integer.to_string(seconds), executable | args]},
        {:cd, cd}
      ])

    deadline = System.monotonic_time(:millisecond) + seconds * 1000 + @grace_ms

    state = %{
      output: [],
      bytes: 0,
      recent: "",
      line: "",
      on_progress: on_progress,
      cancelled: false
    }

    try do
      collect(port, state, deadline)
    catch
      kind, reason ->
        abort(port, deadline)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Asks the command that the process `pid` runs, or else its next command,
  to stop. `run/3` in that process then answers `{:error, :cancelled}`.
  """
  @spec cancel(pid()) :: :ok
  def cancel(pid) when is_pid(pid) do
    send(pid, @cancel)
    :ok
  end

  @doc """
  Drops the requests of `cancel/1` that no command of the calling process
  took, so that none of them stops a later command.
  """
  @spec drop_cancel() :: :ok
  def drop_cancel do
    if cancel_requested?(), do: drop_cancel(), else: :ok
  end

  @doc "The absolute path of `timeout`, or a raise when it is missing."
  @spec timeout_path() :: Path.t()
  def timeout_path, do: executable!("timeout")

  @doc "The absolute path of `name` on the `PATH`, or a raise when it is missing."
  @spec executable!(String.t()) :: Path.t()
  def executable!(name) do
    System.find_executable(name) || raise "#{name} is not installed"
  end

  defp cancel_requested? do
    receive do
      @cancel -> true
    after
      0 -> false
    end
  end

  defp collect(port, state, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        case state |> keep(data) |> progress(data) do
          {:halt, state} -> collect(port, stop(port, state), deadline)
          {:cont, state} -> collect(port, state, deadline)
        end

      {^port, {:exit_status, status}} ->
        result(state, status)

      @cancel ->
        collect(port, stop(port, state), deadline)
    after
      remaining ->
        close(port)
        if state.cancelled, do: {:error, :cancelled}, else: {:error, :timeout}
    end
  end

  defp result(%{cancelled: true}, _status), do: {:error, :cancelled}
  defp result(state, 0), do: {:ok, output(state)}
  defp result(_state, status) when status in [124, 137], do: {:error, :timeout}
  defp result(state, status), do: {:error, {:exit, status, tail(state.recent)}}

  # The first cancel ends the process; collect/3 then waits for its exit
  # status, so the process has ended when run/3 answers.
  defp stop(_port, %{cancelled: true} = state), do: state

  defp stop(port, state) do
    terminate(port)
    %{state | cancelled: true}
  end

  # TERM goes to timeout, the process of the port, which passes it to its
  # child and kills the child ten seconds later. Port.info/2 answers nil
  # once the port has closed with the exit of its process. The executable
  # comes from System.find_executable/1, and the only other arguments are
  # the signal and the process id of the port.
  # sobelow_skip ["CI.System"]
  defp terminate(port) do
    case {Port.info(port, :os_pid), System.find_executable("kill")} do
      {nil, _kill} ->
        :ok

      {{:os_pid, os_pid}, kill} when is_binary(kill) ->
        _output = System.cmd(kill, ["-TERM", Integer.to_string(os_pid)], stderr_to_stdout: true)
        :ok

      {_os_pid, nil} ->
        Logger.warning("kill is not installed, so a cancelled media command runs until it ends")
        :ok
    end
  end

  # An exception, a throw or an exit in collect/3, such as one of the
  # progress callback, ends the process as a cancel does and waits for its
  # exit status up to the same deadline before it goes on: the port would
  # close with the calling process, and ffmpeg would keep running. The
  # output that still arrives is dropped, and no line reaches the callback.
  defp abort(port, deadline) do
    terminate(port)
    await_exit(port, deadline)
  end

  # A port that has closed already leaves at most its last messages, which
  # are read without a wait.
  defp await_exit(port, deadline) do
    remaining =
      if Port.info(port) == nil,
        do: 0,
        else: max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, _data}} -> await_exit(port, deadline)
      {^port, {:exit_status, _status}} -> :ok
    after
      remaining -> close(port)
    end
  end

  defp close(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp keep(state, data), do: state |> keep_recent(data) |> keep_output(data)

  defp keep_recent(%{recent: recent} = state, data) do
    recent = recent <> data
    size = byte_size(recent)

    if size > @recent_bytes,
      do: %{state | recent: binary_part(recent, size - @recent_bytes, @recent_bytes)},
      else: %{state | recent: recent}
  end

  defp keep_output(%{bytes: bytes} = state, _data) when bytes >= @max_output, do: state

  defp keep_output(%{bytes: bytes, output: output} = state, data) do
    room = @max_output - bytes
    kept = binary_part(data, 0, min(room, byte_size(data)))
    %{state | output: [output | kept], bytes: bytes + byte_size(kept)}
  end

  # After a cancel, no line reaches the callback any more.
  defp progress(%{on_progress: nil} = state, _data), do: {:cont, state}
  defp progress(%{cancelled: true} = state, _data), do: {:cont, state}

  defp progress(%{line: line, on_progress: on_progress} = state, data) do
    {lines, rest} = split_lines(line <> data)

    # A line without its end stays for the next chunk, up to a bound.
    state = %{state | line: binary_part(rest, 0, min(byte_size(rest), 1024))}

    # The lines after a :halt of the callback do not reach it.
    if Enum.any?(lines, &(report(on_progress, &1) == :halt)),
      do: {:halt, state},
      else: {:cont, state}
  end

  defp report(on_progress, line) do
    case Regex.run(~r/\Aout_time_us=(\d+)\s*\z/, line) do
      [_match, us] -> if on_progress.(String.to_integer(us)) == :halt, do: :halt, else: :cont
      nil -> :cont
    end
  end

  defp split_lines(text) do
    parts = String.split(text, "\n")
    {Enum.drop(parts, -1), List.last(parts)}
  end

  defp output(%{output: output}), do: IO.iodata_to_binary(output)

  defp tail(output) do
    output
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.take(-@tail_lines)
    |> Enum.map(&String.slice(scrub(&1), 0, @tail_line_chars))
  end

  # The output of a damaged input may hold bytes that are no UTF-8.
  defp scrub(line) do
    if String.valid?(line), do: line, else: :unicode.characters_to_binary(line, :latin1)
  end
end
