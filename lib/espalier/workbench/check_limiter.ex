defmodule Espalier.Workbench.CheckLimiter do
  @moduledoc """
  Bounds the checks and the imports from drafts that run at once on a node
  (task 0016a, step 6; ASVS 15.2.2).

  `run/1` asks this server for a slot. While fewer than
  `Espalier.Workbench.max_parallel_checks/0` slots are taken (2 by default),
  the server grants one and monitors the caller, so that a caller that dies
  frees its slot; otherwise `run/1` answers `{:error, :checks_busy}` at once,
  without a queue. The setting is read at each request, so a changed value
  applies to the next one.

  `await/1` runs the work of a slot in a task of
  `Espalier.Workbench.TaskSupervisor` and waits for the time budget of the
  loader of task 0008 plus 10 seconds (`timeout_ms/0`). The task is not
  linked to the caller: a task that raises or exits makes `await/1` raise
  or exit in the caller, and a task that takes longer is killed and
  `await/1` raises, so that the `after` blocks of the caller run in every
  case, remove its directory and free its slot. A watchdog kills the task
  when the caller dies first.
  """
  use GenServer

  alias Espalier.Catalog.Pack.Loader
  alias Espalier.Workbench

  @task_supervisor Espalier.Workbench.TaskSupervisor
  @margin_ms 10_000

  @doc "Starts the server under the name of the module."
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, opts)

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [Keyword.put_new(opts, :name, __MODULE__)]}
    }
  end

  @doc """
  Runs `fun` in a slot and frees the slot afterwards. Returns the result of
  `fun`, or `{:error, :checks_busy}` when every slot is taken.
  """
  @spec run((-> result)) :: result | {:error, :checks_busy} when result: term()
  def run(fun) when is_function(fun, 0) do
    case GenServer.call(__MODULE__, {:acquire, Workbench.max_parallel_checks()}) do
      {:ok, ref} ->
        try do
          fun.()
        after
          GenServer.call(__MODULE__, {:release, ref})
        end

      :busy ->
        {:error, :checks_busy}
    end
  end

  @doc """
  Runs `fun` in a task and returns its result. An exception or an exit of
  the task is raised again in the caller; a task that takes longer than
  `timeout_ms/0` is killed, and the function raises.
  """
  @spec await((-> result)) :: result when result: term()
  def await(fun) when is_function(fun, 0) do
    task = Task.Supervisor.async_nolink(@task_supervisor, fun)
    watch_caller(self(), task.pid)
    timeout = timeout_ms()

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      {:exit, {exception, stacktrace}} when is_exception(exception) and is_list(stacktrace) ->
        reraise exception, stacktrace

      {:exit, reason} ->
        exit(reason)

      nil ->
        raise "the check of a draft took longer than #{timeout} ms"
    end
  end

  # Kills the task when the caller dies before it, as the loader of task
  # 0008 does for its parse processes.
  defp watch_caller(caller, task) do
    spawn(fn ->
      caller_ref = Process.monitor(caller)
      task_ref = Process.monitor(task)

      receive do
        {:DOWN, ^caller_ref, :process, _pid, _reason} -> Process.exit(task, :kill)
        {:DOWN, ^task_ref, :process, _pid, _reason} -> :ok
      end
    end)
  end

  @doc """
  The time that `await/1` waits: the time budget of a pack and of one YAML
  parse of `Espalier.Catalog.Pack.Loader.parse_budget/0`, plus 10 seconds.
  """
  @spec timeout_ms() :: pos_integer()
  def timeout_ms do
    budget = Loader.parse_budget()
    budget[:pack_timeout_ms] + budget[:timeout_ms] + @margin_ms
  end

  ## Server

  @impl GenServer
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:acquire, max}, {pid, _tag}, slots) do
    if map_size(slots) < max do
      ref = Process.monitor(pid)
      {:reply, {:ok, ref}, Map.put(slots, ref, pid)}
    else
      {:reply, :busy, slots}
    end
  end

  def handle_call({:release, ref}, _from, slots) do
    Process.demonitor(ref, [:flush])
    {:reply, :ok, Map.delete(slots, ref)}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, slots),
    do: {:noreply, Map.delete(slots, ref)}
end
