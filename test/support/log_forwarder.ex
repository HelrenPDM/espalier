defmodule Espalier.Test.LogForwarder do
  @moduledoc """
  A `:logger` handler that forwards the log events of one process to it as
  `{:log_event, event}`, so a test can format them with the production
  formatter. Add it with `attach/0`; it is removed when the test exits.
  """

  @doc "Adds the handler for the calling process and returns its id."
  def attach do
    id = :"log_forwarder_#{System.unique_integer([:positive])}"
    :ok = :logger.add_handler(id, __MODULE__, %{level: :all, config: %{pid: self()}})
    ExUnit.Callbacks.on_exit(fn -> :logger.remove_handler(id) end)
    id
  end

  @doc false
  def log(%{meta: meta} = event, %{config: %{pid: pid}}) do
    if Map.get(meta, :pid) == pid, do: send(pid, {:log_event, event})
    :ok
  end
end
