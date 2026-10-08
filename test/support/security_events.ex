defmodule Espalier.Test.SecurityEvents do
  @moduledoc """
  Collects the security events of the calling test process. The telemetry
  handler runs in the emitting process and forwards only the events of the
  test process, so async tests do not see each other's events.
  """

  @doc """
  Attaches a handler and returns a ref; each event arrives as
  `{ref, metadata}`.
  """
  def attach_security_events do
    ref = make_ref()
    pid = self()
    id = "security-events-#{inspect(ref)}"

    :telemetry.attach(
      id,
      [:espalier, :security, :event],
      fn _event, _measurements, metadata, _config ->
        if self() == pid, do: send(pid, {ref, metadata})
      end,
      nil
    )

    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(id) end)
    ref
  end
end
